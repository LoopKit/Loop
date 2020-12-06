//
//  LoopSettingsAlerterTests.swift
//  LoopTests
//
//  Created by Nathaniel Hamming on 2020-10-22.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import XCTest
import HealthKit
import LoopKit
import LoopCore
@testable import Loop

class LoopSettingsAlerterTests: XCTestCase, LoopSettingsAlerterDelegate {

    private var alertIdentifier: Alert.Identifier?
    private var alert: Alert?
    private var testExpectation: XCTestExpectation!

    var settings: LoopSettings = LoopSettings()

    override func setUp() {
        settings.preMealTargetRange = DoubleRange(minValue: 80, maxValue: 80)
        settings.glucoseTargetRangeSchedule = GlucoseRangeSchedule(
            unit: .milligramsPerDeciliter,
            dailyItems: [.init(startTime: 0, value: DoubleRange(minValue: 95, maxValue: 105))]
        )
        settings.legacyWorkoutTargetRange = DoubleRange(minValue: 120, maxValue: 150)
        settings.enableLegacyWorkoutOverride(for: .infinity)
        
        alert = nil
    }

    func testWorkoutOverrideReminderElasped() {
        testExpectation = self.expectation(description: #function)

        let loopSettingsAlerter = LoopSettingsAlerter(alertPresenter: self, workoutOverrideReminderInterval:  -.seconds(1)) // the elasped time will always be greater than a negative number
        loopSettingsAlerter.delegate = self

        NotificationCenter.default.post(name: .LoopRunning, object: nil)
        wait(for: [testExpectation], timeout: 1.0)

        XCTAssertEqual(alert, loopSettingsAlerter.workoutOverrideReminderAlert)
    }

    func testWorkoutOverrideReminderRepeated() {
        testExpectation = self.expectation(description: #function)

        let loopSettingsAlerter = LoopSettingsAlerter(alertPresenter: self, workoutOverrideReminderInterval:  -.seconds(1)) // the elasped time will always be greater than a negative number
        loopSettingsAlerter.delegate = self

        NotificationCenter.default.post(name: .LoopRunning, object: nil)
        wait(for: [testExpectation], timeout: 1.0)

        XCTAssertEqual(alert, loopSettingsAlerter.workoutOverrideReminderAlert)

        alert = nil
        testExpectation = self.expectation(description: #function)

        NotificationCenter.default.post(name: .LoopRunning, object: nil)
        wait(for: [testExpectation], timeout: 1.0)

        XCTAssertEqual(alert, loopSettingsAlerter.workoutOverrideReminderAlert)
    }

    func testWorkoutOverrideReminderNotElasped() {
        let loopSettingsAlerter = LoopSettingsAlerter(alertPresenter: self)
        loopSettingsAlerter.delegate = self
        
        NotificationCenter.default.post(name: .LoopRunning, object: nil)
        waitOnMain()

        XCTAssertNil(alert)
    }
}

extension LoopSettingsAlerterTests: AlertPresenter {
    func issueAlert(_ alert: Alert) {
        self.alert = alert
        testExpectation.fulfill()
    }

    func retractAlert(identifier: Alert.Identifier) {
        alertIdentifier = identifier
    }
}
