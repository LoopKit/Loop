//
//  PodLoanPhoneController.swift
//  Loop
//
//  The phone half of lending the pod to the watch: the state machine, the epoch that names a
//  loan, and the shared stored properties the concern-split extensions work on.
//
//  The state is PERSISTED and everything else is derived from it. A phone that relaunches
//  mid-loan must come back believing the watch still has the pod; a volatile flag would come
//  back as owner and dose beside it.
//
//  An epoch names exactly one loan. Every record, ack, revoke and audit anchor carries one, and
//  anything arriving under a different epoch belongs to a different session.
//
//  Dependencies are injected closures so the state machine and its ordering rules can be tested
//  without the device stack; PodLoanPhoneController+Wiring builds the real ones.
//

import Foundation
import HealthKit
import LoopKit
import LoopCore
import UserNotifications
import os.log

final class PodLoanPhoneController {
    /// Where this phone stands with respect to the pod. Persisted by the raw value.
    ///
    /// The ordinary loan runs `owner → grantOffered → loaned → reconciling → owner`:
    /// the pod is offered, the watch confirms it has it, the watch offers it back, and the
    /// phone writes the records before returning to ownership. A take-back inserts
    /// `reclaimPending` in place of the watch's own initiative, and either reaches
    /// `reconciling` when the watch drains or `owner` directly when it is forced.
    ///
    /// `.owner` is the only state in which this phone doses — with one exception: an inferred
    /// yield, where the state is `.owner` but the watch has told us it is running a session the
    /// phone never granted. `podIsOnLoan` is the test that accounts for both.
    enum State: String {
        case owner, grantOffered, loaned, reconciling, reclaimPending
    }

    /// What the pump tile shows while the pod is coming home. Derived from a snapshot and a
    /// clock, never held as state — see PodLoanPhoneController+UIReads.
    struct ReclaimProgress: Equatable {
        enum Phase: Equatable {
            /// The watch is being asked to hand back and is expected to answer.
            case draining

            /// The drain overran its expectation. The tile stops predicting and shows the force
            /// deadline instead.
            case watchNotAnswering

            /// Taking it without the watch's cooperation. A dead-branch ladder starts here,
            /// because nothing that lands on that branch can answer a revoke.
            case forcing

            /// The settle after a hand-back: the phone re-establishing the pod link.
            case reconnectingToPod

            /// The settle after a force reclaim — same wait, different words, because the user
            /// did not hand the pod back.
            case forceReclaimingPod
        }
        let phase: Phase

        let startedAt: Date

        let expectedBy: Date

        /// nil once a phase has overrun its expectation and has nothing honest to predict.
        /// Otherwise capped below 1, so a bar never reads as finished before the thing is.
        let fraction: Double?

        let elapsed: TimeInterval
    }

    /// Every door out of the state machine. Defaults are inert, so a test supplies only what it
    /// exercises.
    struct Dependencies {
        var pumpManager: () -> PumpManager?

        var settings: () -> LoopSettings

        /// The loan's own pause on automatic dosing, held for as long as the pod is elsewhere.
        /// Distinct from the user's closed-loop setting, which only
        /// `openLoopForUncertainReconciliation` touches.
        var setAutomaticDosingPaused: (Bool) -> Void

        var send: ([String: Any]) -> Void

        var addPumpEvents: ([NewPumpEvent], _ lastReconciliation: Date?, @escaping (Error?) -> Void) -> Void

        var addCarb: (NewCarbEntry, String, @escaping (Error?) -> Void) -> Void

        var deleteCarb: (LoanReconciler.DeletedCarb, @escaping (Error?) -> Void) -> Void = { _, done in done(nil) }

        /// Diagnostic only. It must never gate a grant: the flag lags reality by a minute or
        /// more, and its refusal would have to travel over the very link it claims is down.
        var watchAppInstalled: () -> Bool = { true }

