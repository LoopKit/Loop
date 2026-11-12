//
//  LoanReconciler.swift
//  Loop
//
//  Two pure calculations behind a hand-back: `reconcile` turns drained records into writes;
//  `expectedInsulin` predicts the pod's odometer over a window: temps in whole pulses, the schedule
//  continuously.
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

        /// False for an interim drain: records still running at the stamp are held back.
        var isFinalHandback: Bool = true
    }

    /// Both identities: the phone may only match on start date and grams.
    struct DeletedCarb: Equatable {
        let syncIdentifier: String?
        let startDate: Date
        let grams: Double

        /// As swipe-to-delete does: by identity where both have one, else start date and grams.
        func matches(_ entry: StoredCarbEntry) -> Bool {
            if let id = syncIdentifier, let entryID = entry.syncIdentifier { return id == entryID }
            return abs(entry.startDate.timeIntervalSince(startDate)) < 1
                && abs(entry.quantity.doubleValue(for: .gram) - grams) < 0.01
        }
    }


    struct Outcome: Equatable {
        /// The caller drops any record whose end precedes its start.
        var doses: [DoseEntry] = []

        /// On an interim drain, the records not finished yet: a rate record still running and any
        /// bolus still being given. Acked but not committed, and absent from `doses`: each is written
        /// once, finished, by a later drain. A final drain leaves none.
        var openEventIDs: Set<UUID> = []

        /// Each under its journal event's ID as its sync identifier, the identity the watch stored it under.
        var carbs: [NewCarbEntry] = []

        /// Never a carb this same drain added; that pair cancels.
        var deletedCarbs: [DeletedCarb] = []

        /// Every override change in the drain, in the wrist's order, so each one reaches the
        /// phone's override history: stock applies past overrides to past dosing.
        var overrideChanges: [OverrideChange] = []
    }

    /// `.cleared` is a deliberate change, not missing information. `at`: when the wrist made it.
    enum OverrideChange: Equatable {
        case set(TemporaryScheduleOverride, at: Date)
        case cleared(at: Date)
    }

    /// Events are processed in the order given; carbs and overrides depend on it. Every dose
    /// written is finished and immutable: the phone's stores never hold a loan dose that a later
    /// record must replace.
    static func reconcile(_ input: Input) -> Outcome {
        var outcome = Outcome()
        let events = input.events

        // A rate record runs until the next one starts, as `expectedInsulin` reads them: a zero-length
        // record is a cancel or a resume, and ends what was running.
        let rates = events
            .filter { e in
                switch e.record.kind {
                case .tempBasal, .suspend: return e.record.unitsPerHour != nil && e.record.endDate != nil
                default: return false
                }
            }
            .sorted { ($0.record.startDate, $0.seq) < ($1.record.startDate, $1.seq) }
        var rateEnd: [UUID: Date] = [:]
        for (index, event) in rates.enumerated() {
            var end = event.record.endDate ?? event.record.startDate
            if index + 1 < rates.count { end = Swift.min(end, rates[index + 1].record.startDate) }
            rateEnd[event.id] = end
        }

        // Not finished at the stamp: held back on an interim drain; cut at the stamp on a final one.
        func isRunning(_ event: LoanEvent) -> Bool {
            switch event.record.kind {
            case .bolus: return (event.record.endDate ?? event.record.startDate) > input.loanEnd
            case .tempBasal, .suspend: return rateEnd[event.id].map { $0 > input.loanEnd } ?? false
            default: return false
            }
        }
        if !input.isFinalHandback {
            outcome.openEventIDs = Set(events.filter(isRunning).map(\.id))
        }

        for event in events {
            if outcome.openEventIDs.contains(event.id) { continue }
            switch event.record.kind {
            case .bolus:
                if let units = event.record.amount {
                    // A bolus still being given when the loan ends counts whole, ending at the stamp.
                    let end = Swift.max(event.record.startDate,
                                        Swift.min(event.record.endDate ?? event.record.startDate, input.loanEnd))
                    outcome.doses.append(DoseEntry(
                        type: .bolus,
                        startDate: event.record.startDate,
                        endDate: end,
                        value: units, unit: .units,
                        doseId: event.record.doseId,
                        syncIdentifier: syncIdentifier(for: event),
                        automatic: event.record.automatic))
                }
            case .tempBasal, .suspend:
                if let rate = event.record.unitsPerHour, let end = rateEnd[event.id] {
                    outcome.doses.append(DoseEntry(
                        type: .tempBasal,
                        startDate: event.record.startDate,
                        endDate: Swift.min(end, input.loanEnd),
                        value: rate, unit: .unitsPerHour,
                        doseId: event.record.doseId,
                        syncIdentifier: syncIdentifier(for: event)))
                }
            case .carb:
                if let grams = event.record.amount {
                    outcome.carbs.append(NewCarbEntry(
                        date: event.record.userCreatedDate ?? Date(),
                        syncIdentifier: event.id.uuidString,
                        quantity: LoopQuantity(unit: .gram, doubleValue: grams),
                        startDate: event.record.startDate,
                        foodType: event.record.note,
                        absorptionTime: event.record.absorptionTime))
                }
            // Added and deleted in the same drain: cancels (seq order makes that safe).
            case .carbDeleted:

                if let grams = event.record.amount {
                    let start = event.record.startDate
                    let before = outcome.carbs.count
                    outcome.carbs.removeAll { $0.startDate == start && $0.quantity.doubleValue(for: .gram) == grams }
                    guard outcome.carbs.count == before else { break }
                    outcome.deletedCarbs.append(DeletedCarb(
                        syncIdentifier: event.record.syncIdentifier,
                        startDate: start,
                        grams: grams))
                }
            // In order; an undecodable one changes nothing.
            case .overrideChange:

                if event.record.overrideChangeIsClear {
                    outcome.overrideChanges.append(.cleared(at: event.record.startDate))
                } else if let override = event.record.overrideChangePayload {
                    outcome.overrideChanges.append(.set(override, at: event.record.startDate))
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

    /// What the pump's delivered total rose by between two readings, less what `records` and the
    /// schedule explain. Positive: the pump delivered insulin the records do not hold. Boluses still
    /// delivering are pro-rated. Milli-unit quantized.
    static func insulinNotInRecords(totalThen: Double, then: Date, totalNow: Double, now: Date,
                                    records: [LoanDoseRecord], schedule: BasalRateSchedule?, pulseUnits: Double) -> Double {
        // Synthetic events; only their order matters.
        let rateEvents = records.filter { $0.kind != .bolus }.enumerated().map {
            LoanEvent(id: UUID(), seq: $0.offset + 1, provenance: .confirmed, record: $0.element, loggedAt: now)
        }
        var expected = expectedInsulin(events: rateEvents, schedule: schedule, pulseUnits: pulseUnits, from: then, to: now)
        for bolus in records where bolus.kind == .bolus {
            guard let amount = bolus.amount, amount > 0 else { continue }
            let end = bolus.endDate ?? bolus.startDate
            if end > bolus.startDate {
                let overlap = min(end, now).timeIntervalSince(max(bolus.startDate, then))
                if overlap > 0 { expected += amount * overlap / end.timeIntervalSince(bolus.startDate) }
            } else if bolus.startDate >= then, bolus.startDate <= now {
                expected += amount
            }
        }
        return ((totalNow - totalThen - expected) * 1000).rounded() / 1000
    }

    /// Insulin the records say the pump delivered between two instants, in whole `pulseUnits`.
    /// `schedule` fills gaps (nil: journaled only); `includingBolusesAtEnd` is false at a mid-loan reading.
    static func expectedInsulin(events: [LoanEvent], schedule: BasalRateSchedule?, pulseUnits: Double,
                                from start: Date, to end: Date, includingBolusesAtEnd: Bool = true) -> Double {
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
                      let segEnd = event.record.endDate, segEnd >= event.record.startDate else { continue }
                // On the record's own span: a zero-length record is a cancel and must truncate its temp
                // even when it falls just before the window (a mid-loan odometer is read a second
                // after the cancel; clipping first dropped it — false OPEN LOOP 2026-09-05, 9b19f160).
                segments.append(Segment(start: event.record.startDate, end: segEnd, rate: rate))
            default:
                break
            }
        }

        // Each rate record supersedes what was running; resolved unclipped, then clipped to the window.
        segments.sort { $0.start < $1.start }
        var unclipped: [Segment] = []
        for seg in segments {
            while let last = unclipped.last, last.end > seg.start {
                let trimmed = Segment(start: last.start, end: seg.start, rate: last.rate)
                unclipped.removeLast()
                if trimmed.end > trimmed.start { unclipped.append(trimmed) }
            }
            unclipped.append(seg)
        }
        let resolved: [Segment] = unclipped.compactMap { seg in
            let s = max(seg.start, start), e = min(seg.end, end)
            return e > s ? Segment(start: s, end: e, rate: seg.rate) : nil
        }

        for seg in resolved {
            total += pulsedInsulin(rate: seg.rate, seconds: seg.end.timeIntervalSince(seg.start), pulseUnits: pulseUnits)
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

    /// Whole pulses: a temp starts its own pulse clock (its first pulse one full interval in), so rate × time
    /// over-counts it.
    private static func pulsedInsulin(rate: Double, seconds: TimeInterval, pulseUnits: Double) -> Double {
        guard rate > 0, seconds > 0 else { return 0 }
        let pulseInterval = 3600.0 * pulseUnits / rate
        let pulses = (seconds / pulseInterval).rounded(.down)
        return pulses * pulseUnits
    }

    /// Rate × time, not whole pulses: the pod runs its schedule on an ongoing grid whose phase the records
    /// don't carry, so a stretch of schedule delivers the floor or one pulse more. Flooring it under-counted
    /// by about half a pulse per stretch and per schedule item (false OPEN LOOPs on long loans, 2026-10-05/06);
    /// rate × time is unbiased (Monte Carlo 2026-10-08: mean 0.000 U, p95 within 0.15 U at 6 h).
    private static func scheduleInsulin(_ schedule: BasalRateSchedule, from: Date, to: Date) -> Double {
        return schedule.between(start: from, end: to).reduce(0) { partial, item in
            let s = max(item.startDate, from)
            let e = min(item.endDate, to)
            guard e > s else { return partial }
            return partial + item.value * e.timeIntervalSince(s) / 3600
        }
    }
}
