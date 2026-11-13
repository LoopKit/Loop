//
//  DeviceDataManagerScheduledProfileSwitchTests.swift
//  LoopTests
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import XCTest
import LoopKit
import LoopCore
@testable import Loop

@MainActor
final class RecordingAlertIssuer: AlertIssuer {
    private(set) var issued: [LoopKit.Alert] = []
    private(set) var retracted: [LoopKit.Alert.Identifier] = []

    func issueAlert(_ alert: LoopKit.Alert) async {
        issued.append(alert)
    }

    func retractAlert(identifier: LoopKit.Alert.Identifier) async {
        retracted.append(identifier)
    }

    var pending: [LoopKit.Alert] {
        issued.filter { $0.identifier.alertIdentifier == "pending" }
    }

    var failures: [LoopKit.Alert] {
        issued.filter { $0.identifier.alertIdentifier != "pending" }
    }
}

extension DeviceDataManagerTests {

    private var scheduleCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        // The schedules follow the pump's time zone.
        calendar.timeZone = pumpManager.status.timeZone
        return calendar
    }

    /// A start time two hours before the tests run, on a whole minute, so a switch made by hand is after it.
    private static let occurrenceTime = Date(timeIntervalSinceReferenceDate: (Date().timeIntervalSinceReferenceDate / 60).rounded(.down) * 60 - .hours(2))

    private var occurrence: Date {
        Self.occurrenceTime
    }

    private func start(_ profileName: String, at date: Date, id: String = UUID().uuidString, paused: Bool = false) -> ScheduledProfileSwitch {
        let components = scheduleCalendar.dateComponents([.weekday, .hour, .minute], from: date)
        return ScheduledProfileSwitch(id: id, profileName: profileName, weekday: components.weekday!, time: TimeInterval(components.hour! * 3600 + components.minute! * 60), paused: paused)
    }

    /// Default active, a stored Sport profile, `entries` saved and settled at `settledAt`.
    private func setUpSchedule(_ entries: (Date) -> [ScheduledProfileSwitch], settledAt: Date) async throws -> RecordingAlertIssuer {
        pumpManager.supportedBasalRates = (0...600).map { (Double($0) * 5).rounded() / 100 }
        settingsManager.therapySettings = TherapySettings.mockTherapySettings
        settingsManager.setScheduleTimeZone(pumpManager.status.timeZone)
        let live = settingsManager.loopSettings.liveTherapyProfile!
        var sport = live
        sport.name = "Sport"
        sport.basalRateSchedule = BasalRateSchedule(dailyItems: [RepeatingScheduleValue(startTime: 0, value: 0.5)], timeZone: live.basalRateSchedule.timeZone)!
        try await deviceDataManager.saveTherapyProfile(sport, originalName: nil)
        let issuer = RecordingAlertIssuer()
        deviceDataManager.scheduledProfileSwitchAlertIssuer = issuer
        try await deviceDataManager.saveScheduledProfileSwitches(entries(occurrence), expectedFingerprint: nil)
        settingsManager.mutateLoopSettings { settings in
            settings.scheduledSwitchesSettledAt = settledAt
        }
        return issuer
    }

    private func storedSettingsCount() async throws -> Int {
        try await settingsManager.settingsStore!.getStoredSettings(start: .distantPast).count
    }

    func testDueStartSwitchesWithTheScheduledTriggerAndSettlesAtItsTime() async throws {
        let issuer = try await setUpSchedule({ [self.start("Sport", at: $0)] }, settledAt: occurrence.addingTimeInterval(-.hours(1)))
        let pendingBefore = issuer.pending.count

        await deviceDataManager.runDueScheduledProfileSwitch(now: occurrence.addingTimeInterval(.minutes(3)))

        XCTAssertEqual(deviceDataManager.activeTherapyProfileName, "Sport")
        XCTAssertEqual(pumpManager.basalRateSchedule?.items.map(\.value), [0.5])
        XCTAssertEqual(settingsManager.loopSettings.activeProfileSwitchTrigger, .scheduled)
        XCTAssertEqual(settingsManager.loopSettings.scheduledSwitchesSettledAt, occurrence)
        XCTAssertEqual(settingsManager.settings.activeProfileSwitchTrigger, .scheduled)
        XCTAssertTrue(issuer.failures.isEmpty)
        // The pending alert moves to the next start, a week later.
        XCTAssertEqual(issuer.retracted.last?.alertIdentifier, "pending")
        XCTAssertEqual(issuer.pending.count, pendingBefore, "The only start makes Sport active, so nothing is pending while Sport is")
    }

    func testStartWhoseProfileIsActiveIsSettledWithoutASwitch() async throws {
        _ = try await setUpSchedule({ [self.start("Default", at: $0)] }, settledAt: occurrence.addingTimeInterval(-.hours(1)))
        let before = settingsManager.loopSettings

        await deviceDataManager.runDueScheduledProfileSwitch(now: occurrence.addingTimeInterval(.minutes(3)))

        XCTAssertNil(pumpManager.basalRateSchedule)
        XCTAssertEqual(settingsManager.loopSettings.activeProfileName, before.activeProfileName)
        XCTAssertNil(settingsManager.loopSettings.activeProfileSwitchTrigger)
        XCTAssertEqual(settingsManager.loopSettings.scheduledSwitchesSettledAt, occurrence.addingTimeInterval(.minutes(3)))
    }

    func testManualSwitchAfterTheStartHolds() async throws {
        _ = try await setUpSchedule({ [self.start("Sport", at: $0)] }, settledAt: occurrence.addingTimeInterval(-.hours(1)))
        try await deviceDataManager.activateTherapyProfile(named: "Sport")
        try await deviceDataManager.activateTherapyProfile(named: "Default")
        XCTAssertEqual(settingsManager.loopSettings.activeProfileSwitchTrigger, .local)
        let settledByHand = try XCTUnwrap(settingsManager.loopSettings.scheduledSwitchesSettledAt)

        await deviceDataManager.runDueScheduledProfileSwitch(now: max(settledByHand, occurrence).addingTimeInterval(.minutes(1)))

        XCTAssertEqual(deviceDataManager.activeTherapyProfileName, "Default")
    }

    func testOnlyTheNewestOfTwoMissedStartsRuns() async throws {
        _ = try await setUpSchedule({ [self.start("Sport", at: $0.addingTimeInterval(-.hours(2))), self.start("Default", at: $0)] }, settledAt: occurrence.addingTimeInterval(-.hours(3)))
        try await deviceDataManager.activateTherapyProfile(named: "Sport")
        settingsManager.mutateLoopSettings { settings in
            settings.scheduledSwitchesSettledAt = self.occurrence.addingTimeInterval(-.hours(3))
        }

        await deviceDataManager.runDueScheduledProfileSwitch(now: occurrence.addingTimeInterval(.minutes(10)))

        XCTAssertEqual(deviceDataManager.activeTherapyProfileName, "Default")
        XCTAssertEqual(settingsManager.loopSettings.scheduledSwitchesSettledAt, occurrence)
    }

    func testStartOlderThanTheGraceIsReportedAndNotRun() async throws {
        let issuer = try await setUpSchedule({ [self.start("Sport", at: $0)] }, settledAt: occurrence.addingTimeInterval(-.hours(1)))
        let now = occurrence.addingTimeInterval(.hours(25))

        await deviceDataManager.runDueScheduledProfileSwitch(now: now)

        XCTAssertEqual(deviceDataManager.activeTherapyProfileName, "Default")
        XCTAssertNil(pumpManager.basalRateSchedule)
        XCTAssertEqual(settingsManager.loopSettings.scheduledSwitchesSettledAt, now)
        XCTAssertEqual(issuer.failures.count, 1)
        XCTAssertEqual(issuer.failures.first?.interruptionLevel, .timeSensitive)
        XCTAssertEqual(issuer.failures.first?.trigger, .immediate)
    }

    func testStartWithinTheGraceRunsLate() async throws {
        _ = try await setUpSchedule({ [self.start("Sport", at: $0)] }, settledAt: occurrence.addingTimeInterval(-.hours(1)))

        await deviceDataManager.runDueScheduledProfileSwitch(now: occurrence.addingTimeInterval(.hours(23)))

        XCTAssertEqual(deviceDataManager.activeTherapyProfileName, "Sport")
        XCTAssertEqual(settingsManager.loopSettings.scheduledSwitchesSettledAt, occurrence)
    }

    func testPumpFailureIsRetriedAndArmsTheLateAlertWithTheReason() async throws {
        let issuer = try await setUpSchedule({ [self.start("Sport", at: $0)] }, settledAt: occurrence.addingTimeInterval(-.hours(1)))
        let settledBefore = settingsManager.loopSettings.scheduledSwitchesSettledAt
        pumpManager.basalRateScheduleSyncError = PumpManagerError.communication(nil)

        await deviceDataManager.runDueScheduledProfileSwitch(now: occurrence.addingTimeInterval(.minutes(5)))

        XCTAssertEqual(deviceDataManager.activeTherapyProfileName, "Default")
        XCTAssertEqual(settingsManager.loopSettings.scheduledSwitchesSettledAt, settledBefore)
        XCTAssertTrue(issuer.failures.isEmpty)
        let pending = try XCTUnwrap(issuer.pending.last)
        XCTAssertEqual(pending.trigger, .delayed(interval: .minutes(25)))
        XCTAssertTrue(pending.backgroundContent.body.contains(TherapyProfileError.pumpSyncFailed(PumpManagerError.communication(nil).localizedDescription).localizedDescription))

        // Once delivered, a retry leaves the alert in place.
        let retractions = issuer.retracted.count
        await deviceDataManager.runDueScheduledProfileSwitch(now: occurrence.addingTimeInterval(.minutes(35)))
        XCTAssertEqual(issuer.retracted.count, retractions)
        XCTAssertEqual(deviceDataManager.activeTherapyProfileName, "Default")

        pumpManager.basalRateScheduleSyncError = nil
        await deviceDataManager.runDueScheduledProfileSwitch(now: occurrence.addingTimeInterval(.minutes(40)))
        XCTAssertEqual(deviceDataManager.activeTherapyProfileName, "Sport")
        XCTAssertEqual(settingsManager.loopSettings.scheduledSwitchesSettledAt, occurrence)
    }

    func testSuspendedPumpIsRetried() async throws {
        _ = try await setUpSchedule({ [self.start("Sport", at: $0)] }, settledAt: occurrence.addingTimeInterval(-.hours(1)))
        let status = pumpManager.status
        pumpManager.status = PumpManagerStatus(timeZone: status.timeZone, device: status.device, pumpBatteryChargeRemaining: nil,
                                               basalDeliveryState: .suspended(occurrence), bolusState: .noBolus, insulinType: status.insulinType)

        await deviceDataManager.runDueScheduledProfileSwitch(now: occurrence.addingTimeInterval(.minutes(5)))
        XCTAssertEqual(deviceDataManager.activeTherapyProfileName, "Default")
        XCTAssertNil(pumpManager.basalRateSchedule)

        pumpManager.status = status
        await deviceDataManager.runDueScheduledProfileSwitch(now: occurrence.addingTimeInterval(.minutes(15)))
        XCTAssertEqual(deviceDataManager.activeTherapyProfileName, "Sport")
    }

    func testBolusInProgressSkipsTheRunWithoutAPumpCall() async throws {
        _ = try await setUpSchedule({ [self.start("Sport", at: $0)] }, settledAt: occurrence.addingTimeInterval(-.hours(1)))
        let status = pumpManager.status
        let bolus = DoseEntry(type: .bolus, startDate: occurrence, value: 1, unit: .units, decisionId: nil, automatic: false)
        pumpManager.status = PumpManagerStatus(timeZone: status.timeZone, device: status.device, pumpBatteryChargeRemaining: nil,
                                               basalDeliveryState: status.basalDeliveryState, bolusState: .inProgress(bolus), insulinType: status.insulinType)
        let settledBefore = settingsManager.loopSettings.scheduledSwitchesSettledAt

        await deviceDataManager.runDueScheduledProfileSwitch(now: occurrence.addingTimeInterval(.minutes(1)))

        XCTAssertNil(pumpManager.basalRateSchedule)
        XCTAssertEqual(settingsManager.loopSettings.scheduledSwitchesSettledAt, settledBefore)
    }

    func testValidationFailureSettlesAndAlertsWithoutRetry() async throws {
        let issuer = try await setUpSchedule({ [self.start("Sport", at: $0)] }, settledAt: occurrence.addingTimeInterval(-.hours(1)))
        pumpManager.supportedBasalRates = [0.05, 0.1]
        let now = occurrence.addingTimeInterval(.minutes(2))

        await deviceDataManager.runDueScheduledProfileSwitch(now: now)

        XCTAssertEqual(deviceDataManager.activeTherapyProfileName, "Default")
        XCTAssertEqual(settingsManager.loopSettings.scheduledSwitchesSettledAt, now)
        XCTAssertEqual(issuer.failures.count, 1)
        XCTAssertTrue(issuer.failures[0].backgroundContent.body.contains(TherapyProfileError.unsupportedBasalRate(0.5).localizedDescription))
        XCTAssertNil(pumpManager.basalRateSchedule)
    }

    func testPausedStartDoesNotRunWhileAnotherStartDoes() async throws {
        let issuer = try await setUpSchedule({ [self.start("Sport", at: $0, paused: true), self.start("Default", at: $0.addingTimeInterval(-.minutes(30)))] }, settledAt: occurrence.addingTimeInterval(-.hours(1)))
        try await deviceDataManager.activateTherapyProfile(named: "Sport")
        settingsManager.mutateLoopSettings { settings in
            settings.scheduledSwitchesSettledAt = self.occurrence.addingTimeInterval(-.hours(1))
        }

        await deviceDataManager.runDueScheduledProfileSwitch(now: occurrence.addingTimeInterval(.minutes(5)))

        // The paused Sport start is not newer than the Default start, which runs.
        XCTAssertEqual(deviceDataManager.activeTherapyProfileName, "Default")
        XCTAssertEqual(settingsManager.loopSettings.scheduledSwitchesSettledAt, occurrence.addingTimeInterval(-.minutes(30)))
        XCTAssertFalse(issuer.pending.contains { $0.backgroundContent.body.contains("Sport") })
        XCTAssertTrue(issuer.failures.isEmpty)
    }

    func testResumingDoesNotCatchUpAndTheNextStartRuns() async throws {
        let paused = start("Sport", at: occurrence, id: "sport", paused: true)
        _ = try await setUpSchedule({ _ in [paused] }, settledAt: occurrence.addingTimeInterval(-.hours(1)))

        var resumed = paused
        resumed.paused = false
        try await deviceDataManager.saveScheduledProfileSwitches([resumed], expectedFingerprint: ScheduledProfileSwitches.fingerprint([paused]))
        let resumedAt = try XCTUnwrap(settingsManager.loopSettings.scheduledSwitchesSettledAt)
        XCTAssertGreaterThan(resumedAt, occurrence)

        await deviceDataManager.runDueScheduledProfileSwitch(now: resumedAt.addingTimeInterval(.minutes(5)))
        XCTAssertEqual(deviceDataManager.activeTherapyProfileName, "Default")

        let next = try XCTUnwrap(ScheduledProfileSwitches.next(in: [resumed], after: resumedAt, timeZone: scheduleCalendar.timeZone))
        await deviceDataManager.runDueScheduledProfileSwitch(now: next.date.addingTimeInterval(.minutes(1)))
        XCTAssertEqual(deviceDataManager.activeTherapyProfileName, "Sport")
    }

    func testManualSwitchWhileStartsArePausedHolds() async throws {
        _ = try await setUpSchedule({ [self.start("Default", at: $0, paused: true)] }, settledAt: occurrence.addingTimeInterval(-.hours(1)))
        try await deviceDataManager.activateTherapyProfile(named: "Sport")
        let settledAt = try XCTUnwrap(settingsManager.loopSettings.scheduledSwitchesSettledAt)

        await deviceDataManager.runDueScheduledProfileSwitch(now: settledAt.addingTimeInterval(.hours(24 * 8)))

        XCTAssertEqual(deviceDataManager.activeTherapyProfileName, "Sport")
    }

    func testPendingAlertIsArmedForTheNextStartOfAnotherProfile() async throws {
        let issuer = try await setUpSchedule({ [self.start("Sport", at: $0), self.start("Default", at: $0.addingTimeInterval(.hours(48)))] }, settledAt: occurrence.addingTimeInterval(-.hours(1)))

        await deviceDataManager.armScheduledProfileSwitchAlert(now: occurrence.addingTimeInterval(-.hours(1)))
        XCTAssertEqual(issuer.pending.last?.trigger, .delayed(interval: .minutes(90)))
        XCTAssertEqual(issuer.pending.last?.interruptionLevel, .timeSensitive)
        XCTAssertEqual(issuer.pending.last?.categoryIdentifier, LoopNotificationCategory.scheduledProfileSwitch.rawValue)

        await deviceDataManager.runDueScheduledProfileSwitch(now: occurrence.addingTimeInterval(.minutes(1)))
        XCTAssertEqual(deviceDataManager.activeTherapyProfileName, "Sport")
        XCTAssertEqual(issuer.pending.last?.trigger, .delayed(interval: .hours(48) + .minutes(29)))
    }

    func testSavingTheListValidatesChecksTheFingerprintAndSettles() async throws {
        _ = try await setUpSchedule({ _ in [] }, settledAt: occurrence)
        let entry = start("Sport", at: occurrence)

        do {
            try await deviceDataManager.saveScheduledProfileSwitches([entry], expectedFingerprint: "0000000000000000")
            XCTFail("Saved over a list with another fingerprint")
        } catch {
            XCTAssertEqual(error as? ScheduledProfileSwitchError, .conflict)
        }
        do {
            try await deviceDataManager.saveScheduledProfileSwitches([start("Gone", at: occurrence)], expectedFingerprint: ScheduledProfileSwitches.fingerprint([]))
            XCTFail("Saved a start of a missing profile")
        } catch {
            XCTAssertEqual(error as? TherapyProfileError, .notFound("Gone"))
        }
        XCTAssertEqual(deviceDataManager.scheduledProfileSwitches, [])

        try await deviceDataManager.saveScheduledProfileSwitches([entry], expectedFingerprint: ScheduledProfileSwitches.fingerprint([]))
        XCTAssertEqual(deviceDataManager.scheduledProfileSwitches, [entry])
        XCTAssertGreaterThan(try XCTUnwrap(settingsManager.loopSettings.scheduledSwitchesSettledAt), occurrence)
    }

    func testRenameFollowsAndDeleteRemovesScheduledSwitches() async throws {
        _ = try await setUpSchedule({ [self.start("Sport", at: $0, id: "a"), self.start("Default", at: $0.addingTimeInterval(.hours(48)), id: "b")] }, settledAt: occurrence)
        var running = try XCTUnwrap(deviceDataManager.therapyProfile(named: "Sport"))
        running.name = "Running"
        try await deviceDataManager.saveTherapyProfile(running, originalName: "Sport")
        XCTAssertEqual(deviceDataManager.scheduledProfileSwitches.map(\.profileName), ["Running", "Default"])
        XCTAssertEqual(deviceDataManager.scheduledProfileSwitches.map(\.id), ["a", "b"])

        try await deviceDataManager.deleteTherapyProfile(named: "Running")
        XCTAssertEqual(deviceDataManager.scheduledProfileSwitches.map(\.id), ["b"])
    }

    func testStartOfAMissingProfileIsReportedAndSettled() async throws {
        let issuer = try await setUpSchedule({ [self.start("Sport", at: $0)] }, settledAt: occurrence.addingTimeInterval(-.hours(1)))
        settingsManager.mutateLoopSettings { settings in
            settings.scheduledSwitches = [self.start("Gone", at: self.occurrence)]
            settings.scheduledSwitchesSettledAt = self.occurrence.addingTimeInterval(-.hours(1))
        }
        let now = occurrence.addingTimeInterval(.minutes(1))

        await deviceDataManager.runDueScheduledProfileSwitch(now: now)

        XCTAssertEqual(settingsManager.loopSettings.scheduledSwitchesSettledAt, now)
        XCTAssertTrue(issuer.failures.last?.backgroundContent.body.contains(TherapyProfileError.notFound("Gone").localizedDescription) ?? false)
    }
}
