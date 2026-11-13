//
//  SettingsManager.swift
//  LoopTests
//
//  Created by Pete Schwamb on 12/1/23.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import XCTest
import LoopKit
import LoopCore
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

    private func loopSettings(basal: Double) -> LoopSettings {
        let therapySettings = TherapySettings.mockTherapySettings
        var settings = LoopSettings()
        settings.glucoseTargetRangeSchedule = therapySettings.glucoseTargetRangeSchedule
        settings.carbRatioSchedule = therapySettings.carbRatioSchedule
        settings.insulinSensitivitySchedule = therapySettings.insulinSensitivitySchedule
        settings.basalRateSchedule = BasalRateSchedule(dailyItems: [RepeatingScheduleValue(startTime: 0, value: basal)], timeZone: therapySettings.basalRateSchedule?.timeZone)
        return settings
    }

    private func profile(_ name: String, from settings: LoopSettings) throws -> TherapyProfile {
        var profile = try XCTUnwrap(settings.liveTherapyProfile)
        profile.name = name
        return profile
    }

    func testAnActiveProfileThatIsNotStoredIsRecreatedFromTheLiveSettingsAndDefaultKeepsItsValues() throws {
        var settings = loopSettings(basal: 0.5)
        let defaultProfile = try profile(TherapyProfile.defaultName, from: loopSettings(basal: 1.0))
        let weekend = try profile("Weekend", from: loopSettings(basal: 0.7))
        settings.therapyProfiles = [defaultProfile, weekend]
        settings.activeProfileName = "Sport"

        XCTAssertEqual(settings.synchronizeTherapyProfiles(), "Sport")

        XCTAssertEqual(settings.activeProfileName, "Sport")
        XCTAssertEqual(settings.therapyProfiles.map(\.name), ["Default", "Weekend", "Sport"])
        XCTAssertEqual(settings.therapyProfiles.map { $0.basalRateSchedule.items.map(\.value) }, [[1.0], [0.7], [0.5]])
        XCTAssertNil(settings.synchronizeTherapyProfiles())
    }

    func testAnActiveProfileThatIsNotStoredIsKeptByNameWithoutLiveSettings() throws {
        var settings = LoopSettings()
        let defaultProfile = try profile(TherapyProfile.defaultName, from: loopSettings(basal: 1.0))
        settings.therapyProfiles = [defaultProfile]
        settings.activeProfileName = "Sport"

        XCTAssertNil(settings.synchronizeTherapyProfiles())

        XCTAssertEqual(settings.activeProfileName, "Sport")
        XCTAssertEqual(settings.therapyProfiles, [defaultProfile])
    }

    func testAnActiveProfileWithNoStoredProfilesRecreatesDefaultAndTheActiveProfile() throws {
        var settings = loopSettings(basal: 0.5)
        settings.activeProfileName = "Sport"

        XCTAssertEqual(settings.synchronizeTherapyProfiles(), "Sport")

        XCTAssertEqual(settings.activeProfileName, "Sport")
        XCTAssertEqual(settings.therapyProfiles.map(\.name), ["Default", "Sport"])
        XCTAssertEqual(settings.therapyProfiles.map { $0.basalRateSchedule.items.map(\.value) }, [[0.5], [0.5]])
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
