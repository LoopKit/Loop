//
//  LoanReconciler.swift
//  Loop
//
//  The two pure calculations behind a hand-back.
//
//  `reconcile` turns the records the watch drained home into the doses, carbs and override
//  changes the phone should write. `expectedInsulin` answers the separate question every audit
//  asks: given those same records, how much insulin should the pod have delivered over a window?
//  Subtracting it from what the pod's own counter says is the residual the verdict turns on.
//
//  Both are static and take everything they need as arguments — no stores, no clock, no timers —
//  so the ordering and boundary rules below can be tested directly.
//
//  The expectation is modelled in whole pod pulses, never rate × time; see `pulsedInsulin`.
//

import Foundation
import LoopCore
import LoopAlgorithm
import HealthKit
import LoopKit

enum LoanReconciler {
    struct Input {
        /// What this drain should produce writes for — normally the staged events not yet in
        /// `committedIDs`, or that one offer's own events when it speaks for a closed loan.
        let events: [LoanEvent]

        let schedule: BasalRateSchedule?

        let loanStart: Date
        /// The instant the watch stamped this hand-back. On a final drain it is also where
        /// still-running rate records are cut, so nothing the watch programmed outlives the
        /// moment it gave the pod back.
        let loanEnd: Date

        /// False for an interim drain — the watch is still dosing and its newest rate record is
        /// still open. That distinction decides both the clamping above and `openEventID`.
        var isFinalHandback: Bool = true
    }

    /// A carb the wrist deleted that the phone already holds. Carries both identities because
    /// the phone may never have seen the wrist's syncIdentifier: the fallback is a match on
    /// start date and grams.
    struct DeletedCarb: Equatable {
        let syncIdentifier: String?
        let startDate: Date
        let grams: Double
    }

    /// A carb entry paired with the loan event that produced it. `NewCarbEntry` carries no
    /// identity of its own and the carb store mints a fresh one per add, so the event ID is what
    /// the phone passes as the sync identifier — the only thing standing between a resend and a
    /// duplicate meal.
    struct IdentifiedCarb: Equatable {
        let eventID: UUID
        let entry: NewCarbEntry
    }

    struct Outcome: Equatable {
        /// Ready to write, except for the sanity check the caller applies: a record whose end
        /// precedes its start is dropped individually rather than failing the batch.
        var doses: [DoseEntry] = []

        /// On an interim drain, the rate record the watch is still running. It is deliberately
        /// absent from `doses`: the caller acks it (which releases the watch's finalize gate)
        /// but does not commit it, so it drains again at the end and lands clamped and finished.
        /// Committing it early would freeze a dose that is still being delivered and lose the
        /// rest of it from IOB.
        var openEventID: UUID? = nil

        var carbs: [IdentifiedCarb] = []

        /// Deletes the phone must apply to entries it already holds. Never includes a carb that
        /// this same drain added — that pair cancels instead.
        var deletedCarbs: [DeletedCarb] = []

        /// At most one, because only the last override change in a drain survives.
        var overrideChange: OverrideChange?
    }

    /// `.cleared` means the user turned the override off on the wrist — it is a deliberate
    /// change the phone must follow, not the absence of information.
    enum OverrideChange: Equatable {
        case set(TemporaryScheduleOverride)
        case cleared
    }

