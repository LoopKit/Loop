//
//  PodLoanWatchController.swift
//  WatchApp Extension
//
//  The watch half of the loan protocol: the state machine, grant intake into the pump manager
//  the phone's exported configuration builds, hand-back, revoke and the relaunch drain.
//  Transport is injected (`send`).
//

import Foundation
import HealthKit
import LoopKit
import LoopAlgorithm
import LoopCore
import WatchKit
import os.log

extension Notification.Name {
    /// Posted from the controller's queue; observers hop to main themselves.
    static let podLoanPhaseDidChange = Notification.Name("com.loopkit.Loop.podLoanPhaseDidChange")

    static let manualBolusStateDidChange = Notification.Name("com.loopkit.Loop.manualBolusStateDidChange")

    static let carbAndBolusFlowDidComplete = Notification.Name("com.loopkit.Loop.carbAndBolusFlowDidComplete")
}

/// Why a hand-back gets no acks. A wedge is claimed only after three offers with the phone
/// reachable throughout; any unreachable moment explains the silence.
enum HandbackWedge: Equatable {
    /// Nothing to claim: too few attempts, or the phone was out of reach at some point.
    case none

    /// Sends succeeded, no ack: the copy must not name which app to restart.
    case oneWay

    /// Sends errored: the session is re-establishing. Logged, never alerted.
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
    /// idle → requested → takingOver → active → handingBack → idle, plus `revoked` and `recoveredDrain`.
    enum Phase: String {
        case idle, requested, takingOver, active, handingBack, revoked

        /// Records that outlived their loan, still offering. Start works from here.
        case recoveredDrain
    }

    let log = OSLog(subsystem: "com.loopkit.Loop", category: "PodLoanWatchController")
    /// Also the pump manager's delegate queue; main never syncs onto it (see +Debug).
    let queue = DispatchQueue(label: "com.loopkit.Loop.PodLoanWatchController", qos: .utility)
    let loopManager: WatchLoopManager
    let journal: LoanEventJournal

    /// Injected clock. Every deadline in the controller reads it, so tests can move time.
    var now: () -> Date = Date.init

    /// Test seam; nil in the app.
    var scheduler: ((_ delay: TimeInterval, _ label: String, _ work: DispatchWorkItem) -> Void)?

    /// Every timer logs armed, fired or skipped, with lateness and epoch. The work is wrapped so a
    /// cancelled item still records its skip.
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

    /// Where state files live; nil in the app (Documents).
    let stateDirectory: URL?

    /// The loaned pump manager's `managerIdentifier` and `state`, saved on every update as stock
    /// saves a pump manager; beside an active phase it means the loan can resume.
    var pumpStateStore: PersistedProperty<PumpManager.RawStateValue>

    /// Each pump kit's `localState` (what it knows about the pump that is this watch's own, e.g.
    /// its Bluetooth handle), by `managerIdentifier`. Outlives the loan: the next adopt reads it.
    var pumpLocalStateStore: PersistedProperty<[String: Any]>

    /// The stored seize credential, in its own file: large, and replaced whole by each refresh.
    var dormantGrantStore: PersistedProperty<Data>

    /// Sets the request timeout and refuses to queue a live offer; never gates a start.
    var isPhoneReachable: () -> Bool = { true }

    /// Logs reachability transitions, not every resend.
    var lastHandbackReachable: Bool?

    /// Sticky for the hand-back.
    var handbackSawUnreachable = false

    /// Tells a re-establishing session from a one-way wedge.
    var handbackSawUrgentSendError = false

    /// Called by the transport when an urgent send errors, from whichever queue it errored on.
    func noteUrgentSendFailed() {
        queue.async { self.handbackSawUrgentSendError = true }
        urgentSendWedged = true
    }

    /// Once an urgent send fails, stop choosing that channel; reset per hand-back.
    var urgentSendWedged = false

    /// Transport seam: the controller is testable without WCSession.
    var send: (([String: Any]) -> Void)?

    /// Background file transport for the loan's history (`transferFile`); false when the file
    /// could not be handed over.
    var transferLoanHistory: ((_ data: Data, _ metadata: [String: Any]) -> Bool)?

