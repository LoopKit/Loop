//
//  InsulinDeliveryHistoryTests.swift
//  LoopTests
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import XCTest
import LoopKit
import LoopAlgorithm
@testable import Loop

final class InsulinDeliveryHistoryTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        return calendar
    }()

    private func date(_ day: Int, _ hour: Double) -> Date {
        let midnight = calendar.date(from: DateComponents(year: 2026, month: 10, day: day))!
        return midnight.addingTimeInterval(.hours(hour))
    }

    private func bolus(_ units: Double, at start: Date, duration: TimeInterval = 0, automatic: Bool = false) -> SimpleInsulinDose {
        SimpleInsulinDose(deliveryType: .bolus, automatic: automatic, startDate: start, endDate: start.addingTimeInterval(duration), volume: units, insulinModel: ExponentialInsulinModelPreset.rapidActingAdult)
    }

    private func tempBasal(rate: Double, from start: Date, to end: Date) -> SimpleInsulinDose {
        SimpleInsulinDose(deliveryType: .basal, automatic: true, startDate: start, endDate: end, volume: rate * end.timeIntervalSince(start).hours, insulinModel: ExponentialInsulinModelPreset.rapidActingAdult)
    }

    private func scheduledBasal(_ rate: Double, from start: Date, to end: Date) -> [AbsoluteScheduleValue<Double>] {
        [AbsoluteScheduleValue(startDate: start, endDate: end, value: rate)]
    }

    func testBolusWithoutDurationOnlyCountsOnItsOwnDay() {
        let history = InsulinDeliveryHistory(
            doses: [bolus(5, at: date(20, 22)), bolus(2, at: date(21, 8))],
            scheduledBasal: [],
            coverageStart: date(20, 0),
            end: date(21, 12)
        )

        XCTAssertEqual(history.totals(from: date(21, 0), to: date(21, 12)).total, 2, accuracy: 0.0001)
    }

    func testBolusSpanningMidnightIsSplit() {
        let history = InsulinDeliveryHistory(
            doses: [bolus(4, at: date(20, 23.75), duration: .minutes(30))],
            scheduledBasal: [],
            coverageStart: date(20, 0),
            end: date(21, 12)
        )

        XCTAssertEqual(history.totals(from: date(21, 0), to: date(21, 12)).bolus, 2, accuracy: 0.0001)
    }

    func testUncoveredTimeCountsAsScheduledBasal() {
        let history = InsulinDeliveryHistory(
            doses: [
                tempBasal(rate: 0, from: date(21, 2), to: date(21, 4)),
                tempBasal(rate: 3, from: date(21, 6), to: date(21, 7)),
            ],
            scheduledBasal: scheduledBasal(1, from: date(20, 0), to: date(22, 0)),
            coverageStart: date(21, 0),
            end: date(21, 10)
        )

        // 2 h scheduled, 2 h suspended, 2 h scheduled, 1 h at 3 U/h, 3 h scheduled
        XCTAssertEqual(history.totals(from: date(21, 0), to: date(21, 10)).basal, 10, accuracy: 0.0001)
    }

    func testOverlappingBasalRecordsAreNotDoubleCounted() {
        let history = InsulinDeliveryHistory(
            doses: [
                tempBasal(rate: 2, from: date(21, 1), to: date(21, 3)),
                tempBasal(rate: 2, from: date(21, 2), to: date(21, 4)),
            ],
            scheduledBasal: scheduledBasal(1, from: date(21, 0), to: date(21, 5)),
            coverageStart: date(21, 0),
            end: date(21, 5)
        )

        XCTAssertEqual(history.totals(from: date(21, 0), to: date(21, 5)).basal, 8, accuracy: 0.0001)
    }

    func testBolusesAreSplitByAutomation() {
        let history = InsulinDeliveryHistory(
            doses: [bolus(0.5, at: date(21, 1), automatic: true), bolus(0.3, at: date(21, 2), automatic: true), bolus(4, at: date(21, 3))],
            scheduledBasal: [],
            coverageStart: date(21, 0),
            end: date(21, 5)
        )

        let totals = history.totals(from: date(21, 0), to: date(21, 5))
        XCTAssertEqual(totals.automaticBolus, 0.8, accuracy: 0.0001)
        XCTAssertEqual(totals.manualBolus, 4, accuracy: 0.0001)
    }

    func testDailyTotalsSkipThePartlyCoveredFirstDay() {
        let history = InsulinDeliveryHistory(
            doses: [bolus(3, at: date(19, 12)), bolus(4, at: date(20, 12)), bolus(5, at: date(21, 6))],
            scheduledBasal: scheduledBasal(1, from: date(19, 0), to: date(22, 0)),
            coverageStart: date(19, 9),
            end: date(21, 12)
        )

        let days = history.dailyTotals(calendar: calendar)
        XCTAssertEqual(days.map(\.start), [date(20, 0), date(21, 0)])
        XCTAssertEqual(days.map(\.isComplete), [true, false])
        XCTAssertEqual(days[0].totals.total, 28, accuracy: 0.0001)
        XCTAssertEqual(days[1].totals.total, 17, accuracy: 0.0001)
    }

    func testTypicalDeliveryUsesTheSameClockTimeOnEarlierDays() {
        let breakfasts = [2.0, 6, 4, 8].enumerated().map { bolus($0.element, at: date(17 + $0.offset, 7)) }
        let dinners = (17...20).map { bolus(10, at: date($0, 18)) }
        let history = InsulinDeliveryHistory(
            doses: breakfasts + dinners,
            scheduledBasal: scheduledBasal(1, from: date(17, 0), to: date(22, 0)),
            coverageStart: date(17, 0),
            end: date(21, 9)
        )

        let typical = history.typicalDelivery(by: date(21, 9), calendar: calendar)
        XCTAssertEqual(typical?.dayCount, 4)
        XCTAssertEqual(typical?.median ?? 0, 9 + 5, accuracy: 0.0001)
    }

    func testTypicalDeliveryNeedsEnoughDays() {
        let history = InsulinDeliveryHistory(
            doses: [],
            scheduledBasal: scheduledBasal(1, from: date(19, 0), to: date(22, 0)),
            coverageStart: date(19, 0),
            end: date(21, 9)
        )

        XCTAssertNil(history.typicalDelivery(by: date(21, 9), calendar: calendar))
        XCTAssertEqual(history.typicalDelivery(by: date(21, 9), minimumDays: 2, calendar: calendar)?.median ?? 0, 9, accuracy: 0.0001)
    }

    func testTypicalDeliveryKeepsClockTimeAcrossDaylightSavingTime() {
        // Clocks fall back on 2026-11-01 in Chicago, so midnight to 9:00 that day is 10 hours.
        let history = InsulinDeliveryHistory(
            doses: [],
            scheduledBasal: scheduledBasal(1, from: date(30, 0), to: calendar.date(from: DateComponents(year: 2026, month: 11, day: 3))!),
            coverageStart: date(30, 0),
            end: calendar.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 9))!
        )

        let typical = history.typicalDelivery(by: history.end, days: 3, minimumDays: 3, calendar: calendar)
        XCTAssertEqual(typical?.median ?? 0, 9, accuracy: 0.0001)
    }
}
