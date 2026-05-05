//
//  LoopInsights_GlucoseUnitContext.swift
//  Loop
//
//  LoopInsights — Shared glucose unit helper for mg/dL vs mmol/L localization.
//  Used by LoopInsights and AutoPresets to honor the user's HealthKit-derived
//  display glucose unit in analysis, AI prompts, thresholds, and formatting.
//
//  Idea by Taylor Patterson. Coded by Claude Code.
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Foundation
import HealthKit
import LoopKit
import LoopKitUI

/// Wraps `DisplayGlucosePreference` and exposes unit-aware thresholds, formatters,
/// and AI-prompt context strings. Created on demand from a `DisplayGlucosePreference`
/// instance — does not retain state of its own beyond the `HKUnit`.
///
/// Standard clinical thresholds are defined in mg/dL as `HKQuantity` constants and
/// converted to the user's unit on read. Display strings round to whole numbers for
/// mg/dL and one decimal place for mmol/L.
struct LoopInsights_GlucoseUnitContext {

    // MARK: - Standard clinical thresholds (canonical mg/dL)

    static let urgentLow   = HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 54)
    static let low         = HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 70)
    static let overnightLow = HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 80)
    static let high        = HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 180)
    static let overnightHigh = HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 200)
    static let veryHigh    = HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 250)

    // MARK: - State

    let unit: HKUnit
    private let preference: DisplayGlucosePreference?

    /// Build from a `DisplayGlucosePreference` (preferred path — uses its formatter).
    init(displayGlucosePreference: DisplayGlucosePreference) {
        self.unit = displayGlucosePreference.unit
        self.preference = displayGlucosePreference
    }

    /// Build from a raw `HKUnit` (used by services without a preference reference).
    init(unit: HKUnit) {
        self.unit = unit
        self.preference = nil
    }

    /// Fallback constructor — assumes mg/dL. Use only when no preference is reachable.
    static var fallbackMgdl: LoopInsights_GlucoseUnitContext {
        LoopInsights_GlucoseUnitContext(unit: .milligramsPerDeciliter)
    }

    var isMmolL: Bool { unit == .millimolesPerLiter }

    var unitString: String {
        isMmolL ? "mmol/L" : "mg/dL"
    }

    // MARK: - Threshold values in current unit (for direct numeric comparison)

    var urgentLowValue: Double  { Self.urgentLow.doubleValue(for: unit) }
    var lowValue: Double        { Self.low.doubleValue(for: unit) }
    var overnightLowValue: Double  { Self.overnightLow.doubleValue(for: unit) }
    var highValue: Double       { Self.high.doubleValue(for: unit) }
    var overnightHighValue: Double { Self.overnightHigh.doubleValue(for: unit) }
    var veryHighValue: Double   { Self.veryHigh.doubleValue(for: unit) }

    // MARK: - Conversion

    /// Convert an mg/dL value to the user's unit.
    func userValue(fromMgdl mgdl: Double) -> Double {
        HKQuantity(unit: .milligramsPerDeciliter, doubleValue: mgdl).doubleValue(for: unit)
    }

    /// Convert a user-unit value back to mg/dL.
    func mgdlValue(fromUser value: Double) -> Double {
        HKQuantity(unit: unit, doubleValue: value).doubleValue(for: .milligramsPerDeciliter)
    }

    // MARK: - Formatting

    /// Format an mg/dL value into the user's display unit.
    /// e.g. 144 → "144 mg/dL" or "8.0 mmol/L".
    func formatMgdl(_ mgdl: Double, includeUnit: Bool = true) -> String {
        let q = HKQuantity(unit: .milligramsPerDeciliter, doubleValue: mgdl)
        return format(q, includeUnit: includeUnit)
    }

    /// Format an `HKQuantity` glucose value in the user's display unit.
    func format(_ quantity: HKQuantity, includeUnit: Bool = true) -> String {
        if let pref = preference {
            return pref.format(quantity, includeUnit: includeUnit)
        }
        let value = quantity.doubleValue(for: unit)
        let formatted = isMmolL
            ? String(format: "%.1f", value)
            : String(format: "%.0f", value)
        return includeUnit ? "\(formatted) \(unitString)" : formatted
    }

    /// Format a numeric value already expressed in the user's unit.
    func formatUserValue(_ value: Double, includeUnit: Bool = true) -> String {
        let formatted = isMmolL
            ? String(format: "%.1f", value)
            : String(format: "%.0f", value)
        return includeUnit ? "\(formatted) \(unitString)" : formatted
    }

    // MARK: - Display strings

    /// Localized "Time in Range (X-Y)" label using user-unit thresholds.
    var tirRangeLabel: String {
        let lo = formatUserValue(lowValue, includeUnit: false)
        let hi = formatUserValue(highValue, includeUnit: false)
        return "Time in Range (\(lo)-\(hi))"
    }

    /// "70-180 mg/dL" or "3.9-10.0 mmol/L" — for inline use in narrative strings.
    var tirRangeString: String {
        let lo = formatUserValue(lowValue, includeUnit: false)
        let hi = formatUserValue(highValue, includeUnit: false)
        return "\(lo)-\(hi) \(unitString)"
    }

    // MARK: - AI prompt context

    /// Append-to-system-prompt block instructing the model to respond in the user's unit.
    /// Includes ISF rule (1800 vs 100), TIR target range, and a directive that all numeric
    /// and prose glucose values must use the user's unit. Data sent in the prompt body is
    /// still in mg/dL (Claude's strongest training surface) — the model converts on output.
    func aiPromptUnitContext() -> String {
        let isfRule = isMmolL
            ? "Rule of 100 (ISF mmol/L per unit ≈ 100 ÷ TDD)"
            : "Rule of 1800 (ISF mg/dL per unit ≈ 1800 ÷ TDD)"
        return """

        UNIT CONTEXT — IMPORTANT:
        - The user uses \(unitString) for blood glucose.
        - ALL glucose values in your response — both numeric figures and any prose — MUST be expressed in \(unitString).
        - Glucose data in the prompt below may be in mg/dL; convert to \(unitString) for the user.
        - Use \(isfRule) for any insulin sensitivity factor calculations.
        - Time in Range target range is \(tirRangeString).
        """
    }

    /// Numeric ISF divisor — 1800 for mg/dL, 100 for mmol/L. Used in `ISF = divisor / TDD`.
    var isfRuleDivisor: Double {
        isMmolL ? 100.0 : 1800.0
    }
}
