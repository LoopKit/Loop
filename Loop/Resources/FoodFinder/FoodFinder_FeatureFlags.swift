//
//  FoodFinder_FeatureFlags.swift
//  Loop
//
//  FoodFinder — Feature toggle and configuration flags.
//  All FoodFinder enable/disable logic lives here.
//
//  Idea by Taylor Patterson. Coded by Claude Code.
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit

// MARK: - Feature Toggle

/// Central on/off switch for the entire FoodFinder feature.
/// Loop host files check `FoodFinder_FeatureFlags.isEnabled` to gate UI insertion.
enum FoodFinder_FeatureFlags {

    /// Register default values — location tagging defaults ON.
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            Keys.locationTaggingEnabled: true
        ])
    }

    /// Master toggle — persisted in UserDefaults.
    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.foodSearchEnabled) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.foodSearchEnabled) }
    }

    /// Location tagging — captures venue-level GPS when FoodFinder opens.
    /// Defaults to ON via registerDefaults().
    static var locationTaggingEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.locationTaggingEnabled) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.locationTaggingEnabled) }
    }

    /// Carb tracking — daily/weekly/monthly totals with historical comparison.
    static var carbTrackingEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.carbTrackingEnabled) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.carbTrackingEnabled) }
    }

}

// MARK: - UserDefaults Keys

/// All FoodFinder-specific UserDefaults keys live here, not in Loop's UserDefaults+Loop.swift.
/// This keeps the host codebase clean and makes the feature self-contained.
extension FoodFinder_FeatureFlags {
    enum Keys {
        // Feature toggle
        static let foodSearchEnabled                = "com.loopkit.Loop.foodSearchEnabled"

        // Favorite food thumbnails
        static let favoriteFoodImageIDs             = "com.loopkit.Loop.favoriteFoodImageIDs"

        // BYO AI Provider configuration (non-secret settings stored in UserDefaults)
        // API keys are stored securely in Keychain via FoodFinder_SecureStorage.
        static let customAIBaseURL                  = "com.loopkit.Loop.customAIBaseURL"
        static let customAIModel                    = "com.loopkit.Loop.customAIModel"
        static let customAIAPIVersion               = "com.loopkit.Loop.customAIAPIVersion"
        static let customAIOrganization             = "com.loopkit.Loop.customAIOrganization"
        static let customAIEndpointPath             = "com.loopkit.Loop.customAIEndpointPath"

        // Advanced dosing (FoodFinder-related)
        static let advancedDosingRecommendationsEnabled = "com.loopkit.Loop.advancedDosingRecommendationsEnabled"

        // Analysis History
        static let analysisHistory                  = "com.loopkit.Loop.analysisHistory"
        static let analysisHistoryRetentionDays     = "com.loopkit.Loop.analysisHistoryRetentionDays"

        // Location tagging
        static let locationTaggingEnabled            = "com.loopkit.Loop.locationTaggingEnabled"

        // Carb tracking
        static let carbTrackingEnabled               = "com.loopkit.Loop.carbTrackingEnabled"

        // Migration tracking
        static let byoMigrationComplete             = "com.loopkit.Loop.byoMigrationComplete"
    }
}

// MARK: - Convenience Accessors

/// UserDefaults convenience properties for FoodFinder settings.
/// Other FoodFinder files access these instead of raw key strings.
extension UserDefaults {

    // MARK: Feature Toggle

    var foodFinderEnabled: Bool {
        get { bool(forKey: FoodFinder_FeatureFlags.Keys.foodSearchEnabled) }
        set { set(newValue, forKey: FoodFinder_FeatureFlags.Keys.foodSearchEnabled) }
    }

    // MARK: Favorite Food Thumbnails

    var favoriteFoodImageIDs: [String: String] {
        get { dictionary(forKey: FoodFinder_FeatureFlags.Keys.favoriteFoodImageIDs) as? [String: String] ?? [:] }
        set { set(newValue, forKey: FoodFinder_FeatureFlags.Keys.favoriteFoodImageIDs) }
    }

