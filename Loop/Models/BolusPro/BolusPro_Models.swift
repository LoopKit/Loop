//
//  BolusPro_Models.swift
//  Loop
//
//  BolusPro — Value types for FPU calculation results and dual-entry pairing.
//
//  Idea by Taylor Patterson. Coded by Claude Code.
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Foundation

/// Result of running fat + protein through the BolusPro FPU calculator.
///
/// FPU-additive math: the bonus grams are an *extra* carb-equivalent entry
/// scheduled later, ON TOP of the user's primary carbs. They are never
/// subtracted from the carb total.
struct BolusProFPUResult: Equatable {

    /// Raw fat+protein FPU score (1 FPU = 100 kcal of fat+protein).
    /// Used for threshold checks and UI display.
    let fpuScore: Double

    /// Carb-equivalent grams to dose for the protein/fat tail, after applying
    /// the user's coverage factor. This is what the secondary entry contains.
    let bonusGrams: Double

    /// Trio-formula intermediate before coverage scaling, useful for UI
    /// when the user moves the slider to see the maximum at 100%.
    let bonusGramsAtFullCoverage: Double

    /// Whether the meal crosses the auto-trigger threshold.
    let crossesAutoTriggerThreshold: Bool

    /// Returns true when `bonusGrams` is non-trivial enough to write a
    /// secondary entry (≥ 1g — anything less is noise).
    var isWorthWriting: Bool { bonusGrams >= 1.0 }
}

/// Macro inputs to the FPU calculator. Either provided by FoodFinder's AI
/// analysis or entered manually by the user.
struct BolusProMacroInputs: Equatable {
    var fatGrams: Double
    var proteinGrams: Double

    static let zero = BolusProMacroInputs(fatGrams: 0, proteinGrams: 0)

    var hasMacros: Bool { fatGrams > 0 || proteinGrams > 0 }
}

/// State a CarbEntryView holds to render BolusPro UI and produce a paired
/// secondary entry on submit. Lives on `CarbEntryViewModel` as a single
/// `@Published` blob so the rest of the existing model stays clean.
struct BolusProEntryState: Equatable {

    /// Master per-entry toggle. When false, BolusPro contributes nothing to
    /// the carb-entry submission.
    var enabled: Bool

    /// User's manual or AI-derived fat/protein values.
    var macros: BolusProMacroInputs

    /// 0.0…1.0 — slider position. 1.0 maps to the user's configured
    /// `coverageFactorPercent`. Slider value of 0 = no FPU bonus.
    var sliderCoverage: Double

    /// Origin of the macro values — drives DataLayer analytics and gates
    /// the manual entry fields (hidden when source is `.ai`/`.product`/
    /// `.favorite`, shown when `.manual` or `nil`).
    var macrosSource: BolusProMacrosSource?

    /// True when the per-entry toggle was flipped on by FoodFinder
    /// auto-detection rather than by user tap. Recorded for analytics.
    var autoDetected: Bool

    static let off = BolusProEntryState(
        enabled: false,
        macros: .zero,
        sliderCoverage: 1.0,
        macrosSource: nil,
        autoDetected: false
    )

    var macrosFromFoodFinder: Bool {
        switch macrosSource {
        case .ai, .product, .favorite: return true
        case .manual, .none: return false
        }
    }
}
