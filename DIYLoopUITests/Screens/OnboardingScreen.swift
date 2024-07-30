//
//  OnboardingScreen.swift
//  DIYLoopUITests
//
//  Created by Cameron Ingham on 2/13/24.
//  Copyright © 2024 LoopKit Authors. All rights reserved.
//

import LoopUITestingKit
import XCTest

class OnboardingScreen: BaseScreen {
    
    // MARK: Elements

    var loopLogo: XCUIElement {
        app.images.matching(identifier: "loopLogo").firstMatch
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
        if loopLogo.exists {
            skipAllOfOnboarding()
        }
    }
    
    func skipAllOfOnboarding() {
        allowSiri()
        skipOnboarding()
        allowNotificationsAuthorization()
        allowHealthKitAuthorization()
    }
    
    private func allowSiri() {
        waitForExistence(alertAllowButton)
        if alertAllowButton.exists {
            alertAllowButton.tap()
        }
    }

    private func skipOnboarding() {
        waitForExistence(loopLogo)
        loopLogo.press(forDuration: 2)
    }
    
    private func allowSimulatorAlert() {
        waitForExistence(simulatorAlert)
        useSimulatorConfirmationButton.tap()
    }
    
    private func allowNotificationsAuthorization() {
        waitForExistence(alertAllowButton)
        alertAllowButton.tap()
    }
    
    private func allowHealthKitAuthorization() {
        waitForExistence(turnOnAllHealthCategoriesText)
        turnOnAllHealthCategoriesText.tap()
        healthDoneButton.tap()
    }
}
