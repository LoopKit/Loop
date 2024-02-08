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

class OnboardingScreen: BaseScreen {
    
    // MARK: Elements

    var welcomeTitleText: XCUIElement {
        app.staticTexts.element(matching: .staticText, identifier: "welcome data 0")
    }
    
    var simulatorAlert: XCUIElement {
        app.alerts["Are you sure you want to skip the rest of onboarding (and use simulators)?"]
    }
    
    var useSimulatorConfirmationButton: XCUIElement {
        app.buttons["Yes"]
    }
    
    var alertAllowButton:XCUIElement {
        springboardApp.buttons["Allow"]
    }
    
    var turnOnAllHealthCategoriesText: XCUIElement {
        app.tables.staticTexts["Turn On All"]
    }
    
    var healthDoneButton: XCUIElement {
        app.navigationBars["Health Access"].buttons["Allow"]
    }
    
    // MARK: Actions
    
    func skipAllOfOnboardingIfNeeded() {
        if welcomeTitleText.exists {
            skipAllOfOnboarding()
        }
    }
    
    func skipAllOfOnboarding() {
        skipOnboarding()
        allowSimulatorAlert()
        allowNotificationsAuthorization()
        allowCriticalAlertsAuthorization()
        allowHealthKitAuthorization()
    }

    private func skipOnboarding() {
        welcomeTitleText.press(forDuration: 2.5)
    }
    
    private func allowSimulatorAlert() {
        waitForExistence(simulatorAlert)
        useSimulatorConfirmationButton.tap()
    }
    
    private func allowNotificationsAuthorization() {
        waitForExistence(alertAllowButton)
        alertAllowButton.tap()
    }
    
    private func allowCriticalAlertsAuthorization() {
        waitForExistence(alertAllowButton)
        alertAllowButton.tap()
    }
    
    private func allowHealthKitAuthorization() {
        waitForExistence(turnOnAllHealthCategoriesText)
        turnOnAllHealthCategoriesText.tap()
        healthDoneButton.tap()
    }
}
