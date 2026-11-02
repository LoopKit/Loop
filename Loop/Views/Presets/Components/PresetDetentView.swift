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
import LoopCore

struct PresetDetentView: View {

    enum Operation {
        case start
        case end
    }
    
    @EnvironmentObject private var displayGlucosePreference: DisplayGlucosePreference
    @Environment(\.settingsManager) private var settingsManager
    @Environment(\.temporaryPresetsManager) private var temporaryPresetsManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appName) private var appName

    let preset: SelectablePreset
    let roundBasalRate: ((Double) -> Double)?
    let didTapEdit: () -> Void

    var operation: Operation? {
        if temporaryPresetsManager.activeOverride?.presetId == preset.id {
            return .end
        } else if case .custom(let temporaryPreset) = preset,
            !settingsManager.settings.overridePresets.contains(where: { $0.id == temporaryPreset.id })
        {
            // if a custom preset is not saved, it is single use and cannot start again
            return nil
        } else {
            return .start
        }
    }
    
    @ViewBuilder
    private var subtitle: some View {
        Group {
            switch operation {
            case .start:
                HStack {
                    if preset.isScheduled {
                        Text(Image(systemName: "alarm"))
                            .font(.footnote)
                            .foregroundColor(.carbs)
                            .accessibilityLabel(Text("Scheduled reminder"))
                    }
                    Text("Duration: \(preset.duration.localizedTitle)")
                }
            case .end:
                if let activeOverride = temporaryPresetsManager.activeOverride {
                    if activeOverride.presetId == preset.id {
                        switch activeOverride.duration {
                        case .finite:
                            let endTimeText = DateFormatter.localizedString(from: activeOverride.activeInterval.end, dateStyle: .none, timeStyle: .short)
                            Text(String(format: NSLocalizedString("on until %@", comment: "The format for the description of a custom preset end date"), endTimeText))
                                .accessibilityIdentifier("text_PresetActionSheetActiveOn")
                        case .indefinite:
                            EmptyView()
                        }
                    } else {
                        let startTimeText = DateFormatter.localizedString(from: activeOverride.startDate, dateStyle: .none, timeStyle: .short)
                        Text(String(format: NSLocalizedString("starting at %@", comment: "The format for the description of a custom preset start date"), startTimeText))
                    }
                }
            default:
                EmptyView()
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
                    temporaryPresetsManager.startPreset(preset)
                    dismiss()
                }
                .buttonStyle(ActionButtonStyle())
                .disabled((temporaryPresetsManager.activeOverride != nil && preset.id != temporaryPresetsManager.activeOverride?.presetId) || (preset.isPreMeal && settingsManager.dosingEnabled == false))
                .accessibilityIdentifier("button_startPreset")
            case .end:
                Button("End Preset") {
                    temporaryPresetsManager.clearOverride()
                    dismiss()
                }
                .buttonStyle(ActionButtonStyle(.destructive))
                .accessibilityIdentifier("button_endPreset")
                
                if preset.duration != .untilCarbsEntered {
                    NavigationLink("Adjust Preset Duration") {
                        EditPresetDurationView()
                    }
                    .buttonStyle(ActionButtonStyle(.tertiary))
                    .accessibilityIdentifier("button_adjustPresetDuration")
                }
            default:
                EmptyView()
            }
            
            Button("Close") {
                dismiss()
            }
            .tint(.accentColor)
            .fontWeight(.semibold)
            .accessibilityIdentifier("button_close")
        }
    }
    
    @State var sheetContentHeight: Double = 0

    var settingsImpact: TherapySettings.InsulinMultiplierImpact {
        var settingsImpact = settingsManager.therapySettings.impact(for: preset.insulinNeedsScaleFactor)
        guard let basalRate = settingsImpact.basalRate,
              let roundBasalRate
        else {
            return settingsImpact
        }
        
        settingsImpact.basalRate = LoopQuantity(unit: .internationalUnitsPerHour, doubleValue:  roundBasalRate(basalRate.doubleValue(for: .internationalUnitsPerHour)))
        return settingsImpact
    }

    var highInsulinNeedsWarningText: String {
        switch operation {
        case .start:
            String(format: NSLocalizedString("%1$@ will set your correction range to 110 mg/dL or higher when this preset is enabled.", comment: "The format string for the high insulin needs preset warning text on the preset detent screen when starting a preset. (1: app name)"), appName)
        case .end:
            String(format: NSLocalizedString("%1$@ has set your correction range to 110 mg/dL or higher.", comment: "The format string for the high insulin needs preset warning text on the preset detent screen when stopping a preset. (1: app name)"), appName)
        default:
            ""
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
                            didTapEdit()
                        } label: {
                            Group {
                                Text(Image(systemName: "pencil")) + Text(" ") + Text("Edit Preset")
                            }
                            .font(.subheadline)
                        }
                        .tint(.accentColor)
                        .padding(.bottom, -8)
                        .accessibilityIdentifier("button_EditPreset")
                    }
                }
                
                Divider()
                
                PresetStatsView(
                    insulinMultiplier: preset.insulinNeedsScaleFactor,
                    correctionRange: preset.correctionRange,
                    guardrail: settingsManager.correctionRangeGuardrailForPreset(preset),
                    therapySettingsImpactDisplayState: operation == .end ? .show(settingsImpact) : .hide,
                    isScheduled: false,
                    isActive: temporaryPresetsManager.activePreset?.id == preset.id,
                    effectiveCorrectionRange: temporaryPresetsManager.effectiveCorrectionRange
                )
                .padding(.horizontal)

                if case let .activity(activityPreset) = preset, !activityPreset.isModifiedFromDefault {
                    Text("\(Image(systemName: "checkmark.seal.fill")) Recommended starting values")
                        .font(.subheadline)
                        .foregroundStyle(Color.accentColor)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 4)
                }

                if preset.veryHighInsulinNeeds {
                    WarningPanel {
                        Text(highInsulinNeedsWarningText)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                actionArea
            }
            .toolbar(.hidden)
            .padding(.top)
            .padding(16)
            .readContentHeight(to: $sheetContentHeight)
        }
        .sheetDetent(height: sheetContentHeight)
    }
}

extension SelectablePreset {
    func title(font: Font, iconSize: Double) -> some View {
        HStack(spacing: 6) {
            if let icon, !icon.isEmpty {
                PresetSymbolView(icon)
            }

            Text(name)
                .font(font)
                .fontWeight(.semibold)
        }
    }
}
