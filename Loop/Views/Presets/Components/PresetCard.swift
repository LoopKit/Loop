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

    private var numberFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        return formatter
    }
    
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

    var overallInsulinView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Overall Insulin")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .accessibilitySortPriority(2)

            let percent = numberFormatter.string(from: insulinSensitivityMultiplier ?? 1)!
            Group { Text(percent).bold() + Text(" of scheduled") }
                .font(.subheadline)
                .accessibilitySortPriority(1)
        }
        .accessibilityElement(children: .contain)
    }

    func guidanceColor(for classification: SafetyClassification?) -> Color? {
        guard let classification else { return nil }

        switch classification {
        case .outsideRecommendedRange(let threshold):
            switch threshold {
            case .aboveRecommended, .belowRecommended:
                return guidanceColors.warning
            case .maximum, .minimum:
                return guidanceColors.critical
            }
        case .withinRecommendedRange:
            return nil
        }
    }

    func annotatedRangeText(target: ClosedRange<LoopQuantity>) -> some View {

        let lowerColor = guardrail?.color(for: target.lowerBound, guidanceColors: guidanceColors) ?? .primary
        let upperColor = guardrail?.color(for: target.upperBound, guidanceColors: guidanceColors) ?? .primary

        let units = Text(" \(displayGlucosePreference.unit.localizedUnitString(in: .medium) ?? displayGlucosePreference.unit.unitString)")
            .foregroundStyle(upperColor)
        let lower = Text(displayGlucosePreference.format(target.lowerBound, includeUnit: false))
            .foregroundStyle(lowerColor)
            .bold()
        let upper = Text(displayGlucosePreference.format(target.upperBound, includeUnit: false))
            .foregroundStyle(upperColor)
            .bold()
        let warningSymbol = Text("\(Image(systemName: "exclamationmark.triangle.fill"))")

        let lowerClassification = guardrail?.classification(for: target.lowerBound) ?? .withinRecommendedRange
        let upperClassification = guardrail?.classification(for: target.upperBound) ?? .withinRecommendedRange

        return Group {
            switch (lowerClassification, upperClassification) {
            case (.withinRecommendedRange, .withinRecommendedRange):
                lower + Text(" - ") + upper + units
            case (.withinRecommendedRange, .outsideRecommendedRange):
                lower + Text(" - ") + warningSymbol.foregroundStyle(upperColor) + upper + units
            case (.outsideRecommendedRange, .outsideRecommendedRange):
                warningSymbol.foregroundStyle(lowerColor) + lower + Text("-").foregroundStyle(lowerColor) + upper + units
            case (.outsideRecommendedRange, .withinRecommendedRange):
                warningSymbol.foregroundStyle(lowerColor) + lower + Text("-") + upper + units
            }
        }
    }

    var correctionRangeView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Correction Range")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .accessibilitySortPriority(2)
            
            Group {
                if let target = correctionRange {
                    annotatedRangeText(target: target)
                } else {
                    Text("Scheduled Range")
                        .bold()
                }
            }
                .font(.subheadline)
                .accessibilitySortPriority(1)
        }
        .accessibilityElement(children: .contain)
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
            
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 0) {
                    overallInsulinView
                    
                    Spacer()
                    
                    correctionRangeView
                }
                
                VStack(alignment: .leading, spacing: 16) {
                    overallInsulinView
                    
                    correctionRangeView
                }
            }
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
