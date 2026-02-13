//
//  LoopInsights_FeatureFlags.swift
//  Loop
//
//  Concept & design by Taylor Patterson. Coded & tested by Claude Code in February 2026.
//  Copyright (c) 2025-2026 LoopKit Authors. All rights reserved.
//

import Foundation

/// Runtime feature flags for LoopInsights. All flags are UserDefaults-backed
/// so they can be toggled without recompilation.
struct LoopInsights_FeatureFlags {

    private enum Keys {
        static let isEnabled = "LoopInsights_isEnabled"
        static let developerModeEnabled = "LoopInsights_developerModeEnabled"
        static let applyMode = "LoopInsights_applyMode"
        static let analysisPeriod = "LoopInsights_analysisPeriod"
        static let aiConfiguration = "LoopInsights_aiConfiguration"
        static let developerUnlockCount = "LoopInsights_developerUnlockCount"
        static let useTestData = "LoopInsights_useTestData"
        static let aiPersonality = "LoopInsights_aiPersonality"
        static let backgroundMonitorEnabled = "LoopInsights_backgroundMonitorEnabled"
        static let monitorFrequency = "LoopInsights_monitorFrequency"
        static let monitorMinConfidence = "LoopInsights_monitorMinConfidence"
        static let quietHoursEnabled = "LoopInsights_quietHoursEnabled"
        static let quietHoursStart = "LoopInsights_quietHoursStart"
        static let quietHoursEnd = "LoopInsights_quietHoursEnd"
        static let notificationStyle = "LoopInsights_notificationStyle"
        static let biometricsEnabled = "LoopInsights_biometricsEnabled"
        static let circadianEnabled = "LoopInsights_circadianEnabled"
        static let foodResponseEnabled = "LoopInsights_foodResponseEnabled"
        static let caffeineTrackingEnabled = "LoopInsights_caffeineTrackingEnabled"
        static let nightscoutImportEnabled = "LoopInsights_nightscoutImportEnabled"
        static let agpChartEnabled = "LoopInsights_agpChartEnabled"
    }

    private static let defaults = UserDefaults.standard

    // MARK: - Primary Feature Toggle

    /// Master on/off switch for LoopInsights. Defaults to false.
    static var isEnabled: Bool {
        get { defaults.bool(forKey: Keys.isEnabled) }
        set { defaults.set(newValue, forKey: Keys.isEnabled) }
    }

    // MARK: - Developer Mode (Hidden)

    /// Developer-only mode that unlocks auto-apply and advanced testing options.
    /// Activated by long-pressing the LoopInsights header 5 times.
    /// Not visible in the public settings UI.
    static var developerModeEnabled: Bool {
        get { defaults.bool(forKey: Keys.developerModeEnabled) }
        set { defaults.set(newValue, forKey: Keys.developerModeEnabled) }
    }

    /// Tracks long-press count toward developer mode activation
    static var developerUnlockCount: Int {
        get { defaults.integer(forKey: Keys.developerUnlockCount) }
        set { defaults.set(newValue, forKey: Keys.developerUnlockCount) }
    }

    /// Number of long-presses required to unlock developer mode
    static let developerUnlockThreshold = 3

    /// Use test data fixtures instead of real Loop data stores (developer mode only).
    /// When enabled, LoopInsights loads JSON fixtures from Documents/LoopInsights/ or the app bundle.
    static var useTestData: Bool {
        get { developerModeEnabled && defaults.bool(forKey: Keys.useTestData) }
        set { defaults.set(newValue, forKey: Keys.useTestData) }
    }

    // MARK: - Apply Mode

