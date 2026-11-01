//
//  LoopHistoryMathTests.swift
//  LoopTests
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import XCTest
import HealthKit
import LoopKit
@testable import Loop

class LoopHistoryMathTests: XCTestCase {

    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private func at(_ minutes: Double) -> Date { start.addingTimeInterval(minutes * 60) }

    // MARK: Basal

    func testUnrecordedBasalCountsAtTheProgrammedRateOnlyAfterRecordsBegin() {
        let window = DateInterval(start: at(0), end: at(240))
        let programmed = [LoopHistoryMath.ScheduleValue(start: at(0), end: at(240), rate: 1.2)]
        let temp = LoopHistoryMath.BasalDelivery(start: at(120), end: at(150), rate: 0.4, kind: .temp, automatic: true)
        let segments = LoopHistoryMath.basalSegments(window: window, schedule: programmed, deliveries: [temp],
                                                     programmedRates: programmed, recordsStart: at(60))
        // Nothing before the first record; 60–120 and 150–240 at 1.2 U/h; 120–150 at the temp rate.
        XCTAssertNil(LoopHistoryMath.basalRate(at: at(30), in: segments))
        XCTAssertEqual(LoopHistoryMath.basalRate(at: at(90), in: segments)?.kind, .scheduled)
        XCTAssertEqual(LoopHistoryMath.basalRate(at: at(135), in: segments)?.rate, 0.4)
        XCTAssertEqual(segments.reduce(0) { $0 + $1.units }, 1.2 * 2.5 + 0.4 * 0.5, accuracy: 1e-9)
    }