    /// Drops queued requests not yet transferring; returns how many.
    var cancelQueuedLoanRequests: (() -> Int)?

    /// A queued request delivered at reunion could re-grant over the running loan.
    func cancelStaleQueuedRequests(context: String) {
        guard let cancelled = cancelQueuedLoanRequests?(), cancelled > 0 else { return }
        SportLog.event("loan", "cancelled \(cancelled) queued loan request(s) — \(context); a delivered ghost would re-grant over whatever this watch does next")
    }

    /// Fired when a loan starts and when it ends, for whoever owns app-level runtime and UI.
    var onLoanActiveChanged: ((Bool) -> Void)?

    /// Runtime for the whole takeover.
    var onTakeoverRadioHold: ((Bool) -> Void)?

    /// Runtime for the whole hand-back.
    var onHandbackRuntimeHold: ((Bool) -> Void)?

    /// Transient glance notes, stamped so they age out.
    var handbackFailure: (at: Date, text: String)?

    var startNote: (at: Date, text: String)?

    /// The copy's pod total and records, consumed once at takeover.
    var takeoverCopyTotal: (units: Double, asOf: Date)?
    var takeoverCopyRecords: [LoanDoseRecord] = []
    /// The persisted state (+State): phase, epoch, high-water, the live loan's settings,
    /// odometer and reunion token. Written whole by `updateState`.
    var stateStore: PersistedProperty<[String: Any]>
    var _persisted: PodLoanWatchState
    let stateLock = NSLock()

    /// Repaint without a phase change — for the notes and prompts the glance draws.
    func notifyUI() {
        NotificationCenter.default.post(name: .podLoanPhaseDidChange, object: nil)
    }

    /// Non-nil means this watch has the pod; only `teardownPump` clears it.
    var pumpManager: PumpManager?

    /// Every pump the watch can be loaned has both (checked at the grant).
    var pumpControl: ExclusiveDeviceControl? { pumpManager as? ExclusiveDeviceControl }
    var pumpOdometer: PumpDeliveryOdometer? { pumpManager as? PumpDeliveryOdometer }

    /// For the wire and the debug page: the kit's own words for why the pump is inoperable.
    var pumpFaultDescription: String? {
        guard let pumpManager, pumpManager.isInoperable else { return nil }
        return pumpManager.localizedInoperableDescription
            ?? NSLocalizedString("Pump Inoperable", comment: "Fault text for a pump whose kit gives none")
    }

    /// Takeover timings and the glance's bar are measured from it.
    var attemptStartedAt: Date?

    /// When the last ladder read came back, so the gap to the next one can be measured.
    var lastTakeoverReadAt: Date?

    /// Separate objects for the event-driven retry and the backstop: a cancelled work item
    /// performs nothing.
    var takeoverRetryAction: (() -> Void)?
    var takeoverBackstop: DispatchWorkItem?
    /// A large gap means the app was suspended, not that the pod was unreachable.
    var takeoverMaxReadGap: TimeInterval = 0

    /// Feeds the wedge check and the drain's ceiling.
    var handbackResendCount = 0

    /// End asked for, still dosing, still cancellable.
    var handbackRequested = false

    /// From the grant; an old phone gets the single-phase hand-back.
    var phoneSupportsInterimHandback = false

    /// From the grant; without it override changes stay local.
    var phoneSupportsOverrideRecords = false

    /// Guards against a duplicate interim ack closing the loan early.
    var finalOfferSent = false
    /// What the watch confirmed it uploaded before releasing, per remote service; the released
    /// offer and the loan history carry it. Cleared at each grant.
    var uploadsConfirmed: [String: [String]]?
    /// The single armed resend.
    var resendWorkItem: DispatchWorkItem?

    /// Twenty unacked offers 15 s apart, then idle.
    static let maxDrainResends = 20

    /// Spans two offers and a pod read.
    var handbackDeadline: Date?

    /// When End was tapped, for the glance's progress and the log.
    var handbackStartedAt: Date?

