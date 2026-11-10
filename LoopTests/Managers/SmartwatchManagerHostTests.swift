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

    private func alert(_ identifier: Alert.Identifier, level: Alert.InterruptionLevel) -> Alert {
        let content = Alert.Content(title: "Title", body: "Body", acknowledgeActionButtonLabel: "OK")
        return Alert(identifier: identifier, foregroundContent: content, backgroundContent: content, trigger: .immediate, interruptionLevel: level, sound: .vibrate)
    }

    /// A watch plugin can't raise a critical alert: Loop issues it time-sensitive.
    /// Lower levels and everything else about the alert are kept.
    func testAWatchPluginAlertIsAtMostTimeSensitive() {
        let identifier = Alert.Identifier(managerIdentifier: "Watch", alertIdentifier: "appMissing")
        let critical = SmartwatchManagerHost.watchPluginAlert(alert(identifier, level: .critical), from: "Watch")
        XCTAssertEqual(critical.interruptionLevel, .timeSensitive)
        XCTAssertEqual(critical.identifier, identifier)
        XCTAssertEqual(critical.foregroundContent, alert(identifier, level: .critical).foregroundContent)
        XCTAssertEqual(critical.trigger, .immediate)
        XCTAssertEqual(critical.sound, .vibrate)

        XCTAssertEqual(SmartwatchManagerHost.watchPluginAlert(alert(identifier, level: .timeSensitive), from: "Watch").interruptionLevel, .timeSensitive)
        XCTAssertEqual(SmartwatchManagerHost.watchPluginAlert(alert(identifier, level: .active), from: "Watch").interruptionLevel, .active)
    }

    /// A watch plugin's alert is issued, and retracted, as the plugin's own, so it
    /// can't stand in for or retract another device's alert.
    func testAWatchPluginAlertIsThePluginsOwn() {
        let pumpAlert = Alert.Identifier(managerIdentifier: "Omnipod", alertIdentifier: "lowReservoir")
        let issued = SmartwatchManagerHost.watchPluginAlert(alert(pumpAlert, level: .timeSensitive), from: "Watch")
        XCTAssertEqual(issued.identifier, Alert.Identifier(managerIdentifier: "Watch", alertIdentifier: "lowReservoir"))
        XCTAssertEqual(SmartwatchManagerHost.watchPluginAlertIdentifier(pumpAlert, from: "Watch"), issued.identifier)
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
