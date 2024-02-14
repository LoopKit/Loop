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
        app = XCUIApplication(bundleIdentifier: "org.tidepool.diy.Loop")
        app.launch()
        baseScreen = BaseScreen(app: app)
        homeScreen = HomeScreen(app: app)
        settingsScreen = SettingsScreen(app: app)
        systemSettingsScreen = SystemSettingsScreen()
        pumpSimulatorScreen = PumpSimulatorScreen(app: app)
        onboardingScreen = OnboardingScreen(app: app)
        common = Common(appName: "DIY Loop")
    }
    
    func testSkippingOnboarding() async throws {
        baseScreen.deleteApp(appName: "DIY Loop")
        app.launch()
        onboardingScreen.skipAllOfOnboarding()
    }
}
