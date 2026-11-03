//
//  GlucoseBand+Display.swift
//  Loop
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopKit
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
}