    /// How suggestions are applied. Defaults to manual.
    static var applyMode: LoopInsightsApplyMode {
        get {
            guard let raw = defaults.string(forKey: Keys.applyMode),
                  let mode = LoopInsightsApplyMode(rawValue: raw) else {
                return .manual
            }
            // Auto-apply only available in developer mode
            if mode == .autoApply && !developerModeEnabled {
                return .manual
            }
            return mode
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.applyMode)
        }
    }

    // MARK: - Analysis Period

    /// Default analysis lookback period. Defaults to 14 days.
    static var analysisPeriod: LoopInsightsAnalysisPeriod {
        get {
            let raw = defaults.integer(forKey: Keys.analysisPeriod)
            return LoopInsightsAnalysisPeriod(rawValue: raw) ?? .fourteenDays
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.analysisPeriod)
        }
    }

    // MARK: - AI Personality

    /// Personality style for AI responses. Defaults to supportive coach.
    static var aiPersonality: LoopInsightsAIPersonality {
        get {
            guard let raw = defaults.string(forKey: Keys.aiPersonality),
                  let personality = LoopInsightsAIPersonality(rawValue: raw) else {
                return .supportiveCoach
            }
            return personality
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.aiPersonality)
        }
    }

    // MARK: - Background Monitor

    /// Master toggle for background monitoring. Defaults to false.
    static var backgroundMonitorEnabled: Bool {
        get { defaults.bool(forKey: Keys.backgroundMonitorEnabled) }
        set { defaults.set(newValue, forKey: Keys.backgroundMonitorEnabled) }
    }

    /// How frequently background analysis runs. Defaults to daily.
    static var monitorFrequency: LoopInsightsMonitorFrequency {
        get {
            guard let raw = defaults.string(forKey: Keys.monitorFrequency),
                  let freq = LoopInsightsMonitorFrequency(rawValue: raw) else {
                return .daily
            }
            return freq
        }
        set { defaults.set(newValue.rawValue, forKey: Keys.monitorFrequency) }
    }

    /// Minimum confidence level for background notifications. Defaults to medium.
    static var monitorMinConfidence: LoopInsightsConfidence {
        get {
            guard let raw = defaults.string(forKey: Keys.monitorMinConfidence),
                  let conf = LoopInsightsConfidence(rawValue: raw) else {
                return .medium
            }
            return conf
        }
        set { defaults.set(newValue.rawValue, forKey: Keys.monitorMinConfidence) }
    }

    /// Whether quiet hours are enabled. Defaults to false.
    static var quietHoursEnabled: Bool {
        get { defaults.bool(forKey: Keys.quietHoursEnabled) }
        set { defaults.set(newValue, forKey: Keys.quietHoursEnabled) }
    }

    /// Quiet hours start (hour 0-23). Defaults to 22 (10 PM).
    static var quietHoursStart: Int {
        get {
            let val = defaults.integer(forKey: Keys.quietHoursStart)
            return val == 0 && !defaults.bool(forKey: Keys.quietHoursEnabled + "_startSet") ? 22 : val
        }
        set {
            defaults.set(newValue, forKey: Keys.quietHoursStart)
            defaults.set(true, forKey: Keys.quietHoursEnabled + "_startSet")
        }
    }

    /// Quiet hours end (hour 0-23). Defaults to 7 (7 AM).
    static var quietHoursEnd: Int {
        get {
            let val = defaults.integer(forKey: Keys.quietHoursEnd)
            return val == 0 && !defaults.bool(forKey: Keys.quietHoursEnabled + "_endSet") ? 7 : val
        }
        set {
            defaults.set(newValue, forKey: Keys.quietHoursEnd)
            defaults.set(true, forKey: Keys.quietHoursEnabled + "_endSet")
        }
    }

    /// Notification delivery style. Defaults to push.
    static var notificationStyle: LoopInsightsNotificationStyle {
        get {
            guard let raw = defaults.string(forKey: Keys.notificationStyle),
                  let style = LoopInsightsNotificationStyle(rawValue: raw) else {
                return .push
            }
            return style
        }
        set { defaults.set(newValue.rawValue, forKey: Keys.notificationStyle) }
    }

    // MARK: - Biometrics

    /// Whether HealthKit biometric data (HR, HRV, steps, sleep, energy, weight)
    /// is included in AI analysis. Defaults to false.
    static var biometricsEnabled: Bool {
        get { defaults.bool(forKey: Keys.biometricsEnabled) }
        set { defaults.set(newValue, forKey: Keys.biometricsEnabled) }
    }

    // MARK: - Phase 5 Feature Flags

    /// Enables circadian analysis, dawn phenomenon detection, negative basal awareness,
    /// and HRV-based stress scoring. All advanced analyzers gated by one flag.
    static var circadianEnabled: Bool {
        get { defaults.bool(forKey: Keys.circadianEnabled) }
        set { defaults.set(newValue, forKey: Keys.circadianEnabled) }
    }

    /// Enables food-type response pattern analysis and the Meal Insights view.
    static var foodResponseEnabled: Bool {
        get { defaults.bool(forKey: Keys.foodResponseEnabled) }
        set { defaults.set(newValue, forKey: Keys.foodResponseEnabled) }
    }

    /// Enables caffeine intake tracking and the Caffeine Log view.
    static var caffeineTrackingEnabled: Bool {
        get { defaults.bool(forKey: Keys.caffeineTrackingEnabled) }
        set { defaults.set(newValue, forKey: Keys.caffeineTrackingEnabled) }
    }

    /// Enables Nightscout data import as an alternative/supplemental data source.
    static var nightscoutImportEnabled: Bool {
        get { defaults.bool(forKey: Keys.nightscoutImportEnabled) }
        set { defaults.set(newValue, forKey: Keys.nightscoutImportEnabled) }
    }

    /// Enables the Ambulatory Glucose Profile chart on the dashboard.
    static var agpChartEnabled: Bool {
        get { defaults.bool(forKey: Keys.agpChartEnabled) }
        set { defaults.set(newValue, forKey: Keys.agpChartEnabled) }
    }

    // MARK: - AI Configuration

    /// User-configurable AI provider configuration. Persisted to UserDefaults (excluding API key).
    static var aiConfiguration: LoopInsightsAIProviderConfiguration {
        get {
            guard let data = defaults.data(forKey: Keys.aiConfiguration),
                  var config = try? JSONDecoder().decode(LoopInsightsAIProviderConfiguration.self, from: data) else {
                return LoopInsightsAIProviderConfiguration()
            }
            // Always enforce temperature=0 for deterministic analysis
            config.temperature = 0.0
            return config
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Keys.aiConfiguration)
            }
        }
    }
}
