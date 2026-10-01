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

    /// Mirrored into plain state rather than read from `glanceModel` inside `body`. Reading the
    /// model here would subscribe THE ROOT VIEW to a timer-driven object on the loan path, so
    /// every glance tick would invalidate the whole app — and a publish that arrives off the main
    /// thread would do it from the wrong thread, which SwiftUI does not survive.
    @State var loanIsLive = false   // ContentView+PodLoan.swift maintains it

    var body: some View {
        VStack {
            // TabView for swipeable pages
            TabView(selection: $selectedPage) {
                // Gated pages keep their slots whether or not they are gated — the page indices
                // below are load-bearing (see sportPage), and a page that vanishes renumbers
                // the ones beside it.
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

                // Sport Mode. Always present rather than conditionally inserted: a page that
                // appears and disappears under the user renumbers the ones beside it, and the
                // glance is also the only way to START a session, so it has to be reachable
                // before there is anything to show.
                GlanceView(model: glanceModel)
                    .tag(Self.sportPage)

                // Diagnostics. Last, so a swipe never lands here by accident.
                //
                // Retracting a loan-time carb lives in the STOCK Active Carbs list (CarbList),
                // reached by tapping through from the chart page — not on a page of its own. It
                // is the same list either way; during a loan it reads the loan's store and gains
                // swipe-to-delete.
                LoanDebugView()
                    .tag(Self.sportPage + 1)
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
        // A loan activating takes the user to the glance — it is the surface that says what the
        // watch is doing while it holds the pump. Replaces the WatchKit page-navigation call the
        // session used to make directly.
        // `.receive(on:)` is load-bearing, not tidiness: the phase notification is posted from
        // the loan's own queue, and both statements below mutate view state.
        .onReceive(NotificationCenter.default.publisher(for: .podLoanPhaseDidChange).receive(on: RunLoop.main)) { _ in
            podLoanPhaseDidChange()
        }
        // Finishing a carb entry or a bolus during a loan returns to the glance.
        //
        // The flow is a SHEET presented from page 0, so dismissing it lands the user back on the
        // stock actions page. That is correct when the phone holds the pod — the actions page is
        // where they started. It is wrong when the WRIST holds it: the glance is the only surface
        // that shows the bolus actually delivering, the resulting IOB, and the loan still being
        // held. Landing on a page that shows none of that reads as "did it work?", which is the
        // one question a just-delivered bolus must not raise.
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
