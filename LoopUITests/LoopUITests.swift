//
//  LoopUITests.swift
//  LoopUITests
//
//  Created by Cameron Ingham on 2/13/24.
//  Copyright © 2024 LoopKit Authors. All rights reserved.
//

import LoopUITestingKit
import XCTest

@MainActor
final class LoopUITests: XCTestCase {
    var app: XCUIApplication!
    var baseScreen: BaseScreen!
    var homeScreen: HomeScreen!
    var settingsScreen: SettingsScreen!
    var systemSettingsScreen: SystemSettingsScreen!
    var pumpSimulatorScreen: PumpSimulatorScreen!
    var onboardingScreen: OnboardingScreen!
    var common: Common!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication(bundleIdentifier: Bundle.main.bundleIdentifier!)
        app.launch()
        baseScreen = BaseScreen(app: app, appName: "Tidepool Loop")
        homeScreen = HomeScreen(app: app, appName: "Tidepool Loop")
        settingsScreen = SettingsScreen(app: app, appName: "Tidepool Loop")
        systemSettingsScreen = SystemSettingsScreen(app: app, appName: "Tidepool Loop")
        pumpSimulatorScreen = PumpSimulatorScreen(app: app, appName: "Tidepool Loop")
        onboardingScreen = OnboardingScreen(app: app, appName: "Tidepool Loop")
        common = Common(appName: "Tidepool Loop")
    }
    
    // https://tidepool.atlassian.net/browse/LOOP-1605
    func testAlertSettingsUI() {
        systemSettingsScreen.launchApp()
        systemSettingsScreen.openAppSystemSettings()
        systemSettingsScreen.openSystemNotificationSettings()
        systemSettingsScreen.toggleAllowNotifications()
        systemSettingsScreen.toggleCriticalAlerts()
        homeScreen.openSettings()
        waitForExistence(settingsScreen.alertManagementAlertWarning)
        settingsScreen.openAlertManagement()
        waitForExistence(settingsScreen.alertPermissionsWarning)
        settingsScreen.openAlertPermissions()
        waitForExistence(settingsScreen.alertPermissionsNotificationsDisabled)
        waitForExistence(settingsScreen.alertPermissionsCriticalAlertsDisabled)
        settingsScreen.openPermissionsInSettings()
        systemSettingsScreen.app.activate()
        systemSettingsScreen.toggleAllowNotifications()
        app.activate()
        waitForExistence(settingsScreen.alertPermissionsNotificationsEnabled)
        systemSettingsScreen.app.activate()
        systemSettingsScreen.toggleCriticalAlerts()
        app.activate()
        waitForExistence(settingsScreen.alertPermissionsCriticalAlertsEnabled)
    }
    
    // https://tidepool.atlassian.net/browse/LOOP-1713
    func testConfigureClosedLoopManagement() {
        waitForExistence(homeScreen.hudStatusClosedLoop)
        waitForExistence(homeScreen.preMealTabEnabled)
        homeScreen.tapPreMealButton()
        homeScreen.dismissPreMealConfirmationDialog()
        homeScreen.openSettings()
        settingsScreen.toggleClosedLoop()
        settingsScreen.closeSettingsScreen()
        waitForExistence(homeScreen.hudStatusOpenLoop)
        waitForExistence(homeScreen.preMealTabDisabled)
        homeScreen.tapLoopStatusOpen()
        waitForExistence(homeScreen.closedLoopOffAlertTitle)
        homeScreen.closeLoopStatusAlert()
        homeScreen.tapBolusEntry()
        waitForExistence(homeScreen.simpleBolusCalculatorTitle)
        homeScreen.closeSimpleBolusEntry()
        homeScreen.tapCarbEntry()
        waitForExistence(homeScreen.simpleMealCalculatorTitle)
        homeScreen.closeSimpleCarbEntry()
        homeScreen.openSettings()
        settingsScreen.toggleClosedLoop()
        settingsScreen.closeSettingsScreen()
        waitForExistence(homeScreen.hudStatusClosedLoop)
        waitForExistence(homeScreen.preMealTabEnabled)
        homeScreen.tapLoopStatusClosed()
        waitForExistence(homeScreen.closedLoopOnAlertTitle)
        homeScreen.closeLoopStatusAlert()
        homeScreen.tapBolusEntry()
        waitForExistence(homeScreen.bolusTitle)
        homeScreen.closeBolusEntry()
        homeScreen.tapCarbEntry()
        waitForExistence(homeScreen.carbEntryTitle)
        homeScreen.closeMealEntry()
    }
    
    // https://tidepool.atlassian.net/browse/LOOP-1636
    func testPumpErrorAndStateHandlingStatusBarDisplay() {
        waitForExistence(homeScreen.hudStatusClosedLoop)
        homeScreen.tapPumpPill()
        pumpSimulatorScreen.tapSuspendInsulinButton()
        waitForExistence(pumpSimulatorScreen.resumeInsulinButton)
        pumpSimulatorScreen.closePumpSimulator()
        waitForExistence(homeScreen.hudPumpPill)
        XCTAssertEqual(homeScreen.hudPumpPill.value as? String, NSLocalizedString("Insulin Suspended", comment: ""))
        homeScreen.tapPumpPill()
        pumpSimulatorScreen.tapResumeInsulinButton()
        waitForExistence(pumpSimulatorScreen.suspendInsulinButton)
        pumpSimulatorScreen.openPumpSettings()
        pumpSimulatorScreen.tapReservoirRemainingRow()
        pumpSimulatorScreen.tapReservoirRemainingTextField()
        pumpSimulatorScreen.clearReservoirRemainingTextField()
        app.typeText("0")
        pumpSimulatorScreen.closeReservoirRemainingScreen()
        pumpSimulatorScreen.closePumpSettings()
        pumpSimulatorScreen.closePumpSimulator()
        waitForExistence(homeScreen.hudPumpPill)
        XCTAssertEqual(homeScreen.hudPumpPill.value as? String, NSLocalizedString("No Insulin", comment: ""))
        homeScreen.tapPumpPill()
        pumpSimulatorScreen.openPumpSettings()
        pumpSimulatorScreen.tapReservoirRemainingRow()
        pumpSimulatorScreen.tapReservoirRemainingTextField()
        pumpSimulatorScreen.clearReservoirRemainingTextField()
        app.typeText("15")
        pumpSimulatorScreen.closeReservoirRemainingScreen()
        pumpSimulatorScreen.closePumpSettings()
        pumpSimulatorScreen.closePumpSimulator()
        waitForExistence(homeScreen.hudPumpPill)
        XCTAssert((homeScreen.hudPumpPill.value as? String)?.contains("15 units remaining") == true)
        homeScreen.tapPumpPill()
        pumpSimulatorScreen.openPumpSettings()
        pumpSimulatorScreen.tapReservoirRemainingRow()
        pumpSimulatorScreen.tapReservoirRemainingTextField()
        pumpSimulatorScreen.clearReservoirRemainingTextField()
        app.typeText("45")
        pumpSimulatorScreen.closeReservoirRemainingScreen()
        pumpSimulatorScreen.closePumpSettings()
        pumpSimulatorScreen.closePumpSimulator()
        waitForExistence(homeScreen.hudPumpPill)
        XCTAssert((homeScreen.hudPumpPill.value as? String)?.contains("45 units remaining") == true)
        homeScreen.tapPumpPill()
        pumpSimulatorScreen.openPumpSettings()
        pumpSimulatorScreen.tapDetectOcclusionButton()
        pumpSimulatorScreen.closePumpSettings()
        pumpSimulatorScreen.closePumpSimulator()
        waitForExistence(homeScreen.hudPumpPill)
        XCTAssertEqual(homeScreen.hudPumpPill.value as? String, NSLocalizedString("Pump Occlusion", comment: ""))
        homeScreen.tapBolusEntry()
        homeScreen.tapBolusEntryTextField()
        app.typeText("2")
        homeScreen.closeKeyboard()
        homeScreen.tapDeliverBolusButton()
        homeScreen.enterPasscode()
        homeScreen.verifyOcclusionAlert()
        homeScreen.tapPumpPill()
        pumpSimulatorScreen.openPumpSettings()
        pumpSimulatorScreen.tapResolveOcclusionButton()
        pumpSimulatorScreen.tapCausePumpErrorButton()
        pumpSimulatorScreen.closePumpSettings()
        pumpSimulatorScreen.closePumpSimulator()
        waitForExistence(homeScreen.hudPumpPill)
        XCTAssertEqual(homeScreen.hudPumpPill.value as? String, NSLocalizedString("Pump Error", comment: ""))
        homeScreen.tapPumpPill()
        pumpSimulatorScreen.openPumpSettings()
        pumpSimulatorScreen.tapResolvePumpErrorButton()
        pumpSimulatorScreen.tapReservoirRemainingRow()
        pumpSimulatorScreen.tapReservoirRemainingTextField()
        pumpSimulatorScreen.clearReservoirRemainingTextField()
        app.typeText("165")
        pumpSimulatorScreen.closeReservoirRemainingScreen()
        pumpSimulatorScreen.closePumpSettings()
        pumpSimulatorScreen.closePumpSimulator()
    }
}
