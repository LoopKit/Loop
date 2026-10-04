//
//  WristGlucoseAlertTests.swift
//  WatchAppTests
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//
//  During a loan the wrist runs stock's glucose alerts on its own readings, with the phone's settings.
//

import XCTest
import LoopKit
import LoopAlgorithm
import UserNotifications
@testable import OmnipodKit
@testable import WatchApp

@MainActor
final class WristGlucoseAlertTests: XCTestCase {

    private var scheduler: RecordingWristAlertScheduler!
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var dir: URL!
    private var clock = Date()

    override func setUp() async throws {
        try await super.setUp()
        scheduler = RecordingWristAlertScheduler()
        WristAlerts.scheduler = scheduler
        suiteName = "WristGlucoseAlertTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        clock = Date()
    }

    override func tearDown() async throws {
        WristAlerts.scheduler = UNUserNotificationCenter.current()
        defaults.removePersistentDomain(forName: suiteName)
        try await super.tearDown()
    }

    private func makeManager() async -> WatchLoopManager {
        let cacheStore = PersistenceController(directoryURL: dir.appendingPathComponent("cache"))
        let doseStore = await DoseStore(healthKitSampleStore: nil, cacheStore: cacheStore,
                                        longestEffectDuration: ExponentialInsulinModelPreset.rapidActingAdult.effectDuration,
                                        provenanceIdentifier: "WristGlucoseAlertTests")
        let glucoseStore = await GlucoseStore(healthKitSampleStore: nil, cacheStore: cacheStore,
                                              cacheLength: 4 * 60 * 60, provenanceIdentifier: "WristGlucoseAlertTests")
        let carbStore = CarbStore(healthKitSampleStore: nil, cacheStore: cacheStore,
                                  cacheLength: 24 * 60 * 60, provenanceIdentifier: "WristGlucoseAlertTests")
        let manager = WatchLoopManager(doseStore: doseStore, glucoseStore: glucoseStore, carbStore: carbStore,
                                       defaults: defaults, stateDirectory: dir)
        manager.now = { [unowned self] in self.clock }
        return manager
    }

    /// The phone's settings as the grant carries them: stock defaults, low 70, urgent low 55.
    private var phoneSettings: Data? {
        let primary = GlucoseAlertProfile.makePrimary()
        return GlucoseAlertSettings(profiles: [primary], activeProfileID: primary.id, cgmProvidesOwnAlerts: false,
                                    loopAlertsOverrideForOwnAlertingCGM: false).encoded
    }

    /// A live reading now, five minutes after the previous one.
    private func reading(_ mgdl: Double) -> NewGlucoseSample {
        clock = clock.addingTimeInterval(5 * 60)
        return NewGlucoseSample(date: clock, quantity: LoopQuantity(unit: .milligramsPerDeciliter, doubleValue: mgdl),
                                condition: nil, trend: nil, trendRate: nil, isDisplayOnly: false,
                                wasUserEntered: false, syncIdentifier: "wrist-\(clock.timeIntervalSince1970)")
    }

    private func request(_ alertIdentifier: String) -> UNNotificationRequest? {
        let id = WatchAlertPresenter.requestIdentifier(
            for: LoopKit.Alert.Identifier(managerIdentifier: GlucoseAlertManager.managerIdentifier, alertIdentifier: alertIdentifier))
        return scheduler.pending.first { $0.identifier == id }
    }

    func testAReadingBelowTheLowThresholdDuringALoanRaisesTheLowOnTheWrist() async {
        let manager = await makeManager()
        manager.configureGlucoseAlerts(from: phoneSettings)

        await manager.evaluateGlucoseAlerts([reading(65)]).value

        let low = request(GlucoseAlertManager.lowAlertIdentifier)
        XCTAssertNotNil(low, "the phone may be off: the wrist is the only place a low can sound")
        XCTAssertEqual(low?.content.title, "Low Glucose")
    }

    func testAnUrgentLowIsRaisedAndSupersedesTheLow() async {
        let manager = await makeManager()
        manager.configureGlucoseAlerts(from: phoneSettings)

        await manager.evaluateGlucoseAlerts([reading(50)]).value

        XCTAssertEqual(request(GlucoseAlertManager.urgentLowAlertIdentifier)?.content.interruptionLevel, .timeSensitive,
                       "the highest level the watch is entitled to")
        XCTAssertNil(request(GlucoseAlertManager.lowAlertIdentifier), "stock surfaces only the more severe of the two")
    }

