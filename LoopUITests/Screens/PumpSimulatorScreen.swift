//
//  PumpSimulatorScreen.swift
//  LoopUITests
//
//  Created by Cameron Ingham on 2/6/24.
//  Copyright © 2024 LoopKit Authors. All rights reserved.
//

import XCTest

final class PumpSimulatorScreen: BaseScreen {

    // MARK: Elements
    
    var suspendInsulinButton: XCUIElement {
        app.descendants(matching: .any).buttons["Suspend Insulin Delivery"]
    }
    
    var resumeInsulinButton: XCUIElement {
        app.descendants(matching: .any).buttons["Tap to Resume Insulin Delivery"]
    }
    
    var doneButton: XCUIElement {
        app.navigationBars["Pump Simulator"].buttons["Done"]
    }
    
    var pumpProgressView: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "mockPumpManagerProgressView").firstMatch
    }
    
    var reservoirRemainingButton: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "mockPumpSettingsReservoirRemaining").firstMatch
    }
    
    var reservoirRemainingTextField: XCUIElement {
        app.descendants(matching: .any).textFields.firstMatch
    }
    
    var pumpSettingsBackButton: XCUIElement {
        app.navigationBars.firstMatch.buttons["Back"]
    }
    
    var reservoirRemainingBackButton: XCUIElement {
        app.navigationBars.firstMatch.buttons["Back"]
    }
    
    var detectOcclusionButton: XCUIElement {
        app.staticTexts["Detect Occlusion"]
    }
    
    var resolveOcclusionButton: XCUIElement {
        app.staticTexts["Resolve Occlusion"]
    }
    
    var causePumpErrorButton: XCUIElement {
        app.staticTexts["Cause Pump Error"]
    }
    
    var resolvePumpErrorButton: XCUIElement {
        app.staticTexts["Resolve Pump Error"]
    }
    
    // MARK: Actions
    
    func tapSuspendInsulinButton() {
        waitForExistence(suspendInsulinButton)
        suspendInsulinButton.tap()
    }
    
    func tapResumeInsulinButton() {
        waitForExistence(resumeInsulinButton)
        resumeInsulinButton.tap()
    }
    
    func closePumpSimulator() {
        waitForExistence(doneButton)
        doneButton.tap()
    }
    
    func openPumpSettings() {
        waitForExistence(pumpProgressView)
        pumpProgressView.press(forDuration: 10)
    }
    
    func closePumpSettings() {
        waitForExistence(pumpSettingsBackButton)
        pumpSettingsBackButton.tap()
    }
    
    func tapReservoirRemainingRow() {
        waitForExistence(reservoirRemainingButton)
        reservoirRemainingButton.tap()
    }
    
    func tapReservoirRemainingTextField() {
        waitForExistence(reservoirRemainingTextField)
        reservoirRemainingTextField.tap()
    }
    
    func clearReservoirRemainingTextField() {
        guard let value = reservoirRemainingTextField.value as? String else {
            XCTFail()
            return
        }
        
        app.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count))
    }
    
    func closeReservoirRemainingScreen() {
        waitForExistence(reservoirRemainingBackButton)
        reservoirRemainingBackButton.tap()
    }
    
    func tapDetectOcclusionButton() {
        waitForExistence(detectOcclusionButton)
        detectOcclusionButton.tap()
    }
    
    func tapResolveOcclusionButton() {
        waitForExistence(resolveOcclusionButton)
        resolveOcclusionButton.tap()
    }
    
    func tapCausePumpErrorButton() {
        waitForExistence(causePumpErrorButton)
        causePumpErrorButton.tap()
    }
    
    func tapResolvePumpErrorButton() {
        waitForExistence(resolvePumpErrorButton)
        resolvePumpErrorButton.tap()
    }
}
