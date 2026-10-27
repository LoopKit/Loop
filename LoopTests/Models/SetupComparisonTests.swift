//
//  SetupComparisonTests.swift
//  LoopTests
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import XCTest
import LoopKit
import LoopAlgorithm
@testable import Loop

final class SetupComparisonTests: XCTestCase {
    private let changeDate = Date(timeIntervalSinceReferenceDate: 800_000_000)

    /// Readings every 5 minutes; `value` gives mg/dL for each reading's date.
    private func samples(from start: Date, to end: Date, value: (Date) -> Double) -> [StoredGlucoseSample] {
        stride(from: start.timeIntervalSinceReferenceDate, to: end.timeIntervalSinceReferenceDate, by: .minutes(5)).map {
            let date = Date(timeIntervalSinceReferenceDate: $0)
            return StoredGlucoseSample(startDate: date, quantity: LoopQuantity(unit: .milligramsPerDeciliter, doubleValue: value(date)))
        }
    }

    private func change(previousDate: Date? = nil) -> SetupChange {
        SetupChange(date: changeDate, isLowerBound: false, items: [.therapySetting(.carbRatio)], previousDate: previousDate)
    }

    func testBeforeAndAfter() throws {
        let now = changeDate.addingTimeInterval(.days(5))
        // Before: all in range. After: one reading in ten is low.
        var index = 0
        let glucose = samples(from: changeDate - .days(20), to: now) { date in
            index += 1
            return date < self.changeDate ? 120 : (index % 10 == 0 ? 60 : 120)
        }
        let comparison = try XCTUnwrap(SetupComparison(change: change(), samples: glucose, insulinHistory: nil, now: now))
        let before = try XCTUnwrap(comparison.before)

        XCTAssertEqual(before.start, changeDate - .days(14))
        XCTAssertEqual(before.timeInRange ?? 0, 1, accuracy: 0.001)
        XCTAssertEqual(before.timeBelowRange ?? 1, 0, accuracy: 0.001)
        XCTAssertEqual(comparison.after.start, changeDate)
        XCTAssertEqual(comparison.after.timeBelowRange ?? 0, 0.1, accuracy: 0.01)
        XCTAssertTrue(comparison.isSettling)
    }

    func testBeforeStopsAtPreviousChange() throws {
        let now = changeDate.addingTimeInterval(.days(15))
        let glucose = samples(from: changeDate - .days(20), to: now) { _ in 120 }
        let comparison = try XCTUnwrap(SetupComparison(change: change(previousDate: changeDate - .days(4)), samples: glucose, insulinHistory: nil, now: now))

        XCTAssertEqual(comparison.before?.start, changeDate - .days(4))
        XCTAssertEqual(comparison.before?.days ?? 0, 4, accuracy: 0.001)
        XCTAssertFalse(comparison.isSettling)
    }

    func testNoBeforeWhenThePreviousSetupWasShort() throws {
        let now = changeDate.addingTimeInterval(.days(3))
        let glucose = samples(from: changeDate - .days(20), to: now) { _ in 120 }
        let comparison = try XCTUnwrap(SetupComparison(change: change(previousDate: changeDate - .hours(12)), samples: glucose, insulinHistory: nil, now: now))
        XCTAssertNil(comparison.before)
    }

    func testNoBeforeWithoutEnoughCGMData() throws {
        let now = changeDate.addingTimeInterval(.days(3))
        let glucose = samples(from: changeDate - .days(2), to: now) { _ in 120 }
        let comparison = try XCTUnwrap(SetupComparison(change: change(), samples: glucose, insulinHistory: nil, now: now))
        XCTAssertNil(comparison.before)
    }

    func testPastSetupEndsAtTheNextChange() throws {
        let now = changeDate.addingTimeInterval(.days(30))
        let glucose = samples(from: changeDate - .days(20), to: now) { _ in 120 }
        let comparison = try XCTUnwrap(SetupComparison(change: change(), end: changeDate + .days(6), samples: glucose, insulinHistory: nil, now: now))

        XCTAssertEqual(comparison.after.end, changeDate + .days(6))
        XCTAssertFalse(comparison.isCurrent)
        XCTAssertFalse(comparison.isSettling)
        XCTAssertNil(SetupComparison(change: change(), end: changeDate + .hours(10), samples: glucose, insulinHistory: nil, now: now))
    }

    func testNothingUntilADayHasPassed() {
        let now = changeDate.addingTimeInterval(.hours(20))
        let glucose = samples(from: changeDate - .days(14), to: now) { _ in 120 }
        XCTAssertNil(SetupComparison(change: change(), samples: glucose, insulinHistory: nil, now: now))
    }

    func testNothingForALowerBound() {
        let now = changeDate.addingTimeInterval(.days(20))
        let bound = SetupChange(date: changeDate, isLowerBound: true, items: [])
        XCTAssertNil(SetupComparison(change: bound, samples: [], insulinHistory: nil, now: now))
    }

    func testInsulinPerDay() throws {
        let now = changeDate.addingTimeInterval(.days(2))
        let start = changeDate - .days(14)
        let glucose = samples(from: start, to: now) { _ in 120 }
        let bolus = SimpleInsulinDose(deliveryType: .bolus, automatic: false, startDate: changeDate + .hours(1), endDate: changeDate + .hours(1), volume: 4, insulinModel: ExponentialInsulinModelPreset.rapidActingAdult)
        let history = InsulinDeliveryHistory(
            doses: [bolus],
            scheduledBasal: [AbsoluteScheduleValue(startDate: start, endDate: now, value: 1.0)],
            coverageStart: start,
            end: now)
        let comparison = try XCTUnwrap(SetupComparison(change: change(), samples: glucose, insulinHistory: history, now: now))

        XCTAssertEqual(comparison.before?.insulinPerDay ?? 0, 24, accuracy: 0.001)
        XCTAssertEqual(comparison.after.insulinPerDay ?? 0, 26, accuracy: 0.001)
    }

    func testNoInsulinWhenDosesDontCoverThePeriod() throws {
        let now = changeDate.addingTimeInterval(.days(2))
        let glucose = samples(from: changeDate - .days(14), to: now) { _ in 120 }
        let history = InsulinDeliveryHistory(doses: [], scheduledBasal: [], coverageStart: changeDate - .days(1), end: now)
        let comparison = try XCTUnwrap(SetupComparison(change: change(), samples: glucose, insulinHistory: history, now: now))

        XCTAssertNil(comparison.before?.insulinPerDay)
        XCTAssertNotNil(comparison.after.insulinPerDay)
    }
}