    func testBasalGapsDoNotInventDelivery() {
        let window = DateInterval(start: at(0), end: at(120))
        let schedule = [LoopHistoryMath.ScheduleValue(start: at(-60), end: at(240), rate: 1.0)]
        let temp = LoopHistoryMath.BasalDelivery(start: at(60), end: at(90), rate: 2.0, kind: .temp, automatic: true)
        let segments = LoopHistoryMath.basalSegments(window: window, schedule: schedule, deliveries: [temp])
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments.reduce(0) { $0 + $1.units }, 1, accuracy: 1e-9)
        XCTAssertEqual(segments[0].netUnits, 0.5, accuracy: 1e-9)
    }

    func testSuspendDeliversNothingAndLaterRecordWins() {
        let window = DateInterval(start: at(0), end: at(60))
        let schedule = [LoopHistoryMath.ScheduleValue(start: at(0), end: at(60), rate: 1.2)]
        let deliveries = [
            LoopHistoryMath.BasalDelivery(start: at(0), end: at(60), rate: 3.0, kind: .temp, automatic: true),
            LoopHistoryMath.BasalDelivery(start: at(20), end: at(40), rate: 0, kind: .suspended, automatic: false),
        ]
        let segments = LoopHistoryMath.basalSegments(window: window, schedule: schedule, deliveries: deliveries)
        XCTAssertEqual(segments.map(\.kind), [.temp, .suspended, .temp])
        XCTAssertEqual(segments[1].units, 0)
        XCTAssertEqual(segments[1].netUnits, -0.4, accuracy: 1e-9)
    }

    func testNormalisedBasalPreservesDeliveredQuantityInPartialWindow() throws {
        // The pump reports 1.05 U delivered, although the programmed rate implies 1.0625 U.
        let dose = DoseEntry(type: .tempBasal, startDate: at(0), endDate: at(30), value: 2.125,
                             unit: .unitsPerHour, decisionId: nil, deliveredUnits: 1.05, automatic: true)
        let delivery = try XCTUnwrap(LoopHistoryMath.BasalDelivery(dose: dose))
        for (end, expected) in [(30.0, 1.05), (15.0, 0.525)] {
            let segments = LoopHistoryMath.basalSegments(window: DateInterval(start: at(0), end: at(end)),
                                                         schedule: [], deliveries: [delivery])
            XCTAssertEqual(segments.reduce(0) { $0 + $1.units }, expected, accuracy: 1e-9)
        }
    }

    func testHealthAndLocalPartitionsConserveBasalDelivery() throws {
        let sample = HKQuantitySample(type: HKQuantityType(.insulinDelivery),
                                      quantity: HKQuantity(unit: .internationalUnit(), doubleValue: 1),
                                      start: at(0), end: at(60),
                                      metadata: [HKMetadataKeyInsulinDeliveryReason: HKInsulinDeliveryReason.basal.rawValue])
        let left = try XCTUnwrap(BasalSegment(healthSample: sample, in: DateInterval(start: at(-30), end: at(30))))
        let right = try XCTUnwrap(BasalSegment(healthSample: sample, in: DateInterval(start: at(30), end: at(90))))
        XCTAssertEqual(left.units, 0.5, accuracy: 1e-9)
        XCTAssertEqual(right.units, 0.5, accuracy: 1e-9, "Include basal beginning before the selected interval")
        let dose = DoseEntry(type: .basal, startDate: at(0), endDate: at(60), value: 1, unit: .units, decisionId: nil, deliveredUnits: 1)
        let local = LoopHistoryMath.basalSegments(window: DateInterval(start: at(30), end: at(90)), schedule: [],
                                                 deliveries: [try XCTUnwrap(LoopHistoryMath.BasalDelivery(dose: dose))])
        XCTAssertEqual(left.units + local.reduce(0) { $0 + $1.units }, 1, accuracy: 1e-9)
        XCTAssertNil(BasalSegment(healthSample: sample, in: DateInterval(start: at(60), end: at(90))))

    }

    func testBolusWindowIsHalfOpenAndPreservesDeliveredUnits() {
        let window = DateInterval(start: at(0), end: at(60))
        for (minute, expected) in [(-1.0, false), (0.0, true), (30.0, true), (60.0, false)] {
            let dose = DoseEntry(type: .bolus, startDate: at(minute), value: 1, unit: .units, decisionId: nil, deliveredUnits: 0.75)
            let event = BolusEvent(dose: dose, in: window)
            XCTAssertEqual(event != nil, expected, "Bolus at minute \(minute)")
            if expected { XCTAssertEqual(event?.units, 0.75) }
        }
    }

    // MARK: Glucose

    func testTimeInRangeBandsAndRoundingSumTo100() {
        let values: [Double] = [50, 60, 100, 100, 100, 200, 300]
        let points = values.enumerated().map { GlucosePoint(date: at(Double($0.offset * 5)), mgdl: $0.element) }
        let fractions = LoopHistoryMath.timeInRange(points)
        XCTAssertEqual(fractions[.veryLow]!, 1 / 7, accuracy: 1e-9)
        XCTAssertEqual(fractions[.low]!, 1 / 7, accuracy: 1e-9)
        XCTAssertEqual(fractions[.inRange]!, 3 / 7, accuracy: 1e-9)
        XCTAssertEqual(fractions[.high]!, 1 / 7, accuracy: 1e-9)
        XCTAssertEqual(fractions[.veryHigh]!, 1 / 7, accuracy: 1e-9)
        XCTAssertEqual(LoopHistoryMath.roundedPercentages(fractions).values.reduce(0, +), 100)
    }

    func testBandEdgesFollowConsensusThresholds() {
        XCTAssertEqual(LoopHistoryMath.RangeBand.band(for: 53.9), .veryLow)
        XCTAssertEqual(LoopHistoryMath.RangeBand.band(for: 54), .low)
        XCTAssertEqual(LoopHistoryMath.RangeBand.band(for: 70), .inRange)
        XCTAssertEqual(LoopHistoryMath.RangeBand.band(for: 180), .inRange)
        XCTAssertEqual(LoopHistoryMath.RangeBand.band(for: 181), .high)
        XCTAssertEqual(LoopHistoryMath.RangeBand.band(for: 251), .veryHigh)
    }

    func testGMIFromMean() {
        let points = [GlucosePoint(date: at(0), mgdl: 150), GlucosePoint(date: at(5), mgdl: 150)]
        let stats = LoopHistoryMath.glucoseStats(points)!
        XCTAssertEqual(stats.gmiPercent, 3.31 + 0.02392 * 150, accuracy: 1e-9)
        XCTAssertEqual(stats.gmiMmolMol, (stats.gmiPercent - 2.152) * 10.929, accuracy: 1e-9)
        XCTAssertNil(LoopHistoryMath.glucoseStats([points[0]]))
    }

    func testCGMCoverageNotedOnlyWhenReadingsStartLate() {
        let interval = DateInterval(start: at(0), end: at(14 * 1440))
        let late = [GlucosePoint(date: at(9 * 1440), mgdl: 120), GlucosePoint(date: at(10 * 1440), mgdl: 130)]
        XCTAssertEqual(LoopHistoryMath.cgmCoveredDays(late, in: interval, periodDays: 14), 5)
        // Within a day of the full period, or a one-day period, says nothing.
        XCTAssertNil(LoopHistoryMath.cgmCoveredDays([GlucosePoint(date: at(600), mgdl: 120)], in: interval, periodDays: 14))
        XCTAssertNil(LoopHistoryMath.cgmCoveredDays(late, in: DateInterval(start: at(0), end: at(1440)), periodDays: 1))
        XCTAssertNil(LoopHistoryMath.cgmCoveredDays([], in: interval, periodDays: 14))
    }

    func testScheduledUnitsNeedTheWholeSpanCovered() {
        let points = [ScheduledBasalPoint(start: at(0), end: at(120), rate: 1.0), ScheduledBasalPoint(start: at(120), end: at(240), rate: 0.5)]
        XCTAssertEqual(try XCTUnwrap(LoopHistoryMath.scheduledUnits(points, over: DateInterval(start: at(60), end: at(180)))), 1.5, accuracy: 1e-9)
        XCTAssertNil(LoopHistoryMath.scheduledUnits(points, over: DateInterval(start: at(60), end: at(360))))
    }

    func testPercentileInterpolates() {
        XCTAssertEqual(LoopHistoryMath.percentile([1, 2, 3, 4, 5], 0.5), 3)
        XCTAssertEqual(LoopHistoryMath.percentile([1, 2, 3, 4], 0.5), 2.5)
        XCTAssertEqual(LoopHistoryMath.percentile([10, 20], 0.25), 12.5)
    }

    // MARK: Loop modes

    func testLoopModesStartAtFirstModeRecord() {
        let interval = DateInterval(start: at(0), end: at(60))
        let runs = stride(from: 0.0, through: 60, by: 5).map { LoopHistoryMath.LoopRun(date: at($0), succeeded: true, error: nil) }
        let spans = LoopHistoryMath.loopModeSpans(interval: interval, runs: runs,
                                                  modeChanges: [.init(date: at(30), closedLoop: true)], coverageStart: at(0))
        XCTAssertEqual(spans.first?.start, at(30), "Before the first record the mode is unknown and left out")
        XCTAssertEqual(LoopHistoryMath.duration(of: .closed, in: spans), 30 * 60, accuracy: 1)

        XCTAssertTrue(LoopHistoryMath.loopModeSpans(interval: interval, runs: runs, modeChanges: [], coverageStart: at(0)).isEmpty)
    }

    func testLoopModesClassifyOpenAndLimited() {
        let interval = DateInterval(start: at(0), end: at(90))
        // Runs succeed until 20 min, then fail with an error, then stop.
        var runs = stride(from: 0.0, through: 20, by: 5).map { LoopHistoryMath.LoopRun(date: at($0), succeeded: true, error: nil) }
        runs.append(.init(date: at(25), succeeded: false, error: "Glucose too old"))
        let changes: [LoopHistoryMath.ModeChange] = [.init(date: at(0), closedLoop: true), .init(date: at(60), closedLoop: false)]

        let spans = LoopHistoryMath.loopModeSpans(interval: interval, runs: runs, modeChanges: changes, coverageStart: at(0))
        XCTAssertEqual(spans.map(\.mode), [.closed, .limited, .open])
        XCTAssertEqual(spans[1].cause, "Glucose too old")
        XCTAssertEqual(spans[1].start, at(35), "Limited starts once the last good run is over 15 minutes old")
        XCTAssertEqual(spans[2].start, at(55), "The slot ending at the switch-off counts as open")
    }

    // MARK: Calendar

    func testDaysAndQuarterMarksOnClockChangeDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/London"))
        // 25 Oct 2026: clocks go back an hour, so the day is 25 hours long.
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 25)))
        let next = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: day))
        XCTAssertEqual(next.timeIntervalSince(day), 25 * 3600)

        let marks = DayAxis.quarterDayMarks(in: DateInterval(start: day, end: next), calendar: calendar)
        XCTAssertEqual(marks.map { calendar.component(.hour, from: $0) }, [0, 6, 12, 18, 0])

        let days = LoopHistoryMath.days(in: DateInterval(start: day, end: next.addingTimeInterval(3600)), calendar: calendar)
        XCTAssertEqual(days.count, 2)
        XCTAssertEqual(days[0].duration, 25 * 3600)
    }

    func testWeeklyAveragesDays() {
        let monday = Date(timeIntervalSinceReferenceDate: 815_270_400) // 9436 days after Monday 1 Jan 2001, so a Monday at midnight UTC
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let totals = (0..<14).map { LoopHistoryMath.DayTotal(day: monday.addingTimeInterval(Double($0) * 86400), basal: 10, bolus: Double($0)) }
        let weeks = LoopHistoryMath.weekly(totals, calendar: calendar)
        XCTAssertEqual(weeks.count, 2)
        XCTAssertEqual(weeks[0].bolus, 3, accuracy: 1e-9)
        XCTAssertEqual(weeks[1].bolus, 10, accuracy: 1e-9)
    }

    func testDailyInsulinAverageLeavesOutTheDayInProgress() {
        let day0 = Date(timeIntervalSinceReferenceDate: 815_270_400)
        let complete = (0..<3).map { LoopHistoryMath.DayTotal(day: day0.addingTimeInterval(Double($0) * 86400), basal: 10, bolus: 20) }
        let today = LoopHistoryMath.DayTotal(day: day0.addingTimeInterval(3 * 86400), basal: 3, bolus: 2, isComplete: false)
        XCTAssertEqual(LoopHistoryMath.averageDailyInsulin(complete + [today]), 30, accuracy: 1e-9)
        XCTAssertEqual(LoopHistoryMath.averagingDays(complete + [today]).count, 3)
        // With nothing complete, the day in progress is all there is to show.
        XCTAssertEqual(LoopHistoryMath.averageDailyInsulin([today]), 5, accuracy: 1e-9)
    }

    func testInsulinSplitSeparatesManualAutomaticAndUnclassifiedBolus() {
        let boluses = [
            BolusEvent(id: "m", date: at(0), units: 4, automatic: false, manuallyEntered: false),
            BolusEvent(id: "a", date: at(5), units: 0.5, automatic: true, manuallyEntered: false),
            BolusEvent(id: "u", date: at(10), units: 1, automatic: false, manuallyEntered: false, automaticKnown: false),
        ]
        let split = InsulinSplit(basal: 14.5, boluses: Array(boluses.prefix(2)))
        XCTAssertEqual(split.manualBolus, 4, accuracy: 1e-9)
        XCTAssertEqual(split.automaticBolus, 0.5, accuracy: 1e-9)
        XCTAssertEqual(split.total, 19, accuracy: 1e-9)
        XCTAssertTrue(split.isClassified)
        // Shares round independently but always add up to 100.
        XCTAssertEqual(split.basalPercent + split.bolusPercent, 100)
        XCTAssertEqual(split.bolusPercent, 24)

        // A bolus that doesn't say who gave it still counts, but hides the manual and automatic detail.
        let health = InsulinSplit(basal: 14.5, boluses: boluses)
        XCTAssertEqual(health.bolus, 5.5, accuracy: 1e-9)
        XCTAssertFalse(health.isClassified)

        let average = InsulinSplit.average([split, InsulinSplit(basal: 10.5, manualBolus: 2, automaticBolus: 1.5)])
        XCTAssertEqual(average.basal, 12.5, accuracy: 1e-9)
        XCTAssertEqual(average.manualBolus, 3, accuracy: 1e-9)
        XCTAssertEqual(average.automaticBolus, 1, accuracy: 1e-9)
    }

    func testWeeklyInsulinUsesTheSummaryAveragingDays() {
        let monday = Date(timeIntervalSinceReferenceDate: 815_270_400)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let totals = [
            LoopHistoryMath.DayTotal(day: monday, basal: 0, bolus: 0),
            LoopHistoryMath.DayTotal(day: monday.addingTimeInterval(86400), basal: 10, bolus: 20),
            LoopHistoryMath.DayTotal(day: monday.addingTimeInterval(2 * 86400), basal: 10, bolus: 20),
            LoopHistoryMath.DayTotal(day: monday.addingTimeInterval(3 * 86400), basal: 1, bolus: 2, isComplete: false),
        ]
        let weeks = LoopHistoryMath.weekly(totals, calendar: calendar)
        XCTAssertEqual(weeks.count, 1)
        XCTAssertEqual(weeks[0].basal, 10, accuracy: 1e-9)
        XCTAssertEqual(weeks[0].bolus, 20, accuracy: 1e-9)

        // A current week with no complete day must still show the data it has.
        let currentWeek = LoopHistoryMath.weekly([totals[3]], calendar: calendar)
        XCTAssertEqual(currentWeek.first?.total, 3)
    }

    func testGapMessageForADayWithoutReadings() {
        let start = Date(timeIntervalSinceReferenceDate: 815_270_400)
        let day = DateInterval(start: start, duration: 86400)
        let empty = DayAxis.gaps(in: [], window: day, until: day.end.addingTimeInterval(3600))
        XCTAssertEqual(DayAxis.gapMessage(empty, window: day, until: day.end.addingTimeInterval(3600)), "No CGM data on this day")
        let morning = start.addingTimeInterval(9 * 3600)
        XCTAssertEqual(DayAxis.gapMessage(DayAxis.gaps(in: [], window: day, until: morning), window: day, until: morning), "No CGM data yet today")
        let reading = [GlucosePoint(date: start.addingTimeInterval(12 * 3600), mgdl: 120)]
        let partial = DayAxis.gaps(in: reading, window: day, until: day.end)
        XCTAssertTrue(DayAxis.gapMessage(partial, window: day, until: day.end)?.hasSuffix("and 1 shorter gap") ?? false)
    }

    // MARK: Formatting

    func testRangeFormatting() throws {
        let calendar = Calendar.current
        let a = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 12)))
        let b = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 12)))
        let c = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 28, hour: 12)))
        // Ranges and durations come from the system's formatters, so they follow the user's locale;
        // the test host runs in en_US.
        XCTAssertEqual(LoopFormat.range(b, b), LoopFormat.day(b))
        let sameMonth = LoopFormat.range(a, b)
        XCTAssertTrue(sameMonth.contains("12") && sameMonth.contains("25"))
        XCTAssertEqual(sameMonth.components(separatedBy: "2026").count, 2, "the year appears once")
        let twoMonths = LoopFormat.range(c, b)
        XCTAssertTrue(twoMonths.contains("Sep") && twoMonths.contains("Oct"))
        XCTAssertEqual(LoopFormat.duration(13 * 86400 + 11 * 3600), "13d 11h")
        XCTAssertEqual(LoopFormat.duration(9 * 3600 + 45 * 60), "9h 45m")
        XCTAssertEqual(LoopFormat.number(7.25, decimals: 1), 7.25.formatted(.number.precision(.fractionLength(1)).grouping(.never)))
        XCTAssertEqual(LoopFormat.signed(-0.4), "−0.40")
        XCTAssertEqual(LoopFormat.signed(0.0001), "+0.00")
    }

    @MainActor
    func testCSVExportsTenColumnsWithASCIINumbers() throws {
        let day = Calendar.current.startOfDay(for: start)
        let nextDay = day.addingTimeInterval(86400)
        for isMmol in [true, false] {
            var summary = TrendsModel.Summary(interval: DateInterval(start: day, duration: 2 * 86400),
                                              unit: GlucoseUnitStyle(isMmol: isMmol))
            summary.glucose = [GlucosePoint(date: day, mgdl: 131.53286)]
            summary.totals = [
                .init(day: day, split: InsulinSplit(basal: 1.25, manualBolus: 2, automaticBolus: 0.5)),
                // From another app in Health: the bolus doesn't say whether it was manual or automatic.
                .init(day: nextDay, split: InsulinSplit(basal: 1, unclassifiedBolus: 3)),
            ]
            summary.carbsByDay = [day: 45]
            let url = try TrendsModel.exportCSV(summary)
            defer { try? FileManager.default.removeItem(at: url) }
            let rows = try String(contentsOf: url, encoding: .utf8).components(separatedBy: "\n")
            XCTAssertEqual(rows.count, 3)
            XCTAssertEqual(rows[0].components(separatedBy: ",").count, 10)
            XCTAssertTrue(rows[0].hasSuffix(",carbs_g,manual_bolus_u,auto_bolus_u"))
            let columns = rows[1].components(separatedBy: ",")
            XCTAssertEqual(columns.count, 10)
            XCTAssertEqual(Array(columns.dropFirst()), [isMmol ? "7.3" : "132", "1", "100", "1.25", "2.50", "3.75", "45", "2.00", "0.50"])
            XCTAssertEqual(Array(rows[2].components(separatedBy: ",").suffix(5)), ["3.00", "4.00", "0", "", ""])
        }
    }

    func testModeHistoryRetainsTheModeBeforeTheRetentionWindow() throws {
        let suite = "LoopHistoryMathTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let history = LoopModeHistory(defaults: defaults)
        history.record(closedLoop: false, at: at(0))
        history.record(closedLoop: true, at: at(60))
        let switchDate = at(200 * 1440)
        history.record(closedLoop: false, at: switchDate)
        XCTAssertEqual(history.changes, [.init(date: at(60), closedLoop: true), .init(date: switchDate, closedLoop: false)])
        let interval = DateInterval(start: switchDate.addingTimeInterval(-3600), end: switchDate)
        let spans = LoopHistoryMath.loopModeSpans(interval: interval, runs: [], modeChanges: history.changes,
                                                  coverageStart: interval.start)
        XCTAssertEqual(spans.first?.start, interval.start, "Retaining the old mode must preserve recent coverage")
    }

    func testIssueDescriptions() {
        XCTAssertEqual(LoopHistoryProvider.describe(issue: "glucoseTooOld"), "Glucose too old")
        XCTAssertEqual(LoopHistoryProvider.describe(issue: "pumpDataTooOld"), "Pump data too old")
    }

    // MARK: Day history

    func testDayHistoryClippedToNowDropsLaterEventsAndCutsBasal() {
        var history = DayHistory(window: DateInterval(start: at(0), end: at(1440)))
        history.glucose = [GlucosePoint(date: at(10), mgdl: 100), GlucosePoint(date: at(700), mgdl: 120)]
        history.boluses = [BolusEvent(id: "a", date: at(30), units: 1, automatic: false, manuallyEntered: false),
                           BolusEvent(id: "b", date: at(650), units: 2, automatic: true, manuallyEntered: false)]
        history.basal = [BasalSegment(start: at(0), end: at(720), rate: 1, scheduledRate: 1, kind: .scheduled, automatic: false)]
        let clipped = history.clipped(to: DateInterval(start: at(0), end: at(600)))
        XCTAssertEqual(clipped.window.end, at(600))
        XCTAssertEqual(clipped.glucose.count, 1)
        XCTAssertEqual(clipped.boluses.map(\.id), ["a"])
        XCTAssertEqual(clipped.basalUnits, 10, accuracy: 1e-9)
    }
}
