//
//  PresetDetentView.swift
//  Loop
//
//  Created by Cameron Ingham on 12/11/24.
//  Copyright © 2024 LoopKit Authors. All rights reserved.
//

import LoopKit
import LoopKitUI
import SwiftUI

struct PresetDetentView: View {
    
    enum Operation {
        case start
        case end
    }
    
    @EnvironmentObject private var displayGlucosePreference: DisplayGlucosePreference
    @Environment(\.dismiss) private var dismiss
    
    let preset: SelectablePreset
    let viewModel: PresetsViewModel
    
    let activeOverride: TemporaryScheduleOverride?

    init(viewModel: PresetsViewModel, preset: SelectablePreset) {
        self.viewModel = viewModel
        self.preset = preset
        self.activeOverride = viewModel.temporaryPresetsManager.activeOverride
    }
    
    
    init?(viewModel: PresetsViewModel) {
        guard let preset = viewModel.pendingPreset else { return nil }
        self.init(viewModel: viewModel, preset: preset)
    }
    
    var operation: Operation {
        if activeOverride?.presetId == preset.id {
            return .end
        } else {
            return .start
        }
    }
    
    @ViewBuilder
    private var subtitle: some View {
        Group {
            switch operation {
            case .start:
                Text("Duration: \(preset.duration.localizedTitle)")
            case .end:
                if let activeOverride {
                    if activeOverride.presetId == preset.id {
                        switch activeOverride.duration {
                        case .finite:
                            let endTimeText = DateFormatter.localizedString(from: activeOverride.activeInterval.end, dateStyle: .none, timeStyle: .short)
                            Text(String(format: NSLocalizedString("on until %@", comment: "The format for the description of a custom preset end date"), endTimeText))
                        case .indefinite:
                            EmptyView()
                        }
                    } else {
                        let startTimeText = DateFormatter.localizedString(from: activeOverride.startDate, dateStyle: .none, timeStyle: .short)
                        Text(String(format: NSLocalizedString("starting at %@", comment: "The format for the description of a custom preset start date"), startTimeText))
                    }
                }
            }
        }
        .font(.subheadline)
    }
    
    @ViewBuilder
    var actionArea: some View {
        VStack(spacing: 12) {
            switch operation {
            case .start:
                Button("Start Preset") {
                    viewModel.startPreset(preset)
                }
                .buttonStyle(ActionButtonStyle())
                .disabled(viewModel.activePreset != nil && preset.id != viewModel.activePreset?.id)
            case .end:
                Button("End Preset") {
                    viewModel.endPreset()
                    dismiss()
                }
                .buttonStyle(ActionButtonStyle(.destructive))
                
                if preset.duration != .untilCarbsEntered {
                    NavigationLink("Adjust Preset Duration") {
                        if let activeOverride {
                            EditOverrideDurationView(override: activeOverride, viewModel: viewModel)
                        }
                    }
                    .buttonStyle(ActionButtonStyle(.tertiary))
                }
            }
            
            Button("Close") {
                dismiss()
            }
            .tint(.accentColor)
            .fontWeight(.semibold)
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(spacing: 16) {
                    VStack(spacing: 4) {
                        preset.title(font: .title2, iconSize: 20)
                        subtitle
                    }
                    
                    if operation == .start {
                        Button {
                            print("Edit \(preset.name)")
                        } label: {
                            Group {
                                Text(Image(systemName: "pencil")) + Text(" ") + Text("Edit Preset")
                            }
                            .font(.subheadline)
                        }
                        .tint(.accentColor)
                        .padding(.bottom, -8)
                    }
                }
                
                Divider()
                
                PresetStatsView(
                    insulinSensitivityMultiplier: preset.insulinSensitivityMultiplier,
                    correctionRange: preset.correctionRange,
                    guardrail: preset.guardrail
                )
                
                actionArea
            }
            .toolbar(.hidden)
            .padding(.top)
            .padding(16)
            .presentationHuggingDetent()
        }
    }
}
