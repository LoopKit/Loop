//
//  PodLoanPhoneController.swift
//  Loop
//
//  The phone half of lending the pod to the watch: the persisted state machine, the epoch
//  that names each loan, and the stored properties the extensions share. Dependencies are
//  injected (see +Wiring) so the ordering rules are testable.
//

import Foundation
import HealthKit
import LoopKit
import LoopCore
import UserNotifications
import os.log

final class PodLoanPhoneController {
    /// Loan: owner → grantOffered → loaned → reconciling → owner. A take-back goes through
    /// reclaimPending. The phone doses only at owner, and not while yielding to an inferred loan.
    enum State: String {
        case owner, grantOffered, loaned, reconciling, reclaimPending
    }

    /// Derived from a snapshot and a clock (see +UIReads).
    struct ReclaimProgress: Equatable {
        enum Phase: Equatable {
            /// The watch is being asked to hand back and is expected to answer.
            case draining

            /// The drain overran; the tile shows the force deadline.
            case watchNotAnswering

            /// Taking the pod without the watch; where a dead-branch ladder starts.
            case forcing

            /// The settle after a hand-back: the phone re-establishing the pod link.
            case reconnectingToPod

            /// The settle after a force reclaim.
            case forceReclaimingPod
        }
        let phase: Phase

        let startedAt: Date

        let expectedBy: Date

        /// nil once overrun; otherwise capped below 1.
        let fraction: Double?

        let elapsed: TimeInterval
    }

    /// Defaults are inert, so a test supplies only what it exercises.
    struct Dependencies {
        var pumpManager: () -> PumpManager?

        var settings: () -> LoopSettings

        /// The loan's dosing pause; distinct from the user's closed-loop setting.
        var setAutomaticDosingPaused: (Bool) -> Void

        var send: ([String: Any]) -> Void

        var addPumpEvents: ([NewPumpEvent], _ lastReconciliation: Date?, @escaping (Error?) -> Void) -> Void

        var addCarb: (NewCarbEntry, String, @escaping (Error?) -> Void) -> Void

        var deleteCarb: (LoanReconciler.DeletedCarb, @escaping (Error?) -> Void) -> Void = { _, done in done(nil) }

        /// Diagnostic only; it lags, so it never gates a grant.
        var watchAppInstalled: () -> Bool = { true }

        /// Read and write: the reader tells a clear from the wrist whether there is anything to clear.
        var scheduleOverride: () -> TemporaryScheduleOverride? = { nil }
        /// Recorded in the override history at `changedAt`, when the wrist made the change.
        var applyScheduleOverride: (TemporaryScheduleOverride?, _ changedAt: Date) -> Void = { _, _ in }

        var noteWatchClosedLoop: (Bool) -> Void = { _ in }

        var lastLoopCompleted: () -> Date? = { nil }

        var noteWatchLoopCompleted: (Date) -> Void = { _ in }

        var doseHistory: (_ start: Date, _ completion: @escaping ([DoseEntry]) -> Void) -> Void

        var carbHistory: (_ start: Date, _ completion: @escaping ([LoanCarbRecord]) -> Void) -> Void = { _, done in done([]) }

        var glucoseHistory: (_ start: Date, _ completion: @escaping ([LoanGlucoseRecord]) -> Void) -> Void = { _, done in done([]) }

        /// Overrides overlapping `start` onward, ended ones included, as the phone's history holds them.
        var overrideHistory: (_ start: Date, _ completion: @escaping ([TemporaryScheduleOverride]) -> Void) -> Void = { _, done in done([]) }

        /// Stock's settings-history queries over the window; nil leaves the wrist on its snapshot.
        var settingsHistory: (_ start: Date, _ end: Date, _ completion: @escaping (LoanSettingsHistory?) -> Void) -> Void = { _, _, done in done(nil) }

        /// The glucose alert settings, encoded for the grant; nil leaves the wrist without them.
        var glucoseAlertSettings: (_ completion: @escaping (Data?) -> Void) -> Void = { $0(nil) }

        var issueNotice: (_ title: String, _ body: String) -> Void