        /// The phone's active override, read and written. Both halves are needed — the reader
        /// is what tells a clear arriving from the wrist whether there is anything to clear.
        var scheduleOverride: () -> TemporaryScheduleOverride? = { nil }
        var applyScheduleOverride: (TemporaryScheduleOverride?) -> Void = { _ in }

        var noteWatchClosedLoop: (Bool) -> Void = { _ in }

        var lastLoopCompleted: () -> Date? = { nil }

        var noteWatchLoopCompleted: (Date) -> Void = { _ in }

        var doseHistory: (_ start: Date, _ completion: @escaping ([DoseEntry]) -> Void) -> Void

        var carbHistory: (_ start: Date, _ completion: @escaping ([LoanCarbRecord]) -> Void) -> Void = { _, done in done([]) }

        var glucoseHistory: (_ start: Date, _ completion: @escaping ([LoanGlucoseRecord]) -> Void) -> Void = { _, done in done([]) }

        var issueNotice: (_ title: String, _ body: String) -> Void

        var ownershipDidChange: () -> Void = {}

        var isConnectionReady: () -> Bool = { true }

        var cancelTempBasalAfterPodReturn: (@escaping (Error?) -> Void) -> Void = { $0(nil) }

        var cancelTempBasalForGrant: (@escaping (Error?) -> Void) -> Void = { $0(nil) }

        /// Turns the user's closed-loop setting OFF, and must not be implemented as the loan's
        /// dosing pause. A pause would be matched by a resume at the end of the next loan and
        /// would quietly re-close a loop this deliberately opened.
        var openLoopForUncertainReconciliation: () -> Void = {}

        /// Time-sensitive delivery. Both directions of the reconciliation verdict use it, even
        /// though only one stops dosing: a plain notice can be swallowed by a Focus mode,
        /// leaving a recording failure with no witness.
        var issueUrgentNotice: (_ title: String, _ body: String) -> Void = { _, _ in }

        var bookGapDose: (_ entry: DoseEntry, _ completion: @escaping (Bool) -> Void) -> Void = { _, done in done(false) }

        var deleteGapDose: (_ syncIdentifier: String, _ completion: @escaping (Bool) -> Void) -> Void = { _, done in done(false) }

        var backfillDoses: (_ doses: [DoseEntry], _ completion: @escaping (Error?) -> Void) -> Void = { _, done in done(nil) }

        /// Called after any back-dated insulin write, with the earliest dose start. The
        /// algorithm's counteraction memo is append-only, so without this its bins go on
        /// attributing the watch's insulin to unexplained glucose movement.
        var insulinHistoryRewritten: (_ earliestDoseStart: Date) -> Void = { _ in }

        /// Defers launch-time store work until after first unlock.
        var whenProtectedDataAvailable: (@escaping () -> Void) -> Void = { $0() }

        var beginReclaimBackgroundTask: () -> Void = {}
        var endReclaimBackgroundTask: () -> Void = {}

        /// A channel selector, and admissible as a POSITIVE signal only. It reads false for a
        /// perfectly healthy backgrounded watch, so it may never be the reason to conclude one
        /// is dead.
        var isWatchReachable: () -> Bool = { false }

        var isBluetoothPoweredOff: () -> Bool = { false }

        /// When this phone last heard anything from the watch. During a loan that cadence comes
        /// from the record batch the watch sends on every completed cycle, which is what makes
        /// silence a usable liveness signal.
        var lastWatchContactAt: () -> Date? = { nil }

        /// This phone's own newest sensor reading — a proxy for the phone being near the user,
        /// so it does not mistake its own absence for the watch's failure.
        var latestGlucoseDate: () -> Date? = { nil }
        var now: () -> Date = { Date() }
    }

    /// Whether an unexplained positive residual after a force reclaim is booked as a placeholder
    /// bolus as well as opening the loop.
    static let bookUnattributedInsulinOnForceReclaim = true

    let log = OSLog(subsystem: "com.loopkit.Loop", category: "PodLoanPhoneController")

