//
//  PodLoanWatchController.swift
//  WatchApp Extension
//
//  The watch half of loan protocol v2 (docs/DESIGN_LOAN_PROTOCOL_V2.md §3.2, §10).
//  State machine, grant intake -> stock OmniPumpManager construction, the pump-host
//  delegate duties (the pump manager's report writes the book AND the journal — one
//  identity per dose, the pod-native raw), hand-back with resend-until-ack, revoke, and
//  the relaunch drain (data-first: a dead session is never resurrected). Uncertainty is
//  the pump manager's own: an unacknowledged command is resolved on its next session.
//
//  Transport is injected (`send`) so the controller is testable without WCSession;
//  the app-lifecycle integration wires WCSession.transferUserInfo/didReceiveUserInfo
//  to `send`/`handleIncoming`.
//

import Foundation
import HealthKit
import LoopKit
import LoopAlgorithm
import LoopCore
import OmnipodKit
import WatchKit
import os.log

extension Notification.Name {
    /// Posted from the controller's own queue, so every observer must hop to main itself before
    /// touching SwiftUI state.
    static let podLoanPhaseDidChange = Notification.Name("com.loopkit.Loop.podLoanPhaseDidChange")

    static let manualBolusStateDidChange = Notification.Name("com.loopkit.Loop.manualBolusStateDidChange")

    static let carbAndBolusFlowDidComplete = Notification.Name("com.loopkit.Loop.carbAndBolusFlowDidComplete")
}

/// Why a hand-back is getting no acknowledgements — and whether it is honest to say so at all.
///
/// A wedge is only ever claimed when at least three offers went out, the phone was reachable the
/// whole time, and nothing came back. An unreachable phone explains the silence innocently and
/// heals itself, which is why `sawUnreachable` is sticky for the rest of the hand-back.
enum HandbackWedge: Equatable {
    /// Nothing to claim: too few attempts, or the phone was out of reach at some point.
    case none

    /// Sends succeeded silently and no ack came back. The only known recovery is restarting an
    /// app — and this cannot tell WHICH app, so the user-facing copy must not name one.
    case oneWay

    /// The sends themselves errored, which means the session is re-establishing. It clears on its
    /// own, so it is logged and never alerted.
    case sessionReestablishing

    static func classify(resendCount: Int,
                         sawUnreachable: Bool,
                         reachableNow: Bool,
                         sendsErrored: Bool) -> HandbackWedge {
        guard resendCount >= 3, !sawUnreachable, reachableNow else { return .none }
        return sendsErrored ? .sessionReestablishing : .oneWay
    }
}

final class PodLoanWatchController {
    /// idle → requested → takingOver → active → handingBack → idle, plus two exits from a live
    /// loan that are not the user's End: `revoked`, the phone asking for the pod back, and
    /// `recoveredDrain`.
    enum Phase: String {
        case idle, requested, takingOver, active, handingBack, revoked

        /// Records that outlived their loan — after a relaunch, a revoke, or a released hand-back
        /// nobody acked. The pod is gone and the events keep offering. This is startable ground,
        /// not a wall: Start works from here, and a seize folds the drain into the new loan.
        case recoveredDrain
    }

    let log = OSLog(subsystem: "com.loopkit.Loop", category: "PodLoanWatchController")
    /// The controller's serial queue, which also serves as the pump manager's delegate queue.
    /// Main must never `sync` onto it — read the mirrors in +Debug instead.
    let queue = DispatchQueue(label: "com.loopkit.Loop.PodLoanWatchController", qos: .utility)
    let loopManager: WatchLoopManager
    let journal: LoanEventJournal

    /// Injected clock. Every deadline in the controller reads it, so tests can move time.
    var now: () -> Date = Date.init

    /// Injected timer seam. Tests fire a timer instead of waiting for one; in the app this is nil
    /// and the queue's own `asyncAfter` is used.
    var scheduler: ((_ delay: TimeInterval, _ label: String, _ work: DispatchWorkItem) -> Void)?

