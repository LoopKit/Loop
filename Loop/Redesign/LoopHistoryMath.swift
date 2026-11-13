//
//  LoopHistoryMath.swift
//  Loop
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Foundation

/// Pure calculations behind the Trends screen. Nothing here touches a store.
enum LoopHistoryMath {

    // MARK: Glucose

    /// An HbA1c or GMI percentage (NGSP) in mmol/mol (IFCC).
    static func mmolPerMol(percent: Double) -> Double {
        (percent - 2.152) * 10.929
    }

    /// Whether GMI is as representative as the consensus asks: a period of at least 14 calendar days (today counts,
    /// so "14 d" does while it runs), with CGM data for at least 70% of it.
    static func gmiIsRepresentative(periodDays: Int, cgmActive: Double) -> Bool {
        periodDays >= 14 && cgmActive >= 0.7
    }

    /// Hours a day with CGM readings: what a band's share of time is a share of. One day gives that day's hours
    /// with readings, so far when it is today; a longer period gives the average over its days.
    static func cgmHoursPerDay(cgmActive: Double, over interval: DateInterval, periodDays: Int) -> Double {
        periodDays <= 1 ? cgmActive * interval.duration / 3600 : cgmActive * 24
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

    // MARK: Time in range

    /// Whole-number percentages that add up to 100 (largest remainder), so the labels never sum to 99 or 101.
    static func roundedPercentages(_ fractions: [GlucoseBand: Double]) -> [GlucoseBand: Int] {
        let raw = GlucoseBand.allCases.map { (band: $0, value: (fractions[$0] ?? 0) * 100) }
        let total = raw.reduce(0) { $0 + $1.value }
        guard total > 0 else { return Dictionary(uniqueKeysWithValues: GlucoseBand.allCases.map { ($0, 0) }) }
        var floors = raw.map { (band: $0.band, floor: Int($0.value.rounded(.down)), remainder: $0.value - $0.value.rounded(.down)) }
        var missing = Int(total.rounded()) - floors.reduce(0) { $0 + $1.floor }
        for index in floors.indices.sorted(by: { floors[$0].remainder > floors[$1].remainder }) where missing > 0 {
            floors[index].floor += 1
            missing -= 1
        }
        return Dictionary(uniqueKeysWithValues: floors.map { ($0.band, $0.floor) })
    }

    // MARK: Scheduled basal

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

    // MARK: Loop's stores and Apple Health

    /// Where one kind of data switches from Apple Health to Loop's own records: the later of the start of Loop's
    /// local history and its first record of that kind. With no records of that kind, it is `now`, so all of it
    /// comes from Health. Loop writes what it records to Health too, so reading Health only before this point and
    /// Loop's stores only from it counts nothing twice.
    static func healthBoundary(localHistoryStart: Date, firstLocalRecord: Date?, now: Date) -> Date {
        max(localHistoryStart, firstLocalRecord ?? now)
    }

    /// The earliest record that lies in `chunk`, from records given as start and end. A store can return records
    /// outside the range it was asked for, such as a pump's dose still in progress, so only those overlapping the
    /// chunk count. A record crossing into the chunk keeps its real start; one with no duration, such as a bolus,
    /// counts by its start.
    static func firstRecord(in chunk: DateInterval, of records: [(start: Date, end: Date)]) -> Date? {
        records
            .filter { $0.start < chunk.end && ($0.end > chunk.start || ($0.end <= $0.start && $0.start >= chunk.start)) }
            .map(\.start)
            .min()
    }

    /// `window` cut at `boundary`: the part before it is read from Apple Health, the part from it on from Loop's
    /// stores. Either is nil when the window has none of it; the two never overlap.
    static func split(_ window: DateInterval, at boundary: Date) -> (health: DateInterval?, local: DateInterval?) {
        let health = window.start < boundary ? DateInterval(start: window.start, end: min(window.end, boundary)) : nil
        let local = window.end > boundary ? DateInterval(start: max(window.start, boundary), end: window.end) : nil
        return (health, local)
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
        /// The run stopped because a manual temp basal was running, which Loop shows as open loop.
        var manualTempBasal = false
    }

    /// Closed loop switched on or off, from Loop's stored settings.
    struct ModeChange: Equatable {
        let date: Date
        let closedLoop: Bool
    }

    /// Splits `interval` into closed, limited and open stretches.
    ///
    /// Each 5-minute slot is open when closed loop was switched off (from `modeChanges`), or while a manual temp basal
    /// from `manualTempBasals` runs. A run that stopped for a manual temp basal with no dose record of it holds the
    /// loop open for 15 minutes; where the record exists, its end or cancellation decides instead. Otherwise a slot is
    /// closed when Loop completed a run in the 15 minutes before it ends, and limited when it didn't. Before the first mode change the setting is unknown, so the
    /// result starts at the later of `coverageStart` and the first mode change.
    static func loopModeSpans(interval: DateInterval, runs: [LoopRun], modeChanges: [ModeChange], coverageStart: Date?,
                              manualTempBasals: [DateInterval] = [],
                              recency: TimeInterval = 15 * 60, slot: TimeInterval = 5 * 60) -> [LoopModeSpan] {
        guard let coverageStart, let firstChange = modeChanges.map(\.date).min() else { return [] }
        let start = max(interval.start, coverageStart, firstChange)
        guard interval.end > start else { return [] }

        let sortedRuns = runs.sorted { $0.date < $1.date }
        let changes = modeChanges.sorted { $0.date < $1.date }
        var spans: [LoopModeSpan] = []
        var runIndex = 0
        var lastRun: LoopRun? = nil
        var lastRunHasDoseRecord = false
        var lastSuccess: Date? = nil
        var changeIndex = 0
        var closedSetting: Bool? = nil
        let manualTemps = manualTempBasals.sorted { $0.start < $1.start }
        var manualIndex = 0
        let recorded = { (date: Date) in manualTemps.contains { $0.start <= date && date <= $0.end } }

        var t = start
        while t < interval.end {
            let slotEnd = min(t.addingTimeInterval(slot), interval.end)
            while runIndex < sortedRuns.count && sortedRuns[runIndex].date <= slotEnd {
                let run = sortedRuns[runIndex]
                lastRun = run
                lastRunHasDoseRecord = run.manualTempBasal && recorded(run.date)
                if run.succeeded {
                    lastSuccess = run.date
                }
                runIndex += 1
            }
            while changeIndex < changes.count && changes[changeIndex].date <= slotEnd {
                closedSetting = changes[changeIndex].closedLoop
                changeIndex += 1
            }

            // A manual temp basal holds Loop open for as long as the pump runs it, whatever a later run failed on.
            let middle = t.addingTimeInterval(slotEnd.timeIntervalSince(t) / 2)
            while manualIndex < manualTemps.count && manualTemps[manualIndex].end <= middle {
                manualIndex += 1
            }
            let inManualTemp = manualIndex < manualTemps.count && manualTemps[manualIndex].start <= middle

            let mode: LoopModeSpan.Mode
            if closedSetting == false || inManualTemp {
                mode = .open
            } else if let lastRun, lastRun.manualTempBasal, !lastRunHasDoseRecord, slotEnd.timeIntervalSince(lastRun.date) <= recency {
                mode = .open
            } else if let lastSuccess, slotEnd.timeIntervalSince(lastSuccess) <= recency {
                mode = .closed
            } else {
                mode = .limited
            }

            if let last = spans.last, last.mode == mode, last.end == t {
                spans[spans.count - 1] = LoopModeSpan(start: last.start, end: slotEnd, mode: mode)
            } else {
                spans.append(LoopModeSpan(start: t, end: slotEnd, mode: mode))
            }
            t = slotEnd
        }
        return spans
    }

    static func duration(of mode: LoopModeSpan.Mode, in spans: [LoopModeSpan]) -> TimeInterval {
        spans.filter { $0.mode == mode }.reduce(0) { $0 + $1.duration }
    }
}
