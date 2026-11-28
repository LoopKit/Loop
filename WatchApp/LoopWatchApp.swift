//
//  LoopWatchApp.swift
//  Loop
//
//  Created by Pete Schwamb on 9/21/25.
//  Copyright © 2025 LoopKit Authors. All rights reserved.
//
import SwiftUI

@main
struct LoopWatchApp: App {
    @WKApplicationDelegateAdaptor(ExtensionDelegate.self) private var appDelegate

    var loopManager = LoopDataManager.shared

    /// With Sport Mode on, the onboarding gate lives in ContentView, so Sport Mode and
    /// diagnostics stay reachable while the phone is not onboarded.
    var body: some Scene {
        WindowGroup {
            if !FeatureFlags.sportModeEnabled, loopManager.activeContext?.isOnboardingCompleted != true {
                CompleteOnboardingView()
            } else {
                ContentView()
                    .environment(loopManager)
            }
        }
    }
}
