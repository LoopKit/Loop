//
//  AutoPresetsCoordinator.swift
//  Loop
//
//  Created for Loop AutoPresets Feature
//

import Combine
import Foundation
import LoopKit
import os.log

// MARK: - AutoPresets Coordinator

/// Main entry point for AutoPresets feature
/// Coordinates activity detection and preset activation with minimal coupling to Loop
public class AutoPresetsCoordinator: ObservableObject {

    // MARK: - Singleton

    public static let shared = AutoPresetsCoordinator()

    // MARK: - Published Properties

    @Published public private(set) var isMonitoring: Bool = false
    @Published public private(set) var currentDetectedActivity: AutoPresetActivityType?
    @Published public private(set) var lastError: AutoPresetDetectionError?

    // MARK: - Private Properties

    private let log = OSLog(subsystem: "com.loopkit.Loop.AutoPresets", category: "Coordinator")
    private let storage = AutoPresetsStorage()
    private let activityDetectionManager = ActivityDetectionManager()

    // Debounce/guard properties to prevent rapid restarts
    private var isUpdatingSettings = false
    private var pendingRestart: DispatchWorkItem?

    public weak var delegate: AutoPresetsDelegate? {
        didSet {
            // Start monitoring when delegate is set (if not already running)
            if delegate != nil && !isMonitoring {
                startIfConfigured()
            }
        }
    }

    // Track which preset we activated so we can deactivate the same one
    private var activatedPresetId: UUID?

    // MARK: - Public Settings Access

    /// Current settings (read-only access)
    public var settings: AutoPresetsSettings {
        storage.settings
    }

    /// Whether the feature is enabled
    public var isEnabled: Bool {
        get { storage.settings.isEnabled }
        set {
            // Skip if no change
            guard newValue != storage.settings.isEnabled else { return }

            objectWillChange.send()
            storage.updateSettings { $0.isEnabled = newValue }
            if newValue {
                startIfConfigured()
            } else {
                stop()
            }
            logEvent(newValue ? .featureEnabled : .featureDisabled)
        }
    }

    // MARK: - Initialization

    private init() {
        activityDetectionManager.delegate = self

        // Perform migration from legacy settings if needed
        storage.migrateFromLegacyIfNeeded()

        // Note: Monitoring starts when delegate is set (see delegate didSet)
        os_log("AutoPresetsCoordinator initialized", log: log, type: .debug)
    }

    // MARK: - Public Methods

