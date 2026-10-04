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
                                              cacheLength: .hours(4), provenanceIdentifier: "WristGlucoseAlertTests")
        let carbStore = CarbStore(healthKitSampleStore: nil, cacheStore: cacheStore,
                                  cacheLength: .hours(24), provenanceIdentifier: "WristGlucoseAlertTests")
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
