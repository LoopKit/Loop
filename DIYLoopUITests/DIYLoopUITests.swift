//
//  DIYLoopUITests.swift
//  DIYLoopUITests
//
//  Created by Cameron Ingham on 2/13/24.
//  Copyright © 2024 LoopKit Authors. All rights reserved.
//

import LoopUITestingKit
import XCTest

@MainActor
final class DIYLoopUITests: XCTestCase {
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
        baseScreen = BaseScreen(app: app, appName: "DIY Loop")
        homeScreen = HomeScreen(app: app, appName: "DIY Loop")
        settingsScreen = SettingsScreen(app: app, appName: "DIY Loop")
        systemSettingsScreen = SystemSettingsScreen(app: app, appName: "DIY Loop")
        pumpSimulatorScreen = PumpSimulatorScreen(app: app, appName: "DIY Loop")
        onboardingScreen = OnboardingScreen(app: app, appName: "DIY Loop")
        common = Common(appName: "DIY Loop")
    }
    
    func testSkippingOnboarding() async throws {
        baseScreen.deleteApp()
        app.launch()
        onboardingScreen.skipAllOfOnboarding()
    }
}
