//
//  SmartwatchManagerHostTests.swift
//  LoopTests
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import XCTest
import LoopKit
@testable import Loop

@MainActor
final class SmartwatchManagerHostTests: XCTestCase {
    private func identifier(_ alertIdentifier: Alert.AlertIdentifier) -> Alert.Identifier {
        Alert.Identifier(managerIdentifier: GlucoseAlertManager.managerIdentifier, alertIdentifier: alertIdentifier)
    }

    private var testAlertIdentifiers: [Alert.AlertIdentifier] {
        GlucoseAlarmKind.allCases.map(\.testAlertIdentifier)
    }

    /// A watch bolus that reached the pump counts for the time between boluses,
    /// delivered or not: a failure can be uncertain. Only a delivered one counts
    /// toward the daily total.
    func testABolusThatReachedThePumpCountsForTheTimeBetweenBoluses() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let token = UUID()
        let context = SmartwatchBolusContext(token: token, issuedAt: now.addingTimeInterval(-60), recommendedBolus: 2, maximumBolus: 5, supportedBolusVolumes: [])
        func evaluate(_ deliveries: [SmartwatchBolusPolicy.Delivery], at date: Date) -> Result<Double, SmartwatchBolusError> {
            SmartwatchBolusPolicy(isAllowed: true, currentContext: context, latestGlucoseDate: date.addingTimeInterval(-60), recentDeliveries: deliveries, roundToSupportedVolume: { $0 })
                .evaluate(SmartwatchBolusRequest(units: 1, contextToken: token, requestedAt: date), now: date)
        }

        let failed = SmartwatchManagerHost.bolusAttempted(at: now, in: [])
        XCTAssertEqual(evaluate(failed, at: now.addingTimeInterval(60)), .failure(.rateLimited))
        XCTAssertEqual(evaluate(failed, at: now.addingTimeInterval(5 * 60 + 1)), .success(1))
        XCTAssertEqual(failed.reduce(0) { $0 + $1.units }, 0)

        let delivered = SmartwatchManagerHost.bolusDelivered(1.5, attemptedAt: now, in: failed)
        XCTAssertEqual(delivered, [SmartwatchBolusPolicy.Delivery(date: now, units: 1.5)])
        XCTAssertEqual(evaluate(delivered, at: now.addingTimeInterval(60)), .failure(.rateLimited))
    }

    /// A test alert counts as its alarm's, so the watch colours its ring and buzzes for it.
    func testTestAlertsHaveTheirAlarmsGlucoseType() {
        XCTAssertEqual(SmartwatchManagerHost.glucoseAlertType(of: identifier(GlucoseAlarmKind.urgentLow.testAlertIdentifier)), .urgentLow)
        XCTAssertEqual(SmartwatchManagerHost.glucoseAlertType(of: identifier(GlucoseAlarmKind.low.testAlertIdentifier)), .low)
        XCTAssertEqual(SmartwatchManagerHost.glucoseAlertType(of: identifier(GlucoseAlarmKind.high.testAlertIdentifier)), .high)
        XCTAssertEqual(SmartwatchManagerHost.glucoseAlertType(of: identifier(GlucoseAlarmKind.predictedLow.testAlertIdentifier)), .predictedLow)
        XCTAssertEqual(SmartwatchManagerHost.glucoseAlertType(of: identifier(GlucoseAlertManager.highAlertIdentifier)), .high)
        XCTAssertNil(SmartwatchManagerHost.glucoseAlertType(of: Alert.Identifier(managerIdentifier: "Omni", alertIdentifier: "glucose.low")))

        XCTAssertTrue(SmartwatchManagerHost.isTestAlert(identifier(GlucoseAlarmKind.low.testAlertIdentifier)))
        XCTAssertFalse(SmartwatchManagerHost.isTestAlert(identifier(GlucoseAlertManager.lowAlertIdentifier)))
    }

    /// With every alarm on, nothing is retracted while a test alert is still showing.
    func testNothingIsRetractedWhileEveryAlarmIsOnAndATestIsShowing() {
        let now = Date()
        XCTAssertEqual(SmartwatchManagerHost.watchAlertsToRetract(configuration: .default, loopAlertsEnabled: true, lastTestAlertAt: now.addingTimeInterval(-5), now: now), [])
    }

    /// A test alert is cleared once it has shown long enough, and after a relaunch
    /// (no test sent since), as Loop never retracts it.
    func testTestAlertsAreRetractedOnceShown() {
        let now = Date()
        let shownLongEnough = now.addingTimeInterval(-SmartwatchManagerHost.watchTestAlertDuration)
        XCTAssertEqual(SmartwatchManagerHost.watchAlertsToRetract(configuration: .default, loopAlertsEnabled: true, lastTestAlertAt: shownLongEnough, now: now), testAlertIdentifiers)
        XCTAssertEqual(SmartwatchManagerHost.watchAlertsToRetract(configuration: .default, loopAlertsEnabled: true, lastTestAlertAt: nil, now: now), testAlertIdentifiers)
    }

    /// An alarm switched off (or off in the active profile) is retracted: Loop stops
    /// checking it, so it would never clear otherwise.
    func testAlarmsThatAreOffAreRetracted() {
        let now = Date()
        var configuration = GlucoseAlertConfiguration.default
        configuration.lowEnabled = false
        configuration.highEnabled = false
        XCTAssertEqual(
            Set(SmartwatchManagerHost.watchAlertsToRetract(configuration: configuration, loopAlertsEnabled: true, lastTestAlertAt: now, now: now)),
            [GlucoseAlertManager.lowAlertIdentifier, GlucoseAlertManager.highAlertIdentifier]
        )
        configuration.urgentLowEnabled = false
        configuration.predictedLowEnabled = false
        XCTAssertEqual(
            Set(SmartwatchManagerHost.watchAlertsToRetract(configuration: configuration, loopAlertsEnabled: true, lastTestAlertAt: now, now: now)),
            Set(GlucoseAlarmKind.allCases.map(\.alertIdentifier))
        )
    }

    /// While Loop's alerts are off (the CGM raises its own), every alarm is retracted.
    func testEveryAlarmIsRetractedWhileLoopsAlertsAreOff() {
        let now = Date()
        XCTAssertEqual(
            Set(SmartwatchManagerHost.watchAlertsToRetract(configuration: .default, loopAlertsEnabled: false, lastTestAlertAt: now, now: now)),
            Set(GlucoseAlarmKind.allCases.map(\.alertIdentifier))
        )
    }
}