    /// Persist favorite foods with explicit call and lightweight logging.
    func foodFinder_writeFavoriteFoods(_ newValue: [StoredFavoriteFood]) {
        do {
            let data = try JSONEncoder().encode(newValue)
            set(data, forKey: "com.loopkit.Loop.favoriteFoods")
            #if DEBUG
            print("FoodFinder: Saved favorite foods count: \(newValue.count)")
            #endif
        } catch {
            assertionFailure("FoodFinder: Unable to encode stored favorite foods")
        }
    }

    // MARK: BYO AI Provider (non-secret settings)

    var foodFinder_customAIBaseURL: String {
        get { string(forKey: FoodFinder_FeatureFlags.Keys.customAIBaseURL) ?? "" }
        set { set(newValue, forKey: FoodFinder_FeatureFlags.Keys.customAIBaseURL) }
    }

    var foodFinder_customAIModel: String {
        get { string(forKey: FoodFinder_FeatureFlags.Keys.customAIModel) ?? "" }
        set { set(newValue, forKey: FoodFinder_FeatureFlags.Keys.customAIModel) }
    }

    var foodFinder_customAIAPIVersion: String {
        get { string(forKey: FoodFinder_FeatureFlags.Keys.customAIAPIVersion) ?? "" }
        set { set(newValue, forKey: FoodFinder_FeatureFlags.Keys.customAIAPIVersion) }
    }

    var foodFinder_customAIOrganization: String {
        get { string(forKey: FoodFinder_FeatureFlags.Keys.customAIOrganization) ?? "" }
        set { set(newValue, forKey: FoodFinder_FeatureFlags.Keys.customAIOrganization) }
    }

    var foodFinder_customAIEndpointPath: String {
        get { string(forKey: FoodFinder_FeatureFlags.Keys.customAIEndpointPath) ?? "" }
        set { set(newValue, forKey: FoodFinder_FeatureFlags.Keys.customAIEndpointPath) }
    }

    // MARK: API Keys (Keychain-backed via FoodFinder_SecureStorage)

    var foodFinder_aiAPIKey: String {
        get { FoodFinder_SecureStorage.loadAPIKey() ?? "" }
        set {
            if newValue.isEmpty {
                try? FoodFinder_SecureStorage.deleteAPIKey()
            } else {
                try? FoodFinder_SecureStorage.saveAPIKey(newValue)
            }
        }
    }

    var foodFinder_usdaAPIKey: String {
        get { FoodFinder_SecureStorage.loadUSDAKey() ?? "" }
        set {
            if newValue.isEmpty {
                try? FoodFinder_SecureStorage.deleteUSDAKey()
            } else {
                try? FoodFinder_SecureStorage.saveUSDAKey(newValue)
            }
        }
    }

    // MARK: Location Tagging

    var foodFinder_locationTaggingEnabled: Bool {
        get { bool(forKey: FoodFinder_FeatureFlags.Keys.locationTaggingEnabled) }
        set { set(newValue, forKey: FoodFinder_FeatureFlags.Keys.locationTaggingEnabled) }
    }

    // MARK: Carb Tracking

    var foodFinder_carbTrackingEnabled: Bool {
        get { bool(forKey: FoodFinder_FeatureFlags.Keys.carbTrackingEnabled) }
        set { set(newValue, forKey: FoodFinder_FeatureFlags.Keys.carbTrackingEnabled) }
    }

    // MARK: Analysis History

    var analysisHistoryRetentionDays: Int {
        get {
            let v = integer(forKey: FoodFinder_FeatureFlags.Keys.analysisHistoryRetentionDays)
            return v > 0 ? v : 7
        }
        set { set(newValue, forKey: FoodFinder_FeatureFlags.Keys.analysisHistoryRetentionDays) }
    }

    // MARK: Advanced Dosing

