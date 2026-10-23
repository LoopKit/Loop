//
//  WatchAppContent.swift
//  Loop
//
//  Created by Pete Schwamb on 9/21/25.
//  Copyright © 2025 LoopKit Authors. All rights reserved.
//

import LoopKit
import SwiftUI

struct ContentView: View {
    @Environment(LoopDataManager.self) var loopManager

    @State private var presetToConfirm: SelectablePreset? = nil
    @State var selectedPage = UserDefaults.standard.startOnChartPage ? 1 : 0
    @StateObject var glanceModel = GlanceViewModel()   // ContentView+PodLoan.swift reads it

    /// Mirrored so the root view does not subscribe to the timer-driven glance model.
    @State var loanIsLive = false   // ContentView+PodLoan.swift maintains it

    var body: some View {
        VStack {
            // TabView for swipeable pages
            TabView(selection: $selectedPage) {
                // Gated pages keep their slots; the indices are load-bearing (see sportPage).
                Group {
                    if isOnboarded { WatchActionsView() } else { CompleteOnboardingView() }
                }
                    .tag(0)
                    .task {
                        loopManager.requestContextUpdate {}
                    }

                Group {
                    if isOnboarded { ChartPageView() } else { CompleteOnboardingView() }
                }
                    .tag(1)
                    .task {
                        loopManager.requestContextUpdate {}
                    }

                // Sport Mode: always present, and the only way to start a session.
                if FeatureFlags.sportModeEnabled {
                    GlanceView(model: glanceModel)
                        .tag(Self.sportPage)
                }

                // Diagnostics, last. Loan carbs are retracted in the stock CarbList.
                if FeatureFlags.sportModeEnabled {
                    LoanDebugView()
                        .tag(Self.sportPage + 1)
                }
            }
            .tabViewStyle(.page)
            .indexViewStyle(.page(backgroundDisplayMode: .automatic))
        }
        .onChange(of: loopManager.pendingPresetReminder) { oldValue, newValue in
            if oldValue == nil, newValue != nil {
                presetToConfirm = loopManager.pendingPreset
            }
        }
        .sheet(item: $presetToConfirm) { preset in
            PresetConfirmationView(preset: preset)
        }
        .onChange(of: selectedPage, { oldValue, newValue in
            podLoanRememberPage(newValue)
        })
        // A loan activating shows the glance. Posted from the loan queue, hence `.receive(on:)`.
        .onReceive(NotificationCenter.default.publisher(for: .podLoanPhaseDidChange).receive(on: RunLoop.main)) { _ in
            podLoanPhaseDidChange()
        }
        // During a loan, finishing a carb or bolus flow returns to the glance, which shows the dose landing.
        .onReceive(NotificationCenter.default.publisher(for: .carbAndBolusFlowDidComplete).receive(on: RunLoop.main)) { _ in
            podLoanReturnToGlanceAfterFlow()
        }
        .task {
            podLoanSyncGateOnLaunch()
        }
    }
}


#Preview {
    ContentView()
}
