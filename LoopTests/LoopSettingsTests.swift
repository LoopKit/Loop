//
//  LoopSettingsTests.swift
//  LoopTests
//
//  Created by Michael Pangburn on 3/1/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import XCTest
import LoopCore
import LoopKit


class LoopSettingsTests: XCTestCase {
    private let preMealRange = DoubleRange(minValue: 80, maxValue: 80)
    private let targetRange = DoubleRange(minValue: 95, maxValue: 105)
    
    private lazy var settings: LoopSettings = {
        var settings = LoopSettings()
        settings.preMealTargetRange = preMealRange
        settings.glucoseTargetRangeSchedule = GlucoseRangeSchedule(
            unit: .milligramsPerDeciliter,
            dailyItems: [.init(startTime: 0, value: targetRange)]
        )
        return settings
    }()
    
    func testPreMealOverride() {
        var settings = self.settings
        let preMealStart = Date()
        settings.enablePreMealOverride(at: preMealStart, for: 1 /* hour */ * 60 * 60)
        let actualPreMealRange = settings.effectiveGlucoseTargetRangeSchedule()?.value(at: preMealStart.addingTimeInterval(30 /* minutes */ * 60))
        XCTAssertEqual(preMealRange, actualPreMealRange)
    }
    
    func testPreMealOverrideWithPotentialCarbEntry() {
        var settings = self.settings
        let preMealStart = Date()
        settings.enablePreMealOverride(at: preMealStart, for: 1 /* hour */ * 60 * 60)
        let actualRange = settings.effectiveGlucoseTargetRangeSchedule(presumingMealEntry: true)?.value(at: preMealStart.addingTimeInterval(30 /* minutes */ * 60))
        XCTAssertEqual(targetRange, actualRange)
    }

    func testScheduleOverride() {
        var settings = self.settings
        let overrideStart = Date()
        let overrideTargetRange = DoubleRange(minValue: 130, maxValue: 150)
        let override = TemporaryScheduleOverride(
            context: .custom,
            settings: TemporaryScheduleOverrideSettings(
                unit: .milligramsPerDeciliter,
                targetRange: overrideTargetRange
            ),
            startDate: overrideStart,
            duration: .finite(3 /* hours */ * 60 * 60),
            enactTrigger: .local,
            syncIdentifier: UUID()
        )
        settings.scheduleOverride = override
        let actualOverrideRange = settings.effectiveGlucoseTargetRangeSchedule()?.value(at: overrideStart.addingTimeInterval(30 /* minutes */ * 60))
        XCTAssertEqual(actualOverrideRange, overrideTargetRange)
    }

    func testBothPreMealAndScheduleOverride() {
        var settings = self.settings
        let preMealStart = Date()
        settings.enablePreMealOverride(at: preMealStart, for: 1 /* hour */ * 60 * 60)

        let overrideStart = Date()
        let overrideTargetRange = DoubleRange(minValue: 130, maxValue: 150)
        let override = TemporaryScheduleOverride(
            context: .custom,
            settings: TemporaryScheduleOverrideSettings(
                unit: .milligramsPerDeciliter,
                targetRange: overrideTargetRange
            ),
            startDate: overrideStart,
            duration: .finite(3 /* hours */ * 60 * 60),
            enactTrigger: .local,
            syncIdentifier: UUID()
        )
        settings.scheduleOverride = override

        let actualPreMealRange = settings.effectiveGlucoseTargetRangeSchedule()?.value(at: preMealStart.addingTimeInterval(30 /* minutes */ * 60))
        XCTAssertEqual(actualPreMealRange, preMealRange)

        // The pre-meal range should be projected into the future, despite the simultaneous schedule override
        let preMealRangeDuringOverride = settings.effectiveGlucoseTargetRangeSchedule()?.value(at: preMealStart.addingTimeInterval(2 /* hours */ * 60 * 60))
        XCTAssertEqual(preMealRangeDuringOverride, preMealRange)
    }

    func testScheduleOverrideWithExpiredPreMealOverride() {
        var settings = self.settings
        settings.preMealOverride = TemporaryScheduleOverride(
            context: .preMeal,
            settings: TemporaryScheduleOverrideSettings(unit: .milligramsPerDeciliter, targetRange: preMealRange),
            startDate: Date(timeIntervalSinceNow: -2 /* hours */ * 60 * 60),
            duration: .finite(1 /* hours */ * 60 * 60),
            enactTrigger: .local,
            syncIdentifier: UUID()
        )

        let overrideStart = Date()
        let overrideTargetRange = DoubleRange(minValue: 130, maxValue: 150)
        let override = TemporaryScheduleOverride(
            context: .custom,
            settings: TemporaryScheduleOverrideSettings(
                unit: .milligramsPerDeciliter,
                targetRange: overrideTargetRange
            ),
            startDate: overrideStart,
            duration: .finite(3 /* hours */ * 60 * 60),
            enactTrigger: .local,
            syncIdentifier: UUID()
        )
        settings.scheduleOverride = override

        let actualOverrideRange = settings.effectiveGlucoseTargetRangeSchedule()?.value(at: overrideStart.addingTimeInterval(2 /* hours */ * 60 * 60))
        XCTAssertEqual(actualOverrideRange, overrideTargetRange)
    }
}