    func testARecoveredReadingClearsTheLowAndANormalOneRaisesNothing() async {
        let manager = await makeManager()
        manager.configureGlucoseAlerts(from: phoneSettings)

        await manager.evaluateGlucoseAlerts([reading(110)]).value
        XCTAssertTrue(scheduler.pending.isEmpty, "an in-range reading raises nothing")

        await manager.evaluateGlucoseAlerts([reading(65)]).value
        XCTAssertNotNil(request(GlucoseAlertManager.lowAlertIdentifier))

        await manager.evaluateGlucoseAlerts([reading(80)]).value
        XCTAssertNil(request(GlucoseAlertManager.lowAlertIdentifier), "past the recovery margin the low is withdrawn")
    }

    func testWithoutThePhonesSettingsNoAlarmSoundsAndTheWristSaysSo() async {
        let manager = await makeManager()
        let note = manager.configureGlucoseAlerts(from: nil)

        await manager.evaluateGlucoseAlerts([reading(45)]).value

        XCTAssertTrue(scheduler.pending.isEmpty, "no settings means no invented thresholds")
        XCTAssertTrue(note.contains("UNAVAILABLE"), "the log says the wrist has no low alarms: \(note)")
    }

    func testOnceTheLoanEndsTheWristStopsEvaluating() async {
        let manager = await makeManager()
        manager.configureGlucoseAlerts(from: phoneSettings)
        manager.clearGlucoseAlerts()

        await manager.evaluateGlucoseAlerts([reading(45)]).value

        XCTAssertTrue(scheduler.pending.isEmpty, "between loans the phone has the pod and its own alarms")
    }

    /// Between loans no reading closes an episode, so a low left open by the last loan must not
    /// silence the next loan's first low (stock repeats a low only with snooze on).
    func testANewLoanForgetsTheLastLoansLowEpisode() async {
        let manager = await makeManager()
        manager.configureGlucoseAlerts(from: phoneSettings, startingLoan: true)
        await manager.evaluateGlucoseAlerts([reading(65)]).value
        XCTAssertNotNil(request(GlucoseAlertManager.lowAlertIdentifier))
        manager.clearGlucoseAlerts()

        scheduler = RecordingWristAlertScheduler()
        WristAlerts.scheduler = scheduler
        manager.configureGlucoseAlerts(from: phoneSettings, startingLoan: true)
        await manager.evaluateGlucoseAlerts([reading(65)]).value

        XCTAssertNotNil(request(GlucoseAlertManager.lowAlertIdentifier), "the next loan's low sounds")
    }

    /// During a loan the wrist owns the alarms, so a reading relayed by the phone alarms there too:
    /// a loan without the watch's own sensor must not run without low alarms.
    func testARelayedLowDuringALoanRaisesTheLowOnTheWrist() async throws {
        let manager = await makeManager()
        manager.configureGlucoseAlerts(from: phoneSettings)
        var podState = PodState(address: 0x1f0b3557, firmwareVersion: "2.7.0", iFirmwareVersion: "2.7.0",
                                lotNo: 1, lotSeq: 1, insulinType: .novolog, podType: dashType)
        podState.setupProgress = .completed
        let raw: [String: Any] = ["basalSchedule": ["entries": [["rate": 0.7, "startTime": 0.0]]],
                                  "controllerId": UInt32(0x1234_5678), "podId": UInt32(0x1234_5679),
                                  "podState": podState.rawValue]
        manager.pumpManager = try XCTUnwrap(OmniPumpManager(rawState: raw))

        manager.ingestPhoneGlucose(reading(65))

        let deadline = Date().addingTimeInterval(5)
        while request(GlucoseAlertManager.lowAlertIdentifier) == nil, Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertNotNil(request(GlucoseAlertManager.lowAlertIdentifier), "the relayed low alarms on the wrist")
    }

    func testAPredictedLowFromTheWristsForecastIsRaised() async {
        let manager = await makeManager()
        manager.configureGlucoseAlerts(from: phoneSettings)
        let forecast = (0...6).map { i in
            PredictedGlucoseValue(startDate: clock.addingTimeInterval(Double(i) * 5 * 60),
                                  quantity: LoopQuantity(unit: .milligramsPerDeciliter, doubleValue: 120 - Double(i) * 20))
        }

        await manager.evaluatePredictedLowAlert(forecast)?.value

        XCTAssertNotNil(request(GlucoseAlertManager.predictedLowAlertIdentifier),
                        "the wrist raises predicted low from its own forecast, which has the loan's doses")
    }
}