    /// The controller's serial queue. Every mutation of the state below happens on it, and it is
    /// the reason the UI reads a mirror rather than the state itself.
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
            // Never ack-and-drop something we could not read. The sender is told, loudly, and
            // the user is told the builds may not match — a message silently discarded here
            // could be a dose record or a hand-back.
            sendMessage(.nack(ProtocolNack(seenVersion: nil)))
            warnProtocolMismatch()
            return
        }
        // A message that decoded clears the warning latch, so a later stretch of skew is
        // announced again rather than suppressed by an old one.
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
        // The mirror image of the decode failure above: the WATCH could not read something this
        // phone sent. Logged at fault level because it means a grant or a revoke may not have
        // been understood.
        case .nack:

            os_log("Loan protocol skew — the WATCH could not decode a message from this phone", log: log, type: .fault)
        // Phone-authored kinds, seen only if something loops a message back.
        case .grant, .handbackAck, .revoke, .statusQuery, .denied, .diag, .dormantGrant:
            break
        }
    }

    /// Abandon a loan and take the pod back into phone control, without a hand-back to commit.
    ///
    /// Used where the loan never really started — an aborted grant, a takeover the watch says
    /// failed, a dead-man that expired. It clears the audit anchors because an audit describes
    /// ONE loan: anchors left behind make the next take-back judge a session that already
    /// closed, and report its insulin as unexplained.
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

    /// Adds records to the holding area, keyed by event ID so a resend replaces rather than
    /// duplicates, and persists immediately. Tombstones are the watch retracting records it has
    /// superseded; they accumulate and are never removed while the loan is open.
    func stage(events: [LoanEvent], tombstones: [UUID]) {
        for event in events { staged[event.id] = event }
        stagedTombstones.formUnion(tombstones)
        persistStaged()
    }

    /// A message that will not encode is dropped silently on purpose: there is nothing to tell
    /// the other side with, and every caller here is best-effort with a retry above it.
    func sendMessage(_ message: LoanMessage) {
        guard let dictionary = try? message.transportDictionary() else { return }
        deps.send(dictionary)
    }

    /// Converts one of the phone's own doses into a wire record for the grant's history seed.
    ///
    /// Scheduled basal and resume produce nothing: they are not deliveries the watch needs to
    /// know about individually, and the watch reconstructs the profile from the basal schedule
    /// it is given.
    static func loanRecord(from dose: DoseEntry) -> LoanDoseRecord? {
        switch dose.type {
        case .bolus:
            return LoanDoseRecord(kind: .bolus, startDate: dose.startDate, endDate: dose.endDate, amount: dose.deliveredUnits ?? dose.programmedUnits,
                                  syncIdentifier: dose.syncIdentifier, insulinType: dose.insulinType)
        // Rate records carry `deliveredUnits` explicitly. The pod delivers whole pulses and the
        // driver floors a superseded temp, so a watch left to re-derive from the programmed rate
        // over-states IOB on every elapsed slice.
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

    /// Restores the loan from disk and re-arms whatever the previous run left owing.
    ///
    /// Nothing here waits for a message to arrive: if the persisted state says the pod is
    /// elsewhere, dosing is paused before anything else can happen.
    init(dependencies: Dependencies) {
        self.deps = dependencies
        self.state = State(rawValue: UserDefaults.standard.string(forKey: Keys.state) ?? "") ?? .owner
        self.epoch = UserDefaults.standard.object(forKey: Keys.epoch) as? Int ?? 0

        self.yieldingToInferredLoan = UserDefaults.standard.bool(forKey: Keys.yieldingToInferredLoan)
        self.committedCursor = UserDefaults.standard.object(forKey: Keys.cursor) as? Int ?? 0
        self.pendingRevoke = UserDefaults.standard.bool(forKey: Keys.pendingRevoke)
        self.loanStartedAt = UserDefaults.standard.object(forKey: Keys.loanStartedAt) as? Date
        if let raw = UserDefaults.standard.array(forKey: Keys.committedIDs) as? [String] {
            self.committedIDs = Set(raw.compactMap(UUID.init(uuidString:)))
        } else {
            self.committedIDs = []
        }
        loadStaged()

        // Epoch-guarded. A base persisted by some other loan would turn that whole loan's
        // delivery into this loan's unexplained insulin.
        if let d = UserDefaults.standard.dictionary(forKey: Keys.auditBase),
           let units = d["units"] as? Double, let asOf = d["asOf"] as? Date,
           (d["epoch"] as? Int) == self.epoch {
            self.auditBase = AuditBase(units: units, asOf: asOf)
            self.checkpointsThisLoan = d["count"] as? Int ?? 0
        }
        installPodLinkCensus()

        // One-time cleanup of the diagnostic residual series: force-reclaim residuals were once
        // banked alongside clean hand-backs, and they describe a watch whose records never
        // arrived rather than a reconciliation error.
        if !UserDefaults.standard.bool(forKey: Keys.residualHistoryPurged) {
            if var history = UserDefaults.standard.array(forKey: Keys.residualHistory) as? [Double] {
                let before = history.count
                history.removeAll { $0 > 0.5 }
                if history.count != before {
                    UserDefaults.standard.set(history, forKey: Keys.residualHistory)
                }
            }
            UserDefaults.standard.set(true, forKey: Keys.residualHistoryPurged)
        }

        // A force-reclaim audit that had not ruled when the app went away is re-armed here.
        // Whether the loop closes again must depend on the pod's answer, never on whether the
        // app happened to relaunch before that answer arrived.
        if let saved = UserDefaults.standard.dictionary(forKey: Keys.pendingForceAudit),
           let e = saved["epoch"] as? Int, let atStart = saved["atStart"] as? Double,
           let expected = saved["expected"] as? Double, let loanMinutes = saved["loanMinutes"] as? Double {
            pendingHandbackAudit = PendingHandbackAudit(
                epoch: e, deliveredAtStart: atStart, expected: expected,
                loanMinutes: loanMinutes, cycles: 0,
                watchLatest: nil, watchFreshened: false, flavor: .forceReclaim)
            queue.async { [weak self] in
                guard let self = self else { return }
                self.handbackDiag(e, "R37 audit RE-ARMED after relaunch — verdict still owed")
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

            // Heal only the TRANSIENT states. Relaunching into one of them means a hand-back was
            // interrupted, and nothing else will finish it. `.loaned` is never healed on a
            // timer: a relaunch during a real multi-hour loan is ordinary, and its recovery is a
            // new request or the user's own take-back.
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

    /// The tile's view of the state, published under a lock. The UI never touches `queue`; a
    /// stalled settle holds it for minutes and a waiting tile would freeze the app.
    let uiMirrorLock = NSLock()
    var uiMirror = UISnapshot()

    var reclaimStartedAt: Date?
    var reclaimSettleWork: DispatchWorkItem?

    /// When the pod last completed a round-trip after coming home. nil during a settle, and the
    /// readiness test a new grant is refused against.
    var reclaimVerifiedAt: Date?
    var reclaimVerifyInFlight = false

    var reclaimLinkUpAt: Date?

    var reclaimEscalated = false
    var reclaimStaleReads = 0

    /// Where the tile counts the wait from. Separate from the settle's own start so that a
    /// window re-opening moments later does not restart the bar in front of the user.
    var reclaimDisplayAnchor: Date?

    /// The last request answered, for suppressing transport redeliveries of the same one.
    var lastRequestID: String?
    var lastRequestAt: Date?

    var hasWarnedProtocolMismatch = false

    var checkpointsThisLoan = 0

    var worstWindowThisLoan: Double = 0

    /// The one-write-at-a-time latch. Events enter `committedIDs` only in a write's completion,
    /// so without it every duplicate arriving mid-write starts its own write against a set that
    /// has not been updated yet, and each one makes the next more likely.
    var commitInFlight = false

    /// Offers that arrived while a write was in flight, at most one per epoch. Coalesced, never
    /// dropped.
    var coalescedOffers: [Int: HandbackOffer] = [:]

    var grantInFlight = false
    /// A force reclaim that is waiting for the in-flight write to land.
    var pendingForceReclaimReason: String?

    /// The exactly-once record: every event whose dose or carb is in the phone's books.
    /// Persisted, and the ONLY dedup test — the ack cursor cannot serve, because the watch
    /// withholds unclassified events and its cursor legitimately has gaps.
    var committedIDs: Set<UUID>

    var staged: [UUID: LoanEvent] = [:]
    var stagedTombstones: Set<UUID> = []
    var loanStartedAt: Date?
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

    /// The newest loan the watch has claimed to hold that this phone never granted, and when it
    /// said so. Freshness is half the signal: an old sighting describes a session that has since
    /// ended.
    var newestForeignLoanEvidence: (epoch: Int, at: Date)?

    /// When the current grant was offered. Per grant, and cleared wherever a loan is abandoned,
    /// so a failed takeover's clock can never be quoted against the next grant.
    var grantOfferedAt: Date?

    /// The phone standing aside for a loan it did not grant. Persisted, because the blackout
    /// this answers can include a phone reboot.
    var yieldingToInferredLoan: Bool {
        didSet { UserDefaults.standard.set(yieldingToInferredLoan, forKey: Keys.yieldingToInferredLoan) }
    }

    /// Persisted on every write, and the single place a transition is published.
    ///
    /// The order inside is load-bearing. EVERY route back into `.owner` opens the settle window,
    /// and it opens BEFORE the transition is announced: an observer must never see ownership
    /// without its baseline, or the tile draws a pod that is home while the phone has not
    /// reached it. The mirror is likewise written before observers are notified — the async
    /// refresh alone loses the race and the re-render draws the previous state.
    var state: State {
        didSet {
            UserDefaults.standard.set(state.rawValue, forKey: Keys.state)

            if oldValue != state {
                if oldValue != .owner, state == .owner {
                    beginReclaimSettleWindow()
                }

                syncUIMirror()
                deps.ownershipDidChange()
            }
        }
    }

    /// Names the current loan. Minted by incrementing at the grant, and monotonic — the watch
    /// rejects anything at or below an epoch it has seen, which is what keeps a queued duplicate
    /// grant from restarting a session that already ended.
    var epoch: Int {
        didSet { UserDefaults.standard.set(epoch, forKey: Keys.epoch) }
    }

    /// How far the watch may consider its journal acknowledged. Reported to the watch; never
    /// used here to decide what has been committed.
    var committedCursor: Int {
        didSet { UserDefaults.standard.set(committedCursor, forKey: Keys.cursor) }
    }

    /// Persisted WITH the epoch that owns it, so a base can never be adopted by another loan.
    var auditBase: AuditBase? {
        didSet {
            if let b = auditBase {
                UserDefaults.standard.set(["units": b.units, "asOf": b.asOf, "epoch": epoch,
                                           "count": checkpointsThisLoan],
                                          forKey: Keys.auditBase)
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.auditBase)
            }
        }
    }

    /// Only the force-reclaim flavour is written to disk. A clean hand-back's audit does not
    /// need to survive a relaunch: the watch's records are already committed, and the loop was
    /// never left closed on unverified books.
    var pendingHandbackAudit: PendingHandbackAudit? {
        didSet {
            if let p = pendingHandbackAudit, p.flavor == .forceReclaim {
                UserDefaults.standard.set(["epoch": p.epoch, "atStart": p.deliveredAtStart,
                                           "expected": p.expected, "loanMinutes": p.loanMinutes],
                                          forKey: Keys.pendingForceAudit)
            } else if oldValue?.flavor == .forceReclaim {
                UserDefaults.standard.removeObject(forKey: Keys.pendingForceAudit)
            }
        }
    }

    /// A revoke this phone still owes the watch. Persisted so a relaunch mid-reclaim re-sends it
    /// the moment the watch is reachable again.
    var pendingRevoke: Bool {
        didSet { UserDefaults.standard.set(pendingRevoke, forKey: Keys.pendingRevoke) }
    }
}
