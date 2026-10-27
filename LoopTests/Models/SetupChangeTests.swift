//
//  SetupChangeTests.swift
//  LoopTests
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import XCTest
import LoopKit
import LoopAlgorithm
@testable import Loop

final class SetupChangeTests: XCTestCase {
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func settings(
        at hours: Double,
        basal: Double = 1.0,
        isf: Double = 50,
        isfUnit: LoopUnit = .milligramsPerDeciliter,
        maximumBolus: Double = 10,
        strategy: AutomaticDosingStrategy = .automaticBolus,
        dosingEnabled: Bool = true,
        deviceToken: String? = nil,
        insulinType: InsulinType? = .novolog,
        timeZone: TimeZone = TimeZone(identifier: "America/Chicago")!
    ) -> StoredSettings {
        StoredSettings(
            date: start.addingTimeInterval(.hours(hours)),
            dosingEnabled: dosingEnabled,
            maximumBolus: maximumBolus,
            deviceToken: deviceToken,
            insulinType: insulinType,
            basalRateSchedule: BasalRateSchedule(dailyItems: [RepeatingScheduleValue(startTime: 0, value: basal)], timeZone: timeZone),
            insulinSensitivitySchedule: InsulinSensitivitySchedule(unit: isfUnit, dailyItems: [RepeatingScheduleValue(startTime: 0, value: isf)], timeZone: timeZone),
            automaticDosingStrategy: strategy)
    }

    func testNoChangeIsLowerBoundAtOldestRecord() {
        let change = SetupChange.latest(in: [settings(at: 5), settings(at: 0), settings(at: 10)])
        XCTAssertEqual(change, SetupChange(date: start, isLowerBound: true, items: []))
    }

    func testEmptyHistory() {
        XCTAssertNil(SetupChange.latest(in: []))
    }

    func testLatestChangeWins() {
        let change = SetupChange.latest(in: [settings(at: 0), settings(at: 10, basal: 1.2), settings(at: 20, basal: 1.2, maximumBolus: 8)])
        XCTAssertEqual(change, SetupChange(date: start.addingTimeInterval(.hours(20)), isLowerBound: false, items: [.therapySetting(.deliveryLimits)], previousDate: start.addingTimeInterval(.hours(10))))
    }

    func testChangesWithinAnHourAreGrouped() {
        let change = SetupChange.latest(in: [settings(at: 0), settings(at: 10, isf: 45), settings(at: 10.5, isf: 45, strategy: .tempBasalOnly)])
        XCTAssertEqual(change?.date, start.addingTimeInterval(.hours(10.5)))
        XCTAssertEqual(change?.items, [.dosingStrategy, .therapySetting(.insulinSensitivity)])
        XCTAssertEqual(change?.previousDate, start)
    }

    func testIgnoredChanges() {
        let other = TimeZone(identifier: "Europe/Paris")!
        let change = SetupChange.latest(in: [
            settings(at: 0),
            settings(at: 1, dosingEnabled: false),
            settings(at: 2, deviceToken: "abc"),
            settings(at: 3, timeZone: other),
            settings(at: 4, insulinType: nil),
            settings(at: 5),
        ])
        XCTAssertEqual(change, SetupChange(date: start, isLowerBound: true, items: []))
    }

    func testInsulinTypeChange() {
        let change = SetupChange.latest(in: [settings(at: 0), settings(at: 1, insulinType: nil), settings(at: 2, insulinType: .fiasp)])
        XCTAssertEqual(change?.items, [.insulinType])
        XCTAssertEqual(change?.date, start.addingTimeInterval(.hours(2)))
    }

    func testSameSensitivityInAnotherUnitIsNotAChange() {
        let mmol = LoopQuantity(unit: .milligramsPerDeciliter, doubleValue: 50).doubleValue(for: .millimolesPerLiter)
        let change = SetupChange.latest(in: [settings(at: 0), settings(at: 1, isf: (mmol * 10).rounded() / 10, isfUnit: .millimolesPerLiter)])
        XCTAssertEqual(change?.isLowerBound, true)
    }

    func testExperimentChangeAfterSettingsChange() {
        let settingsChange = SetupChange(date: start, isLowerBound: false, items: [.therapySetting(.carbRatio)])
        let experimentChange = SetupChange(date: start.addingTimeInterval(.hours(30)), isLowerBound: false, items: [.experiment(.guardAndRunway, enabled: true)])
        XCTAssertEqual(SetupChange.latest(settingsChange, experimentChange)?.previousDate, start)
        XCTAssertEqual(SetupChange.latest(settingsChange, experimentChange)?.items, experimentChange.items)
    }

    func testCloseChangesAreMerged() {
        let settingsChange = SetupChange(date: start, isLowerBound: false, items: [.therapySetting(.carbRatio)])
        let experimentChange = SetupChange(date: start.addingTimeInterval(.minutes(20)), isLowerBound: false, items: [.experiment(.guardAndRunway, enabled: true)])
        XCTAssertEqual(SetupChange.latest(settingsChange, experimentChange)?.items, [.experiment(.guardAndRunway, enabled: true), .therapySetting(.carbRatio)])
    }

    func testLaterLowerBoundWins() {
        let settingsChange = SetupChange(date: start, isLowerBound: false, items: [.therapySetting(.carbRatio)])
        let experimentsBound = SetupChange(date: start.addingTimeInterval(.days(3)), isLowerBound: true, items: [])
        XCTAssertEqual(SetupChange.latest(settingsChange, experimentsBound), experimentsBound)
    }

    func testChangeAfterLowerBoundWins() {
        let settingsBound = SetupChange(date: start, isLowerBound: true, items: [])
        let experimentChange = SetupChange(date: start.addingTimeInterval(.minutes(20)), isLowerBound: false, items: [.experiment(.integralRetrospectiveCorrection, enabled: false)])
        XCTAssertEqual(SetupChange.latest(settingsBound, experimentChange)?.date, experimentChange.date)
        XCTAssertEqual(SetupChange.latest(settingsBound, experimentChange)?.previousDate, start)
    }
}
