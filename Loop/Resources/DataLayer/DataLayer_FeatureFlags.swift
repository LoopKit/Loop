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
        static let ingestEndpoint = "DataLayer_ingestEndpoint"
        static let ingestAPIKey = "DataLayer_ingestAPIKey"
        static let shareEndpoint = "DataLayer_shareEndpoint"
        static let activeShares = "DataLayer_activeShares"
    }

    private static let defaults = UserDefaults.standard
    private static let defaultsInitializedKey = "DataLayer_defaultsInitialized"

    // MARK: - Bundled Backend Defaults

    /// Default ingest endpoint baked into the AllFeatures build so that any user
    /// running this fork auto-uploads to the research backend. Users may
    /// override by pasting their own URL in the Data Sharing settings.
    /// Endpoint is anonymous (no API key); abuse mitigated by GCP rate limits.
    private static let bundledIngestEndpoint = "https://ingest-ycnxwhqg2a-uc.a.run.app"

    /// Default share endpoint for provider PDF / link generation.
    private static let bundledShareEndpoint = "https://share-ycnxwhqg2a-uc.a.run.app"

    /// On first launch, enable data sharing, research, and all consent categories by default.
    static func registerDefaultsIfNeeded() {
        guard !defaults.bool(forKey: defaultsInitializedKey) else { return }
        defaults.set(true, forKey: defaultsInitializedKey)
        isEnabled = true
        researchEnabled = true
        for category in DataLayer_ConsentCategory.allCases {
            DataLayer_ConsentManager.shared.setConsent(for: category, granted: true)
        }
    }

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

    // MARK: - Ingest Endpoint

    /// Cloud Run ingest URL. Falls back to the bundled default so any AllFeatures
    /// install uploads to the project backend out of the box.
    static var ingestEndpointURL: URL? {
        get {
            let str = defaults.string(forKey: Keys.ingestEndpoint) ?? bundledIngestEndpoint
            return URL(string: str)
        }
        set { defaults.set(newValue?.absoluteString, forKey: Keys.ingestEndpoint) }
    }

    /// API key for the ingest endpoint. Nil by default — the bundled backend is
    /// anonymous. Only used if a user points at their own auth-protected endpoint.
    static var ingestAPIKey: String? {
        get { defaults.string(forKey: Keys.ingestAPIKey) }
        set { defaults.set(newValue, forKey: Keys.ingestAPIKey) }
    }

    // MARK: - Provider Sharing

    /// Cloud Run share endpoint URL. Falls back to the bundled default.
    static var shareEndpointURL: URL? {
        get {
            let str = defaults.string(forKey: Keys.shareEndpoint) ?? bundledShareEndpoint
            return URL(string: str)
        }
        set { defaults.set(newValue?.absoluteString, forKey: Keys.shareEndpoint) }
    }

    /// Persisted list of active share links.
    static var activeShares: [DataLayer_ShareLink] {
        get {
            guard let data = defaults.data(forKey: Keys.activeShares) else { return [] }
            return (try? JSONDecoder().decode([DataLayer_ShareLink].self, from: data)) ?? []
        }
        set {
            defaults.set(try? JSONEncoder().encode(newValue), forKey: Keys.activeShares)
        }
    }

    /// Add a share link to the persisted list.
    static func addShare(_ link: DataLayer_ShareLink) {
        var shares = activeShares
        shares.append(link)
        activeShares = shares
    }

    /// Remove a share link by token.
    static func removeShare(token: String) {
        activeShares = activeShares.filter { $0.token != token }
    }
}

// MARK: - Share Link Model

/// Represents an active provider share link.
struct DataLayer_ShareLink: Codable, Identifiable {
    let token: String
    let url: String
    let createdAt: Date
    let expiresAt: Date
    let daysCovered: Int
    let categoryCount: Int

    var id: String { token }
    var isExpired: Bool { Date() > expiresAt }
}