    /// When the released offer went out, so the ack's latency can be stated rather than guessed.
    var finalOfferSentAt: Date?
    /// Cancelled when a grant arrives.
    var requestTimeoutWork: DispatchWorkItem?

    /// Cleared when a new attempt starts.
    var lastIdleNote: String?

    /// Reported to the phone at the next opportunity.
    var pendingInterruptedTakeoverEpoch: Int?

    /// First contact must find the pod, which needs the screen on. Queue-confined.
    var takeoverFirstContact = false
    var takeoverPodReached = false
    var takeoverNudges = 0
    /// The standing copy's pump export, read once from disk and replaced with each refresh.
    lazy var standingPumpConfiguration: SharedDeviceConfiguration? = storedDormantGrant()?.grant.sharedPumpConfiguration
    /// Seams: is the app on screen right now, and the tap itself.
    var isWatchAppActive: () -> Bool = { RuntimeStateLog.appStateName() == "active" }
    var playTakeoverNudge: () -> Void = { WKInterfaceDevice.current().play(.notification) }

    /// From persisted state alone: resume (rebuilt later in `resumeIfNeeded`), drain, or idle.
    init(loopManager: WatchLoopManager, journal: LoanEventJournal = LoanEventJournal(),
         stateDirectory: URL? = nil) {
        self.loopManager = loopManager
        self.journal = journal
        self.stateDirectory = stateDirectory
        self.dormantGrantStore = Self.fileStore("PodLoanDormantGrant", in: stateDirectory)
        self.pumpStateStore = Self.fileStore("PumpManagerState", in: stateDirectory)
        self.pumpLocalStateStore = Self.fileStore("PumpLocalState", in: stateDirectory)
        let store: PersistedProperty<[String: Any]> = Self.fileStore("PodLoanWatchState", in: stateDirectory)
        self._persisted = store.wrappedValue.flatMap(PodLoanWatchState.init(rawValue:)) ?? PodLoanWatchState()
        self.stateStore = store

        // Normalised without the phase observers, then saved once below.
        let savedPumpState = _persisted.phase == .active ? pumpStateStore.wrappedValue : nil
        if let savedPumpState {
            pendingResumeState = savedPumpState

            // init sets `phase` without running its observer.
            loanActiveMirrorLock.lock()
            _loanActiveMirror = true
            _resumingMirror = true
            _wristAlarmsMirror = true
            loanActiveMirrorLock.unlock()
        } else if journal.hasUndrainedEvents {
            // Records outlived their loan: park as a drain and say so.
            _persisted.phase = .recoveredDrain
            issueSessionEndedAlert()
        } else {
            switch _persisted.phase {
            case .idle:
                break
            case .requested, .takingOver:
                // A start that never finished: tell the phone, stay startable.
                pendingInterruptedTakeoverEpoch = _persisted.epoch
                lastIdleNote = NSLocalizedString("Sport Mode start was interrupted. Tap Start to try again.", comment: "Glance: start interrupted by relaunch")
                _persisted.phase = .idle
                _persisted.epoch = nil
            case .active, .handingBack, .revoked, .recoveredDrain:
                // No saved pod state: drain the records, never resurrect the session.
                _persisted.phase = .recoveredDrain
                issueSessionEndedAlert()
            }
        }
        // Saved, or the next launch repeats the normalisation.
        stateStore.wrappedValue = _persisted.rawValue
    }

    /// Saved pump state handed from `init` to `resumeIfNeeded`, which does the rebuild.
    var pendingResumeState: PumpManager.RawStateValue?

    /// Serialized with timers and the pump's callbacks.
    func handleIncoming(userInfo: [String: Any], channel: LoanTransportChannel) {
        queue.async { self.handleIncomingOnQueue(userInfo: userInfo, channel: channel) }
    }

