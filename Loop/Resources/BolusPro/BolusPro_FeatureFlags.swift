//
//  BolusPro_FeatureFlags.swift
//  Loop
//
//  BolusPro — Feature toggle, settings keys, and tunable defaults.
//  All BolusPro enable/disable + dosing-knob logic lives here.
//
//  Idea by Taylor Patterson. Coded by Claude Code.
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Foundation

/// Central on/off switch and tunable defaults for BolusPro.
/// Loop host files check `BolusPro_FeatureFlags.isEnabled` to gate UI insertion.
enum BolusPro_FeatureFlags {

    // MARK: - Defaults Registration

    /// Register default values. Call once at app launch.
    /// Defaults: master OFF, auto-detection ON, manual-macro fields ON,
    /// Trio's gram formula at 50% coverage, 60min delay, 6h FPU absorption,
    /// 1.5 FPU auto-trigger threshold.
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            Keys.isEnabled: false,
            Keys.autoDetectFromFoodFinder: true,
            Keys.showManualMacroFields: true,
            Keys.coverageFactorPercent: 50,
            Keys.fpuDelayMinutes: 60,
            Keys.fpuAbsorptionHours: 6,
            Keys.triggerThresholdFPU: 1.5,
            Keys.onboardingCompleted: false
        ])
    }

    // MARK: - Master Toggle

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.isEnabled) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.isEnabled) }
    }

    // MARK: - Auto-Detection

    /// When true, FoodFinder analyses with FPU >= triggerThreshold flip the
    /// per-entry BolusPro toggle ON automatically.
    static var autoDetectFromFoodFinder: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.autoDetectFromFoodFinder) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.autoDetectFromFoodFinder) }
    }

    /// When true, manual carb entries (no AI macro data) show fat/protein
    /// input fields when the BolusPro toggle is ON.
    static var showManualMacroFields: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.showManualMacroFields) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.showManualMacroFields) }
    }

    // MARK: - Tunable Coverage Knobs (Trio-equivalent)

    /// Coverage factor as a percentage (10–100). Scales the raw FPU grams.
    /// Trio default is 50; range 10–120 in Trio. We cap at 100 because
    /// going above is rarely safe without per-meal review.
    static var coverageFactorPercent: Int {
        get { UserDefaults.standard.integer(forKey: Keys.coverageFactorPercent) }
        set { UserDefaults.standard.set(min(100, max(10, newValue)), forKey: Keys.coverageFactorPercent) }
    }

    /// Minutes to post-date the FPU carb entry's startDate (0–120).
    static var fpuDelayMinutes: Int {
        get { UserDefaults.standard.integer(forKey: Keys.fpuDelayMinutes) }
        set { UserDefaults.standard.set(min(120, max(0, newValue)), forKey: Keys.fpuDelayMinutes) }
    }

    /// Absorption time for the FPU entry, in hours (4–8).
    static var fpuAbsorptionHours: Int {
        get { UserDefaults.standard.integer(forKey: Keys.fpuAbsorptionHours) }
        set { UserDefaults.standard.set(min(8, max(4, newValue)), forKey: Keys.fpuAbsorptionHours) }
    }

    // MARK: - Auto-Trigger Threshold

    /// Auto-flip the per-entry toggle when computed FPU >= this value.
    /// Range 0.5–3.0. Default 1.5 (~150 kcal fat+protein).
    static var triggerThresholdFPU: Double {
        get { UserDefaults.standard.double(forKey: Keys.triggerThresholdFPU) }
        set { UserDefaults.standard.set(min(3.0, max(0.5, newValue)), forKey: Keys.triggerThresholdFPU) }
    }

    // MARK: - First-Run Onboarding

    static var onboardingCompleted: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.onboardingCompleted) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.onboardingCompleted) }
    }

    // MARK: - Reset

    /// Restore all tunables (NOT the master toggle or onboarding state) to defaults.
    static func resetTunablesToDefaults() {
        let ud = UserDefaults.standard
        ud.removeObject(forKey: Keys.coverageFactorPercent)
        ud.removeObject(forKey: Keys.fpuDelayMinutes)
        ud.removeObject(forKey: Keys.fpuAbsorptionHours)
        ud.removeObject(forKey: Keys.triggerThresholdFPU)
        ud.removeObject(forKey: Keys.autoDetectFromFoodFinder)
        ud.removeObject(forKey: Keys.showManualMacroFields)
        registerDefaults()
    }
}

// MARK: - UserDefaults Keys

extension BolusPro_FeatureFlags {
    enum Keys {
        static let isEnabled                 = "com.loopkit.Loop.bolusProEnabled"
        static let autoDetectFromFoodFinder  = "com.loopkit.Loop.bolusProAutoDetectFromFoodFinder"
        static let showManualMacroFields     = "com.loopkit.Loop.bolusProShowManualMacroFields"
        static let coverageFactorPercent     = "com.loopkit.Loop.bolusProCoverageFactorPercent"
        static let fpuDelayMinutes           = "com.loopkit.Loop.bolusProFpuDelayMinutes"
        static let fpuAbsorptionHours        = "com.loopkit.Loop.bolusProFpuAbsorptionHours"
        static let triggerThresholdFPU       = "com.loopkit.Loop.bolusProTriggerThresholdFPU"
        static let onboardingCompleted       = "com.loopkit.Loop.bolusProOnboardingCompleted"
    }
}

// MARK: - FPU Entry Marker

extension BolusPro_FeatureFlags {
    /// Emoji used as `foodType` on the secondary FPU carb entry, so users can
    /// tell the protein/fat tail apart from the primary carb entry in history.
    static let fpuEntryEmoji = "🥩"
}