    /// Maps one drain of watch records onto what the phone should do with them. Events are
    /// processed in the order given, and that order is load-bearing for carbs and overrides.
    static func reconcile(_ input: Input) -> Outcome {
        var outcome = Outcome()
        var events = input.events

        // The still-open rate record on an interim drain: the latest-starting temp or suspend
        // that runs past the hand-back stamp. A final drain has none by definition.
        let openEventID: UUID? = input.isFinalHandback ? nil : events
            .filter { e in
                switch e.record.kind {
                case .tempBasal, .suspend:
                    return (e.record.endDate ?? e.record.startDate) > input.loanEnd
                default:
                    return false
                }
            }
            .max(by: { $0.record.startDate < $1.record.startDate })?.id
        outcome.openEventID = openEventID

        for event in events {
            switch event.record.kind {
            case .bolus:
                if let units = event.record.amount {
                    outcome.doses.append(DoseEntry(
                        type: .bolus,
                        startDate: event.record.startDate,
                        endDate: event.record.endDate ?? event.record.startDate,
                        value: units, unit: .units,
                        decisionId: nil,
                        syncIdentifier: syncIdentifier(for: event)))
                }
            case .tempBasal, .suspend:

                if event.id == openEventID { continue }
                if let rate = event.record.unitsPerHour, let end = event.record.endDate {
                    // A final drain cuts anything still running at the hand-back: past that
                    // instant the watch no longer owns the pod, so it cannot claim delivery.
                    let clampedEnd = input.isFinalHandback ? Swift.min(end, input.loanEnd) : end
                    outcome.doses.append(DoseEntry(
                        type: .tempBasal,
                        startDate: event.record.startDate,
                        endDate: clampedEnd,
                        value: rate, unit: .unitsPerHour,
                        decisionId: nil,
                        syncIdentifier: syncIdentifier(for: event)))
                }
            case .carb:
                if let grams = event.record.amount {
                    outcome.carbs.append(IdentifiedCarb(
                        eventID: event.id,
                        entry: NewCarbEntry(
                            quantity: LoopQuantity(unit: .gram, doubleValue: grams),
                            startDate: event.record.startDate,
                            foodType: nil,
                            absorptionTime: event.record.absorptionTime)))
                }
            // A carb added and then deleted within the same drain CANCELS: it is dropped from
            // the batch and no delete is reported. The phone never minted an identity for it,
            // so a delete sent home would find nothing to match and the carb would survive.
            // Seq order is what makes the cancellation safe.
            case .carbDeleted:

                if let grams = event.record.amount {
                    let start = event.record.startDate
                    let before = outcome.carbs.count
                    outcome.carbs.removeAll { $0.entry.startDate == start && $0.entry.quantity.doubleValue(for: .gram) == grams }
                    guard outcome.carbs.count == before else { break }
                    outcome.deletedCarbs.append(DeletedCarb(
                        syncIdentifier: event.record.syncIdentifier,
                        startDate: start,
                        grams: grams))
                }
            // The LAST override change in the drain wins, so a set-then-clear pair lands as
            // cleared. A payload that will not decode falls through both arms and changes
            // nothing — it must never be read as a clear, which would cancel an override the
            // user is relying on.
            case .overrideChange:

                if event.record.overrideChangeIsClear {
                    outcome.overrideChange = .cleared
                } else if let override = event.record.overrideChangePayload {
                    outcome.overrideChange = .set(override)
                }

                break
            }
        }

        return outcome
    }

    /// The identity the phone's stores will know this record by. Records minted from real pump
    /// history carry the pump's own identifier; anything else gets a stable one derived from the
    /// event ID, so a resend of the same event still dedups.
    static func syncIdentifier(for event: LoanEvent) -> String {
        return event.record.syncIdentifier ?? "loanv2-\(event.id.uuidString)"
    }

