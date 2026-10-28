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
    /// Standing aside for a loan this phone never granted; survives a phone reboot.
    var yieldingToInferredLoan = false

    /// When the watch last reported a cycle, so a relaunch is not read as silence.
    var holdRenewedAt: Date?
    /// When this phone last took control on silence (a query unanswered); a revived watch's claim to a
    /// loan started before it is refused.
    var tookOverOnSilenceAt: Date?

    /// The watch has asked for a loan at least once; no standing copy goes to a watch that never has.
    var watchUsesSportMode = false
    /// Minted once and echoed by a watch that started alone: this phone's reunion credential.
    var seizeToken: UUID?

    /// When the current loan began; for the loan minutes in the log.
    var loanStartedAt: Date?

    /// A force-reclaim verdict still owed; re-armed at launch.
    struct ForceAudit: Equatable {
        let epoch: Int
        /// The window: the pod's total at the watch's takeover, and when.
        let deliveredAtStart: Double
        let from: Date
        let expected: Double
        let loanMinutes: Double
    }
    var pendingForceAudit: ForceAudit?

    /// The insulin ledger: the pod's total at the last reading, and the estimates standing in the dose
    /// store. Each reading at a change of custody ends one window and starts the next.
    struct Ledger: Equatable {
        struct Reading: Equatable {
            let units: Double
            let at: Date
        }
        /// The open window's start.
        var last: Reading?

        /// A bolus standing in for insulin the records could not explain over `window`; retired by
        /// late records of that window.
        struct Booking: Equatable {
            let sync: String
            let units: Double
            let bookedAt: Date
            let window: DateInterval
            var deleteFailed = false
        }
        var bookings: [Booking] = []
    }
    var ledger = Ledger()

    init() {}

    init?(rawValue: [String: Any]) {
        phase = (rawValue["phase"] as? String).flatMap(PodLoanPhoneController.State.init(rawValue:)) ?? .owner
        epoch = rawValue["epoch"] as? Int ?? 0
        committedCursor = rawValue["committedCursor"] as? Int ?? 0
        committedIDs = Set((rawValue["committedIDs"] as? [String] ?? []).compactMap(UUID.init(uuidString:)))
        yieldingToInferredLoan = rawValue["yieldingToInferredLoan"] as? Bool ?? false
        holdRenewedAt = rawValue["holdRenewedAt"] as? Date
        tookOverOnSilenceAt = rawValue["tookOverOnSilenceAt"] as? Date
        watchUsesSportMode = rawValue["watchUsesSportMode"] as? Bool ?? false
        seizeToken = (rawValue["seizeToken"] as? String).flatMap(UUID.init(uuidString:))
        loanStartedAt = rawValue["loanStartedAt"] as? Date
        pendingForceAudit = (rawValue["pendingForceAudit"] as? [String: Any]).flatMap(Self.forceAudit(from:))
        if let l = rawValue["ledger"] as? [String: Any] {
            if let units = l["lastUnits"] as? Double, let at = l["lastAt"] as? Date {
                ledger.last = .init(units: units, at: at)
            }
            ledger.bookings = (l["bookings"] as? [[String: Any]] ?? []).compactMap(Self.booking(from:))
        }
    }

    var rawValue: [String: Any] {
        var raw: [String: Any] = ["phase": phase.rawValue, "epoch": epoch, "committedCursor": committedCursor,
                                  "committedIDs": committedIDs.map(\.uuidString),
                                  "yieldingToInferredLoan": yieldingToInferredLoan,
                                  "watchUsesSportMode": watchUsesSportMode]
        raw["seizeToken"] = seizeToken?.uuidString
        raw["holdRenewedAt"] = holdRenewedAt
        raw["tookOverOnSilenceAt"] = tookOverOnSilenceAt
        raw["loanStartedAt"] = loanStartedAt
        raw["pendingForceAudit"] = pendingForceAudit.map {
            ["epoch": $0.epoch, "atStart": $0.deliveredAtStart, "from": $0.from, "expected": $0.expected, "loanMinutes": $0.loanMinutes]
        }
        var l: [String: Any] = ["bookings": ledger.bookings.map { b -> [String: Any] in
            ["sync": b.sync, "units": b.units, "bookedAt": b.bookedAt, "from": b.window.start, "to": b.window.end,
             "deleteFailed": b.deleteFailed]
        }]
        l["lastUnits"] = ledger.last?.units
        l["lastAt"] = ledger.last?.at
        raw["ledger"] = l
        return raw
    }

    /// Dictionary shapes in the state file.
    static func forceAudit(from d: [String: Any]) -> ForceAudit? {
        guard let e = d["epoch"] as? Int, let atStart = d["atStart"] as? Double, let from = d["from"] as? Date,
              let expected = d["expected"] as? Double, let minutes = d["loanMinutes"] as? Double else { return nil }
        return ForceAudit(epoch: e, deliveredAtStart: atStart, from: from, expected: expected, loanMinutes: minutes)
    }

    static func booking(from d: [String: Any]) -> Ledger.Booking? {
        guard let sync = d["sync"] as? String, let units = d["units"] as? Double, let bookedAt = d["bookedAt"] as? Date,
              let from = d["from"] as? Date, let to = d["to"] as? Date, to >= from else { return nil }
        return Ledger.Booking(sync: sync, units: units, bookedAt: bookedAt, window: DateInterval(start: from, end: to),
                              deleteFailed: d["deleteFailed"] as? Bool ?? false)
    }
}

extension PodLoanPhoneController {
    static let stateFileKey = "PodLoanPhoneState"

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
        // A question is about the situation it was asked in: a new state ends it, so the next loan
        // can be asked at once.
        watchAskedAt = nil
        if oldValue != .owner, state == .owner {
            beginReclaimSettleWindow()
        }
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

    var yieldingToInferredLoan: Bool {
        get { persisted.yieldingToInferredLoan }
        set { updateState { $0.yieldingToInferredLoan = newValue } }
    }

    /// When the current loan began.
    var loanStartedAt: Date? {
        get { persisted.loanStartedAt }
        set { updateState { $0.loanStartedAt = newValue } }
    }

    /// Applies one change and writes the whole value once, before returning.
    func updateState(_ change: (inout PodLoanPhoneState) -> Void) {
        change(&persisted)
        stateStore.wrappedValue = persisted.rawValue
    }
}
