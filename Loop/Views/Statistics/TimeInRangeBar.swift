//
//  TimeInRangeBar.swift
//  Loop
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopAlgorithm
import LoopKitUI
import LoopUI

/// Writes one band edge in the unit the user reads glucose in.
///
/// The consensus thresholds are defined in mg/dL, but the AGP report publishes
/// its own rounded mmol/L edges rather than conversions of them: converting
/// 181 mg/dL yields 10.046, which prints as "10.0" and collides with the top of
/// the target band. So each edge carries both spellings, and only the number
/// formatting — decimal separator included — is left to the preference.
private func bandEdge(mgdl: Double, mmol: Double, _ preference: DisplayGlucosePreference) -> String {
    let quantity = preference.unit == .millimolesPerLiter
        ? LoopQuantity(unit: .millimolesPerLiter, doubleValue: mmol)
        : LoopQuantity(unit: .milligramsPerDeciliter, doubleValue: mgdl)
    return preference.format(quantity, includeUnit: false)
}

/// captūrAGP / IDC report palette for the glucose bands, matched to the standard
/// Ambulatory Glucose Profile report colors.
extension GlucoseBand {
    var agpColor: Color {
        switch self {
        case .veryLow:  return Color(red: 0.60, green: 0.13, blue: 0.15)  // dark red
        case .low:      return Color(red: 0.85, green: 0.26, blue: 0.24)  // red
        case .target:   return Color(red: 0.36, green: 0.65, blue: 0.37)  // green
        case .high:     return Color(red: 0.91, green: 0.77, blue: 0.26)  // gold / yellow
        case .veryHigh: return Color(red: 0.85, green: 0.55, blue: 0.24)  // orange
        }
    }

    var localizedTitle: String {
        switch self {
        case .veryLow:  return NSLocalizedString("Very Low", comment: "Time-in-range band label (<54 mg/dL)")
        case .low:      return NSLocalizedString("Low", comment: "Time-in-range band label (54–69 mg/dL)")
        case .target:   return NSLocalizedString("In Range", comment: "Time-in-range band label (70–180 mg/dL)")
        case .high:     return NSLocalizedString("High", comment: "Time-in-range band label (181–250 mg/dL)")
        case .veryHigh: return NSLocalizedString("Very High", comment: "Time-in-range band label (>250 mg/dL)")
        }
    }

    /// The band's range, written in the unit the user reads glucose in.
    func rangeDescription(_ preference: DisplayGlucosePreference) -> String {
        func edge(_ mgdl: Double, _ mmol: Double) -> String {
            bandEdge(mgdl: mgdl, mmol: mmol, preference)
        }
        switch self {
        case .veryLow:  return "<\(edge(54, 3.0))"
        case .low:      return "\(edge(54, 3.0))–\(edge(69, 3.8))"
        case .target:   return "\(edge(70, 3.9))–\(edge(180, 10.0))"
        case .high:     return "\(edge(181, 10.1))–\(edge(250, 13.9))"
        case .veryHigh: return ">\(edge(250, 13.9))"
        }
    }

    /// The consensus per-band goal, where the standard report lists one.
    var goalText: String? {
        switch self {
        case .veryHigh: return NSLocalizedString("Goal: <5%", comment: "TIR goal for very high")
        case .target:   return NSLocalizedString("Goal: >70%", comment: "TIR goal for target range")
        case .veryLow:  return NSLocalizedString("Goal: <1%", comment: "TIR goal for very low")
        default:        return nil
        }
    }
}

/// A vertical stacked time-in-range bar (Very High at top → Very Low at bottom)
/// with per-band percentages, consensus goals, and the standard clinical helper
/// notes, styled after the IDC / captūrAGP report.
struct TimeInRangeBar: View {
    let timeInRange: [GlucoseBand: Double]

    @EnvironmentObject private var displayGlucosePreference: DisplayGlucosePreference

    // Top-to-bottom display order.
    private static let order: [GlucoseBand] = [.veryHigh, .high, .target, .low, .veryLow]

    private func fraction(_ band: GlucoseBand) -> Double { timeInRange[band] ?? 0 }
    private func percent(_ band: GlucoseBand) -> Int { Int(fraction(band) * 100 + 0.5) }
    private var aboveRange: Int { Int((fraction(.veryHigh) + fraction(.high)) * 100 + 0.5) }
    private var belowRange: Int { Int((fraction(.low) + fraction(.veryLow)) * 100 + 0.5) }

    /// A target-range edge, written in the user's unit.
    private func edge(_ mgdl: Double, _ mmol: Double) -> String {
        bandEdge(mgdl: mgdl, mmol: mmol, displayGlucosePreference)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                // Vertical stacked bar.
                GeometryReader { geo in
                    VStack(spacing: 0) {
                        ForEach(Self.order, id: \.self) { band in
                            band.agpColor
                                .frame(height: max(0, geo.size.height * fraction(band)))
                        }
                        Spacer(minLength: 0)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                }
                .frame(width: 26)

                // Per-band rows: name + range on the left, percentage with its
                // goal directly beneath it on the right.
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Self.order, id: \.self) { band in
                        HStack(alignment: .top, spacing: 8) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(band.agpColor)
                                .frame(width: 10, height: 10)
                                .padding(.top, 3)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(band.localizedTitle).font(.subheadline.weight(.medium))
                                Text(band.rangeDescription(displayGlucosePreference)).font(.caption2).foregroundColor(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 1) {
                                Text("\(percent(band))%").font(.subheadline.monospacedDigit())
                                if let goal = band.goalText {
                                    Text(goal).font(.caption2).foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 220)

            // Clinical helper / suggestion text, as on the standard report.
            VStack(alignment: .leading, spacing: 4) {
                Text(String(format: NSLocalizedString("Above range (>%1$@): %2$d%% · goal <25%%",
                                                      comment: "TIR above-range summary (1: upper target edge, 2: percent of time)"),
                            edge(180, 10.0), aboveRange))
                Text(String(format: NSLocalizedString("Below range (<%1$@): %2$d%% · goal <4%%",
                                                      comment: "TIR below-range summary (1: lower target edge, 2: percent of time)"),
                            edge(70, 3.9), belowRange))
                Text(NSLocalizedString("Each 5% increase in range is clinically beneficial.", comment: "TIR suggestion"))
                Text(NSLocalizedString("Each 1% time in range ≈ 15 minutes.", comment: "TIR helper"))
            }
            .font(.caption)
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#if DEBUG
#Preview {
    TimeInRangeBar(timeInRange: [.veryLow: 0.04, .low: 0.04, .target: 0.36, .high: 0.25, .veryHigh: 0.31])
        .padding()
        .environmentObject(DisplayGlucosePreference(displayGlucoseUnit: .milligramsPerDeciliter))
}
#endif