        var ownershipDidChange: () -> Void = {}

        var isConnectionReady: () -> Bool = { true }

        var cancelTempBasalAfterPodReturn: (@escaping (Error?) -> Void) -> Void = { $0(nil) }

        var cancelTempBasalForGrant: (@escaping (Error?) -> Void) -> Void = { $0(nil) }

        /// Turns the user's closed-loop setting off; not the loan pause, which a later resume would undo.
        var openLoopForUncertainReconciliation: () -> Void = {}

        /// Time-sensitive, so a Focus mode cannot swallow a recording failure.
        var issueUrgentNotice: (_ title: String, _ body: String) -> Void = { _, _ in }

        var bookGapDose: (_ entry: DoseEntry, _ completion: @escaping (Bool) -> Void) -> Void = { _, done in done(false) }

        var deleteGapDose: (_ syncIdentifier: String, _ completion: @escaping (Bool) -> Void) -> Void = { _, done in done(false) }

        var backfillDoses: (_ doses: [DoseEntry], _ completion: @escaping (Error?) -> Void) -> Void = { _, done in done(nil) }

        /// After a back-dated insulin write; the counteraction memo is append-only.
        var insulinHistoryRewritten: (_ earliestDoseStart: Date) -> Void = { _ in }

        /// Defers launch-time store work until after first unlock.
        var whenProtectedDataAvailable: (@escaping () -> Void) -> Void = { $0() }

        var beginReclaimBackgroundTask: () -> Void = {}
        var endReclaimBackgroundTask: () -> Void = {}

        /// Channel selection, and a positive signal only: false for a healthy backgrounded watch.
        var isWatchReachable: () -> Bool = { false }

        var isBluetoothPoweredOff: () -> Bool = { false }

        /// During a loan the watch reports every cycle, so silence means something.
        var lastWatchContactAt: () -> Date? = { nil }

        /// Proxy for the phone being near the user.
        var latestGlucoseDate: () -> Date? = { nil }
        var now: () -> Date = { Date() }

        /// Storage seam for tests. A nil directory keeps each file in its app location.
        var stateDirectory: URL? = nil

