//
//  AutoPresets_Storage.swift
//  Loop
//
//  AutoPresets — Isolated persistence using its own UserDefaults suite.
//
//  Idea by Taylor Patterson. Coded by Claude Code.
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Foundation
import os.log

/// Isolated persistence for AutoPresets using its own UserDefaults suite
public class AutoPresets_Storage {

    private let log = OSLog(subsystem: "com.loopkit.Loop.AutoPresets", category: "Storage")

    // MARK: - Constants

    /// Separate UserDefaults suite - not Loop's main UserDefaults
    private static let suiteName = "com.loopkit.Loop.AutoPresets"
    private static let settingsKey = "settings"
    private static let migrationKey = "didMigrateFromLegacy"

    // MARK: - Properties

    private let defaults: UserDefaults

    // MARK: - Initialization

    public init() {
        self.defaults = UserDefaults(suiteName: Self.suiteName) ?? .standard
    }

    // MARK: - Settings Access

    /// Current settings (reads from UserDefaults)
    public var settings: AutoPresetsSettings {
        get {
            guard let data = defaults.data(forKey: Self.settingsKey),
                  let settings = try? JSONDecoder().decode(AutoPresetsSettings.self, from: data)
            else {
                return AutoPresetsSettings()
            }
            return settings
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Self.settingsKey)
            }
        }
    }

    /// Update settings with a closure
    public func updateSettings(_ update: (inout AutoPresetsSettings) -> Void) {
        var current = settings
        update(&current)
        settings = current
    }

    // MARK: - Activity Log

    /// Add a log entry to the activity log
    public func addLogEntry(_ entry: AutoPresetsLogEntry) {
        updateSettings { settings in
            settings.recentActivityLog.insert(entry, at: 0)
            if settings.recentActivityLog.count > 20 {
                settings.recentActivityLog = Array(settings.recentActivityLog.prefix(20))
            }
        }
    }

    /// Clear all activity log entries
    public func clearActivityLog() {
        updateSettings { settings in
            settings.recentActivityLog = []
        }
    }

    /// Add a log entry with parameters
    public func addLogEntry(
        event: AutoPresetsLogEvent,
        activityType: AutoPresetsActivityType? = nil,
        presetName: String? = nil
    ) {
        let entry = AutoPresetsLogEntry(
            date: Date(),
            event: event,
            activityType: activityType,
            presetName: presetName
        )
        addLogEntry(entry)
    }

    // MARK: - Migration

    /// Whether migration from legacy UserDefaults has been performed
    public var didMigrateFromLegacy: Bool {
        get { defaults.bool(forKey: Self.migrationKey) }
        set { defaults.set(newValue, forKey: Self.migrationKey) }
    }

    /// Migrate settings from legacy Loop UserDefaults to new isolated suite
    public func migrateFromLegacyIfNeeded() {
        guard !didMigrateFromLegacy else { return }

        let legacyDefaults = UserDefaults.standard

        // Read legacy values
        let isEnabled = legacyDefaults.bool(forKey: "com.loopkit.Loop.walkingAutoPresetEnabled")
        let confirmationInterval = legacyDefaults.double(forKey: "com.loopkit.Loop.walkingConfirmationInterval")
        let stopInterval = legacyDefaults.double(forKey: "com.loopkit.Loop.walkingStopInterval")
        let continuousWindow = legacyDefaults.double(forKey: "com.loopkit.Loop.autoPresetContinuousActivityWindow")
        let requireHighConfidence = legacyDefaults.bool(forKey: "com.loopkit.Loop.autoPresetRequireHighConfidence")
        let supportedTypesRaw = legacyDefaults.stringArray(forKey: "com.loopkit.Loop.supportedActivityTypes") ?? ["walking"]
        let activityPresetsMap = legacyDefaults.dictionary(forKey: "com.loopkit.Loop.activityPresets") as? [String: String] ?? [:]

        // Migrate activity log
        var migratedLog: [AutoPresetsLogEntry] = []
        if let logData = legacyDefaults.data(forKey: "com.loopkit.Loop.recentWalkingActivityLog") {
            if let legacyEntries = try? JSONDecoder().decode([LegacyLogEntry].self, from: logData) {
                migratedLog = legacyEntries.compactMap { legacy in
                    guard let event = convertLegacyEvent(legacy.event) else { return nil }
                    return AutoPresetsLogEntry(
                        id: UUID(),
                        date: legacy.date,
                        event: event,
                        activityType: legacy.activityType.flatMap { AutoPresetsActivityType(rawValue: $0) },
                        presetName: legacy.presetName
                    )
                }
            }
        }

        // Convert supported types
        let supportedTypes = Set(supportedTypesRaw.compactMap { AutoPresetsActivityType(rawValue: $0) })

        // Create new settings
        var newSettings = AutoPresetsSettings()
        newSettings.isEnabled = isEnabled
        newSettings.supportedActivityTypes = supportedTypes.isEmpty ? [.walking] : supportedTypes
        newSettings.activityPresets = activityPresetsMap
        newSettings.stopInterval = stopInterval > 0 ? stopInterval : 300
        newSettings.continuousActivityTime = continuousWindow > 0 ? continuousWindow : 30
        newSettings.requireHighConfidence = requireHighConfidence
        newSettings.recentActivityLog = migratedLog

        // Save to new suite
        settings = newSettings
        didMigrateFromLegacy = true

        // If user had AutoPresets enabled previously, enable the feature flag
        if isEnabled {
            AutoPresets_FeatureFlags.isEnabled = true
        }

        os_log(
            "Migrated AutoPresets settings - enabled: %{public}@, activities: %{public}@, presets: %{public}@, continuous activity time: %.0fs, stop: %.0fs",
            log: log,
            type: .info,
            isEnabled ? "YES" : "NO",
            supportedTypes.map(\.displayName).joined(separator: ", "),
            activityPresetsMap.keys.joined(separator: ", "),
            newSettings.continuousActivityTime,
            newSettings.stopInterval
        )
    }

    // MARK: - Reset

    /// Reset all AutoPresets data
    public func reset() {
        if let bundleId = Bundle.main.bundleIdentifier {
            defaults.removePersistentDomain(forName: Self.suiteName)
        }
    }

    // MARK: - Legacy Migration Helpers

    /// Legacy log entry format for migration
    private struct LegacyLogEntry: Codable {
        let date: Date
        let event: String
        let activityType: String?
        let presetName: String?
    }

    /// Convert legacy event string to new enum
    private func convertLegacyEvent(_ legacyEvent: String) -> AutoPresetsLogEvent? {
        switch legacyEvent {
        case "featureEnabled": return .featureEnabled
        case "featureDisabled": return .featureDisabled
        case "presetActivated": return .presetActivated
        case "presetDeactivated": return .presetDeactivated
        default: return nil
        }
    }
}
