//
//  BaseScreen.swift
//  LoopUITests
//
//  Created by Ginny Yadav on 10/27/23.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import XCTest

class BaseScreen {
    var app: XCUIApplication
    var springboardApp: XCUIApplication
    var bundleIdentifier: String?

    init(app: XCUIApplication) {
        self.app = app
        self.springboardApp = XCUIApplication(bundleIdentifier:"com.apple.springboard")
        self.bundleIdentifier = Bundle.main.bundleIdentifier
    }
    
    func deleteApp() {
        XCUIApplication().terminate()

        let icon = springboardApp.icons["Tidepool Loop"]
        if icon.exists {
            let iconFrame = icon.frame
            let springboardFrame = springboardApp.frame
            icon.press(forDuration: 5)

            // Tap the little "X" button at approximately where it is. The X is not exposed directly
            springboardApp.coordinate(withNormalizedOffset: CGVector(dx: (iconFrame.minX + 3) / springboardFrame.maxX, dy: (iconFrame.minY + 3) / springboardFrame.maxY)).tap()

            springboardApp.alerts.buttons["Delete App"].tap()
            
            waitForExistence(springboardApp.alerts.buttons["Delete"])
            springboardApp.alerts.buttons["Delete"].tap()
            
            waitForExistence(springboardApp.alerts.buttons["OK"])
            springboardApp.alerts.buttons["OK"].tap()
        }
    }
}




