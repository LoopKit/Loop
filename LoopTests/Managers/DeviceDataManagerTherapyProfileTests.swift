//
//  DeviceDataManagerTherapyProfileTests.swift
//  LoopTests
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import XCTest
import LoopKit
import LoopCore
import LoopKitUI
@testable import Loop

extension DeviceDataManagerTests {

    private func setUpTherapySettings() {
        pumpManager.supportedBasalRates = (0...600).map { (Double($0) * 5).rounded() / 100 }
        settingsManager.therapySettings = TherapySettings.mockTherapySettings
    }

    private func assertThrows(_ expected: TherapyProfileError, file: StaticString = #filePath, line: UInt = #line, _ operation: () async throws -> Void) async {
        do {
            try await operation()
            XCTFail("No error, expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? TherapyProfileError, expected, file: file, line: line)
        }
    }

    private func sportProfile(basal: Double = 0.5) -> TherapyProfile {
        let live = settingsManager.loopSettings.liveTherapyProfile!
        return TherapyProfile(name: "Sport",
                              glucoseTargetRangeSchedule: GlucoseRangeSchedule(unit: .milligramsPerDeciliter, dailyItems: [RepeatingScheduleValue(startTime: 0, value: DoubleRange(minValue: 120, maxValue: 130))], timeZone: live.basalRateSchedule.timeZone)!,
                              carbRatioSchedule: live.carbRatioSchedule,
                              basalRateSchedule: BasalRateSchedule(dailyItems: [RepeatingScheduleValue(startTime: 0, value: basal)], timeZone: live.basalRateSchedule.timeZone)!,
                              insulinSensitivitySchedule: live.insulinSensitivitySchedule)
    }

    func testCreatingProfileKeepsDefaultActiveAndPumpUntouched() async throws {
        setUpTherapySettings()
        let liveBefore = settingsManager.loopSettings.liveTherapyProfile!

        try await deviceDataManager.saveTherapyProfile(sportProfile(), originalName: nil)

        XCTAssertEqual(deviceDataManager.therapyProfiles.map(\.name), ["Default", "Sport"])
        XCTAssertEqual(deviceDataManager.activeTherapyProfileName, "Default")
        XCTAssertTrue(settingsManager.loopSettings.liveTherapyProfile!.hasSameValues(as: liveBefore))
        XCTAssertNil(pumpManager.basalRateSchedule)
    }

    func testActivatingProfileWritesPumpThenSettings() async throws {
        setUpTherapySettings()
        let defaultValues = settingsManager.loopSettings.liveTherapyProfile!
        try await deviceDataManager.saveTherapyProfile(sportProfile(), originalName: nil)

        try await deviceDataManager.activateTherapyProfile(named: "Sport")

        XCTAssertEqual(pumpManager.basalRateSchedule?.items.map(\.value), [0.5])
        XCTAssertEqual(settingsManager.loopSettings.activeProfileName, "Sport")
        XCTAssertEqual(settingsManager.loopSettings.basalRateSchedule?.items.map(\.value), [0.5])
        XCTAssertEqual(settingsManager.loopSettings.glucoseTargetRangeSchedule?.items.map(\.value.minValue), [120])
        XCTAssertEqual(settingsManager.settings.activeProfileName, "Sport")
        XCTAssertTrue(deviceDataManager.therapyProfile(named: "Default")!.hasSameValues(as: defaultValues))

        try await deviceDataManager.activateTherapyProfile(named: "Default")
        XCTAssertNil(settingsManager.loopSettings.activeProfileName)
        XCTAssertTrue(settingsManager.loopSettings.liveTherapyProfile!.hasSameValues(as: defaultValues))
    }

    func testPumpFailureLeavesSettingsUnchanged() async throws {
        setUpTherapySettings()
        try await deviceDataManager.saveTherapyProfile(sportProfile(), originalName: nil)
        let before = settingsManager.loopSettings
        pumpManager.basalRateScheduleSyncError = PumpManagerError.communication(nil)

        do {
            try await deviceDataManager.activateTherapyProfile(named: "Sport")
            XCTFail("Activation succeeded although the pump failed")
        } catch {
            XCTAssertEqual(error as? TherapyProfileError, .pumpSyncFailed(PumpManagerError.communication(nil).localizedDescription))
        }
        XCTAssertEqual(settingsManager.loopSettings, before)

        try await deviceDataManager.activateTherapyProfile(named: "Default")
        do {
            var edited = deviceDataManager.therapyProfile(named: "Default")!
            edited.basalRateSchedule = BasalRateSchedule(dailyItems: [RepeatingScheduleValue(startTime: 0, value: 0.7)], timeZone: edited.basalRateSchedule.timeZone)!
            try await deviceDataManager.saveTherapyProfile(edited, originalName: "Default")
            XCTFail("Saving the active profile succeeded although the pump failed")
        } catch {
            XCTAssertEqual(error as? TherapyProfileError, .pumpSyncFailed(PumpManagerError.communication(nil).localizedDescription))
        }
        XCTAssertEqual(settingsManager.loopSettings, before)
    }

    func testSuspendedPumpRefusesBasalChangesAndKeepsOtherEdits() async throws {
        setUpTherapySettings()
        try await deviceDataManager.saveTherapyProfile(sportProfile(), originalName: nil)
        let status = pumpManager.status
        pumpManager.status = PumpManagerStatus(timeZone: status.timeZone, device: status.device, pumpBatteryChargeRemaining: nil,
                                               basalDeliveryState: .suspended(Date()), bolusState: .noBolus, insulinType: status.insulinType)
        let before = settingsManager.loopSettings

        await assertThrows(.pumpSuspended) { try await self.deviceDataManager.activateTherapyProfile(named: "Sport") }
        var edited = deviceDataManager.therapyProfile(named: "Default")!
        edited.basalRateSchedule = BasalRateSchedule(dailyItems: [RepeatingScheduleValue(startTime: 0, value: 0.7)], timeZone: edited.basalRateSchedule.timeZone)!
        await assertThrows(.pumpSuspended) { try await self.deviceDataManager.saveTherapyProfile(edited, originalName: "Default") }
        let editorRefused = expectation(description: "Editor basal sync refused")
        deviceDataManager.syncBasalRateSchedule(items: [RepeatingScheduleValue(startTime: 0, value: 0.7)]) { result in
            if case .failure(let error) = result {
                XCTAssertEqual(error as? TherapyProfileError, .pumpSuspended)
            } else {
                XCTFail("Editor basal sync reached a suspended pump")
            }
            editorRefused.fulfill()
        }
        await fulfillment(of: [editorRefused], timeout: 2)
        XCTAssertFalse(deviceDataManager.therapyProfileChangeInProgress)
        XCTAssertEqual(settingsManager.loopSettings, before)
        XCTAssertNil(pumpManager.basalRateSchedule)

        // Profiles that do not reach the pump can still be changed.
        try await deviceDataManager.saveTherapyProfile(sportProfile(basal: 0.6), originalName: "Sport")
        XCTAssertEqual(deviceDataManager.therapyProfile(named: "Sport")?.basalRateSchedule.items.map(\.value), [0.6])
        XCTAssertNil(pumpManager.basalRateSchedule)
    }

    func testValidationRejectsBeforePump() async throws {
        setUpTherapySettings()
        do {
            try await deviceDataManager.saveTherapyProfile(sportProfile(basal: 9.0), originalName: nil)
            XCTFail("A basal rate above the maximum was saved")
        } catch {
            XCTAssertEqual(error as? TherapyProfileError, .basalRateAboveMaximum(9.0))
        }
        XCTAssertEqual(deviceDataManager.therapyProfiles.map(\.name), ["Default"])
        XCTAssertNil(pumpManager.basalRateSchedule)
    }

    func testEditingTherapySettingsWritesThroughToActiveProfile() async throws {
        setUpTherapySettings()
        let defaultValues = settingsManager.loopSettings.liveTherapyProfile!
        try await deviceDataManager.saveTherapyProfile(sportProfile(), originalName: nil)
        try await deviceDataManager.activateTherapyProfile(named: "Sport")

        var therapySettings = settingsManager.therapySettings
        therapySettings.carbRatioSchedule = CarbRatioSchedule(unit: .gram, dailyItems: [RepeatingScheduleValue(startTime: 0, value: 7)], timeZone: therapySettings.carbRatioSchedule!.timeZone)
        deviceDataManager.saveCompletion(therapySettings: therapySettings)

        XCTAssertEqual(deviceDataManager.therapyProfile(named: "Sport")?.carbRatioSchedule.items.map(\.value), [7])
        XCTAssertTrue(deviceDataManager.therapyProfile(named: "Default")!.hasSameValues(as: defaultValues))
        XCTAssertEqual(settingsManager.settings.therapyProfiles.first { $0.name == "Sport" }?.carbRatioSchedule.items.map(\.value), [7])
    }

    func testEditingProfileThatIsNotActiveLeavesLiveSettings() async throws {
        setUpTherapySettings()
        let live = settingsManager.loopSettings
        try await deviceDataManager.saveTherapyProfile(sportProfile(), originalName: nil)

        try await deviceDataManager.saveTherapyProfile(sportProfile(basal: 0.6), originalName: "Sport")

        XCTAssertEqual(deviceDataManager.therapyProfile(named: "Sport")?.basalRateSchedule.items.map(\.value), [0.6])
        XCTAssertEqual(settingsManager.loopSettings.basalRateSchedule, live.basalRateSchedule)
        XCTAssertNil(pumpManager.basalRateSchedule)
    }

    func testFingerprintMismatchRejectsChangeAndDeleteRules() async throws {
        setUpTherapySettings()
        try await deviceDataManager.saveTherapyProfile(sportProfile(), originalName: nil)
        let before = settingsManager.loopSettings
        let sportFingerprint = try XCTUnwrap(sportProfile().fingerprint(unit: .milligramsPerDeciliter))

        await assertThrows(.conflict) { try await self.deviceDataManager.activateTherapyProfile(named: "Sport", expectedFingerprint: "0000000000000000", trigger: .remote) }
        await assertThrows(.conflict) { try await self.deviceDataManager.saveTherapyProfile(self.sportProfile(basal: 0.6), originalName: "Sport", expectedFingerprint: "0000000000000000") }
        await assertThrows(.conflict) { try await self.deviceDataManager.deleteTherapyProfile(named: "Sport", expectedFingerprint: "0000000000000000") }
        XCTAssertEqual(settingsManager.loopSettings, before)
        XCTAssertNil(pumpManager.basalRateSchedule)

        await assertThrows(.cannotDeleteDefault) { try await self.deviceDataManager.deleteTherapyProfile(named: "Default", expectedFingerprint: "0000000000000000") }
        try await deviceDataManager.activateTherapyProfile(named: "Sport", expectedFingerprint: sportFingerprint, trigger: .remote)
        await assertThrows(.cannotDeleteActive) { try await self.deviceDataManager.deleteTherapyProfile(named: "Sport", expectedFingerprint: "0000000000000000") }
        try await deviceDataManager.activateTherapyProfile(named: "Default")
        try await deviceDataManager.deleteTherapyProfile(named: "Sport", expectedFingerprint: sportFingerprint)
        XCTAssertEqual(deviceDataManager.therapyProfiles.map(\.name), ["Default"])
        XCTAssertEqual(settingsManager.loopSettings.therapyProfiles, [])
    }

    // MARK: Editors and profile changes

    func testEditorSaveFromPreviousActiveProfileIsRefused() async throws {
        setUpTherapySettings()
        let defaultValues = settingsManager.loopSettings.liveTherapyProfile!
        try await deviceDataManager.saveTherapyProfile(sportProfile(), originalName: nil)
        let editorSettings = settingsManager.therapySettings
        try await deviceDataManager.activateTherapyProfile(named: "Sport")
        let sportValues = settingsManager.loopSettings.liveTherapyProfile!

        XCTAssertThrowsError(try deviceDataManager.validateTherapySettingsEdit(from: editorSettings)) {
            XCTAssertEqual($0 as? TherapyProfileError, .activeProfileChangedWhileEditing("Sport"))
        }
        var edited = editorSettings
        edited.carbRatioSchedule = CarbRatioSchedule(unit: .gram, dailyItems: [RepeatingScheduleValue(startTime: 0, value: 7)], timeZone: edited.carbRatioSchedule!.timeZone)
        deviceDataManager.saveCompletion(therapySettings: edited)

        XCTAssertEqual(settingsManager.loopSettings.activeProfileName, "Sport")
        XCTAssertTrue(settingsManager.loopSettings.liveTherapyProfile!.hasSameValues(as: sportValues))
        XCTAssertTrue(deviceDataManager.therapyProfile(named: "Default")!.hasSameValues(as: defaultValues))
    }

    func testEditorSaveAfterActiveProfileChangedElsewhereIsRefused() async throws {
        setUpTherapySettings()
        let editorSettings = settingsManager.therapySettings
        XCTAssertNoThrow(try deviceDataManager.validateTherapySettingsEdit(from: editorSettings))

        var remote = deviceDataManager.therapyProfile(named: "Default")!
        remote.basalRateSchedule = BasalRateSchedule(dailyItems: [RepeatingScheduleValue(startTime: 0, value: 0.7)], timeZone: remote.basalRateSchedule.timeZone)!
        try await deviceDataManager.saveTherapyProfile(remote, originalName: "Default")

        XCTAssertThrowsError(try deviceDataManager.validateTherapySettingsEdit(from: editorSettings)) {
            XCTAssertEqual($0 as? TherapyProfileError, .settingsChangedWhileEditing)
        }
        XCTAssertNoThrow(try deviceDataManager.validateTherapySettingsEdit(from: settingsManager.therapySettings))
    }

    func testEditorBasalSyncHoldsOffProfileChanges() async throws {
        setUpTherapySettings()
        try await deviceDataManager.saveTherapyProfile(sportProfile(), originalName: nil)
        pumpManager.holdsBasalRateScheduleSync = true

        let synced = expectation(description: "Editor basal sync finished")
        deviceDataManager.syncBasalRateSchedule(items: [RepeatingScheduleValue(startTime: 0, value: 0.9)]) { result in
            XCTAssertNotNil(try? result.get())
            synced.fulfill()
        }
        await assertThrows(.operationInProgress) { try await self.deviceDataManager.activateTherapyProfile(named: "Sport") }
        XCTAssertThrowsError(try deviceDataManager.validateTherapySettingsEdit(from: settingsManager.therapySettings)) {
            XCTAssertEqual($0 as? TherapyProfileError, .operationInProgress)
        }

        pumpManager.holdsBasalRateScheduleSync = false
        pumpManager.finishBasalRateScheduleSync()
        await fulfillment(of: [synced], timeout: 2)
        try await deviceDataManager.activateTherapyProfile(named: "Sport")
        XCTAssertEqual(pumpManager.basalRateSchedule?.items.map(\.value), [0.5])
    }

    func testEditorBasalSyncIsRefusedWhileProfileSwitches() async throws {
        setUpTherapySettings()
        try await deviceDataManager.saveTherapyProfile(sportProfile(), originalName: nil)
        pumpManager.holdsBasalRateScheduleSync = true

        let switching = Task { try await deviceDataManager.activateTherapyProfile(named: "Sport") }
        while !deviceDataManager.therapyProfileChangeInProgress {
            await Task.yield()
        }
        let refused = expectation(description: "Editor basal sync refused")
        deviceDataManager.syncBasalRateSchedule(items: [RepeatingScheduleValue(startTime: 0, value: 0.9)]) { result in
            if case .failure(let error) = result {
                XCTAssertEqual(error as? TherapyProfileError, .operationInProgress)
            } else {
                XCTFail("Editor basal sync ran during a profile switch")
            }
            refused.fulfill()
        }
        await fulfillment(of: [refused], timeout: 2)

        pumpManager.holdsBasalRateScheduleSync = false
        while deviceDataManager.therapyProfileChangeInProgress {
            pumpManager.finishBasalRateScheduleSync()
            await Task.yield()
        }
        try await switching.value
        XCTAssertEqual(pumpManager.basalRateSchedule?.items.map(\.value), [0.5])
        XCTAssertEqual(settingsManager.loopSettings.basalRateSchedule?.items.map(\.value), [0.5])
    }

    func testSecondProfileCommandWhileOneRunsIsRefused() async throws {
        setUpTherapySettings()
        try await deviceDataManager.saveTherapyProfile(sportProfile(), originalName: nil)
        pumpManager.holdsBasalRateScheduleSync = true

        let switching = Task { try await deviceDataManager.activateTherapyProfile(named: "Sport") }
        while !deviceDataManager.therapyProfileChangeInProgress {
            await Task.yield()
        }
        await assertThrows(.operationInProgress) { try await self.deviceDataManager.activateTherapyProfile(named: "Default") }
        await assertThrows(.operationInProgress) { try await self.deviceDataManager.saveTherapyProfile(self.sportProfile(basal: 0.6), originalName: "Sport") }

        pumpManager.holdsBasalRateScheduleSync = false
        while deviceDataManager.therapyProfileChangeInProgress {
            pumpManager.finishBasalRateScheduleSync()
            await Task.yield()
        }
        try await switching.value
        XCTAssertEqual(deviceDataManager.activeTherapyProfileName, "Sport")
        XCTAssertEqual(settingsManager.loopSettings.basalRateSchedule?.items.map(\.value), [0.5])
    }

    func testEditorBasalSaveAfterProfileSwitchIsRefused() async throws {
        setUpTherapySettings()
        let defaultValues = settingsManager.loopSettings.liveTherapyProfile!
        try await deviceDataManager.saveTherapyProfile(sportProfile(), originalName: nil)
        let editor = TherapySettingsViewModel(therapySettings: settingsManager.therapySettings, delegate: deviceDataManager)

        let synced = expectation(description: "Editor basal sync finished")
        var syncedSchedule: BasalRateSchedule?
        editor.syncBasalRateSchedule(items: [RepeatingScheduleValue(startTime: 0, value: 0.9)]) { result in
            syncedSchedule = try? result.get()
            synced.fulfill()
        }
        await fulfillment(of: [synced], timeout: 2)
        try await deviceDataManager.activateTherapyProfile(named: "Sport")

        // The editor saves the synced schedule on the next main queue turn, after the switch finished.
        editor.saveBasalRates(basalRates: try XCTUnwrap(syncedSchedule))

        XCTAssertEqual(editor.saveError as? TherapyProfileError, .activeProfileChangedWhileEditing("Sport"))
        XCTAssertEqual(settingsManager.loopSettings.activeProfileName, "Sport")
        XCTAssertEqual(settingsManager.loopSettings.basalRateSchedule?.items.map(\.value), [0.5])
        XCTAssertEqual(pumpManager.basalRateSchedule?.items.map(\.value), [0.5])
        XCTAssertTrue(deviceDataManager.therapyProfile(named: "Default")!.hasSameValues(as: defaultValues))
    }

    // MARK: Time zones

    private func setPumpTimeZone(_ timeZone: TimeZone) {
        let status = pumpManager.status
        pumpManager.status = PumpManagerStatus(timeZone: timeZone, device: status.device, pumpBatteryChargeRemaining: status.pumpBatteryChargeRemaining,
                                               basalDeliveryState: status.basalDeliveryState, bolusState: status.bolusState, insulinType: status.insulinType)
        settingsManager.setScheduleTimeZone(timeZone)
    }

    func testProfilesFollowThePumpTimeZoneWithoutMovingStartTimes() async throws {
        setUpTherapySettings()
        let home = TimeZone(secondsFromGMT: 3600)!
        let travel = TimeZone(secondsFromGMT: -5 * 3600)!
        setPumpTimeZone(home)
        let multiSegment = BasalRateSchedule(dailyItems: [RepeatingScheduleValue(startTime: 0, value: 0.5),
                                                          RepeatingScheduleValue(startTime: 7200, value: 0.6),
                                                          RepeatingScheduleValue(startTime: 9000, value: 0.7)], timeZone: home)!
        var sport = sportProfile()
        sport.basalRateSchedule = multiSegment
        try await deviceDataManager.saveTherapyProfile(sport, originalName: nil)

        // The pump clock moves to a new time zone (travel, or a daylight saving change synced to the pump).
        setPumpTimeZone(travel)
        XCTAssertEqual(deviceDataManager.therapyProfile(named: "Sport")?.basalRateSchedule.timeZone, travel)

        try await deviceDataManager.activateTherapyProfile(named: "Sport")
        let live = settingsManager.loopSettings
        XCTAssertEqual(live.basalRateSchedule?.items.map(\.startTime), [0, 7200, 9000])
        XCTAssertEqual([live.basalRateSchedule?.timeZone, live.carbRatioSchedule?.timeZone, live.insulinSensitivitySchedule?.timeZone, live.glucoseTargetRangeSchedule?.timeZone], [travel, travel, travel, travel])
        let localTwoThirty = DateComponents(calendar: Calendar(identifier: .gregorian), timeZone: travel, year: 2026, month: 3, day: 29, hour: 2, minute: 30).date!
        XCTAssertEqual(live.basalRateSchedule?.value(at: localTwoThirty), 0.7)

        // A save made in another time zone (a follower's phone) is stored in the live time zone.
        var edited = deviceDataManager.therapyProfile(named: "Sport")!.withTimeZone(TimeZone(identifier: "Asia/Tokyo")!)
        edited.carbRatioSchedule = CarbRatioSchedule(unit: .gram, dailyItems: [RepeatingScheduleValue(startTime: 0, value: 9), RepeatingScheduleValue(startTime: 1800, value: 8)], timeZone: edited.carbRatioSchedule.timeZone)!
        try await deviceDataManager.saveTherapyProfile(edited, originalName: "Sport")
        XCTAssertEqual(settingsManager.loopSettings.carbRatioSchedule?.timeZone, travel)
        XCTAssertEqual(settingsManager.loopSettings.carbRatioSchedule?.items.map(\.startTime), [0, 1800])
        XCTAssertEqual(deviceDataManager.therapyProfile(named: "Sport")?.carbRatioSchedule.timeZone, travel)
    }

    // MARK: Renames and unknown names

    func testRenameAndCopyWithoutMaximumBasalRate() async throws {
        setUpTherapySettings()
        try await deviceDataManager.saveTherapyProfile(sportProfile(), originalName: nil)
        settingsManager.mutateLoopSettings { $0.maximumBasalRatePerHour = nil }

        var renamed = deviceDataManager.therapyProfile(named: "Sport")!
        renamed.name = "Running"
        try await deviceDataManager.saveTherapyProfile(renamed, originalName: "Sport")
        var copy = renamed
        copy.name = "Copy"
        try await deviceDataManager.saveTherapyProfile(copy, originalName: nil)
        XCTAssertEqual(deviceDataManager.therapyProfiles.map(\.name), ["Default", "Running", "Copy"])

        await assertThrows(.maximumBasalRateNotSet) { try await self.deviceDataManager.saveTherapyProfile(self.sportProfile(basal: 0.6), originalName: nil) }
        await assertThrows(.maximumBasalRateNotSet) { try await self.deviceDataManager.activateTherapyProfile(named: "Running") }
    }

    func testUnknownActiveProfileNameIsStoredAgainWithTheLiveSettings() async throws {
        setUpTherapySettings()
        try await deviceDataManager.saveTherapyProfile(sportProfile(), originalName: nil)
        let live = settingsManager.loopSettings.liveTherapyProfile!
        let storedDefault = deviceDataManager.therapyProfile(named: "Default")!

        settingsManager.mutateLoopSettings { $0.activeProfileName = "Missing" }

        XCTAssertEqual(settingsManager.loopSettings.activeProfileName, "Missing")
        XCTAssertEqual(deviceDataManager.activeTherapyProfileName, "Missing")
        XCTAssertEqual(deviceDataManager.therapyProfiles.map(\.name), ["Default", "Sport", "Missing"])
        XCTAssertTrue(deviceDataManager.therapyProfile(named: "Missing")!.hasSameValues(as: live))
        XCTAssertEqual(deviceDataManager.therapyProfile(named: "Default"), storedDefault)
    }
}
