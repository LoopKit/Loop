//
//  OnboardingScreen.swift
//  LoopUITests
//
//  Created by Ginny Yadav on 10/27/23.
//  Copyright © 2023 LoopKit Authors. All rights reserved.

// This is a page file.
// It's intention is to map out all the locators for a particular section of the app.
// If the locator uses a label please use the localization key
// If the locator uses an accesibility ID you don't need the localization key

import XCTest

class HomeScreen: BaseScreen {
    
    // MARK: Elements
    
    var hudStatusClosedLoop: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "loopCompletionHUDLoopStatusClosed").firstMatch
    }
    
    var hudPumpPill: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "pumpHUDView").firstMatch
    }
    
    var closedLoopOnAlertTitle: XCUIElement {
        app.staticTexts["Closed Loop ON"]
    }
    
    var hudStatusOpenLoop: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "loopCompletionHUDLoopStatusOpen").firstMatch
    }
    
    var closedLoopOffAlertTitle: XCUIElement {
        app.staticTexts["Closed Loop OFF"]
    }
    
    var preMealTabEnabled: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "statusTableViewPreMealButtonEnabled").firstMatch
    }
    
    var preMealTabDisabled: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "statusTableViewPreMealButtonDisabled").firstMatch
    }
    
    var settingsTab: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "statusTableViewControllerSettingsButton").firstMatch
    }
    
    var carbsTab: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "statusTableViewControllerCarbsButton").firstMatch
    }
    
    var carbEntryTitle: XCUIElement {
        app.navigationBars.staticTexts["Add Carb Entry"]
    }
    
    var carbEntryCancelButton: XCUIElement {
        app.navigationBars["Add Carb Entry"].buttons["Cancel"]
    }
    
    var simpleMealCalculatorTitle: XCUIElement {
        app.navigationBars.staticTexts["Simple Meal Calculator"]
    }
    
    var simpleMealCalculatorCancelButton: XCUIElement {
        app.navigationBars["Simple Meal Calculator"].buttons["Cancel"]
    }
    
    var bolusTab: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "statusTableViewControllerBolusButton").firstMatch
    }
    
    var bolusTitle: XCUIElement {
        app.navigationBars.staticTexts["Bolus"]
    }
    
    var bolusEntryViewBolusEntryRow: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "dismissibleKeyboardTextField").firstMatch
    }
    
    var bolusCancelButton: XCUIElement {
        app.navigationBars["Bolus"].buttons["Cancel"]
    }
    
    var simpleBolusCalculatorTitle: XCUIElement {
        app.navigationBars.staticTexts["Simple Bolus Calculator"]
    }
    
    var simpleBolusCalculatorCancelButton: XCUIElement {
        app.navigationBars["Simple Bolus Calculator"].buttons["Cancel"]
    }
    
    var safetyNotificationsAlertTitle: XCUIElement {
        app.alerts["\n\nWarning! Safety notifications are turned OFF"]
    }
    
    var safetyNotificationsAlertCloseButton: XCUIElement {
        app.alerts.firstMatch.buttons["Close"]
    }
    
    var alertDismissButton: XCUIElement {
        app.buttons["Dismiss"]
    }
    
    var confirmationDialogCancelButton: XCUIElement {
        app.buttons["Cancel"]
    }
    
    var keyboardDoneButton: XCUIElement {
        app.toolbars.firstMatch.buttons["Done"].firstMatch
    }
    
    var deliverBolusButton: XCUIElement {
        app.buttons["Deliver"]
    }
    
    var notification: XCUIElement {
        springboardApp.descendants(matching: .any).matching(identifier: "NotificationShortLookView").firstMatch
    }
    
    var bolusIssueNotificationTitle: XCUIElement {
        app.alerts["Bolus Issue"]
    }
    
    var passcodeEntry: XCUIElement {
        springboardApp.secureTextFields["Passcode field"]
    }
    
    var springboardKeyboardDoneButton: XCUIElement {
        springboardApp.keyboards.buttons["done"]
    }
    
    // MARK: Actions
    
    func openSettings() {
        waitForExistence(settingsTab)
        settingsTab.tap()
    }
    
    func tapSafetyNotificationAlertCloseButton() {
        waitForExistence(safetyNotificationsAlertCloseButton)
        safetyNotificationsAlertCloseButton.tap()
    }
    
    func tapLoopStatusOpen() {
        waitForExistence(hudStatusOpenLoop)
        hudStatusOpenLoop.tap()
    }
    
    func tapLoopStatusClosed() {
        waitForExistence(hudStatusClosedLoop)
        hudStatusClosedLoop.tap()
    }
    
    func closeLoopStatusAlert() {
        waitForExistence(alertDismissButton)
        alertDismissButton.tap()
    }
    
    func tapPreMealButton() {
        waitForExistence(preMealTabEnabled)
        preMealTabEnabled.tap()
    }
    
    func dismissPreMealConfirmationDialog() {
        waitForExistence(confirmationDialogCancelButton)
        confirmationDialogCancelButton.tap()
    }
    
    func tapCarbEntry() {
        waitForExistence(carbsTab)
        carbsTab.tap()
    }
    
    func closeMealEntry() {
        waitForExistence(carbEntryCancelButton)
        carbEntryCancelButton.tap()
    }
    
    func closeSimpleCarbEntry() {
        waitForExistence(simpleMealCalculatorCancelButton)
        simpleMealCalculatorCancelButton.tap()
    }
    
    func tapBolusEntry() {
        waitForExistence(bolusTab)
        bolusTab.tap()
    }
    
    func closeBolusEntry() {
        waitForExistence(bolusCancelButton)
        bolusCancelButton.tap()
    }
    
    func closeSimpleBolusEntry() {
        waitForExistence(simpleBolusCalculatorCancelButton)
        simpleBolusCalculatorCancelButton.tap()
    }
    
    func tapPumpPill() {
        waitForExistence(hudPumpPill)
        hudPumpPill.tap()
    }
    
    func tapBolusEntryTextField() {
        waitForExistence(bolusEntryViewBolusEntryRow)
        bolusEntryViewBolusEntryRow.tap()
    }
    
    func closeKeyboard() {
        waitForExistence(keyboardDoneButton)
        keyboardDoneButton.tap()
    }
    
    func tapDeliverBolusButton() {
        waitForExistence(deliverBolusButton)
        deliverBolusButton.forceTap()
    }
    
    func verifyOcclusionAlert() {
//        waitForExistence(notification)
//        notification.tap()
//        waitForExistence(bolusIssueNotificationTitle)
//        app.activate()
        #warning("FIXME")
    }
    
    func enterPasscode() {
        waitForExistence(passcodeEntry)
        passcodeEntry.tap()
        springboardApp.typeText("1\n")
    }
}
