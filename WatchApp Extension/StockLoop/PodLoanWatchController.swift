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

@MainActor
final class PodLoanWatchController {
    /// idle → requested → takingOver → active → handingBack → idle, plus `revoked` and `recoveredDrain`.
    enum Phase: String {
        case idle, requested, takingOver, active, handingBack, revoked

        /// Records that outlived their loan, still offering. Start works from here.
        case recoveredDrain
    }

    let log = OSLog(category: "PodLoanWatchController")
    let loopManager: WatchLoopManager
    let journal: LoanEventJournal

    /// Injected clock. Every deadline in the controller reads it, so tests can move time.
    var now: () -> Date = Date.init

    /// Test seam; nil in the app.
    var scheduler: ((_ delay: TimeInterval, _ label: String, _ work: DispatchWorkItem) -> Void)?

    /// The work is wrapped, so cancelling the caller's item stops it even after the wrapper is queued.
    func schedule(after delay: TimeInterval, label: String, execute work: DispatchWorkItem) {
        let wrapper = DispatchWorkItem { [weak self] in
            guard self != nil, !work.isCancelled else { return }
            work.perform()
        }
        if let scheduler = scheduler {
            scheduler(delay, label, wrapper)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: wrapper)
        }
    }

    func schedule(after delay: TimeInterval, label: String, execute body: @escaping () -> Void) {
        schedule(after: delay, label: label, execute: DispatchWorkItem(block: body))
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

    /// Whether the link to the phone has finished starting up. Before it has, a message is lost, so
    /// anything that waits on an answer starts only once it is (`whenLinkActivated`).
    var isLinkActivated: () -> Bool = { true }

    /// When the phone was last heard from; the Sport Mode page says when it has gone quiet.
    var lastHeardFromPhoneAt: Date?

    /// Work waiting for the link to start up; run by `linkDidActivate`. On `queue`.
    var workAwaitingLink: [() -> Void] = []

    /// On `queue`: runs `work` now if the link is up, else when it comes up.
    func whenLinkActivated(_ work: @escaping () -> Void) {
        guard isLinkActivated() else {
            workAwaitingLink.append(work)
            return
        }
        work()
    }

    /// The link to the phone has started up.
    func linkDidActivate() {
        DispatchQueue.main.async {
            let waiting = self.workAwaitingLink
            self.workAwaitingLink = []
            waiting.forEach { $0() }
        }
    }

    /// How long a Start waits for the phone's grant before offering the offline start.
    static let requestTimeout: TimeInterval = LoanControl.Wait.onScreen.seconds

    /// Sticky for the hand-back.
    var handbackSawUnreachable = false

    /// Tells a re-establishing session from a one-way wedge.
    var handbackSawUrgentSendError = false

    /// Called by the transport when an urgent send errors, from whichever queue it errored on.
    func noteUrgentSendFailed() {
        DispatchQueue.main.async { self.handbackSawUrgentSendError = true }
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
        SportLog.event("loan", "cancelled \(cancelled) queued loan request(s): \(context)")
    }

    /// Fired when a loan starts and when it ends, for whoever owns app-level runtime and UI.
    var onLoanActiveChanged: ((Bool) -> Void)?


    /// Transient glance notes, stamped so they age out.
    var handbackFailure: (at: Date, text: String)?
    /// When the phone last acknowledged a hand-back offer; an End with no acknowledgement in the
    /// answer wait is refused.
    var handbackAckedAt: Date?

    var startNote: (at: Date, text: String)?

    /// The persisted state (+State): phase, epoch, high-water, the live loan's settings,
    /// odometer and reunion token. Written whole by `updateState`.
    var stateStore: PersistedProperty<[String: Any]>
    var _persisted: PodLoanWatchState

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

    /// Separate objects for the event-driven retry and the backstop: a cancelled work item
    /// performs nothing.
    var takeoverRetryAction: (() -> Void)?
    var takeoverBackstop: DispatchWorkItem?

    /// Feeds the wedge check and the drain's ceiling.
    var handbackResendCount = 0

    /// End asked for, still dosing, still cancellable.
    var handbackRequested = false

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
    var isWatchAppActive: () -> Bool = { WKExtension.shared().applicationState == .active }
    var playTakeoverNudge: () -> Void = { WKInterfaceDevice.current().play(.notification) }
    /// A Start or End the watch refused on the spot: the looper feels it as well as reads it.
    var playRefusal: () -> Void = { DispatchQueue.main.async { WKInterfaceDevice.current().play(.failure) } }
    /// Where the screens' override goes (`LoopDataManager.wristOverride`); a `var` so the suite can see it.
    var publishOverride: (TemporaryScheduleOverride??) -> Void = { ExtensionDelegate.sharedIfAvailable()?.loopManager.wristOverride = $0 }

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

            isResuming = true
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
                lastIdleNote = NSLocalizedString("Sport Mode start was interrupted. Your iPhone still has the pod. Tap Start to try again.", comment: "Glance: start interrupted by relaunch")
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

        // Installed before anything can resume, so a restored override reaches the screens too.
        loopManager.onScheduleOverrideChanged = { [weak self] in self?.publishOverrideForScreens() }
    }

    /// Saved pump state handed from `init` to `resumeIfNeeded`, which does the rebuild.
    var pendingResumeState: PumpManager.RawStateValue?

    /// The looper cancelled a Start at the offline offer; a grant for it starts nothing. Cleared by
    /// the next Start.
    var startCancelled = false

    /// Serialized with timers and the pump's callbacks. From the link's thread.
    nonisolated func handleIncoming(userInfo: [String: Any]) {
        DispatchQueue.main.async {
            self.handleIncomingMessage(userInfo: userInfo)
            self.notePhoneHeard()
        }
    }

    /// Any word from the phone (its loan messages, or its status for the stock pages). With no loan
    /// running, `LoanControl` row 3: the warning for a silent phone is pushed out.
    func notePhoneHeard() {
        DispatchQueue.main.async {
            self.lastHeardFromPhoneAt = self.now()
            guard self.phase == .idle || self.phase == .recoveredDrain else { return }
            if case .tellIfSilent(.notHearingFromPhone, let after) = LoanControl.decide(LoanControl.Situation(device: .watch, trigger: .phoneHeardWithNoLoan)) {
                NotHearingFromPhoneAlert.arm(after: after)
            }
        }
    }

    private func handleIncomingMessage(userInfo: [String: Any]) {
        let message: LoanMessage?
        do {
            message = try LoanMessage.decode(fromTransport: userInfo)
        } catch {
            // Nack, never ack-and-drop.
            log.error("Undecodable loan message: %{public}@", String(describing: error))
            sendMessage(.nack(ProtocolNack(seenVersion: nil)))
            return
        }
        guard let message = message else { return }

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

            SportLog.event("loan", "phone could not read our message: the builds do not match, so the loan will not start")
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
                playRefusal()
                notifyUI()
            }
            SportLog.event("loan", "phone denied the loan: \(denied.reason)")
        case .dormantGrant(let dormant):
            handleDormantGrant(dormant)
        case .request, .takeoverComplete, .takeoverFailed, .doseRecordBatch, .handbackOffer, .statusReport:
            log.default("Ignoring a message meant for the phone")
        }
    }

    func sendMessage(_ message: LoanMessage) {
        guard let dictionary = try? message.transportDictionary() else { return }
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
        // Uploads stop before the insulin book is reset below.
        LoanRemoteUploads.shared.end()
        // The pod's alerts are the phone's from here: a repeating one left on the wrist would keep
        // sounding while the phone raises the same alert.
        if let pumpIdentifier = pumpManager?.pluginIdentifier {
            let loopManager = self.loopManager
            Task { await loopManager.retractStandingAlerts(managerIdentifier: pumpIdentifier) }
        }
        pumpControl?.releaseControl()
        // Still the driver's delegate: the release lets a command under way finish, and its report
        // must find one (the driver treats none as impossible). The callbacks ignore a released driver.
        pumpManager = nil
        pumpStateStore.wrappedValue = nil
        // The odometer stays until close: the drain's offers still measure from it.
        updateState { $0.grantedSettings = nil }

        let loopManager = self.loopManager
        Task { await loopManager.resetInsulinBook(reason: "the pod's release") }

        loopManager.scheduleOverride = nil
        loopManager.clearGlucoseAlerts()
    }

    /// Raised when a request times out with a credential stored.
    var seizeOffer: (issuedAt: Date, token: UUID)?

    /// Lets the stored credential past the live grant's freshness and epoch guards.
    var seizeActivationInFlight = false

    /// Persisted only once the loan is active (a fold persists at once).
    var pendingSeizeToken: UUID?

    /// The odometer captured before a revoke tears the pump down.
    var revokeCapturedDelivered: Double?

    var revokeCapturedDeliveredAt: Date?

    /// The loan whose pump fault the phone has been told about.
    var faultReportedEpoch: Int?

    /// A saved loan is being rebuilt, and the watch back from off is checking with the phone
    /// before looping (`endResuming`).
    var isResuming = false
}
