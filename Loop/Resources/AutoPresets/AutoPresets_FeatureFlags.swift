//
//  AutoPresets_FeatureFlags.swift
//  Loop
//
//  AutoPresets — Feature toggle and configuration flags.
//  All AutoPresets enable/disable logic lives here.
//
//  Idea by Taylor Patterson. Coded by Claude Code.
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Foundation

// MARK: - Feature Toggle

/// Central on/off switch for the entire AutoPresets feature.
/// Loop host files check `AutoPresets_FeatureFlags.isEnabled` to gate UI insertion.
enum AutoPresets_FeatureFlags {
    /// Master toggle — persisted in UserDefaults.
    /// Controls whether AutoPresets appears in Settings.
    /// Defaults to false; legacy migration sets true for existing users.
    static var isEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: Keys.autoPresetsEnabled) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: Keys.autoPresetsEnabled)
        }
        set { UserDefaults.standard.set(newValue, forKey: Keys.autoPresetsEnabled) }
    }
}

// MARK: - UserDefaults Keys

extension AutoPresets_FeatureFlags {
    enum Keys {
        static let autoPresetsEnabled = "com.loopkit.Loop.autoPresetsFeatureEnabled"
    }
}
