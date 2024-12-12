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
        
        self.activeOverride = viewModel.temporaryPresetsManager.preMealOverride ?? viewModel.temporaryPresetsManager.scheduleOverride
    }
    
    var operation: Operation {
        if activeOverride?.presetId == preset.id {
            return .end
        } else {
            return .start
        }
    }
    
    private func title(font: Font, iconSize: Double) -> some View {
        HStack(spacing: 6) {
            switch preset.icon {
            case .emoji(let emoji):
                Text(emoji)
            case .image(let name, let iconColor):
                Image(name)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundColor(iconColor)
                    .frame(width: UIFontMetrics.default.scaledValue(for: iconSize), height: UIFontMetrics.default.scaledValue(for: iconSize))
            }

            Text(preset.name)
                .font(font)
                .fontWeight(.semibold)
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
                    dismiss()
                    viewModel.startPreset(preset)
                }
                .buttonStyle(ActionButtonStyle())
            case .end:
                Button("End Preset") {
                    dismiss()
                    viewModel.endPreset()
                }
                .buttonStyle(ActionButtonStyle(.destructive))
                
                NavigationLink("Adjust Preset Duration") {
                    ZStack {
                        Color(UIColor.secondarySystemBackground)
                            .edgesIgnoringSafeArea(.all)
                        
                        VStack(spacing: 24) {
                            title(font: .largeTitle, iconSize: 36)
                                .fontWeight(.bold)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            
                            DatePicker("On until", selection: .constant(Date()), displayedComponents: .hourAndMinute)
                                .padding(6)
                                .padding(.leading, 10)
                                .background(Color.white.cornerRadius(10))
                            
                            Spacer()
                        }
                        .padding(.horizontal)
                    }
                }
                .buttonStyle(ActionButtonStyle(.tertiary))
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
                        title(font: .title2, iconSize: 20)
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
