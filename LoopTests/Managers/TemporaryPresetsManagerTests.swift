//
//  TemporaryPresetsManagerTests.swift
//  LoopTests
//
//  Created by Pete Schwamb on 12/11/23.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import XCTest
import LoopKit
import LoopCore

@testable import Loop

@MainActor
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
        let preMealStart = Date()
        manager.enablePreMealOverride(at: preMealStart, for: 1 /* hour */ * 60 * 60)
        let actualPreMealRange = manager.effectiveCorrectionRangeSchedule()?.quantityRange(at: preMealStart.addingTimeInterval(30 /* minutes */ * 60))
        XCTAssertEqual(preMealRange, actualPreMealRange)
    }

    func testPreMealOverrideWithPotentialCarbEntry() {
        let preMealStart = Date()
        manager.enablePreMealOverride(at: preMealStart, for: 1 /* hour */ * 60 * 60)
        let actualRange = manager.effectiveCorrectionRangeSchedule(presumingMealEntry: true)?.value(at: preMealStart.addingTimeInterval(30 /* minutes */ * 60))
        XCTAssertEqual(targetRange, actualRange)
    }

    func testScheduleOverride() {
        let overrideStart = Date()
        let overrideTargetRange = DoubleRange(minValue: 130, maxValue: 150)
        let override = TemporaryScheduleOverride(
            context: .custom,
            settings: TemporaryPresetSettings(
                unit: .milligramsPerDeciliter,
                targetRange: overrideTargetRange
            ),
            startDate: overrideStart,
            duration: .finite(3 /* hours */ * 60 * 60),
            enactTrigger: .local,
            syncIdentifier: UUID()
        )
        manager.scheduleOverride = override
        let actualOverrideRange = manager.effectiveCorrectionRangeSchedule()?.value(at: overrideStart.addingTimeInterval(30 /* minutes */ * 60))
        XCTAssertEqual(actualOverrideRange, overrideTargetRange)
    }

    func testScheduleOverrideWithExpiredPreMealOverride() {
        manager.scheduleOverride = TemporaryScheduleOverride(
            context: .preMeal,
            settings: TemporaryPresetSettings(targetRange: preMealRange),
            startDate: Date(timeIntervalSinceNow: -2 /* hours */ * 60 * 60),
            duration: .finite(1 /* hours */ * 60 * 60),
            enactTrigger: .local,
            syncIdentifier: UUID()
        )

        let overrideStart = Date()
        let overrideTargetRange = DoubleRange(minValue: 130, maxValue: 150)
        let override = TemporaryScheduleOverride(
            context: .custom,
            settings: TemporaryPresetSettings(
                unit: .milligramsPerDeciliter,
                targetRange: overrideTargetRange
            ),
            startDate: overrideStart,
            duration: .finite(3 /* hours */ * 60 * 60),
            enactTrigger: .local,
            syncIdentifier: UUID()
        )
        manager.scheduleOverride = override

        let actualOverrideRange = manager.effectiveCorrectionRangeSchedule()?.value(at: overrideStart.addingTimeInterval(2 /* hours */ * 60 * 60))
        XCTAssertEqual(actualOverrideRange, overrideTargetRange)
    }

    func testHidingActivityPresetsOnlyRemovesThemFromTheList() {
        let userDefaults = UserDefaults(suiteName: UUID().uuidString)!
        let manager = TemporaryPresetsManager(settingsProvider: MockSettingsProvider(settings: settings), presetHistory: TemporaryScheduleOverrideHistory(), userDefaults: userDefaults)
        let activityIDs = ActivityPreset.ActivityType.allCases.map(\.id)
        XCTAssertTrue(manager.showsActivityPresets)
        XCTAssertEqual(manager.listedPresets.filter { activityIDs.contains($0.id) }.count, activityIDs.count)

        manager.showsActivityPresets = false

        XCTAssertTrue(manager.listedPresets.allSatisfy { !activityIDs.contains($0.id) })
        XCTAssertTrue(manager.listedPresets.contains { $0.id == "preMeal" })
        XCTAssertEqual(manager.selectablePresets.filter { activityIDs.contains($0.id) }.count, activityIDs.count, "hidden presets still resolve by id")

        let relaunched = TemporaryPresetsManager(settingsProvider: MockSettingsProvider(settings: settings), presetHistory: TemporaryScheduleOverrideHistory(), userDefaults: userDefaults)
        XCTAssertFalse(relaunched.showsActivityPresets)
    }

    func testSettingsUserInfoCarriesActivityPresetVisibility() {
        let hidden = LoopSettingsUserInfo(loopSettings: LoopSettings(), showsActivityPresets: false)
        XCTAssertEqual(LoopSettingsUserInfo(rawValue: hidden.rawValue)?.showsActivityPresets, false)

        var fromOlderPhone = hidden.rawValue
        fromOlderPhone["a"] = nil
        XCTAssertEqual(LoopSettingsUserInfo(rawValue: fromOlderPhone)?.showsActivityPresets, true)
    }
}
