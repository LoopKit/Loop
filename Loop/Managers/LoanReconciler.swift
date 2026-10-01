//
//  LoanReconciler.swift
//  Loop
//
//  Two pure calculations behind a hand-back: `reconcile` turns drained records into writes;
//  `expectedInsulin` says what the pod should have delivered over a window, in whole pulses.
//

import Foundation
import LoopCore
import LoopAlgorithm
import HealthKit
import LoopKit

enum LoanReconciler {
    struct Input {
        /// Uncommitted staged events, or a stale offer's own events.
        let events: [LoanEvent]

        let schedule: BasalRateSchedule?

        let loanStart: Date
        /// The hand-back stamp; a final drain cuts running rate records here.
        let loanEnd: Date

        /// False for an interim drain, whose newest rate record is still open.
        var isFinalHandback: Bool = true
    }

    /// Both identities: the phone may only match on start date and grams.
    struct DeletedCarb: Equatable {
        let syncIdentifier: String?
        let startDate: Date
        let grams: Double
    }

    /// The event ID is the carb's sync identifier; the store would otherwise mint a new one.
    struct IdentifiedCarb: Equatable {
        let eventID: UUID
        let entry: NewCarbEntry
    }

    struct Outcome: Equatable {
        /// The caller drops any record whose end precedes its start.
        var doses: [DoseEntry] = []

        /// The still-running rate record on an interim drain: acked but not committed, so it lands
        /// finished at the end.
        var openEventID: UUID? = nil

        var carbs: [IdentifiedCarb] = []

        /// Never a carb this same drain added; that pair cancels.
        var deletedCarbs: [DeletedCarb] = []

        /// At most one, because only the last override change in a drain survives.
        var overrideChange: OverrideChange?
    }

    /// `.cleared` is a deliberate change, not missing information.
    enum OverrideChange: Equatable {
        case set(TemporaryScheduleOverride)
        case cleared
    }

    /// Events are processed in the order given; carbs and overrides depend on it.
    static func reconcile(_ input: Input) -> Outcome {
        var outcome = Outcome()
        var events = input.events

        // The open rate record: the latest temp or suspend running past the stamp.
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
                        syncIdentifier: syncIdentifier(for: event),
                        automatic: event.record.automatic))
                }
            case .tempBasal, .suspend:

                if event.id == openEventID { continue }
                if let rate = event.record.unitsPerHour, let end = event.record.endDate {
                    // A final drain cuts anything still running at the hand-back.
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
            // Added and deleted in the same drain: cancels (seq order makes that safe).
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
            // The last override change wins; an undecodable one changes nothing.
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

    /// The pump's own identifier where there is one, else one derived from the event ID.
    static func syncIdentifier(for event: LoanEvent) -> String {
        return event.record.syncIdentifier ?? "loanv2-\(event.id.uuidString)"
    }

    /// Insulin the records say the pod delivered between two instants. `schedule` fills gaps (nil:
    /// journaled only); `includingBolusesAtEnd` is false at an interior checkpoint.
    static func expectedInsulin(events: [LoanEvent], schedule: BasalRateSchedule?, from start: Date, to end: Date,
                                includingBolusesAtEnd: Bool = true) -> Double {
        guard end > start else { return 0 }

        var total: Double = 0

        // Boluses count whole, at their start.
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

                // `>=`: a zero-length record is a cancel and must truncate its temp.
                if e >= s { segments.append(Segment(start: s, end: e, rate: rate)) }
            default:
                break
            }
        }

        // Each rate record supersedes what was running.
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

        // Gaps are the scheduled basal.
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

    /// Whole pulses: each new rate restarts the pod's pulse clock, so rate × time over-counts.
    private static func pulsedInsulin(rate: Double, seconds: TimeInterval) -> Double {
        guard rate > 0, seconds > 0 else { return 0 }
        let pulseInterval = 3600.0 * podPulseSize / rate
        let pulses = (seconds / pulseInterval).rounded(.down)
        return pulses * podPulseSize
    }

    /// The Omnipod's delivery increment.
    private static let podPulseSize: Double = 0.05

    /// Known gap: pulsed per schedule item, which can only make the expectation smaller.
    private static func scheduleInsulin(_ schedule: BasalRateSchedule, from: Date, to: Date) -> Double {
        return schedule.between(start: from, end: to).reduce(0) { partial, item in
            let s = max(item.startDate, from)
            let e = min(item.endDate, to)
            guard e > s else { return partial }
            return partial + pulsedInsulin(rate: item.value, seconds: e.timeIntervalSince(s))
        }
    }
}
