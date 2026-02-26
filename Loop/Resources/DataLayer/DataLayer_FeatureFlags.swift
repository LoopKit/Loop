//
//  DataLayer_FeatureFlags.swift
//  Loop
//
//  DataLayer — Master toggle and per-category feature flags.
//
//  Idea by Taylor Patterson. Coded by Claude Code.
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Foundation
import os.log

/// Feature flags for the DataLayer health data sharing platform.
/// All flags default to OFF. Uses UserDefaults.standard with namespaced keys.
struct DataLayer_FeatureFlags {

    static let log = Logger(subsystem: "com.loopkit.Loop.DataLayer", category: "DataLayer")

    // MARK: - Keys

    private enum Keys {
        static let isEnabled = "DataLayer_isEnabled"
        static let researchEnabled = "DataLayer_researchEnabled"
        static let retentionDays = "DataLayer_retentionDays"
    }

    private static let defaults = UserDefaults.standard

    // MARK: - Master Toggle

    /// Master on/off switch for the entire DataLayer feature.
    static var isEnabled: Bool {
        get { defaults.bool(forKey: Keys.isEnabled) }
        set { defaults.set(newValue, forKey: Keys.isEnabled) }
    }

    // MARK: - Research Toggle

    /// Whether the user has opted in to contribute anonymized data to diabetes research.
    /// Separate from category toggles — controls whether enabled categories are uploaded.
    static var researchEnabled: Bool {
        get { defaults.bool(forKey: Keys.researchEnabled) }
        set { defaults.set(newValue, forKey: Keys.researchEnabled) }
    }

    // MARK: - Retention

    /// Number of days to retain events locally before auto-pruning. Default 90.
    static var retentionDays: Int {
        get {
            let value = defaults.integer(forKey: Keys.retentionDays)
            return value > 0 ? value : 90
        }
        set { defaults.set(newValue, forKey: Keys.retentionDays) }
    }
}