    /// Logs every inbound message, with its channel, before any guard.
    private func handleIncomingOnQueue(userInfo: [String: Any], channel: LoanTransportChannel) {
        let message: LoanMessage?
        do {
            message = try LoanMessage.decode(fromTransport: userInfo)
        } catch {
            // Nack, never ack-and-drop.
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
            // A refusal during a hand-back fails the hand-back, not the loan.
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

    /// `urgentOnly`: never fall back to the queue.
    func sendMessage(_ message: LoanMessage, urgentOnly: Bool = false) {
        guard var dictionary = try? message.transportDictionary() else { return }
        if urgentOnly { dictionary["urgentOnly"] = true }
        send?(dictionary)
    }

    /// Time-sensitive under one shared identifier unless told otherwise. A routine alert takes its
    /// own identifier, so it never replaces an urgent one.
    func issueProtocolAlert(title: String, body: String, identifier: String = "protocolNack",
                            interruptionLevel: Alert.InterruptionLevel = .timeSensitive) {
        Task { @MainActor in
            loopManager.issueAlert(Alert(
                identifier: Alert.Identifier(managerIdentifier: "PodLoan", alertIdentifier: identifier),
                foregroundContent: Alert.Content(title: title, body: body, acknowledgeActionButtonLabel: "OK"),
                backgroundContent: Alert.Content(title: title, body: body, acknowledgeActionButtonLabel: "OK"),
                trigger: .immediate, interruptionLevel: interruptionLevel))
        }
    }

    /// Explicit BLE teardown so the pod advertises for the phone. Also resets the insulin book
    /// and wrist override, since WatchLoopManager outlives the loan.
    func teardownPump() {
        SportLog.event("handback", "teardownPump: releasing control of the pump explicitly")
        // Uploads stop before the insulin book is reset below.
        LoanRemoteUploads.shared.end()
        // The pod's alerts are the phone's from here: a repeating one left on the wrist would keep
        // sounding while the phone raises the same alert.
        if let pumpIdentifier = pumpManager?.pluginIdentifier {
            let loopManager = self.loopManager
            Task { await loopManager.retractStandingAlerts(managerIdentifier: pumpIdentifier) }
        }
        pumpControl?.releaseControl()
        pumpManager?.pumpManagerDelegate = nil
        pumpManager = nil
        pumpStateStore.wrappedValue = nil
        // The odometer stays until close: the drain's offers still measure from it.
        updateState { $0.grantedSettings = nil }

        let loopManager = self.loopManager
        Task { await loopManager.resetInsulinBook(reason: "teardown") }

        if loopManager.scheduleOverride != nil {
            SportLog.event("override", "wrist override reset at teardown — the next loan takes the phone's")
        }
        loopManager.scheduleOverride = nil
        Task { @MainActor in loopManager.clearGlucoseAlerts() }
    }

    /// Raised when a request times out with a credential stored.
    var seizeOffer: (issuedAt: Date, token: UUID)?

    /// Lets the stored credential past the live grant's freshness and epoch guards.
    var seizeActivationInFlight = false

    /// Persisted only once the loan is active (a fold persists at once).
    var pendingSeizeToken: UUID?

    /// One prompt per reachability transition.
    var seizeReunionDebounceArmed = false

    var reunionPromptActive = false

    /// Simulator only: Start and End drive the fake flow in +SimulatorDriver. Set by tests, or
    /// by the `-simFakeLoanFlow` launch argument.
    var simFakeLoanFlow = ProcessInfo.processInfo.arguments.contains("-simFakeLoanFlow")

    /// Simulator only: the fake CGM feed's timer, so a second Start cannot stack two.
    var simGlucoseTimer: DispatchSourceTimer?

    /// The odometer captured before a revoke tears the pump down.
    var revokeCapturedDelivered: Double?

    var revokeCapturedDeliveredAt: Date?

    /// The loan whose pump fault the phone has been told about.
    var faultReportedEpoch: Int?

    /// Main-readable mirrors, written from the queue.
    let loanActiveMirrorLock = NSLock()
    var _loanActiveMirror = false

    var _resumingMirror = false

    /// Taking over, live, handing back, draining or resuming: the phone has left the alarms here.
    var _wristAlarmsMirror = false

    /// The debug page's snapshot, published from the queue.
    let snapshotMirrorLock = NSLock()

    var _snapshotMirror: DebugSnapshot?
}

/// Logged with every inbound message.
enum LoanTransportChannel: String {
    case urgent
    case queued
}
