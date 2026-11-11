//
//  SettingsManager.swift
//  LoopTests
//
//  Created by Pete Schwamb on 12/1/23.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import XCTest
import LoopKit
@testable import Loop

@MainActor
final class SettingsManagerTests: XCTestCase {


    func testChangingMaxBasalUpdatesLoopData() async {

        let persistenceController = PersistenceController.mock()

        let settingsManager = SettingsManager(cacheStore: persistenceController, expireAfter: .days(1), alertMuter: AlertMuter())

        let exp = expectation(description: #function)
        let observer = NotificationCenter.default.addObserver(forName: .LoopDataUpdated, object: settingsManager, queue: nil) { _ in
            exp.fulfill()
        }

        settingsManager.mutateLoopSettings { $0.maximumBasalRatePerHour = 2.0 }

        await fulfillment(of: [exp], timeout: 1.0)
        NotificationCenter.default.removeObserver(observer)
    }

    func testTherapySettingsWithProfilesAreKeptWithTheActiveProfile() throws {
        let settingsManager = SettingsManager(cacheStore: PersistenceController.mock(), expireAfter: .days(1), alertMuter: AlertMuter())
        var therapySettings = TherapySettings.mockTherapySettings
        var sport = try XCTUnwrap(TherapyProfile(name: "Sport",
                                                 glucoseTargetRangeSchedule: therapySettings.glucoseTargetRangeSchedule,
                                                 carbRatioSchedule: therapySettings.carbRatioSchedule,
                                                 basalRateSchedule: therapySettings.basalRateSchedule,
                                                 insulinSensitivitySchedule: therapySettings.insulinSensitivitySchedule))
        var defaultProfile = sport
        defaultProfile.name = TherapyProfile.defaultName
        sport.basalRateSchedule = BasalRateSchedule(dailyItems: [RepeatingScheduleValue(startTime: 0, value: 0.5)], timeZone: sport.basalRateSchedule.timeZone)!
        therapySettings.basalRateSchedule = sport.basalRateSchedule
        therapySettings.therapyProfiles = [defaultProfile, sport]
        therapySettings.activeProfileName = "Sport"

        settingsManager.therapySettings = therapySettings

        let stored = settingsManager.settings
        XCTAssertEqual(stored.therapyProfiles.map(\.name), ["Default", "Sport"])
        XCTAssertEqual(stored.activeProfileName, "Sport")
        XCTAssertEqual(stored.basalRateSchedule?.items.map(\.value), [0.5])
        XCTAssertEqual(stored.therapyProfiles[1].basalRateSchedule.items.map(\.value), [0.5])

        therapySettings.therapyProfiles = nil
        therapySettings.activeProfileName = nil
        settingsManager.therapySettings = therapySettings

        XCTAssertEqual(settingsManager.settings.therapyProfiles.map(\.name), ["Default", "Sport"])
        XCTAssertEqual(settingsManager.settings.activeProfileName, "Sport")
    }

    func testSettingsAreStoredOnceTheDevicesAreKnown() async throws {
        let settingsManager = SettingsManager(cacheStore: PersistenceController.mock(), expireAfter: .days(1), alertMuter: AlertMuter())
        let settingsStore = try XCTUnwrap(settingsManager.settingsStore)

        settingsManager.remoteNotificationRegistrationDidFinish(.success(Data([0xAB])))
        settingsManager.mutateLoopSettings { $0.maximumBasalRatePerHour = 2.0 }
        settingsManager.deviceStatusProvider = DeviceStatusProviderStub()

        var stored: [StoredSettings] = []
        for _ in 0..<20 where stored.isEmpty {
            try await Task.sleep(nanoseconds: 100_000_000)
            stored = try await settingsStore.getStoredSettings(limit: 10)
        }
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored.first?.deviceToken, "ab")
        XCTAssertEqual(stored.first?.maximumBasalRatePerHour, 2.0)
        XCTAssertEqual(stored.first?.pumpSupportedBasalRates, [0.05, 0.1])
    }
}

private struct DeviceStatusProviderStub: DeviceStatusProvider {
    var pumpManagerStatus: PumpManagerStatus? { nil }
    var cgmManagerStatus: CGMManagerStatus? { nil }
    var pumpSupportedBasalRates: [Double]? { [0.05, 0.1] }
    var pumpMaximumBasalScheduleEntryCount: Int? { nil }
}
