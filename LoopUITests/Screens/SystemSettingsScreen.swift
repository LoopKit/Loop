//
//  SystemSettingsScreen.swift
//  LoopUITests
//
//  Created by Cameron Ingham on 2/2/24.
//  Copyright © 2024 LoopKit Authors. All rights reserved.
//

import XCTest

final class SystemSettingsScreen: BaseScreen {
    
    // MARK: Elements
    
    var loopCell: XCUIElement {
        app.cells["Tidepool Loop"]
    }
    
    var notificationsButton: XCUIElement {
        app.descendants(matching: .any).element(matching: .button, identifier: "NOTIFICATIONS")
    }
    
    var allowNotificationsToggle: XCUIElement {
        app.switches["Allow Notifications"]
    }
    
    var criticalAlertsToggle: XCUIElement {
        app.switches["Critical Alerts"]
    }
    
    // MARK: Initializers
    
    init() {
        super.init(app: XCUIApplication(bundleIdentifier: "com.apple.Preferences"))
    }
    
    // MARK: Actions
    
    func launchApp() {
        app.launch()
    }
    
    func openAppSystemSettings() {
        waitForExistence(loopCell)
        loopCell.tap()
    }
    
    func openSystemNotificationSettings() {
        waitForExistence(notificationsButton)
        notificationsButton.tap()
    }
    
    func toggleAllowNotifications() {
        waitForExistence(allowNotificationsToggle)
        allowNotificationsToggle.tap()
    }
    
    func toggleCriticalAlerts() {
        waitForExistence(criticalAlertsToggle)
        criticalAlertsToggle.tap()
    }
}
