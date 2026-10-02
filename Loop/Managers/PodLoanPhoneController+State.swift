//
//  PodLoanPhoneController+State.swift
//  Loop
//
//  The phone controller's persisted state: one value, saved and restored as a unit, like a
//  device manager's state.
//

import Foundation
import LoopCore

struct PodLoanPhoneState: RawRepresentable {
    /// The loan: the phone doses only at `.owner`, and not while yielding to an inferred loan.
    var phase: PodLoanPhoneController.State = .owner
    /// Monotonic; the watch rejects any epoch it has already seen.
    var epoch = 0
    /// Reported to the watch in acks; never the dedup test.
    var committedCursor = 0
    /// Exactly-once record of committed events: the only dedup test.
    var committedIDs: Set<UUID> = []
    /// A relaunch re-sends the revoke.
    var pendingRevoke = false
    /// Standing aside for a loan this phone never granted; survives a phone reboot.
    var yieldingToInferredLoan = false

    /// When the watch last reported a cycle, so a relaunch is not read as silence.
    var holdRenewedAt: Date?
    /// When the silence was noticed.
    var holdLapseNoticedAt: Date?
    var watchSilenceWarningsIssued = 0

    /// The watch said it can start alone; nothing dormant goes to a watch that cannot.
    var watchSupportsSeize = false
    /// Minted once and echoed by a watch that started alone: this phone's reunion credential.
    var seizeToken: UUID?

    /// One loan's audit inputs; every path that ends a loan resets them together.
    struct AuditAnchors {
        /// Start of the audit window, and the floor for every expectation over it.
        var loanStartedAt: Date?
        /// The pod's total at the grant: the fallback origin.
        var deliveredAtGrant: Double?
        /// The total as the watch first read it: the preferred origin.
        var deliveredAtTakeover: Double?
        /// The running base, read back only in the epoch it was set under.
        var base: PodLoanPhoneController.AuditBase?
        var baseEpoch: Int?
        var checkpoints = 0
    }
    var audit = AuditAnchors()

    /// A force-reclaim verdict still owed; re-armed at launch.
    struct ForceAudit: Equatable {
        let epoch: Int
        let deliveredAtStart: Double
        let expected: Double
        let loanMinutes: Double
    }
    var pendingForceAudit: ForceAudit?

    /// The placeholder bolus for insulin a lost watch never reported.
    struct GapBooking: Equatable {
        let epoch: Int
        let units: Double
        let bookedAt: Date?
        var deleteFailedAfterRecords = false
    }
    var gapBooking: GapBooking?

    init() {}

    init?(rawValue: [String: Any]) {
        phase = (rawValue["phase"] as? String).flatMap(PodLoanPhoneController.State.init(rawValue:)) ?? .owner
        epoch = rawValue["epoch"] as? Int ?? 0
        committedCursor = rawValue["committedCursor"] as? Int ?? 0
        committedIDs = Set((rawValue["committedIDs"] as? [String] ?? []).compactMap(UUID.init(uuidString:)))
        pendingRevoke = rawValue["pendingRevoke"] as? Bool ?? false
        yieldingToInferredLoan = rawValue["yieldingToInferredLoan"] as? Bool ?? false
        holdRenewedAt = rawValue["holdRenewedAt"] as? Date
        holdLapseNoticedAt = rawValue["holdLapseNoticedAt"] as? Date
        watchSilenceWarningsIssued = rawValue["watchSilenceWarningsIssued"] as? Int ?? 0
        watchSupportsSeize = rawValue["watchSupportsSeize"] as? Bool ?? false
        seizeToken = (rawValue["seizeToken"] as? String).flatMap(UUID.init(uuidString:))
        if let a = rawValue["audit"] as? [String: Any] {
            audit.loanStartedAt = a["loanStartedAt"] as? Date
            audit.deliveredAtGrant = a["deliveredAtGrant"] as? Double
            audit.deliveredAtTakeover = a["deliveredAtTakeover"] as? Double
            if let units = a["baseUnits"] as? Double, let asOf = a["baseAsOf"] as? Date {
                audit.base = .init(units: units, asOf: asOf)
            }
            audit.baseEpoch = a["baseEpoch"] as? Int
            audit.checkpoints = a["checkpoints"] as? Int ?? 0
        }
        pendingForceAudit = (rawValue["pendingForceAudit"] as? [String: Any]).flatMap(Self.forceAudit(from:))
        gapBooking = (rawValue["gapBooking"] as? [String: Any]).flatMap(Self.gapBooking(from:))
    }

