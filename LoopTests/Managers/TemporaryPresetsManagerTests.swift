//
//  TemporaryPresetsManagerTests.swift
//  LoopTests
//
//  Created by Pete Schwamb on 12/11/23.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import XCTest
import LoopKit
import LoopAlgorithm

@testable import Loop


class TemporaryPresetsManagerTests: XCTestCase {
    private let preMealRange = DoubleRange(minValue: 80, maxValue: 80).quantityRange(for: .milligramsPerDeciliter)
    private let targetRange = DoubleRange(minValue: 95, maxValue: 105)

    private lazy var settings: StoredSettings = {
        var settings = StoredSettings()
        settings.preMealTargetRange = preMealRange
        settings.glucoseTargetRangeSchedule = GlucoseRangeSchedule(
            unit: .milligramsPerDeciliter,
            dailyItems: [.init(startTime: 0, value: targetRange)]
        )
        return settings
    }()

    var manager: TemporaryPresetsManager!

    override func setUp() async throws {
        let settingsProvider = MockSettingsProvider(settings: settings)
        manager = TemporaryPresetsManager(settingsProvider: settingsProvider)
    }

    func testPreMealOverride() {
        var settings = self.settings
        let preMealStart = Date()
        manager.enablePreMealOverride(at: preMealStart, for: 1 /* hour */ * 60 * 60)
        let actualPreMealRange = manager.effectiveGlucoseTargetRangeSchedule()?.quantityRange(at: preMealStart.addingTimeInterval(30 /* minutes */ * 60))
        XCTAssertEqual(preMealRange, actualPreMealRange)
    }

    func testPreMealOverrideWithPotentialCarbEntry() {
        var settings = self.settings
        let preMealStart = Date()
        manager.enablePreMealOverride(at: preMealStart, for: 1 /* hour */ * 60 * 60)
        let actualRange = manager.effectiveGlucoseTargetRangeSchedule(presumingMealEntry: true)?.value(at: preMealStart.addingTimeInterval(30 /* minutes */ * 60))
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
        manager.scheduleOverride = override
        let actualOverrideRange = manager.effectiveGlucoseTargetRangeSchedule()?.value(at: overrideStart.addingTimeInterval(30 /* minutes */ * 60))
        XCTAssertEqual(actualOverrideRange, overrideTargetRange)
    }

    func testBothPreMealAndScheduleOverride() {
        var settings = self.settings
        let preMealStart = Date()
        manager.enablePreMealOverride(at: preMealStart, for: 1 /* hour */ * 60 * 60)

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
        manager.scheduleOverride = override

        let actualPreMealRange = manager.effectiveGlucoseTargetRangeSchedule()?.quantityRange(at: preMealStart.addingTimeInterval(30 /* minutes */ * 60))
        XCTAssertEqual(actualPreMealRange, preMealRange)

        // The pre-meal range should be projected into the future, despite the simultaneous schedule override
        let preMealRangeDuringOverride = manager.effectiveGlucoseTargetRangeSchedule()?.quantityRange(at: preMealStart.addingTimeInterval(2 /* hours */ * 60 * 60))
        XCTAssertEqual(preMealRangeDuringOverride, preMealRange)
    }

    func testScheduleOverrideWithExpiredPreMealOverride() {
        var settings = self.settings
        manager.preMealOverride = TemporaryScheduleOverride(
            context: .preMeal,
            settings: TemporaryScheduleOverrideSettings(targetRange: preMealRange),
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
        manager.scheduleOverride = override

        let actualOverrideRange = manager.effectiveGlucoseTargetRangeSchedule()?.value(at: overrideStart.addingTimeInterval(2 /* hours */ * 60 * 60))
        XCTAssertEqual(actualOverrideRange, overrideTargetRange)
    }
}