    /// How much insulin these records say the pod should have delivered between two instants.
    /// The counterpart to the pod's own delivery counter; the difference is the residual.
    ///
    /// - Parameter schedule: the basal profile to fill gaps between rate records with. Passing
    ///   nil counts only journaled insulin, which is deliberately conservative: a smaller
    ///   expectation pushes the residual positive, the direction that errs toward noticing
    ///   insulin we cannot account for rather than missing it.
    /// - Parameter includingBolusesAtEnd: false at an INTERIOR checkpoint boundary, where a
    ///   bolus stamped exactly at the boundary belongs to the next window — delivery takes
    ///   roughly forty seconds per unit, so the counter read at that instant has metered none of
    ///   it. At the final endpoint it must be true, or the last bolus is dropped and the loan
    ///   closes on a residual that looks like unexplained delivery.
    static func expectedInsulin(events: [LoanEvent], schedule: BasalRateSchedule?, from start: Date, to end: Date,
                                includingBolusesAtEnd: Bool = true) -> Double {
        guard end > start else { return 0 }

        var total: Double = 0

        // Boluses count whole, at their start: they are programmed as one command and the
        // counter picks them up as they run.
        for event in events where event.record.kind == .bolus {
            guard event.record.startDate >= start else { continue }
            guard includingBolusesAtEnd ? event.record.startDate <= end
                                        : event.record.startDate < end else { continue }
            total += event.record.amount ?? 0
        }

        struct Segment { let start: Date; let end: Date; let rate: Double }
        var segments: [Segment] = []
        for event in events {
            switch event.record.kind {
            case .tempBasal, .suspend:
                guard let rate = event.record.unitsPerHour,
                      let segEnd = event.record.endDate else { continue }
                let s = max(event.record.startDate, start)
                let e = min(segEnd, end)

                // `>=`, not `>`: a zero-duration rate record is a CANCEL, and it has to reach
                // the resolution below to truncate the temp it cancelled. Dropped here, the
                // cancelled temp stays standing for its whole programmed window and the
                // expectation runs far above what the pod actually delivered.
                if e >= s { segments.append(Segment(start: s, end: e, rate: rate)) }
            default:
                break
            }
        }

        // Resolution: each record supersedes whatever was running, so earlier segments are
        // trimmed back to the newer one's start. This is what a stack of overlapping temps
        // actually did on the pod, rather than the sum of what each one asked for.
        segments.sort { $0.start < $1.start }
        var resolved: [Segment] = []
        for seg in segments {
            while let last = resolved.last, last.end > seg.start {
                let trimmed = Segment(start: last.start, end: seg.start, rate: last.rate)
                resolved.removeLast()
                if trimmed.end > trimmed.start { resolved.append(trimmed) }
            }
            resolved.append(seg)
        }

        for seg in resolved {
            total += pulsedInsulin(rate: seg.rate, seconds: seg.end.timeIntervalSince(seg.start))
        }

        // Fill the gaps between rate records with the scheduled basal: whenever no temp was
        // running the pod was delivering the profile, and the counter includes it.
        if let schedule = schedule {
            var cursor = start
            for seg in resolved {
                if seg.start > cursor {
                    total += scheduleInsulin(schedule, from: cursor, to: seg.start)
                }
                cursor = max(cursor, seg.end)
            }
            if end > cursor {
                total += scheduleInsulin(schedule, from: cursor, to: end)
            }
        }

        return total
    }

    /// Whole pulses only — `rate × time` is not what the pod delivers. The pod doses in discrete
    /// increments and every new rate command restarts its pulse clock, so each short temp loses
    /// whatever fraction of a pulse was still pending. That loss is systematic, always in the
    /// same direction, and on a long loan of five-minute temps it accumulates to enough pure
    /// artifact to drive the residual negative and warn of phantom insulin on a healthy session.
    private static func pulsedInsulin(rate: Double, seconds: TimeInterval) -> Double {
        guard rate > 0, seconds > 0 else { return 0 }
        let pulseInterval = 3600.0 * podPulseSize / rate
        let pulses = (seconds / pulseInterval).rounded(.down)
        return pulses * podPulseSize
    }

    /// The Omnipod's delivery increment.
    private static let podPulseSize: Double = 0.05

    /// Known gap: a gap that spans a schedule-item boundary is pulsed per item, while the pod
    /// does not restart its clock there. Immaterial on a flat profile, and it can only make the
    /// expectation smaller, which is the conservative direction.
    private static func scheduleInsulin(_ schedule: BasalRateSchedule, from: Date, to: Date) -> Double {
        return schedule.between(start: from, end: to).reduce(0) { partial, item in
            let s = max(item.startDate, from)
            let e = min(item.endDate, to)
            guard e > s else { return partial }
            return partial + pulsedInsulin(rate: item.value, seconds: e.timeIntervalSince(s))
        }
    }
}
