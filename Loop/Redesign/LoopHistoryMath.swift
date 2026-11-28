//
//  LoopHistoryMath.swift
//  Loop
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Foundation

/// Pure calculations behind the Trends and Logbook screens. Nothing here touches a store.
enum LoopHistoryMath {

    // MARK: Glucose statistics

    struct GlucoseStats: Equatable {
        let count: Int
        let meanMgdl: Double
        let sdMgdl: Double
        /// Coefficient of variation, 0–1.
        let cv: Double
        /// Glucose management indicator, as a percentage (Bergenstal 2018).
        let gmiPercent: Double
        var gmiMmolMol: Double { (gmiPercent - 2.152) * 10.929 }
    }

    static func glucoseStats(_ points: [GlucosePoint]) -> GlucoseStats? {
        guard points.count >= 2 else { return nil }
        let values = points.map(\.mgdl)
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + pow($1 - mean, 2) } / Double(values.count - 1)
        let sd = variance.squareRoot()
        return GlucoseStats(count: values.count, meanMgdl: mean, sdMgdl: sd, cv: sd / mean, gmiPercent: 3.31 + 0.02392 * mean)
    }

    /// The share of the period with CGM readings, assuming one reading every 5 minutes.
    static func cgmActiveFraction(_ points: [GlucosePoint], over interval: DateInterval) -> Double {
        let expected = interval.duration / 300
        guard expected > 0 else { return 0 }
        return min(1, Double(points.count) / expected)
    }

    // MARK: Time in range

    enum RangeBand: Int, CaseIterable, Identifiable {
        case veryHigh, high, inRange, low, veryLow

        var id: Int { rawValue }

        var name: String {
            switch self {
            case .veryHigh: return NSLocalizedString("Very high", comment: "Time-in-range band name: glucose above 250 mg/dL (13.9 mmol/L)")
            case .high: return NSLocalizedString("High", comment: "Time-in-range band name: glucose 181–250 mg/dL (10.1–13.9 mmol/L)")
            case .inRange: return NSLocalizedString("In range", comment: "Time-in-range band name: glucose 70–180 mg/dL (3.9–10.0 mmol/L)")
            case .low: return NSLocalizedString("Low", comment: "Time-in-range band name: glucose 54–69 mg/dL (3.0–3.8 mmol/L)")
            case .veryLow: return NSLocalizedString("Very low", comment: "Time-in-range band name: glucose below 54 mg/dL (3.0 mmol/L)")
            }
        }

        /// Consensus thresholds, in the person's unit.
        /// Numbers go through the user's locale ("3,9–10,0" in German); the symbols are not words, so they stay in code.
        func thresholds(_ unit: GlucoseUnitStyle) -> String {
            let d = unit.isMmol ? 1 : 0
            func n(_ value: Double) -> String { LoopFormat.number(value, decimals: d) }
            switch (self, unit.isMmol) {
            case (.veryHigh, true): return "> " + n(13.9)
            case (.high, true): return n(10.1) + "–" + n(13.9)
            case (.inRange, true): return n(3.9) + "–" + n(10.0)
            case (.low, true): return n(3.0) + "–" + n(3.8)
            case (.veryLow, true): return "< " + n(3.0)
            case (.veryHigh, false): return "> " + n(250)
            case (.high, false): return n(181) + "–" + n(250)
            case (.inRange, false): return n(70) + "–" + n(180)
            case (.low, false): return n(54) + "–" + n(69)
            case (.veryLow, false): return "< " + n(54)
            }
        }

        static func band(for mgdl: Double) -> RangeBand {
            switch mgdl {
            case ..<54: return .veryLow
            case ..<70: return .low
            case ...180: return .inRange
            case ...250: return .high
            default: return .veryHigh
            }
        }
    }

    /// Fractions (0–1) per band, in ladder order. Empty input gives all zeros.
    static func timeInRange(_ points: [GlucosePoint]) -> [RangeBand: Double] {
        var counts: [RangeBand: Int] = [:]
        for point in points {
            counts[RangeBand.band(for: point.mgdl), default: 0] += 1
        }
        let total = Double(points.count)
        return Dictionary(uniqueKeysWithValues: RangeBand.allCases.map { band in
            (band, total > 0 ? Double(counts[band] ?? 0) / total : 0)
        })
    }

    /// Whole-number percentages that add up to 100 (largest remainder), so the labels never sum to 99 or 101.
    static func roundedPercentages(_ fractions: [RangeBand: Double]) -> [RangeBand: Int] {
        let raw = RangeBand.allCases.map { (band: $0, value: (fractions[$0] ?? 0) * 100) }
        let total = raw.reduce(0) { $0 + $1.value }
        guard total > 0 else { return Dictionary(uniqueKeysWithValues: RangeBand.allCases.map { ($0, 0) }) }
        var floors = raw.map { (band: $0.band, floor: Int($0.value.rounded(.down)), remainder: $0.value - $0.value.rounded(.down)) }
        var missing = Int(total.rounded()) - floors.reduce(0) { $0 + $1.floor }
        for index in floors.indices.sorted(by: { floors[$0].remainder > floors[$1].remainder }) where missing > 0 {
            floors[index].floor += 1
            missing -= 1
        }
        return Dictionary(uniqueKeysWithValues: floors.map { ($0.band, $0.floor) })
    }

    // MARK: AGP

    struct AGPSlot: Equatable {
        /// Minutes after midnight at the start of the slot.
        let minute: Int
        let p5: Double
        let p25: Double
        let p50: Double
        let p75: Double
        let p95: Double
    }

    /// Readings folded onto one day in `slotMinutes` slots, as mg/dL percentiles. Slots with fewer than 3 readings are skipped.
    static func agp(_ points: [GlucosePoint], slotMinutes: Int = 15, calendar: Calendar = .current) -> [AGPSlot] {
        var slots: [Int: [Double]] = [:]
        for point in points {
            let parts = calendar.dateComponents([.hour, .minute], from: point.date)
            let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            slots[minute / slotMinutes, default: []].append(point.mgdl)
        }
        return slots.keys.sorted().compactMap { key in
            let values = slots[key]!.sorted()
            guard values.count >= 3 else { return nil }
            return AGPSlot(minute: key * slotMinutes,
                           p5: percentile(values, 0.05), p25: percentile(values, 0.25), p50: percentile(values, 0.5),
                           p75: percentile(values, 0.75), p95: percentile(values, 0.95))
        }
    }

    /// Linear-interpolated percentile of sorted values.
    static func percentile(_ sorted: [Double], _ p: Double) -> Double {
        guard !sorted.isEmpty else { return .nan }
        let position = p * Double(sorted.count - 1)
        let lower = Int(position.rounded(.down)), upper = Int(position.rounded(.up))
        let weight = position - Double(lower)
        return sorted[lower] * (1 - weight) + sorted[upper] * weight
    }

    /// The number of distinct calendar days with readings.
    static func daysWithReadings(_ points: [GlucosePoint], calendar: Calendar = .current) -> Int {
        Set(points.map { calendar.startOfDay(for: $0.date) }).count
    }

    /// Whole days from the first reading to the end of `interval`, when that falls short of the period by more than a
    /// day; nil when the readings span the period, or there are none.
    static func cgmCoveredDays(_ points: [GlucosePoint], in interval: DateInterval, periodDays: Int) -> Int? {
        guard periodDays > 1, let first = points.map(\.date).min() else { return nil }
        let available = interval.end.timeIntervalSince(first) / 86400
        guard available + 1 < Double(periodDays) else { return nil }
        return max(1, Int(available.rounded()))
    }

    /// Units the schedule would deliver over `span`, or nil where the points don't cover all of it.
    static func scheduledUnits(_ points: [ScheduledBasalPoint], over span: DateInterval) -> Double? {
        var units = 0.0
        var covered: TimeInterval = 0
        for point in points {
            let overlap = min(point.end, span.end).timeIntervalSince(max(point.start, span.start))
            guard overlap > 0 else { continue }
            units += point.rate * overlap / 3600
            covered += overlap
        }
        return covered >= span.duration - 60 ? units : nil
    }

    // MARK: Days

    /// Midnight-to-midnight intervals covering `interval`, oldest first, the last one cut off at `interval.end`.
    static func days(in interval: DateInterval, calendar: Calendar = .current) -> [DateInterval] {
        var result: [DateInterval] = []
        var start = calendar.startOfDay(for: interval.start)
        while start < interval.end {
            guard let next = calendar.date(byAdding: .day, value: 1, to: start) else { break }
            result.append(DateInterval(start: max(start, interval.start), end: min(next, interval.end)))
            start = next
        }
        return result
    }

    struct DayTotal: Equatable, Identifiable {
        let day: Date
        let split: InsulinSplit
        /// False for a day still in progress, so its partial total doesn't pull per-day averages down.
        var isComplete = true
        var id: Date { day }
        var basal: Double { split.basal }
        var bolus: Double { split.bolus }
        var total: Double { split.total }

        init(day: Date, split: InsulinSplit, isComplete: Bool = true) {
            self.day = day
            self.split = split
            self.isComplete = isComplete
        }

        /// A total with no manual or automatic detail: all of its bolus counts as manual.
        init(day: Date, basal: Double, bolus: Double, isComplete: Bool = true) {
            self.init(day: day, split: InsulinSplit(basal: basal, manualBolus: bolus), isComplete: isComplete)
        }
    }

    /// The days per-day insulin figures average over: days with insulin, leaving out a day still in progress
    /// unless no complete day has any.
    static func averagingDays(_ totals: [DayTotal]) -> [DayTotal] {
        let recorded = totals.filter { $0.total > 0 }
        let complete = recorded.filter(\.isComplete)
        return complete.isEmpty ? recorded : complete
    }

    /// One source for the summary, legend and chart rule, before any weekly aggregation.
    static func averageDailyInsulin(_ totals: [DayTotal]) -> Double {
        let days = averagingDays(totals)
        guard !days.isEmpty else { return 0 }
        return days.reduce(0) { $0 + $1.total } / Double(days.count)
    }

    /// Averages daily totals by calendar week (Monday start), for periods past 30 days.
    static func weekly(_ totals: [DayTotal], calendar: Calendar = .current) -> [DayTotal] {
        var cal = calendar
        cal.firstWeekday = 2
        let groups = Dictionary(grouping: totals) { cal.dateInterval(of: .weekOfYear, for: $0.day)?.start ?? $0.day }
        return groups.keys.sorted().map { week in
            DayTotal(day: week, split: InsulinSplit.average(averagingDays(groups[week]!).map(\.split)))
        }
    }

    // MARK: Basal

    struct ScheduleValue {
        let start: Date
        let end: Date
        let rate: Double
    }

    /// A basal record from the pump: scheduled delivery, a temp basal or a suspend.
    struct BasalDelivery {
        let start: Date
        let end: Date
        /// U/h; 0 for a suspend.
        let rate: Double
        let kind: BasalSegment.Kind
        let automatic: Bool
    }

    /// Delivered basal over `window` from the pump's records (the latest-starting one wins where they overlap).
    ///
    /// From `recordsStart` on, time without a basal record counts at `programmedRates`, since that is what the pump
    /// delivers on its own; this matches Loop's own insulin totals (`InsulinDeliveryHistory`). Before it, or without
    /// it, gaps stay unknown.
    static func basalSegments(window: DateInterval, schedule: [ScheduleValue], deliveries temps: [BasalDelivery],
                              programmedRates: [ScheduleValue] = [], recordsStart: Date? = nil) -> [BasalSegment] {
        var cuts = Set<Date>([window.start, window.end])
        if let recordsStart, window.contains(recordsStart) { cuts.insert(recordsStart) }
        for value in schedule + programmedRates {
            if window.contains(value.start) { cuts.insert(value.start) }
            if window.contains(value.end) { cuts.insert(value.end) }
        }
        for temp in temps {
            if window.contains(temp.start) { cuts.insert(temp.start) }
            if window.contains(temp.end) { cuts.insert(temp.end) }
        }
        let sorted = cuts.sorted()
        let sortedTemps = temps.sorted { $0.start < $1.start }
        // The furthest end among records up to each index bounds the backward search, so a week of five-minute
        // records stays linear rather than scanning every record for every cut.
        var furthestEnd: [Date] = []
        furthestEnd.reserveCapacity(sortedTemps.count)
        for temp in sortedTemps { furthestEnd.append(max(furthestEnd.last ?? temp.end, temp.end)) }
        func latestRecord(covering mid: Date) -> BasalDelivery? {
            var low = 0, high = sortedTemps.count
            while low < high {
                let middle = (low + high) / 2
                if sortedTemps[middle].start <= mid { low = middle + 1 } else { high = middle }
            }
            var index = low - 1
            while index >= 0, furthestEnd[index] > mid {
                if mid < sortedTemps[index].end { return sortedTemps[index] }
                index -= 1
            }
            return nil
        }
        var segments: [BasalSegment] = []
        for (a, b) in zip(sorted, sorted.dropFirst()) where b > a {
            let mid = a.addingTimeInterval(b.timeIntervalSince(a) / 2)
            let scheduled = schedule.first { $0.start <= mid && mid < $0.end }?.rate
            let segment: BasalSegment
            if let temp = latestRecord(covering: mid) {
                segment = BasalSegment(start: a, end: b, rate: temp.kind == .suspended ? 0 : temp.rate, scheduledRate: scheduled,
                                       kind: temp.kind, automatic: temp.automatic)
            } else if let recordsStart, a >= recordsStart,
                      let programmed = programmedRates.first(where: { $0.start <= mid && mid < $0.end })?.rate {
                segment = BasalSegment(start: a, end: b, rate: programmed, scheduledRate: scheduled, kind: .scheduled, automatic: false)
            } else {
                continue
            }
            if let last = segments.last, last.end == segment.start, last.rate == segment.rate, last.kind == segment.kind,
               last.scheduledRate == segment.scheduledRate, last.automatic == segment.automatic {
                segments[segments.count - 1] = BasalSegment(start: last.start, end: segment.end, rate: last.rate,
                                                            scheduledRate: last.scheduledRate, kind: last.kind, automatic: last.automatic)
            } else {
                segments.append(segment)
            }
        }
        return segments
    }

    /// Basal rate at a moment, from delivered segments.
    static func basalRate(at date: Date, in segments: [BasalSegment]) -> BasalSegment? {
        segments.last { $0.start <= date && date < $0.end }
    }

    // MARK: Loop modes

    struct LoopRun {
        let date: Date
        let succeeded: Bool
        let error: String?
    }

    struct ModeChange: Codable, Equatable {
        let date: Date
        let closedLoop: Bool
    }

    /// Splits `interval` into closed, limited and open stretches.
    ///
    /// Each 5-minute slot is open when closed loop was switched off (from `modeChanges`), closed when Loop completed a
    /// run in the 15 minutes before the slot ends, and limited otherwise. Before the first mode change the setting is
    /// unknown, so the result starts at the later of `coverageStart` and the first mode change.
    static func loopModeSpans(interval: DateInterval, runs: [LoopRun], modeChanges: [ModeChange], coverageStart: Date?,
                              recency: TimeInterval = 15 * 60, slot: TimeInterval = 5 * 60) -> [LoopModeSpan] {
        guard let coverageStart, let firstChange = modeChanges.map(\.date).min() else { return [] }
        let start = max(interval.start, coverageStart, firstChange)
        guard interval.end > start else { return [] }

        let sortedRuns = runs.sorted { $0.date < $1.date }
        let changes = modeChanges.sorted { $0.date < $1.date }
        var spans: [LoopModeSpan] = []
        var runIndex = 0
        var lastSuccess: Date? = nil
        var lastError: String? = nil
        var changeIndex = 0
        var closedSetting: Bool? = nil

        var t = start
        while t < interval.end {
            let slotEnd = min(t.addingTimeInterval(slot), interval.end)
            while runIndex < sortedRuns.count && sortedRuns[runIndex].date <= slotEnd {
                let run = sortedRuns[runIndex]
                if run.succeeded {
                    lastSuccess = run.date
                    lastError = nil
                } else {
                    lastError = run.error ?? lastError
                }
                runIndex += 1
            }
            while changeIndex < changes.count && changes[changeIndex].date <= slotEnd {
                closedSetting = changes[changeIndex].closedLoop
                changeIndex += 1
            }

            let mode: LoopModeSpan.Mode
            let cause: String?
            if closedSetting == false {
                mode = .open
                cause = NSLocalizedString("Closed loop off", comment: "Reason shown for a stretch of time when Loop was in open loop because closed loop was turned off")
            } else if let lastSuccess, slotEnd.timeIntervalSince(lastSuccess) <= recency {
                mode = .closed
                cause = nil
            } else {
                mode = .limited
                cause = lastError ?? NSLocalizedString("Loop didn't run", comment: "Reason shown for a stretch of time when Loop did not complete a run and recorded no error")
            }

            if let last = spans.last, last.mode == mode, last.cause == cause, last.end == t {
                spans[spans.count - 1] = LoopModeSpan(start: last.start, end: slotEnd, mode: mode, cause: cause)
            } else {
                spans.append(LoopModeSpan(start: t, end: slotEnd, mode: mode, cause: cause))
            }
            t = slotEnd
        }
        return spans
    }

    static func duration(of mode: LoopModeSpan.Mode, in spans: [LoopModeSpan]) -> TimeInterval {
        spans.filter { $0.mode == mode }.reduce(0) { $0 + $1.duration }
    }
}