    /// Update settings with a closure
    public func updateSettings(_ update: (inout AutoPresetsSettings) -> Void) {
        // Guard against re-entrancy
        guard !isUpdatingSettings else { return }
        isUpdatingSettings = true
        defer { isUpdatingSettings = false }

        objectWillChange.send()
        storage.updateSettings(update)
        applySettingsToDetectionManager()

        // Debounce restart to prevent rapid cycling
        pendingRestart?.cancel()
        if isMonitoring {
            let workItem = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                self.stop()
                self.startIfConfigured()
            }
            pendingRestart = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
        }
    }

    /// Get the preset for an activity type
    public func preset(for activity: AutoPresetActivityType) -> TemporaryScheduleOverridePreset? {
        guard let presetId = settings.presetId(for: activity),
              let delegate = delegate
        else {
            return nil
        }

        return delegate.autoPresetsAvailablePresets(self).first { $0.id == presetId }
    }

    /// Set the preset for an activity type
    public func setPreset(_ preset: TemporaryScheduleOverridePreset?, for activity: AutoPresetActivityType) {
        objectWillChange.send()
        storage.updateSettings { settings in
            settings.setPresetId(preset?.id, for: activity)
        }
    }

    /// Get all available presets from Loop
    public func availablePresets() -> [TemporaryScheduleOverridePreset] {
        delegate?.autoPresetsAvailablePresets(self) ?? []
    }

    /// Get the current override from Loop
    public func currentOverride() -> TemporaryScheduleOverride? {
        delegate?.autoPresetsCurrentOverride(self)
    }

    /// Start monitoring (if configured properly)
    public func startIfConfigured() {
        // Prevent starting if already monitoring
        guard !isMonitoring else {
            os_log("AutoPresets already monitoring, skipping start", log: log, type: .debug)
            return
        }

        guard delegate != nil else {
            os_log("AutoPresets delegate not set, not starting", log: log, type: .debug)
            return
        }

        guard settings.isEnabled else {
            os_log("AutoPresets not enabled, not starting", log: log, type: .debug)
            return
        }

        guard settings.hasConfiguredPresets else {
            os_log("AutoPresets has no configured presets, not starting", log: log, type: .debug)
            return
        }

        applySettingsToDetectionManager()
        activityDetectionManager.startMonitoring()
        isMonitoring = true

        os_log(
            "AutoPresets monitoring started - activities: %{public}@, continuous activity time: %.0fs, stop: %.0fs",
            log: log,
            type: .info,
            settings.supportedActivityTypes.map(\.displayName).joined(separator: ", "),
            settings.continuousActivityTime,
            settings.stopInterval
        )
    }

    /// Stop monitoring
    public func stop() {
        activityDetectionManager.stopMonitoring()
        isMonitoring = false
        currentDetectedActivity = nil

        os_log("AutoPresets monitoring stopped", log: log, type: .info)
    }

    /// Clear the last error
    public func clearError() {
        lastError = nil
    }

    /// Clear all activity log entries
    public func clearActivityLog() {
        objectWillChange.send()
        storage.clearActivityLog()
    }

    // MARK: - Private Methods

    private func applySettingsToDetectionManager() {
        let currentSettings = settings

        activityDetectionManager.supportedActivities = currentSettings.supportedActivityTypes
        activityDetectionManager.activityStopInterval = currentSettings.stopInterval
        activityDetectionManager.continuousActivityTime = currentSettings.continuousActivityTime
        activityDetectionManager.requireHighConfidence = currentSettings.requireHighConfidence
    }

    private func logEvent(_ event: AutoPresetLogEvent, activity: AutoPresetActivityType? = nil, presetName: String? = nil) {
        storage.addLogEntry(event: event, activityType: activity, presetName: presetName)
    }

    private func activatePreset(for activity: AutoPresetActivityType) {
        guard let preset = preset(for: activity) else {
            os_log(
                "No preset configured for %{public}@",
                log: log,
                type: .error,
                activity.displayName
            )
            return
        }

        // Check if there's already an active override that wasn't started by us
        if let currentOverride = currentOverride(), activatedPresetId == nil {
            os_log(
                "Override already active (not from AutoPresets), skipping activation",
                log: log,
                type: .info
            )
            return
        }

        activatedPresetId = preset.id
        delegate?.autoPresets(self, shouldActivatePreset: preset)
        logEvent(.presetActivated, activity: activity, presetName: preset.name)

        os_log(
            "Activated preset '%{public}@' for %{public}@",
            log: log,
            type: .info,
            preset.name,
            activity.displayName
        )
    }

    private func deactivatePreset(for activity: AutoPresetActivityType) {
        guard let presetId = activatedPresetId,
              let preset = availablePresets().first(where: { $0.id == presetId })
        else {
            os_log(
                "No AutoPresets-activated preset to deactivate",
                log: log,
                type: .debug
            )
            activatedPresetId = nil
            return
        }

        activatedPresetId = nil
        delegate?.autoPresets(self, shouldDeactivatePreset: preset)
        logEvent(.presetDeactivated, activity: activity, presetName: preset.name)

        os_log(
            "Deactivated preset '%{public}@' for %{public}@",
            log: log,
            type: .info,
            preset.name,
            activity.displayName
        )
    }
}

// MARK: - ActivityDetectionDelegate

extension AutoPresetsCoordinator: ActivityDetectionDelegate {

    func activityDetectionDidConfirm(_ activity: AutoPresetActivityType) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            self.currentDetectedActivity = activity
            self.activatePreset(for: activity)
        }
    }

    func activityDetectionDidStop(_ activity: AutoPresetActivityType) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            self.currentDetectedActivity = nil
            self.deactivatePreset(for: activity)
        }
    }

    func activityDetectionDidEncounterError(_ error: AutoPresetDetectionError) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            self.lastError = error
            os_log(
                "Activity detection error: %{public}@",
                log: self.log,
                type: .error,
                error.localizedDescription
            )

            // Note: We intentionally do NOT disable the feature on errors
            // The user's preference should be preserved
        }
    }
}
