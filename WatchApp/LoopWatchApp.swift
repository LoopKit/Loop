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

    /// The onboarding gate moved INTO ContentView rather than wrapping it.
    ///
    /// Stock swaps the whole app for CompleteOnboardingView until the phone reports both managers
    /// onboarded. That hides Sport Mode and — worse — the diagnostics page, which is the only way
    /// to see what the watch is doing. The two are exactly what you need when the phone
    /// relationship is the thing that is broken, and a watch that says "complete onboarding on
    /// your iPhone" and offers nothing else is undebuggable from the wrist.
    ///
    /// The stock pages still show the stock prompt; see ContentView.
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(loopManager)
        }
    }
}