    var foodFinder_advancedDosingRecommendationsEnabled: Bool {
        get { bool(forKey: FoodFinder_FeatureFlags.Keys.advancedDosingRecommendationsEnabled) }
        set { set(newValue, forKey: FoodFinder_FeatureFlags.Keys.advancedDosingRecommendationsEnabled) }
    }

    // MARK: Legacy Aliases

    /// Used by USDAFoodDataService and other internal FoodFinder code.
    var usdaAPIKey: String {
        get { foodFinder_usdaAPIKey }
        set { foodFinder_usdaAPIKey = newValue }
    }

    /// Used by AIAnalysis prompt cache and ConfigurableAIService.
    var advancedDosingRecommendationsEnabled: Bool {
        get { foodFinder_advancedDosingRecommendationsEnabled }
        set { foodFinder_advancedDosingRecommendationsEnabled = newValue }
    }
}

// MARK: - BYO Migration

extension FoodFinder_FeatureFlags {

    /// Migrates legacy per-provider API keys from UserDefaults to Keychain + BYO format.
    /// Called once on app launch. Idempotent — skips if already completed.
    static func migrateToByoIfNeeded() {
        let ud = UserDefaults.standard
        guard !ud.bool(forKey: Keys.byoMigrationComplete) else { return }

        // Old per-provider key strings (one-time read during migration)
        let oldClaudeKey    = "com.loopkit.Loop.claudeAPIKey"
        let oldOpenAIKey    = "com.loopkit.Loop.openAIAPIKey"
        let oldGeminiKey    = "com.loopkit.Loop.googleGeminiAPIKey"
        let oldCustomKey    = "com.loopkit.Loop.customAIAPIKey"
        let oldUsdaKey      = "com.loopkit.Loop.usdaAPIKey"

        // Find the first configured provider and migrate its key + set BYO config
        let existingKey: String?

        if let k = ud.string(forKey: oldCustomKey), !k.isEmpty {
            // Already had BYO config — keep it
            existingKey = k
        } else if let k = ud.string(forKey: oldClaudeKey), !k.isEmpty {
            existingKey = k
            ud.set("https://api.anthropic.com/v1", forKey: Keys.customAIBaseURL)
            ud.set("claude-sonnet-4-20250514", forKey: Keys.customAIModel)
        } else if let k = ud.string(forKey: oldOpenAIKey), !k.isEmpty {
            existingKey = k
            ud.set("https://api.openai.com/v1", forKey: Keys.customAIBaseURL)
            ud.set("gpt-4o", forKey: Keys.customAIModel)
        } else if let k = ud.string(forKey: oldGeminiKey), !k.isEmpty {
            existingKey = k
            ud.set("https://generativelanguage.googleapis.com/v1beta", forKey: Keys.customAIBaseURL)
            ud.set("gemini-2.0-flash", forKey: Keys.customAIModel)
        } else {
            existingKey = nil
        }

        // Write AI API key to Keychain
        if let key = existingKey, !key.isEmpty {
            try? FoodFinder_SecureStorage.saveAPIKey(key)
        }

        // Migrate USDA key to Keychain
        if let usdaKey = ud.string(forKey: oldUsdaKey), !usdaKey.isEmpty {
            try? FoodFinder_SecureStorage.saveUSDAKey(usdaKey)
        }

        // Clean up old per-provider UserDefaults keys
        for suffix in [
            "claudeAPIKey", "claudeQuery",
            "openAIAPIKey", "openAIQuery",
            "googleGeminiAPIKey", "googleGeminiQuery",
            "customAIAPIKey",
            "usdaAPIKey",
            "aiProvider", "analysisMode", "useGPT5ForOpenAI",
            "textSearchProvider", "barcodeSearchProvider", "aiImageProvider"
        ] {
            ud.removeObject(forKey: "com.loopkit.Loop.\(suffix)")
        }

        ud.set(true, forKey: Keys.byoMigrationComplete)

        #if DEBUG
        print("FoodFinder: BYO migration complete")
        #endif
    }
}
