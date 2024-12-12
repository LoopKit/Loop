//
//  PresetCard.swift
//  Loop
//
//  Created by Cameron Ingham on 10/24/24.
//  Copyright © 2024 LoopKit Authors. All rights reserved.
//

import LoopAlgorithm
import LoopKitUI
import SwiftUI
import LoopKit

struct PresetCard: View {
    @Environment(\.guidanceColors) private var guidanceColors

    @EnvironmentObject var displayGlucosePreference: DisplayGlucosePreference
    
    let icon: PresetIcon
    let presetName: String
    let duration: PresetDurationType
    let insulinSensitivityMultiplier: Double?
    let correctionRange: ClosedRange<LoopQuantity>?
    let guardrail: Guardrail<LoopQuantity>?
    let expectedEndTime: PresetExpectedEndTime?
    
    var presetTitle: some View {
        HStack(spacing: 6) {
            switch icon {
            case .emoji(let emoji):
                Text(emoji)
            case .image(let name, let iconColor):
                Image(name)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundColor(iconColor)
                    .frame(width: UIFontMetrics.default.scaledValue(for: 20), height: UIFontMetrics.default.scaledValue(for: 20))
            }

            Text(presetName)
                .fontWeight(.semibold)
        }
    }
    
    var presetDuration: some View {
        Group { Text(Image(systemName: "timer")) + Text(" \(duration.localizedTitle)") }
            .font(.footnote)
            .foregroundColor(.secondary)
            .accessibilityLabel(Text(duration.accessibilityLabel))
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    VStack(alignment: .leading) {
                        if let expectedEndTime {
                            HStack(spacing: 8) {
                                Text(Image(systemName: "timer"))
                                +
                                Text(" \(expectedEndTime.localizedTitle)")
                                    .accessibilityLabel(Text(expectedEndTime.accessibilityLabel))
                            }
                            .font(.footnote)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 5)
                            .background(Color.presets)
                            .cornerRadius(8)
                        }
                        presetTitle
                    }

                    Spacer()

                    if expectedEndTime == nil {
                        presetDuration
                    }
                    
                    Image(systemName: "chevron.right")
                        .imageScale(.small)
                        .font(.headline)
                        .foregroundColor(.secondary)
                        .opacity(0.5)
                }
                
                VStack(alignment: .leading, spacing: 10) {
                    presetTitle
                    
                    presetDuration
                }
            }
            
            Divider()
                .padding(.horizontal, -10)
            
            PresetStatsView(
                insulinSensitivityMultiplier: insulinSensitivityMultiplier,
                correctionRange: correctionRange,
                guardrail: guardrail
            )
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8)
            .fill(Color(UIColor.tertiarySystemBackground))
            .stroke(Color(UIColor.secondarySystemBackground), lineWidth: 1)
            .frame(maxWidth: .infinity))
    }
}

extension PresetExpectedEndTime {
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }()

    var localizedTitle: String {
        switch self {
        case .untilCarbsEntered:
            return NSLocalizedString("on until carbs added", comment: "Preset card pre-meal expected end time")
        case .indefinite:
            return NSLocalizedString("on indefinitely", comment: "Preset card indefinite scheduled end time")
        case .scheduled(let date):
            return NSLocalizedString("on until \(Self.timeFormatter.string(from: date))", comment: "Presets card time duration accessibility label")
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .untilCarbsEntered:
            return NSLocalizedString("on until carbs added", comment: "Presets card pre-meal expected end time accessibility label")
        case .indefinite:
            return NSLocalizedString("on indefinitely", comment: "Presets card indefinite duration accessibility label")
        case .scheduled(let date):
            let formatter = DateComponentsFormatter()
            formatter.allowedUnits = [.hour, .minute]
            formatter.unitsStyle = .spellOut
            return NSLocalizedString("on until \(Self.timeFormatter.string(from: date))", comment: "Presets card time duration accessibility label")
        }
    }
}

extension PresetDurationType {
    var localizedTitle: String {
        switch self {
        case .untilCarbsEntered:
            return NSLocalizedString("until carbs added", comment: "Preset card pre-meal duration")
        case .indefinite:
            return NSLocalizedString("indefinite", comment: "Preset card indefinite duration")
        case .duration(let duration):
            let formatter = DateComponentsFormatter()
            formatter.allowedUnits = [.hour, .minute]
            formatter.unitsStyle = .short
            return formatter.string(from: duration) ?? ""

        }
    }

    var accessibilityLabel: String {
        switch self {
        case .untilCarbsEntered:
            return NSLocalizedString("Active until carbs are added", comment: "Presets card pre-meal duration accessibility label")
        case .indefinite:
            return NSLocalizedString("Active indefinitely", comment: "Presets card indefinite duration accessibility label")
        case .duration(let duration):
            let formatter = DateComponentsFormatter()
            formatter.allowedUnits = [.hour, .minute]
            formatter.unitsStyle = .spellOut
            return NSLocalizedString("Active for \(formatter.string(from: duration) ?? "")", comment: "Presets card time duration accessibility label")
        }
    }
}
