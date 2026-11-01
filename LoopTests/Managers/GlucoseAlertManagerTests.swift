//
//  GlucoseAlertManagerTests.swift
//  LoopTests
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import XCTest
import LoopKit
import LoopKitUI
@testable import Loop

@MainActor
final class GlucoseAlertManagerTests: XCTestCase {

    private final class MockAlertIssuer: AlertIssuer {
        var issued: [Alert] = []
        var retracted: [Alert.Identifier] = []
        func issueAlert(_ alert: Alert) async { issued.append(alert) }
        func retractAlert(identifier: Alert.Identifier) async { retracted.append(identifier) }
        func reset() { issued.removeAll(); retracted.removeAll() }
        var issuedIDs: [Alert.AlertIdentifier] { issued.map { $0.identifier.alertIdentifier } }
        var retractedIDs: [Alert.AlertIdentifier] { retracted.map { $0.alertIdentifier } }
    }

    private static let suiteName = "GlucoseAlertManagerTests"
    private var issuer: MockAlertIssuer!
    private var defaults: UserDefaults!
    private var manager: GlucoseAlertManager!
    private var preference: DisplayGlucosePreference!

    override func setUp() async throws {
        try await super.setUp()
        issuer = MockAlertIssuer()
        defaults = UserDefaults(suiteName: Self.suiteName)
        defaults.removePersistentDomain(forName: Self.suiteName)
        preference = DisplayGlucosePreference(displayGlucoseUnit: .milligramsPerDeciliter)
        manager = GlucoseAlertManager(alertIssuer: issuer, displayGlucosePreference: preference, userDefaults: defaults)
        // Defaults: low = 70, urgentLow = 55, recoveryMargin = 5.
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: Self.suiteName)
        issuer = nil; defaults = nil; manager = nil; preference = nil
        try await super.tearDown()
    }

    private func sample(_ mgdl: Double, at date: Date) -> NewGlucoseSample {
        NewGlucoseSample(date: date, quantity: .glucose(value: mgdl), condition: nil, trend: nil,
                         trendRate: nil, isDisplayOnly: false, wasUserEntered: false,
                         syncIdentifier: UUID().uuidString)
    }

    /// A reading between the low and urgent-low thresholds issues only the low alert.
    func testReadingInLowBandIssuesOnlyLow() async {
        let now = Date()
        await manager.evaluate(samples: [sample(65, at: now)], now: now)
        XCTAssertEqual(issuer.issuedIDs, [GlucoseAlertManager.lowAlertIdentifier])
    }

    /// While another controller raises these alerts (a watch running the loop), a low and a
    /// predicted low raise nothing here.
    func testNothingIsRaisedWhileAlertsAreHandledElsewhere() async {
        manager.alertsHandledElsewhere = { true }
        let now = Date()
        await manager.evaluate(samples: [sample(50, at: now)], now: now)
        let forecast = (0...6).map { i in
            PredictedGlucoseValue(startDate: now.addingTimeInterval(Double(i) * 5 * 60),
                                  quantity: .glucose(value: 120 - Double(i) * 20))
        }
        await manager.evaluatePredictedGlucose(forecast, now: now)
        XCTAssertTrue(issuer.issued.isEmpty, "got \(issuer.issuedIDs)")

        manager.alertsHandledElsewhere = { false }
        await manager.evaluate(samples: [sample(50, at: now.addingTimeInterval(5 * 60))], now: now.addingTimeInterval(5 * 60))
        XCTAssertEqual(issuer.issuedIDs, [GlucoseAlertManager.urgentLowAlertIdentifier], "back here, the next low alarms")
    }

    /// A low raised here before another controller took the alerts must not silence the first low
    /// after they come back: no reading here closed that episode, and the low has no repeat.
    func testALowRaisedBeforeAlertsWentElsewhereDoesNotSilenceTheNextOne() async {
        let start = Date()
        await manager.evaluate(samples: [sample(65, at: start)], now: start)
        XCTAssertEqual(issuer.issuedIDs, [GlucoseAlertManager.lowAlertIdentifier])

        manager.alertsHandledElsewhere = { true }
        let during = start.addingTimeInterval(30 * 60)
        await manager.evaluate(samples: [sample(120, at: during)], now: during)

        issuer.reset()
        manager.alertsHandledElsewhere = { false }
        let back = start.addingTimeInterval(60 * 60)
        await manager.evaluate(samples: [sample(65, at: back)], now: back)
        XCTAssertEqual(issuer.issuedIDs, [GlucoseAlertManager.lowAlertIdentifier], "a new low alarms once the alerts are back")
    }

    /// A sudden drop straight past low into urgent low issues ONLY the most
    /// severe (urgent-low) alert — not both low and urgent-low in one check.
    func testSuddenUrgentLowIssuesOnlyUrgentLow() async {
        let now = Date()
        await manager.evaluate(samples: [sample(50, at: now)], now: now)
        XCTAssertEqual(issuer.issued.count, 1, "Expected a single alert, got: \(issuer.issuedIDs)")
        XCTAssertEqual(issuer.issuedIDs, [GlucoseAlertManager.urgentLowAlertIdentifier])
        XCTAssertFalse(issuer.issuedIDs.contains(GlucoseAlertManager.lowAlertIdentifier))
    }

    /// A gradual drop that first shows a low alert and then crosses into urgent
    /// low issues the urgent-low alert and retracts the now-superseded low alert,
    /// so the two never coexist.
    func testGradualLowThenUrgentRetractsLow() async {
        let t0 = Date()
        await manager.evaluate(samples: [sample(65, at: t0)], now: t0)
        XCTAssertEqual(issuer.issuedIDs, [GlucoseAlertManager.lowAlertIdentifier])

        issuer.reset()
        let t1 = t0.addingTimeInterval(5 * 60)
        await manager.evaluate(samples: [sample(50, at: t1)], now: t1)
        XCTAssertEqual(issuer.issuedIDs, [GlucoseAlertManager.urgentLowAlertIdentifier],
                       "Only urgent low should be issued once BG is in the urgent range")
        XCTAssertTrue(issuer.retractedIDs.contains(GlucoseAlertManager.lowAlertIdentifier),
                      "The superseded low alert should be retracted")
    }

    /// With urgent low disabled, a reading in the urgent range still issues the
    /// low alert (the most severe *enabled* alert).
    func testUrgentLowDisabledStillIssuesLow() async {
        manager.profiles[0].configuration.urgentLowEnabled = false
        let now = Date()
        await manager.evaluate(samples: [sample(50, at: now)], now: now)
        XCTAssertEqual(issuer.issuedIDs, [GlucoseAlertManager.lowAlertIdentifier])
    }

    /// Simulates an app restart by building a second manager over the same
    /// defaults.
    private func relaunch() -> GlucoseAlertManager {
        GlucoseAlertManager(alertIssuer: issuer, displayGlucosePreference: preference, userDefaults: defaults)
    }

    func testHighAlertDoesNotRepeatAfterRelaunch() async {
        let now = Date()
        await manager.evaluate(samples: [sample(200, at: now)], now: now)
        XCTAssertEqual(issuer.issuedIDs, [GlucoseAlertManager.highAlertIdentifier])

        issuer.reset()
        let restarted = relaunch()
        let later = now.addingTimeInterval(5 * 60)
        await restarted.evaluate(samples: [sample(205, at: later)], now: later)
        XCTAssertEqual(issuer.issuedIDs, [], "Still the same episode; must not re-alert")
    }

    func testRecoveryAfterRelaunchRetractsHigh() async {
        let now = Date()
        await manager.evaluate(samples: [sample(200, at: now)], now: now)
        issuer.reset()

        let restarted = relaunch()
        let later = now.addingTimeInterval(5 * 60)
        await restarted.evaluate(samples: [sample(150, at: later)], now: later)
        XCTAssertEqual(issuer.retractedIDs, [GlucoseAlertManager.highAlertIdentifier])
    }

    /// A new episode after recovery alerts again.
    func testHighAlertsAgainInNewEpisodeAfterRelaunch() async {
        let now = Date()
        await manager.evaluate(samples: [sample(200, at: now)], now: now)

        let restarted = relaunch()
        let recovered = now.addingTimeInterval(5 * 60)
        await restarted.evaluate(samples: [sample(150, at: recovered)], now: recovered)
        issuer.reset()

        let rising = now.addingTimeInterval(10 * 60)
        await restarted.evaluate(samples: [sample(200, at: rising)], now: rising)
        XCTAssertEqual(issuer.issuedIDs, [GlucoseAlertManager.highAlertIdentifier])
    }

    // MARK: - Armed alert tests

    private func predicted(_ mgdl: Double, at date: Date) -> PredictedGlucoseValue {
        PredictedGlucoseValue(startDate: date, quantity: .glucose(value: mgdl))
    }

    /// The point of arming is that the alert arrives later, from whatever state
    /// Loop is in — so it waits for a reading rather than firing on the spot.
    func testArmingDoesNotFireImmediately() async {
        manager.armTest(for: .low)
        XCTAssertEqual(manager.armedTest, .low)
        XCTAssertEqual(issuer.issued, [])
    }

    func testArmedTestFiresOnTheNextReading() async {
        manager.armTest(for: .low)
        let now = Date()
        await manager.evaluate(samples: [sample(120, at: now)], now: now)
        XCTAssertEqual(issuer.issuedIDs, [GlucoseAlarmKind.low.testAlertIdentifier])
        XCTAssertNil(manager.armedTest, "The test is one-shot")
    }

    /// It rides along with the reading; it must not stand in for it. An armed
    /// test while glucose is genuinely urgent-low has to leave the real alert
    /// alone.
    func testArmedTestLeavesTheRealEvaluationAlone() async {
        manager.armTest(for: .high)
        let now = Date()
        await manager.evaluate(samples: [sample(50, at: now)], now: now)
        XCTAssertEqual(issuer.issuedIDs,
                       [GlucoseAlertManager.urgentLowAlertIdentifier, GlucoseAlarmKind.high.testAlertIdentifier])
    }

    /// Arming one alarm must not fire another.
    func testArmedTestFiresOnlyTheArmedAlarm() async {
        manager.armTest(for: .urgentLow)
        let now = Date()
        await manager.evaluate(samples: [sample(120, at: now)], now: now)
        XCTAssertEqual(issuer.issuedIDs, [GlucoseAlarmKind.urgentLow.testAlertIdentifier])
    }

    func testCancellingAnArmedTestStopsIt() async {
        manager.armTest(for: .low)
        manager.cancelArmedTest()
        XCTAssertNil(manager.armedTest)
        let now = Date()
        await manager.evaluate(samples: [sample(120, at: now)], now: now)
        XCTAssertEqual(issuer.issuedIDs, [])
    }

    /// Predicted Low has no reading of its own to ride along with, so a glucose
    /// batch must leave its armed test alone and the next loop cycle must fire it.
    func testPredictedLowTestWaitsForALoopCycle() async {
        manager.armTest(for: .predictedLow)
        let now = Date()
        await manager.evaluate(samples: [sample(120, at: now)], now: now)
        XCTAssertEqual(issuer.issuedIDs, [])
        XCTAssertEqual(manager.armedTest, .predictedLow)

        // A forecast that stays well above the threshold: no real alert.
        await manager.evaluatePredictedGlucose([predicted(140, at: now.addingTimeInterval(15 * 60))], now: now)
        XCTAssertEqual(issuer.issuedIDs, [GlucoseAlarmKind.predictedLow.testAlertIdentifier])
        XCTAssertNil(manager.armedTest)
    }

    /// The test is only worth anything if it asks for delivery on the same
    /// terms as the real alarm: same sound, same interruption level.
    func testArmedTestCarriesTheAlarmsSoundAndInterruptionLevel() async {
        manager.urgentLowSound = "chime.caf"
        manager.armTest(for: .urgentLow)
        let now = Date()
        await manager.evaluate(samples: [sample(120, at: now)], now: now)
        let alert = issuer.issued.first
        XCTAssertEqual(alert?.sound?.filename, "chime.caf")
        XCTAssertEqual(alert?.interruptionLevel, .critical)
        XCTAssertEqual(alert?.trigger, .immediate)
    }

    func testNonUrgentArmedTestsAreTimeSensitive() {
        for kind in [GlucoseAlarmKind.low, .high, .predictedLow] {
            XCTAssertEqual(kind.interruptionLevel, .timeSensitive, "\(kind)")
        }
        XCTAssertEqual(GlucoseAlarmKind.urgentLow.interruptionLevel, .critical)
    }

    /// A test identifier has to be distinct from the real one — that is what
    /// keeps a test out of the real alarm's episode state and retraction — but
    /// still has to resolve to the same alarm's sound and silent-mode setting.
    func testTestIdentifiersAreDistinctButResolveToTheSameAlarm() {
        manager.lowSound = "harp.caf"
        manager.lowPlaysThroughSilent = true
        for kind in GlucoseAlarmKind.allCases {
            XCTAssertNotEqual(kind.testAlertIdentifier, kind.alertIdentifier)
            XCTAssertEqual(GlucoseAlarmKind.kind(forAlertIdentifier: kind.testAlertIdentifier), kind)
            XCTAssertEqual(GlucoseAlarmKind.kind(forAlertIdentifier: kind.alertIdentifier), kind)
            XCTAssertEqual(manager.configuredSoundName(for: kind.testAlertIdentifier),
                           manager.configuredSoundName(for: kind.alertIdentifier))
            XCTAssertEqual(manager.playsThroughSilent(for: kind.testAlertIdentifier),
                           manager.playsThroughSilent(for: kind.alertIdentifier))
        }
        XCTAssertEqual(manager.configuredSoundName(for: GlucoseAlarmKind.low.testAlertIdentifier), "harp.caf")
        XCTAssertTrue(manager.playsThroughSilent(for: GlucoseAlarmKind.low.testAlertIdentifier))
    }

    /// iOS can terminate a backgrounded Loop before the next reading lands; a
    /// test that quietly evaporates looks exactly like a broken alarm.
    func testArmedTestSurvivesRelaunch() async {
        manager.armTest(for: .high)
        let restarted = relaunch()
        XCTAssertEqual(restarted.armedTest, .high)

        let now = Date()
        await restarted.evaluate(samples: [sample(120, at: now)], now: now)
        XCTAssertEqual(issuer.issuedIDs, [GlucoseAlarmKind.high.testAlertIdentifier])

        // And it is cleared, so it can't fire again on the launch after that.
        XCTAssertNil(relaunch().armedTest)
    }

    func testUnknownIdentifierHasNoAlarm() {
        XCTAssertNil(GlucoseAlarmKind.kind(forAlertIdentifier: "something.else"))
        XCTAssertFalse(manager.playsThroughSilent(for: "something.else"))
    }

    // MARK: - Display units

    /// Builds a manager reading glucose in `unit`, over its own defaults.
    private func makeManager(displaying unit: LoopUnit) -> (GlucoseAlertManager, DisplayGlucosePreference) {
        let preference = DisplayGlucosePreference(displayGlucoseUnit: unit)
        return (GlucoseAlertManager(alertIssuer: issuer, displayGlucosePreference: preference, userDefaults: defaults),
                preference)
    }

    private func formatted(_ mgdl: Double, _ preference: DisplayGlucosePreference, includeUnit: Bool = true) -> String {
        preference.format(LoopQuantity(unit: .milligramsPerDeciliter, doubleValue: mgdl), includeUnit: includeUnit)
    }

    /// The reported bug: the body read "above 180 mg/dL (current: 193)" on a
    /// phone set to mmol/L.
    func testHighAlertBodyUsesTheDisplayUnit() async {
        let (mmol, preference) = makeManager(displaying: .millimolesPerLiter)
        let now = Date()
        await mmol.evaluate(samples: [sample(193, at: now)], now: now)

        let body = issuer.issued.first?.backgroundContent.body
        XCTAssertNotNil(body)
        // The formatter writes the unit with word joiners (mg\u{2060}/\u{2060}dL),
        // so match on "mg" rather than the slashed spelling.
        XCTAssertFalse(body!.contains("mg"), "Body still names a mg/dL unit: \(body!)")
        XCTAssertTrue(body!.contains(formatted(180, preference)), "Threshold missing from: \(body!)")
        XCTAssertTrue(body!.contains(formatted(193, preference, includeUnit: false)), "Reading missing from: \(body!)")
    }

    func testLowAndUrgentLowBodiesUseTheDisplayUnit() async {
        let (mmol, preference) = makeManager(displaying: .millimolesPerLiter)
        let t0 = Date()
        await mmol.evaluate(samples: [sample(65, at: t0)], now: t0)
        let low = issuer.issued.first?.backgroundContent.body
        XCTAssertNotNil(low)
        XCTAssertFalse(low!.contains("mg"), "Low body still names a mg/dL unit: \(low!)")
        XCTAssertTrue(low!.contains(formatted(70, preference)))

        issuer.reset()
        let t1 = t0.addingTimeInterval(5 * 60)
        await mmol.evaluate(samples: [sample(50, at: t1)], now: t1)
        let urgent = issuer.issued.first?.backgroundContent.body
        XCTAssertNotNil(urgent)
        XCTAssertFalse(urgent!.contains("mg"), "Urgent low body still names a mg/dL unit: \(urgent!)")
        XCTAssertTrue(urgent!.contains(formatted(55, preference)))
    }

    func testPredictedLowBodyUsesTheDisplayUnit() async {
        let (mmol, preference) = makeManager(displaying: .millimolesPerLiter)
        let now = Date()
        let predicted = [PredictedGlucoseValue(startDate: now.addingTimeInterval(10 * 60),
                                               quantity: .glucose(value: 55))]
        await mmol.evaluatePredictedGlucose(predicted, now: now)

        let body = issuer.issued.first?.backgroundContent.body
        XCTAssertNotNil(body)
        XCTAssertFalse(body!.contains("mg"), "Predicted low body still names a mg/dL unit: \(body!)")
        XCTAssertTrue(body!.contains(formatted(mmol.activeConfiguration().predictedLowThresholdMgDL, preference)))
    }

    /// A phone set to mg/dL must still read in mg/dL.
    func testMgdlPhoneStillReadsInMgdl() async {
        let now = Date()
        await manager.evaluate(samples: [sample(193, at: now)], now: now)
        let body = issuer.issued.first?.backgroundContent.body
        XCTAssertNotNil(body)
        XCTAssertTrue(body!.contains(formatted(180, preference)), "Threshold missing from: \(body!)")
        XCTAssertTrue(body!.contains("mg"), "Body lost its unit: \(body!)")
    }
}
