//
//  AutoPresets_Models.swift
//  Loop
//
//  AutoPresets — Data models for activity types, settings, log entries, and errors.
//
//  Idea by Taylor Patterson. Coded by Claude Code.
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Foundation

// MARK: - Activity Types

/// Supported activity types for auto-preset activation
public enum AutoPresetsActivityType: String, Codable, CaseIterable, Hashable {
    case walking
    case running

    public var displayName: String {
        switch self {
        case .walking: return "Walking"
        case .running: return "Running"
        }
    }

    public var systemImageName: String {
        switch self {
        case .walking: return "figure.walk"
        case .running: return "figure.run"
        }
    }
}

// MARK: - Activity Log Events

/// Events that can be logged in the activity log
public enum AutoPresetsLogEvent: String, Codable {
    case featureEnabled
    case featureDisabled
    case presetActivated
    case presetDeactivated

    public var iconName: String {
        switch self {
        case .featureEnabled: return "power.circle.fill"
        case .featureDisabled: return "power.circle"
        case .presetActivated: return "play.circle.fill"
        case .presetDeactivated: return "stop.circle.fill"
        }
    }

    public var displayName: String {
        switch self {
        case .featureEnabled: return "Feature Enabled"
        case .featureDisabled: return "Feature Disabled"
        case .presetActivated: return "Preset Activated"
        case .presetDeactivated: return "Preset Deactivated"
        }
    }
}

// MARK: - Activity Log Entry

/// A single entry in the activity log
public struct AutoPresetsLogEntry: Codable, Identifiable, Equatable {
    public let id: UUID
    public let date: Date
    public let event: AutoPresetsLogEvent
    public let activityType: AutoPresetsActivityType?
    public let presetName: String?

    public init(
        id: UUID = UUID(),
        date: Date = Date(),
        event: AutoPresetsLogEvent,
        activityType: AutoPresetsActivityType? = nil,
        presetName: String? = nil
    ) {
        self.id = id
        self.date = date
        self.event = event
        self.activityType = activityType
        self.presetName = presetName
    }
}

// MARK: - Settings Model

/// All settings for the AutoPresets feature
public struct AutoPresetsSettings: Codable, Equatable {
    /// Whether the feature is enabled
    public var isEnabled: Bool

    /// Which activity types are being monitored
    public var supportedActivityTypes: Set<AutoPresetsActivityType>

    /// Mapping of activity type to preset UUID
    public var activityPresets: [String: String]  // [ActivityType.rawValue: PresetUUID.uuidString]

    /// How long after activity stops before deactivating preset (seconds)
    public var stopInterval: TimeInterval

    /// How long sustained activity must continue after step threshold before confirming (seconds)
    public var continuousActivityTime: TimeInterval

    /// Whether to require high confidence motion detection
    public var requireHighConfidence: Bool

    /// Whether debug logging is enabled
    public var debugLoggingEnabled: Bool

    /// Recent activity log entries
    public var recentActivityLog: [AutoPresetsLogEntry]

    public init(
        isEnabled: Bool = false,
        supportedActivityTypes: Set<AutoPresetsActivityType> = [.walking],
        activityPresets: [String: String] = [:],
        stopInterval: TimeInterval = 300,
        continuousActivityTime: TimeInterval = 30,
        requireHighConfidence: Bool = false,
        debugLoggingEnabled: Bool = false,
        recentActivityLog: [AutoPresetsLogEntry] = []
    ) {
        self.isEnabled = isEnabled
        self.supportedActivityTypes = supportedActivityTypes
        self.activityPresets = activityPresets
        self.stopInterval = stopInterval
        self.continuousActivityTime = continuousActivityTime
        self.requireHighConfidence = requireHighConfidence
        self.debugLoggingEnabled = debugLoggingEnabled
        self.recentActivityLog = recentActivityLog
    }

    // MARK: - Backward-Compatible Decoding

    /// Handles decoding from previously saved settings that used old key names
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        isEnabled = (try? container.decode(Bool.self, forKey: .isEnabled)) ?? false
        supportedActivityTypes = (try? container.decode(Set<AutoPresetsActivityType>.self, forKey: .supportedActivityTypes)) ?? [.walking]
        activityPresets = (try? container.decode([String: String].self, forKey: .activityPresets)) ?? [:]
        stopInterval = (try? container.decode(TimeInterval.self, forKey: .stopInterval)) ?? 300
        requireHighConfidence = (try? container.decode(Bool.self, forKey: .requireHighConfidence)) ?? false
        debugLoggingEnabled = (try? container.decode(Bool.self, forKey: .debugLoggingEnabled)) ?? false
        recentActivityLog = (try? container.decode([AutoPresetsLogEntry].self, forKey: .recentActivityLog)) ?? []

        // Try new key first, fall back to legacy key
        if let value = try? container.decode(TimeInterval.self, forKey: .continuousActivityTime) {
            continuousActivityTime = value
        } else if let legacyValue = try? container.decode(TimeInterval.self, forKey: .legacyContinuousActivityWindow) {
            continuousActivityTime = legacyValue
        } else {
            continuousActivityTime = 30
        }
    }

    private enum CodingKeys: String, CodingKey {
        case isEnabled
        case supportedActivityTypes
        case activityPresets
        case stopInterval
        case continuousActivityTime
        case requireHighConfidence
        case debugLoggingEnabled
        case recentActivityLog
        // Legacy keys for backward compatibility
        case legacyContinuousActivityWindow = "continuousActivityWindow"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(supportedActivityTypes, forKey: .supportedActivityTypes)
        try container.encode(activityPresets, forKey: .activityPresets)
        try container.encode(stopInterval, forKey: .stopInterval)
        try container.encode(continuousActivityTime, forKey: .continuousActivityTime)
        try container.encode(requireHighConfidence, forKey: .requireHighConfidence)
        try container.encode(debugLoggingEnabled, forKey: .debugLoggingEnabled)
        try container.encode(recentActivityLog, forKey: .recentActivityLog)
    }

    // MARK: - Helper Methods

    /// Get the preset UUID for an activity type
    public func presetId(for activity: AutoPresetsActivityType) -> UUID? {
        guard let uuidString = activityPresets[activity.rawValue] else { return nil }
        return UUID(uuidString: uuidString)
    }

    /// Set the preset UUID for an activity type
    public mutating func setPresetId(_ presetId: UUID?, for activity: AutoPresetsActivityType) {
        if let presetId = presetId {
            activityPresets[activity.rawValue] = presetId.uuidString
        } else {
            activityPresets.removeValue(forKey: activity.rawValue)
        }
    }

    /// Check if at least one supported activity has a preset configured
    public var hasConfiguredPresets: Bool {
        supportedActivityTypes.contains { activity in
            activityPresets[activity.rawValue] != nil
        }
    }
}

// MARK: - Detection Errors

/// Errors that can occur during activity detection
public enum AutoPresetsDetectionError: Error {
    case motionNotAvailable
    case permissionDenied
    case configurationError(String)

    public var localizedDescription: String {
        switch self {
        case .motionNotAvailable:
            return "Motion detection is not available on this device"
        case .permissionDenied:
            return "Motion & Fitness permissions are required for activity detection"
        case .configurationError(let message):
            return "Configuration error: \(message)"
        }
    }
}