    var rawValue: [String: Any] {
        var raw: [String: Any] = ["phase": phase.rawValue, "epoch": epoch, "committedCursor": committedCursor,
                                  "committedIDs": committedIDs.map(\.uuidString), "pendingRevoke": pendingRevoke,
                                  "yieldingToInferredLoan": yieldingToInferredLoan,
                                  "watchSilenceWarningsIssued": watchSilenceWarningsIssued,
                                  "watchSupportsSeize": watchSupportsSeize]
        raw["seizeToken"] = seizeToken?.uuidString
        raw["holdRenewedAt"] = holdRenewedAt
        raw["holdLapseNoticedAt"] = holdLapseNoticedAt
        var a: [String: Any] = ["checkpoints": audit.checkpoints]
        a["loanStartedAt"] = audit.loanStartedAt
        a["deliveredAtGrant"] = audit.deliveredAtGrant
        a["deliveredAtTakeover"] = audit.deliveredAtTakeover
        a["baseUnits"] = audit.base?.units
        a["baseAsOf"] = audit.base?.asOf
        a["baseEpoch"] = audit.baseEpoch
        raw["audit"] = a
        raw["pendingForceAudit"] = pendingForceAudit.map {
            ["epoch": $0.epoch, "atStart": $0.deliveredAtStart, "expected": $0.expected, "loanMinutes": $0.loanMinutes]
        }
        raw["gapBooking"] = gapBooking.map {
            var d: [String: Any] = ["epoch": $0.epoch, "units": $0.units, "deleteFailedAfterRecords": $0.deleteFailedAfterRecords]
            d["bookedAt"] = $0.bookedAt?.timeIntervalSince1970
            return d
        }
        return raw
    }

    /// Dictionary shapes in the state file.
    static func forceAudit(from d: [String: Any]) -> ForceAudit? {
        guard let e = d["epoch"] as? Int, let atStart = d["atStart"] as? Double,
              let expected = d["expected"] as? Double, let minutes = d["loanMinutes"] as? Double else { return nil }
        return ForceAudit(epoch: e, deliveredAtStart: atStart, expected: expected, loanMinutes: minutes)
    }

    static func gapBooking(from d: [String: Any]) -> GapBooking? {
        guard let e = d["epoch"] as? Int, let units = d["units"] as? Double else { return nil }
        return GapBooking(epoch: e, units: units, bookedAt: (d["bookedAt"] as? TimeInterval).map(Date.init(timeIntervalSince1970:)),
                          deleteFailedAfterRecords: d["deleteFailedAfterRecords"] as? Bool ?? false)
    }
}

extension PodLoanPhoneController {
    static let stateFileKey = "PodLoanPhoneState"

    /// The persisted state, readable from any queue.
    var persisted: PodLoanPhoneState {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _persisted
    }

    /// The loan phase. Every route back to `.owner` opens the settle window before observers hear of it.
    var state: State {
        get { persisted.phase }
        set {
            let old = persisted.phase
            updateState { $0.phase = newValue }
            stateDidChange(from: old)
        }
    }

    /// The phase's side effects, for a group write that changed it.
    func stateDidChange(from oldValue: State) {
        guard oldValue != state else { return }
        if oldValue != .owner, state == .owner {
            beginReclaimSettleWindow()
        }
        syncUIMirror()
        deps.ownershipDidChange()
    }

    var epoch: Int {
        get { persisted.epoch }
        set { updateState { $0.epoch = newValue } }
    }

    var committedCursor: Int {
        get { persisted.committedCursor }
        set { updateState { $0.committedCursor = newValue } }
    }

    var committedIDs: Set<UUID> {
        get { persisted.committedIDs }
        set { updateState { $0.committedIDs = newValue } }
    }

    var pendingRevoke: Bool {
        get { persisted.pendingRevoke }
        set { updateState { $0.pendingRevoke = newValue } }
    }

    var yieldingToInferredLoan: Bool {
        get { persisted.yieldingToInferredLoan }
        set { updateState { $0.yieldingToInferredLoan = newValue } }
    }

    /// Start of the current loan's audit window.
    var loanStartedAt: Date? {
        get { persisted.audit.loanStartedAt }
        set { updateState { $0.audit.loanStartedAt = newValue } }
    }

    /// Tagged with the epoch it is set under, so a base can never be adopted by another loan.
    var auditBase: AuditBase? {
        get { persisted.audit.base }
        set {
            let owner = epoch
            updateState { $0.audit.base = newValue; $0.audit.baseEpoch = owner }
        }
    }

    var checkpointsThisLoan: Int {
        get { persisted.audit.checkpoints }
        set { updateState { $0.audit.checkpoints = newValue } }
    }

    /// Applies one change and writes the whole value once, before returning.
    func updateState(_ change: (inout PodLoanPhoneState) -> Void) {
        stateLock.lock()
        defer { stateLock.unlock() }
        change(&_persisted)
        stateStore.wrappedValue = _persisted.rawValue
    }
}
