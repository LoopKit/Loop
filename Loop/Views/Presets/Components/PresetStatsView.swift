//
//  PresetStatsView.swift
//  Loop
//
//  Created by Cameron Ingham on 12/11/24.
//  Copyright © 2024 LoopKit Authors. All rights reserved.
//

import LoopAlgorithm
import LoopKit
import LoopKitUI
import SwiftUI

struct PresetStatsView: View {
    @Environment(\.guidanceColors) private var guidanceColors
    @EnvironmentObject var displayGlucosePreference: DisplayGlucosePreference
    
    let insulinSensitivityMultiplier: Double?
    let correctionRange: ClosedRange<LoopQuantity>?
    let guardrail: Guardrail<LoopQuantity>?
    
    private var numberFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        return formatter
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
}
