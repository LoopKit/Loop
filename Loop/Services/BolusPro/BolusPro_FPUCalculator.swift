//
//  BolusPro_FPUCalculator.swift
//  Loop
//
//  BolusPro — Fat-Protein Unit math + secondary carb entry generator.
//
//  Idea by Taylor Patterson. Coded by Claude Code.
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Foundation
import HealthKit
import LoopKit

/// Stateless calculator that turns fat + protein grams into a secondary
/// carb-equivalent entry sized and timed for delayed (FPU) glucose effect.
///
/// **Math (Trio's gram formula):**
/// ```
/// bonusGrams = (fat × 0.9 + protein × 0.4) × coverageFactor × sliderPosition
/// ```
/// where:
/// - `coverageFactor` is the user's configured `coverageFactorPercent / 100`
/// - `sliderPosition` is 0.0…1.0 from the per-entry slider
///
/// **FPU score** (for threshold checks and UI display, not used in dosing):
/// ```
/// fpuScore = (fat × 9 + protein × 4) / 100      // 1 FPU = 100 kcal
/// ```
///
/// **FPU-additive design** — the bonus grams are ADDITIONAL carbs scheduled
/// later. They never reduce the primary carb count.
enum BolusPro_FPUCalculator {

    // MARK: - FPU Score

    /// Strict-Warsaw 1-FPU-per-100-kcal score. Display-only — used for
    /// threshold gating and UI ("2.4 FPU" pill), NOT for dosing math.
    static func fpuScore(fatGrams: Double, proteinGrams: Double) -> Double {
        let kcal = (fatGrams * 9.0) + (proteinGrams * 4.0)
        return kcal / 100.0
    }

    // MARK: - Bonus Grams (Trio formula)

    /// Carb-equivalent grams for the secondary entry, after applying both the
    /// user's coverage knob and the per-entry slider.
    static func bonusGrams(
        fatGrams: Double,
        proteinGrams: Double,
        coverageFactor: Double,   // 0.10…1.00 from settings
        sliderPosition: Double    // 0.0…1.0 from per-entry slider
    ) -> Double {
        let raw = (fatGrams * 0.9) + (proteinGrams * 0.4)
        let scaled = raw * coverageFactor * sliderPosition
        return max(0, scaled.rounded(toPlaces: 1))
    }

    // MARK: - Combined Result

    /// One-shot helper returning every value the UI needs given a state blob.
    static func calculate(
        from state: BolusProEntryState,
        coverageFactorPercent: Int = BolusPro_FeatureFlags.coverageFactorPercent,
        triggerThresholdFPU: Double = BolusPro_FeatureFlags.triggerThresholdFPU
    ) -> BolusProFPUResult {
        let coverage = Double(coverageFactorPercent) / 100.0
        let score = fpuScore(fatGrams: state.macros.fatGrams, proteinGrams: state.macros.proteinGrams)
        let bonus = bonusGrams(
            fatGrams: state.macros.fatGrams,
            proteinGrams: state.macros.proteinGrams,
            coverageFactor: coverage,
            sliderPosition: state.sliderCoverage
        )
        let bonusFull = bonusGrams(
            fatGrams: state.macros.fatGrams,
            proteinGrams: state.macros.proteinGrams,
            coverageFactor: coverage,
            sliderPosition: 1.0
        )
        return BolusProFPUResult(
            fpuScore: score,
            bonusGrams: bonus,
            bonusGramsAtFullCoverage: bonusFull,
            crossesAutoTriggerThreshold: score >= triggerThresholdFPU
        )
    }

    // MARK: - Secondary Carb Entry

    /// Build the secondary `NewCarbEntry` representing the FPU tail.
    /// Returns `nil` if BolusPro is off or the bonus is too small to bother.
    ///
    /// The secondary entry:
    /// - `startDate` = primary `startDate` + configured `fpuDelayMinutes`
    /// - `absorptionTime` = configured `fpuAbsorptionHours`
    /// - `foodType` = `BolusPro_FeatureFlags.fpuEntryEmoji` (🥩) so users
    ///   can identify it in carb history
    static func makeSecondaryEntry(
        primaryStartDate: Date,
        state: BolusProEntryState,
        delayMinutes: Int = BolusPro_FeatureFlags.fpuDelayMinutes,
        absorptionHours: Int = BolusPro_FeatureFlags.fpuAbsorptionHours,
        coverageFactorPercent: Int = BolusPro_FeatureFlags.coverageFactorPercent
    ) -> NewCarbEntry? {
        guard state.enabled, state.macros.hasMacros else { return nil }

        let result = calculate(
            from: state,
            coverageFactorPercent: coverageFactorPercent
        )
        guard result.isWorthWriting else { return nil }

        let secondaryStart = primaryStartDate.addingTimeInterval(TimeInterval(delayMinutes * 60))
        let absorption = TimeInterval(absorptionHours * 3600)

        return NewCarbEntry(
            date: Date(),
            quantity: HKQuantity(unit: .gram(), doubleValue: result.bonusGrams),
            startDate: secondaryStart,
            foodType: BolusPro_FeatureFlags.fpuEntryEmoji,
            absorptionTime: absorption
        )
    }
}

// MARK: - Math Helpers

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let multiplier = pow(10.0, Double(places))
        return (self * multiplier).rounded() / multiplier
    }
}