    /// Arm a timer and account for it.
    ///
    /// Every scheduled timer logs armed / fired / skipped with how late it was and the epoch it
    /// was armed under. Lateness is the signature of the app having been suspended between the two
    /// — dispatch timers do not run while watchOS has the process parked — and a firing epoch that
    /// differs from the armed one is the signature of a timer surviving into a loan that did not
    /// arm it.
    ///
    /// The caller's work item is wrapped rather than scheduled directly, so cancelling it still
    /// leaves a wrapper to run and record the skip.
    func schedule(after delay: TimeInterval, label: String, execute work: DispatchWorkItem) {
        let armedEpoch = epoch
        let armedAt = now()
        SportLog.event("timer", "armed \(label) +\(fmtDelay(delay)) e=\(armedEpoch.map(String.init) ?? "-")")
        let wrapper = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            if work.isCancelled {
                SportLog.event("timer", "skipped \(label) — cancelled before its deadline")
                return
            }
            let late = self.now().timeIntervalSince(armedAt) - delay
            let lateNote = late > 1.0 ? String(format: " late %.1fs", late) : ""
            let epochNote = armedEpoch != self.epoch
                ? " ** armed e=\(armedEpoch.map(String.init) ?? "-") firing e=\(self.epoch.map(String.init) ?? "-") — cross-epoch **"
                : ""
            SportLog.event("timer", "fired \(label) +\(self.fmtDelay(delay))\(lateNote)\(epochNote)")
            work.perform()
        }
        if let scheduler = scheduler {
            scheduler(delay, label, wrapper)
        } else {
            queue.asyncAfter(deadline: .now() + delay, execute: wrapper)
        }
    }

    func schedule(after delay: TimeInterval, label: String, execute body: @escaping () -> Void) {
        schedule(after: delay, label: label, execute: DispatchWorkItem(block: body))
    }

    private func fmtDelay(_ d: TimeInterval) -> String {
        d < 1 ? String(format: "%.2fs", d) : String(format: "%.0fs", d)
    }

    var defaults: UserDefaults = .standard

    /// Injected. It sets how long the request timeout runs and refuses to QUEUE a live hand-back
    /// offer; it is never allowed to gate an attempt from starting, because it reads false for a
    /// healthy backgrounded phone.
    var isPhoneReachable: () -> Bool = { true }

    /// The last reachability logged during this hand-back, so the log records transitions rather
    /// than one line per resend.
    var lastHandbackReachable: Bool?

    /// Sticky for the whole hand-back: once the phone has been out of reach, the silence has an
    /// innocent explanation and no wedge may be claimed from it.
    var handbackSawUnreachable = false

    /// Whether any urgent send reported an error. This is the discriminator between a session
    /// that is merely re-establishing and a one-way transport wedge.
    var handbackSawUrgentSendError = false

    /// Called by the transport when an urgent send errors, from whichever queue it errored on.
    func noteUrgentSendFailed() {
        queue.async { self.handbackSawUrgentSendError = true }
        urgentSendWedged = true
    }

    /// Once an urgent send has failed, the transport stops choosing that channel. `isReachable`
    /// can be true while `sendMessage` times out, and every later attempt would then burn its full
    /// send timeout before the queued path got its turn. Reset when a new hand-back begins.
    var urgentSendWedged = false

    /// Transport seam: the controller is testable without WCSession.
    var send: (([String: Any]) -> Void)?

    /// Injected. Drops undelivered loan requests from the outgoing queue and returns how many
    /// went; a transfer already in flight is left alone.
    var cancelQueuedLoanRequests: (() -> Int)?

    /// Cancel queued loan requests the moment the watch stops wanting one.
    ///
    /// A request still sitting in the queue for a dark phone is a delayed detonator: delivered at
    /// reunion, inside the phone's freshness window, it grants a fresh epoch over the loan this
    /// watch is already running.
    func cancelStaleQueuedRequests(context: String) {
        guard let cancelled = cancelQueuedLoanRequests?(), cancelled > 0 else { return }
        SportLog.event("loan", "cancelled \(cancelled) queued loan request(s) — \(context); a delivered ghost would re-grant over whatever this watch does next")
    }

    /// Fired when a loan starts and when it ends, for whoever owns app-level runtime and UI.
    var onLoanActiveChanged: ((Bool) -> Void)?

    /// Held for the whole `.takingOver` phase. G7 scans and handshakes starve pod BLE session
    /// establishment on the single watch radio, and without background runtime the read ladder is
    /// throttled the moment the wrist drops, so its attempt budget burns on wall clock instead of
    /// on attempts.
    var onTakeoverRadioHold: ((Bool) -> Void)?

    /// Held for the whole `.handingBack` phase — the pod work and the wait for the phone's commit
    /// both happen there, with the wrist usually down.
    var onHandbackRuntimeHold: ((Bool) -> Void)?

    /// Transient notes the glance renders, stamped so the UI can age them out: why an End did not
    /// take, and what a takeover had to book before it could dose.
    var handbackFailure: (at: Date, text: String)?

    var startNote: (at: Date, text: String)?

    /// The pod's delivery total as the phone's snapshot last saw it, and the records that snapshot
    /// carried. Consumed once at takeover to work out what the copy cannot account for, then
    /// cleared — they describe one grant and must not outlive it.
    var takeoverCopyTotal: (units: Double, asOf: Date)?
    var takeoverCopyRecords: [LoanDoseRecord] = []
    /// Persisted on every change — a launch decides what it is from this and the saved pod state
    /// alone — and mirrored SYNCHRONOUSLY inside the didSet, so a hand-back offer built
    /// immediately after a wrist tap carries the value the user just chose.
    var phase: Phase {
        didSet {
            defaults.set(phase.rawValue, forKey: Keys.phase)
            loanActiveMirrorLock.lock()
            _loanActiveMirror = (phase == .active)
            loanActiveMirrorLock.unlock()
            // The radio and runtime holds are edge-triggered on entering and leaving their phase,
            // so re-asserting the same phase — which the resume path does — cannot double-acquire.
            if (oldValue == .takingOver) != (phase == .takingOver) {
                onTakeoverRadioHold?(phase == .takingOver)
                setTakeoverSessionListener(phase == .takingOver)
            }

            if (oldValue == .handingBack) != (phase == .handingBack) {
                onHandbackRuntimeHold?(phase == .handingBack)
            }

            if oldValue != phase {
                NotificationCenter.default.post(name: .podLoanPhaseDidChange, object: nil)
            }
        }
    }
    /// This loan's epoch, persisted so a relaunch still recognises its own acks and revokes.
    /// Cleared when a loan closes; `Keys.highWaterEpoch` is the memory that survives that.
    var epoch: Int? {
        didSet { defaults.set(epoch, forKey: Keys.epoch) }
    }

    /// Repaint without a phase change — for the notes and prompts the glance draws.
    func notifyUI() {
        NotificationCenter.default.post(name: .podLoanPhaseDidChange, object: nil)
    }

    /// The pod, for as long as this watch holds it. Non-nil is the working definition of "we
    /// have the pod"; `teardownPump` is the only sanctioned way to nil it.
    var pumpManager: OmniPumpManager?

    /// The pod's delivery odometer at the instant the takeover succeeded. Every odometer the
    /// phone audits is measured from it, so it is persisted with the loan and cleared with it.
    var deliveredAtTakeover: Double?

    /// When the current start attempt began — the glance's takeover bar and every takeover timing
    /// line are measured from it.
    var attemptStartedAt: Date?

    /// When the last ladder read came back, so the gap to the next one can be measured.
    var lastTakeoverReadAt: Date?

    /// The two halves of the takeover ladder's retry, deliberately SEPARATE objects: the pod
    /// stack's session-established event fires the action, and the backstop fires only if no event
    /// comes. One work item used for both, cancelled and then performed, kills the ladder dead — a
    /// cancelled `DispatchWorkItem` releases its block and performs nothing.
    var takeoverRetryAction: (() -> Void)?
    var takeoverBackstop: DispatchWorkItem?
    /// The largest gap between two consecutive ladder reads. A takeover that fails with a large
    /// gap was SUSPENDED rather than unreachable — a different failure, with a different thing for
    /// the user to do about it.
    var takeoverMaxReadGap: TimeInterval = 0

    /// Offers sent in this hand-back or drain. Feeds both the wedge classifier and the drain's
    /// give-up ceiling.
    var handbackResendCount = 0

    /// The user asked to End, but the watch is still dosing and the request is still cancellable.
    /// `.handingBack` is the point of no return.
    var handbackRequested = false

    /// From the grant. Without it the phone's decoder drops the `released` key and reads the first
    /// interim offer as a completed hand-back — reclaiming the pod while this watch is still
    /// dosing — so an old phone gets the single-phase path instead.
    var phoneSupportsInterimHandback = false

    /// From the grant. Without it an override change is applied locally and loudly NOT journalled:
    /// a record the phone cannot decode throws rather than degrading, and would strand the loan.
    var phoneSupportsOverrideRecords = false

    /// Whether the released offer has actually gone out. A duplicate interim ack arriving in the
    /// window before it must not close the loan, or the phone strands in `.loaned` forever.
    var finalOfferSent = false
    /// The single armed resend. Re-armed after every offer, cancelled by finalize, by the ack and
    /// by every timeout path.
    var resendWorkItem: DispatchWorkItem?

    /// A drain must terminate: twenty unacked offers at fifteen seconds apart, then close to idle.
    /// Nothing is lost by stopping — the phone owns the pod and has already committed these
    /// records — whereas a one-way session otherwise resends across relaunches indefinitely.
    static let maxDrainResends = 20

    /// When the wait for the phone's commit acknowledgement gives up. It spans two offers and a
    /// pod read, which is why the budget is minutes rather than seconds.
    var handbackDeadline: Date?

    /// When End was tapped, for the glance's progress and the log.
    var handbackStartedAt: Date?

    /// When the released offer went out, so the ack's latency can be stated rather than guessed.
    var finalOfferSentAt: Date?
    /// The armed request timeout. Cancelled as soon as a grant arrives, before any of the grant's
    /// own rejections run.
    var requestTimeoutWork: DispatchWorkItem?

    /// The one-line explanation the glance shows on the idle screen after a refusal, a timeout or
    /// a failed takeover. Cleared when a new attempt starts.
    var lastIdleNote: String?

    /// A takeover that was in flight when the app died. The phone is told it failed at the next
    /// opportunity; left unsaid, the phone waits out its own dead-man for a loan that never began.
    var pendingInterruptedTakeoverEpoch: Int?

    /// The BLE handle substituted into the inherited pod state, kept so a ladder that never
    /// connected can forget it — the next Start then pays for discovery once instead of retrying a
    /// handle that is no longer the pod's.
    var takeoverCachedHandle: (address: UInt32, handle: String)?

    enum Keys {
        static let phase = "PodLoanWatchController.phase"
        static let epoch = "PodLoanWatchController.epoch"

        /// The pod's raw state, rewritten on every pump-manager update. Its PRESENCE beside an
        /// active phase is what tells a launch the loan was live and can be resumed, so it and
        /// the two keys below are written and cleared together with it.
        static let pumpState = "PodLoanWatchController.pumpState"

        static let deliveredAtTakeover = "PodLoanWatchController.deliveredAtTakeover"

        static let grantedTherapySettings = "PodLoanWatchController.grantedTherapySettings"

        /// The highest epoch this watch ever accepted. NEVER cleared: closing a loan wipes
        /// `epoch` and the journal, and that amnesia is what let back-to-back seizes reuse an
        /// epoch the phone had already spent.
        static let highWaterEpoch = "PodLoanWatchController.highWaterEpoch"
    }

    /// Decides from persisted state alone what this launch is: a resume, a drain, or a clean idle.
    ///
    /// An ACTIVE phase with saved pod state is a resume — the mirrors are published here but the
    /// rebuild is deferred to `resumeIfNeeded`, which does it with background runtime held.
    /// Everything else either has records still owed to the phone, in which case the pod session
    /// is never resurrected and only the data drains, or has nothing at all.
    init(loopManager: WatchLoopManager, journal: LoanEventJournal = LoanEventJournal(),
         defaults: UserDefaults = .standard) {
        self.loopManager = loopManager
        self.journal = journal
        self.defaults = defaults
        self.phase = Phase(rawValue: defaults.string(forKey: Keys.phase) ?? "") ?? .idle
        self.epoch = defaults.object(forKey: Keys.epoch) as? Int

        let savedPumpState = phase == .active ? defaults.dictionary(forKey: Keys.pumpState) : nil
        if let savedPumpState {
            pendingResumeState = savedPumpState

            // Published here because init assigns `phase` directly, which does not run its
            // observer: without this the main-safe mirrors stay false and a resumed loan renders
            // as no loan at all.
            loanActiveMirrorLock.lock()
            _loanActiveMirror = true
            _resumingMirror = true
            loanActiveMirrorLock.unlock()
            loopManager.beginAwaitingPumpManager()
        } else if journal.hasUndrainedEvents {
            // Records outlived their loan whatever phase they were left in. Park as a drain — and
            // say so, because those doses and carbs may not be on the phone yet.
            phase = .recoveredDrain
            issueSessionEndedAlert()
        } else {
            switch phase {
            case .idle:
                break
            case .requested, .takingOver:
                // A start that never finished, so the pod is still the phone's. Tell the phone at
                // the next opportunity and leave this watch plainly startable.
                pendingInterruptedTakeoverEpoch = epoch
                lastIdleNote = NSLocalizedString("Sport Mode start was interrupted. Tap Start to try again.", comment: "Glance: start interrupted by relaunch")
                phase = .idle
                epoch = nil
            case .active, .handingBack, .revoked, .recoveredDrain:
                // A loan with no saved pod state cannot be rebuilt. The session is not
                // resurrected: the records drain and the pod stays wherever it now is.
                phase = .recoveredDrain
                issueSessionEndedAlert()
            }
        }
    }

    /// Saved pod state handed from `init` to `resumeIfNeeded`, which does the rebuild.
    var pendingResumeState: PumpManager.RawStateValue?

    /// Transport entry point. Everything after the hop is serialized with the timers and the
    /// pump's own delegate callbacks.
    func handleIncoming(userInfo: [String: Any], channel: LoanTransportChannel) {
        queue.async { self.handleIncomingOnQueue(userInfo: userInfo, channel: channel) }
    }

    /// Logs every inbound message BEFORE any guard, with the CHANNEL it arrived on.
    ///
    /// Without that line "the ack never arrived" and "the ack arrived and a guard dropped it"
    /// produce byte-identical logs. The channel is the discriminator between a wedged immediate
    /// path and an inbound path that is dead in both directions.
    private func handleIncomingOnQueue(userInfo: [String: Any], channel: LoanTransportChannel) {
        let message: LoanMessage?
        do {
            message = try LoanMessage.decode(fromTransport: userInfo)
        } catch {
            // Nacked, never acked-and-dropped: the phone must learn that this watch could not
            // read the payload rather than assume it landed.
            os_log("Undecodable v2 payload: %{public}@", log: log, type: .fault, String(describing: error))
            sendMessage(.nack(ProtocolNack(seenVersion: nil)))
            return
        }
        guard let message = message else { return }

        SportLog.event("loan", "RX \(message.kindLabel) ch=\(channel.rawValue) — ours ev=\(epoch.map(String.init) ?? "nil") phase=\(phase.rawValue)")

        switch message {
        case .grant(let grant):
            handleGrant(grant)
        case .handbackAck(let ack):
            handleAck(ack)
        case .revoke(let revoke):
            handleRevoke(revoke)
        case .statusQuery(let query):
            handleStatusQuery(query)
        case .nack:

            SportLog.event("loan", "phone NACKed our payload — build mismatch; the loan will not start")
        case .denied(let denied):
            // A refusal during a hand-back is a hand-back failure, not a failed start: this watch
            // is still holding the pod and must keep dosing.
            if (phase == .active && handbackRequested) || phase == .handingBack {
                handbackTimedOut(refusal: denied.reason)
                return
            }

            requestTimeoutWork?.cancel()
            if phase == .requested || phase == .idle || phase == .recoveredDrain {
                returnToRestingPhase()
                lastIdleNote = denied.reason
                notifyUI()
            }
            SportLog.event("loan", "DENIED by phone — \(denied.reason)")
        case .diag(let d):
            SportLog.event("phone", d.text)
        case .dormantGrant(let dormant):
            handleDormantGrant(dormant)
        case .request, .takeoverComplete, .takeoverFailed, .doseRecordBatch, .handbackOffer, .statusReport:
            os_log("Ignoring phone-bound message kind on watch", log: log, type: .default)
        }
    }

    /// `urgentOnly` marks a message the transport must NOT fall back to the queue with — for
    /// anything whose late delivery would be worse than its loss.
    func sendMessage(_ message: LoanMessage, urgentOnly: Bool = false) {
        guard var dictionary = try? message.transportDictionary() else { return }
        if urgentOnly { dictionary["urgentOnly"] = true }
        send?(dictionary)
    }

    /// Protocol-level alerts share one identifier, so a second replaces the first rather than
    /// stacking a queue of them behind a user who is already mid-problem.
    func issueProtocolAlert(title: String, body: String) {
        Task { @MainActor in
            loopManager.issueAlert(Alert(
                identifier: Alert.Identifier(managerIdentifier: "PodLoan", alertIdentifier: "protocolNack"),
                foregroundContent: Alert.Content(title: title, body: body, acknowledgeActionButtonLabel: "OK"),
                backgroundContent: Alert.Content(title: title, body: body, acknowledgeActionButtonLabel: "OK"),
                trigger: .immediate))
        }
    }

    /// Give the pod up properly.
    ///
    /// The BLE link is torn down EXPLICITLY rather than left to deallocation: nothing else removes
    /// the pod from the stack's auto-connect set, and a pod that stays connected is not
    /// advertising, so the phone's standing connect can never land on it.
    ///
    /// It also resets the insulin book and clears the wrist override, because `WatchLoopManager`
    /// lives for the PROCESS and not for the loan — an indefinite override from one loan would
    /// otherwise keep rescaling basal, ISF and carb ratio through the next one while every screen
    /// showed none.
    func teardownPump() {
        SportLog.event("handback", "teardownPump: releasing BLE explicitly (see PODLOAN release log for the identifier)")
        pumpManager?.releaseConnection()
        pumpManager?.pumpManagerDelegate = nil
        pumpManager = nil
        defaults.removeObject(forKey: Keys.pumpState)
        defaults.removeObject(forKey: Keys.deliveredAtTakeover)
        defaults.removeObject(forKey: Keys.grantedTherapySettings)

        let loopManager = self.loopManager
        Task { await loopManager.resetInsulinBook(reason: "teardown") }

        loopManager.applyWristOverride(nil)
    }

    /// A live offer to start without the phone, raised when a request times out with a dormant
    /// credential stored. Cleared when it is taken or dismissed.
    var seizeOffer: (issuedAt: Date, token: UUID)?

    /// True only while `confirmSeize` is driving `handleGrant`. It is what lets a stored
    /// credential past the freshness and duplicate-epoch guards a live grant must clear.
    var seizeActivationInFlight = false

    /// The reunion token of a seize being activated. It is promoted to persistence only once the
    /// loan is actually `.active` — an aborted activation never touched the pod, and a stale token
    /// beside a forced-fresh epoch is exactly the pair the phone's retro-acknowledgement matches
    /// on. A FOLD is the exception: real records already exist, so it is persisted at once.
    var pendingSeizeToken: UUID?

    /// The reunion prompt's debounce, and whether the prompt is currently up. At most one prompt
    /// per reachability transition, and none once the user has already asked to End.
    var seizeReunionDebounceArmed = false

    var reunionPromptActive = false

    /// Simulator only: the fake CGM feed's timer, so a second Start cannot stack two.
    var simGlucoseTimer: DispatchSourceTimer?

    /// The pod's odometer captured BEFORE a revoke tears the pump down. The revoke frees the pod's
    /// BLE first on purpose, so reading it afterwards asks a nil pump — and an offer carrying no
    /// odometer skips the phone's authoritative reconcile of the loan entirely.
    var revokeCapturedDelivered: Double?

    var revokeCapturedDeliveredAt: Date?
    /// The highest epoch the phone has asked back. Recorded BEFORE the epoch is matched, so even a
    /// revoke naming no live session closes the split-brain hole: a grant at or below it — the
    /// queued copy of one that raced a request timeout — is refused from then on.
    var lastRevokedEpoch: Int?

    /// Main-readable mirrors of "a loan is live" and "a loan is being rebuilt", written under the
    /// lock from the queue. See +Debug for why main may not ask the queue directly.
    let loanActiveMirrorLock = NSLock()
    var _loanActiveMirror = false

    var _resumingMirror = false

    /// The debug page's snapshot, published from the queue under its own lock for the same
    /// reason — the page ticks on main and must never wait for a pod command to finish.
    let snapshotMirrorLock = NSLock()

    var _snapshotMirror: DebugSnapshot?
}

/// Which WatchConnectivity path a message arrived on — logged with every inbound message, because
/// it is the only way to tell a wedged immediate channel from a dead inbound path.
enum LoanTransportChannel: String {
    case urgent
    case queued
}
