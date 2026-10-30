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
    /// Clear of the pages Sport Mode adds after the chart.
    static let sensorPage = 10

    @Environment(LoopDataManager.self) var loopManager

    @State private var presetToConfirm: SelectablePreset? = nil
    @State private var selectedPage = UserDefaults.standard.startOnChartPage ? 1 : 0

    var body: some View {
        VStack {
            // TabView for swipeable pages
            TabView(selection: $selectedPage) {
                WatchActionsView()
                    .tag(0)
                    .task {
                        loopManager.requestContextUpdate {}
                    }

                ChartPageView()
                    .tag(1)
                    .task {
                        loopManager.requestContextUpdate {}
                    }

                // While the watch reads the CGM itself.
                if WatchCGMHost.shared.isReadingDirectly {
                    WatchSensorView()
                        .tag(Self.sensorPage)
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
            UserDefaults.standard.startOnChartPage = selectedPage == 1
            ExtensionDelegate.shared().usageRecorder.didDisplayScreen(newValue == 0 ? "actions" : newValue == 1 ? "chart" : "sensor")
        })
    }
}


#Preview {
    ContentView()
}
