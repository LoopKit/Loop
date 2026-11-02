//
//  WatchActionsView.swift
//  Loop
//
//  Created by Pete Schwamb on 8/15/25.
//  Copyright © 2025 LoopKit Authors. All rights reserved.
//


import SwiftUI
import LoopKit
import LoopCore

struct WatchActionsView: View {
    @Environment(LoopDataManager.self) var loopManager

    @State private var isShowingPresets: Bool = false
    @State private var overrideToShow: TemporaryScheduleOverride?

    var overrideActive: Bool {
        return loopManager.watchInfo.scheduleOverride?.isActive() == true
    }

    var body: some View {
        ScrollView(.vertical) {
            LoopHeader()

            HStack(spacing: 0) {
                CircleTintedButton(
                    label: "Carbs",
                    image: Image("carbs"),
                    foregroundTint: .carbs,
                    backgroundTint: .darkCarbs
                ) {
                    ExtensionDelegate.shared().usageRecorder.didDisplayScreen("carbEntry")
                    loopManager.bolusViewModel = CarbAndBolusFlowViewModel(configuration: .carbEntry(nil))
                }
                CircleTintedButton(
                    label: "Bolus",
                    image: Image("bolus"),
                    foregroundTint: .insulin,
                    backgroundTint: .darkInsulin
                ) {
                    ExtensionDelegate.shared().usageRecorder.didDisplayScreen("bolus")
                    loopManager.bolusViewModel = CarbAndBolusFlowViewModel(configuration: .manualBolus)
                }
            }
            .padding(.bottom, 4)
            HStack {
                CircleTintedButton(
                    label: "Presets",
                    image: Image("presets"),
                    foregroundTint: overrideActive ? .darkPresets : .presets,
                    backgroundTint: overrideActive ? .presets : .darkPresets
                ) {
                    ExtensionDelegate.shared().usageRecorder.didDisplayScreen("presets")
                    if overrideActive {
                        overrideToShow = loopManager.watchInfo.scheduleOverride
                    } else {
                        isShowingPresets = true
                    }
                }
                Spacer()
                    .frame(maxWidth: .infinity)
            }
        }
        .font(.system(size: 14, weight: .light))
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $isShowingPresets) {
            PresetsView()
        }
        .sheet(isPresented: Binding(get: {
            overrideToShow != nil
        }, set: {
            if !$0 { overrideToShow = nil }
        })) {
            let preset = loopManager.selectablePresets.first(where: { $0.id == overrideToShow!.presetId })
            PresetConfirmationView(preset: preset)
        }
        .sheet(isPresented:Binding(
            get: { loopManager.bolusViewModel != nil },
            set: { if !$0 { loopManager.bolusViewModel = nil } }
        )) {
            CarbAndBolusFlow(viewModel: loopManager.bolusViewModel!)
        }
        .environment(\.glucoseDisplayUnit, loopManager.displayGlucoseUnit)
    }

}