        /// The scheduled reminders' notification centre; tests replace both so nothing reaches the app.
        var addNotification: (UNNotificationRequest) -> Void = { UNUserNotificationCenter.current().add($0) }
        var removeNotifications: ([String]) -> Void = { ids in
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ids)
        }
    }

    /// Book a placeholder bolus for unexplained insulin after a force reclaim.
    static let bookUnattributedInsulinOnForceReclaim = true

    let log = OSLog(subsystem: "com.loopkit.Loop", category: "PodLoanPhoneController")

    /// All state mutation happens here; the UI reads a mirror instead.
    let queue = DispatchQueue(label: "com.loopkit.Loop.PodLoanPhoneController", qos: .utility)
    var deps: Dependencies

    func handleIncoming(userInfo: [String: Any]) {
        queue.async { self.handleIncomingOnQueue(userInfo) }
    }

    func handleIncomingOnQueue(_ userInfo: [String: Any]) {
        let message: LoanMessage?
        do {
            message = try LoanMessage.decode(fromTransport: userInfo)
        } catch {
            // Never drop an undecodable message silently: nack it and warn about a build mismatch.
            sendMessage(.nack(ProtocolNack(seenVersion: nil)))
            warnProtocolMismatch()
            return
        }
        // A decoded message re-arms the mismatch warning.
        hasWarnedProtocolMismatch = false
        guard let message = message else { return }

        switch message {
        case .request(let request):
            handleRequest(request)
        case .takeoverComplete(let complete):
            handleTakeoverComplete(complete)
        case .takeoverFailed(let failed):
            handleTakeoverFailed(failed)
        case .doseRecordBatch(let batch):
            handleBatch(batch)
        case .handbackOffer(let offer):
            handleHandbackOffer(offer)
        case .statusReport(let report):
            handleStatusReport(report)
        // The watch could not read something this phone sent.
        case .nack:

            os_log("Loan protocol skew — the WATCH could not decode a message from this phone", log: log, type: .fault)
        // Phone-authored kinds, seen only if something loops a message back.
        case .grant, .handbackAck, .revoke, .statusQuery, .denied, .diag, .dormantGrant:
            break
        }
    }

    /// Back to the phone without a hand-back, for a loan that never really started. Clears the
    /// audit anchors, which describe one loan.
    func reclaimToOwner(alert: (title: String, body: String)?, reason: String) {
        handbackDiag(epoch, "loan ABANDONED — back to phone control: \(reason)")

        cancelReclaimLadder()
        deps.endReclaimBackgroundTask()

        grantOfferedAt = nil
        clearAuditAnchors()
        reclaimPodConnection()
        state = .owner
        deps.setAutomaticDosingPaused(false)
        if let alert = alert { deps.issueNotice(alert.title, alert.body) }
    }

    /// Keyed by event ID, so a resend replaces. Tombstones are the watch retracting superseded records.
    func stage(events: [LoanEvent], tombstones: [UUID]) {
        for event in events { staged[event.id] = event }
        stagedTombstones.formUnion(tombstones)
        persistStaged()
    }

    /// An unencodable message is dropped: callers are best-effort with a retry.
    func sendMessage(_ message: LoanMessage) {
        guard let dictionary = try? message.transportDictionary() else { return }
        deps.send(dictionary)
    }

    /// A phone dose as a wire record; scheduled basal and resume are omitted.
    static func loanRecord(from dose: DoseEntry) -> LoanDoseRecord? {
        switch dose.type {
        case .bolus:
            return LoanDoseRecord(kind: .bolus, startDate: dose.startDate, endDate: dose.endDate, amount: dose.deliveredUnits ?? dose.programmedUnits,
                                  syncIdentifier: dose.syncIdentifier, insulinType: dose.insulinType, automatic: dose.automatic)
        // Rate records carry delivered units: the pod floors to whole pulses.
        case .tempBasal:

            return LoanDoseRecord(kind: .tempBasal, startDate: dose.startDate, endDate: dose.endDate, unitsPerHour: dose.unitsPerHour,
                                  syncIdentifier: dose.syncIdentifier, insulinType: dose.insulinType,
                                  deliveredUnits: dose.deliveredUnits)
        case .suspend:
            return LoanDoseRecord(kind: .suspend, startDate: dose.startDate, endDate: dose.endDate, unitsPerHour: 0,
                                  syncIdentifier: dose.syncIdentifier, insulinType: dose.insulinType,
                                  deliveredUnits: dose.deliveredUnits)
        case .basal, .resume:
            return nil
        }
    }

    /// Restores the loan and re-arms what was owed; a loaned state pauses dosing at once.
    init(dependencies: Dependencies) {
        self.deps = dependencies
        var store = dependencies.stateDirectory.map { PersistedProperty<[String: Any]>(key: Self.stateFileKey, directory: $0) }
            ?? PersistedProperty(key: Self.stateFileKey)
        self._persisted = store.wrappedValue.flatMap(PodLoanPhoneState.init(rawValue:)) ?? PodLoanPhoneState()
        self.stateStore = store
        loadStaged()

        // Only a base from this epoch.
        if _persisted.audit.baseEpoch != epoch, _persisted.audit.base != nil || _persisted.audit.checkpoints != 0 {
            _persisted.audit.base = nil
            _persisted.audit.checkpoints = 0
            stateStore.wrappedValue = _persisted.rawValue
        }
        installPodLinkCensus()

        // Re-arm an unruled force-reclaim audit.
        if let saved = _persisted.pendingForceAudit {
            let e = saved.epoch
            pendingHandbackAudit = PendingHandbackAudit(
                epoch: e, deliveredAtStart: saved.deliveredAtStart, expected: saved.expected,
                loanMinutes: saved.loanMinutes, cycles: 0,
                watchLatest: nil, watchFreshened: false, flavor: .forceReclaim)
            queue.async { [weak self] in
                guard let self = self else { return }
                self.handbackDiag(e, "force-reclaim audit RE-ARMED after relaunch — verdict still owed")
                self.beginReclaimSettleWindow()
            }
        }

        deps.whenProtectedDataAvailable { [weak self] in
            guard let self = self else { return }
            self.queue.async {
                self.retryPersistedGapDeleteIfAny()

                self.cancelOpenLoopReminderIfLoopClosed()
            }
        }

        if podIsOnLoan {
            deps.setAutomaticDosingPaused(true)

            // Heal only transient states; a relaunch during a real loan is ordinary.
            if state == .reconciling || state == .reclaimPending {
                let stranded = state
                queue.asyncAfter(deadline: .now() + 120) { [weak self] in
                    guard let self = self, self.state == stranded else { return }
                    self.forceReclaimToOwner(reason: "relaunched into \(stranded.rawValue), no hand-back")
                }
            } else if state == .grantOffered {
                armT1(for: epoch)
            }
        }
    }

    /// The persisted state (+State); written whole by `updateState`.
    var stateStore: PersistedProperty<[String: Any]>
    var _persisted: PodLoanPhoneState
    let stateLock = NSLock()

    /// The tile's lock-guarded view; the UI never touches `queue`.
    let uiMirrorLock = NSLock()
    var uiMirror = UISnapshot()

    var reclaimStartedAt: Date?
    var reclaimSettleWork: DispatchWorkItem?

    /// Last verified pod round-trip; a new grant waits for it.
    var reclaimVerifiedAt: Date?
    var reclaimVerifyInFlight = false

    var reclaimLinkUpAt: Date?

    var reclaimEscalated = false
    var reclaimStaleReads = 0

    /// The tile's wait start, kept across a reopened window.
    var reclaimDisplayAnchor: Date?

    /// The last request answered, for suppressing transport redeliveries of the same one.
    var lastRequestID: String?
    var lastRequestAt: Date?

    var hasWarnedProtocolMismatch = false

    /// One write at a time: `committedIDs` updates only in a write's completion.
    var commitInFlight = false

    /// Offers that arrived mid-write, at most one per epoch.
    var coalescedOffers: [Int: HandbackOffer] = [:]

    var grantInFlight = false
    /// A force reclaim that is waiting for the in-flight write to land.
    var pendingForceReclaimReason: String?

    var staged: [UUID: LoanEvent] = [:]
    var stagedTombstones: Set<UUID> = []
    var t1WorkItem: DispatchWorkItem?
    var reclaimTimeoutWork: DispatchWorkItem?
    var reclaimResendWork: DispatchWorkItem?

    var reclaimLadder: ReclaimLadder?

    /// Test seam for the reclaim ladder's timing. nil in the app, where rungs use wall deadlines.
    var scheduler: ((_ delay: TimeInterval, _ label: String, _ work: DispatchWorkItem) -> Void)?

    var lastDormantRefreshAt: Date?

    var trailingDormantRefreshPending = false

    var lastClosedSessionRevokeAt: Date?
    var lastDormantSettingsFingerprint: String?
    /// The phone's glucose alert settings as last seen; part of the standing copy's fingerprint.
    var glucoseAlertSettingsSeen: GlucoseAlertSettings?

    /// The newest loan the watch claimed that this phone never granted, and when.
    var newestForeignLoanEvidence: (epoch: Int, at: Date)?

    /// Per grant; cleared wherever a loan is abandoned.
    var grantOfferedAt: Date?

    /// The pod fault already announced, as "epoch fault", so a repeated report stays quiet.
    var podFaultNoticed: String?

    /// Only the force-reclaim flavour persists.
    var pendingHandbackAudit: PendingHandbackAudit? {
        didSet {
            if let p = pendingHandbackAudit, p.flavor == .forceReclaim {
                updateState { $0.pendingForceAudit = .init(epoch: p.epoch, deliveredAtStart: p.deliveredAtStart,
                                                            expected: p.expected, loanMinutes: p.loanMinutes) }
            } else if oldValue?.flavor == .forceReclaim {
                updateState { $0.pendingForceAudit = nil }
            }
        }
    }
}
