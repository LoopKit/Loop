//
//  SettingsScreen.swift
//  LoopUITests
//
//  Created by Cameron Ingham on 2/2/24.
//  Copyright © 2024 LoopKit Authors. All rights reserved.
//

import XCTest

final class SettingsScreen: BaseScreen {
    
    // MARK: Elements
    
    var insulinPump: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "settingsViewInsulinPump").firstMatch
    }
    
    var pumpSimulatorTitle: XCUIElement {
        app.navigationBars.staticTexts["Pump Simulator"]
    }
    
    var pumpSimulatorDoneButton: XCUIElement {
        app.navigationBars["Pump Simulator"].buttons["Done"]
    }
    
    var cgm: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "settingsViewCGM").firstMatch
    }
    
    var cgmSimulatorTitle: XCUIElement {
        app.navigationBars.staticTexts["CGM Simulator"]
    }
    
    var cgmSimulatorDoneButton: XCUIElement {
        app.navigationBars["CGM Simulator"].buttons["Done"]
    }
    
    var settingsDoneButton: XCUIElement {
        app.navigationBars["Settings"].buttons["Done"]
    }
    
    var alertManagementAlertWarning: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "settingsViewAlertManagementAlertWarning").firstMatch
    }
    
    var alertManagement: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "settingsViewAlertManagement").firstMatch
    }
    
    var alertPermissionsWarning: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "settingsViewAlertManagementAlertPermissionsAlertWarning").firstMatch
    }
    
    var managePermissionsInSettings: XCUIElement {
        app.descendants(matching: .any).buttons["Manage Permissions in Settings"]
    }
    
    var alertPermissionsNotificationsEnabled: XCUIElement {
        app.staticTexts["settingsViewAlertManagementAlertPermissionsNotificationsEnabled"]
    }
    
    var alertPermissionsNotificationsDisabled: XCUIElement {
        app.staticTexts["settingsViewAlertManagementAlertPermissionsNotificationsDisabled"]
    }
    
    var alertPermissionsCriticalAlertsEnabled: XCUIElement {
        app.staticTexts["settingsViewAlertManagementAlertPermissionsCriticalAlertsEnabled"]
    }
    
    var alertPermissionsCriticalAlertsDisabled: XCUIElement {
        app.staticTexts["settingsViewAlertManagementAlertPermissionsCriticalAlertsDisabled"]
    }
    
    var closedLoopToggle: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "settingsViewClosedLoopToggle").switches.firstMatch
    }
    
    // MARK: Actions
    
    func openPumpManager() {
        waitForExistence(insulinPump)
        insulinPump.tap()
    }
    
    func closePumpSimulator() {
        waitForExistence(pumpSimulatorDoneButton)
        pumpSimulatorDoneButton.tap()
    }
    
    func openCGMManager() {
        waitForExistence(cgm)
        cgm.tap()
    }
    
    func closeCGMSimulator() {
        waitForExistence(cgmSimulatorDoneButton)
        cgmSimulatorDoneButton.tap()
    }
    
    func closeSettingsScreen() {
        waitForExistence(settingsDoneButton)
        settingsDoneButton.tap()
    }
    
    func openAlertManagement() {
        waitForExistence(alertManagement)
        alertManagement.tap()
    }
    
    func openAlertPermissions() {
        waitForExistence(alertPermissionsWarning)
        alertPermissionsWarning.tap()
    }
    
    func openPermissionsInSettings() {
        waitForExistence(managePermissionsInSettings)
        managePermissionsInSettings.tap()
    }
    
    func toggleClosedLoop() {
        waitForExistence(closedLoopToggle)
        closedLoopToggle.tap()
    }
}
