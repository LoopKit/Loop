//
//  AutoPresets_GeofenceManager.swift
//  Loop
//
//  AutoPresets — Geofence location monitoring for automatic preset activation.
//
//  Idea by Taylor Patterson. Coded by Claude Code.
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Combine
import CoreLocation
import Foundation
import os.log

// MARK: - Geofence Location Model

/// A saved location that triggers a preset when entered or exited.
public struct AutoPresetsGeofenceLocation: Codable, Identifiable, Equatable {
    public let id: UUID
    public var name: String
    public var latitude: Double
    public var longitude: Double
    public var radius: Double // meters
    public var triggerType: AutoPresetsGeofenceTrigger
    public var presetId: String // UUID string of the TemporaryScheduleOverridePreset
    public var deactivateOnExit: Bool
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        latitude: Double,
        longitude: Double,
        radius: Double = 100,
        triggerType: AutoPresetsGeofenceTrigger = .onEntry,
        presetId: String = "",
        deactivateOnExit: Bool = true,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.radius = radius
        self.triggerType = triggerType
        self.presetId = presetId
        self.deactivateOnExit = deactivateOnExit
        self.isEnabled = isEnabled
    }

    public var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

// MARK: - Trigger Type

public enum AutoPresetsGeofenceTrigger: String, Codable, CaseIterable, Identifiable {
    case onEntry = "entry"
    case onExit = "exit"
    case both = "both"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .onEntry: return "On Arrival"
        case .onExit: return "On Departure"
        case .both: return "Both"
        }
    }

    public var iconName: String {
        switch self {
        case .onEntry: return "arrow.down.to.line"
        case .onExit: return "arrow.up.from.line"
        case .both: return "arrow.up.arrow.down"
        }
    }
}

// MARK: - Geofence Manager

/// Manages CLLocationManager region monitoring for AutoPresets geofences.
public final class AutoPresets_GeofenceManager: NSObject, ObservableObject, CLLocationManagerDelegate {

    // MARK: - Singleton

    public static let shared = AutoPresets_GeofenceManager()

    // MARK: - Published State

    @Published public private(set) var isMonitoring = false
    @Published public private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published public private(set) var lastTriggeredLocation: String?
    @Published public var locations: [AutoPresetsGeofenceLocation] = []

    // MARK: - Private Properties

    private let log = OSLog(subsystem: "com.loopkit.Loop.AutoPresets", category: "Geofence")
    private let locationManager = CLLocationManager()
    private static let storageKey = "AutoPresets_GeofenceLocations"
    private static let enabledKey = "AutoPresets_GeofenceEnabled"
    private let defaults = UserDefaults(suiteName: "com.loopkit.Loop.AutoPresets") ?? .standard

    /// Tracks which preset was activated by a geofence so we can deactivate it.
    private var activatedByGeofence: [String: UUID] = [:] // [region identifier: preset UUID]

    // MARK: - Initialization

    private override init() {
        super.init()
        locationManager.delegate = self
        locationManager.allowsBackgroundLocationUpdates = true
        authorizationStatus = locationManager.authorizationStatus
        loadLocations()
    }

    // MARK: - Feature Toggle

    public var isEnabled: Bool {
        get { defaults.bool(forKey: Self.enabledKey) }
        set {
            defaults.set(newValue, forKey: Self.enabledKey)
            objectWillChange.send()
            if newValue {
                startMonitoring()
            } else {
                stopMonitoring()
            }
        }
    }

    // MARK: - Authorization

    public func requestAuthorization() {
        locationManager.requestAlwaysAuthorization()
    }

    public var hasAlwaysAuthorization: Bool {
        authorizationStatus == .authorizedAlways
    }

    public var hasAnyAuthorization: Bool {
        authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse
    }

    // MARK: - Location Management

    /// Add a new geofence location.
    public func addLocation(_ location: AutoPresetsGeofenceLocation) {
        objectWillChange.send()
        locations.append(location)
        saveLocations()
        if isEnabled && location.isEnabled {
            registerRegion(for: location)
        }
        logEvent(.featureEnabled, presetName: "Added location: \(location.name)")
    }

    /// Update an existing location.
    public func updateLocation(_ location: AutoPresetsGeofenceLocation) {
        objectWillChange.send()
        guard let index = locations.firstIndex(where: { $0.id == location.id }) else { return }

        // Unregister old region
        unregisterRegion(for: locations[index])

        locations[index] = location
        saveLocations()

        // Re-register if enabled
        if isEnabled && location.isEnabled {
            registerRegion(for: location)
        }
    }

    /// Remove a location.
    public func removeLocation(_ location: AutoPresetsGeofenceLocation) {
        objectWillChange.send()
        unregisterRegion(for: location)
        locations.removeAll { $0.id == location.id }
        saveLocations()
    }

    /// Remove locations at offsets (for SwiftUI List delete).
    public func removeLocations(at offsets: IndexSet) {
        let toRemove = offsets.map { locations[$0] }
        for location in toRemove {
            unregisterRegion(for: location)
        }
        objectWillChange.send()
        locations.remove(atOffsets: offsets)
        saveLocations()
    }

    /// Get current device location (one-shot).
    public func requestCurrentLocation() {
        locationManager.requestLocation()
    }

    // MARK: - Monitoring

    public func startMonitoring() {
        guard hasAlwaysAuthorization else {
            os_log("Cannot start geofence monitoring — need Always authorization", log: log, type: .error)
            return
        }

        // Register all enabled locations
        for location in locations where location.isEnabled {
            registerRegion(for: location)
        }
        isMonitoring = true
        os_log("Geofence monitoring started with %d locations", log: log, type: .info, locations.filter(\.isEnabled).count)
    }

    public func stopMonitoring() {
        // Remove all monitored regions that belong to us
        for region in locationManager.monitoredRegions {
            if region.identifier.hasPrefix("AutoPresets_") {
                locationManager.stopMonitoring(for: region)
            }
        }
        isMonitoring = false
        os_log("Geofence monitoring stopped", log: log, type: .info)
    }

    // MARK: - Region Registration

    private func registerRegion(for location: AutoPresetsGeofenceLocation) {
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else {
            os_log("Region monitoring not available on this device", log: log, type: .error)
            return
        }

        let region = CLCircularRegion(
            center: location.coordinate,
            radius: min(location.radius, locationManager.maximumRegionMonitoringDistance),
            identifier: "AutoPresets_\(location.id.uuidString)"
        )

        switch location.triggerType {
        case .onEntry:
            region.notifyOnEntry = true
            region.notifyOnExit = location.deactivateOnExit
        case .onExit:
            region.notifyOnEntry = false
            region.notifyOnExit = true
        case .both:
            region.notifyOnEntry = true
            region.notifyOnExit = true
        }

        locationManager.startMonitoring(for: region)
        os_log("Registered geofence: %{public}@ (radius: %.0fm)", log: log, type: .debug, location.name, location.radius)
    }

    private func unregisterRegion(for location: AutoPresetsGeofenceLocation) {
        let identifier = "AutoPresets_\(location.id.uuidString)"
        if let region = locationManager.monitoredRegions.first(where: { $0.identifier == identifier }) {
            locationManager.stopMonitoring(for: region)
            os_log("Unregistered geofence: %{public}@", log: log, type: .debug, location.name)
        }
    }

    // MARK: - CLLocationManagerDelegate

    public func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard let location = locationForRegion(region) else { return }
        os_log("Entered geofence: %{public}@", log: log, type: .info, location.name)

        if location.triggerType == .onEntry || location.triggerType == .both {
            activatePreset(for: location)
        }
    }

    public func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard let location = locationForRegion(region) else { return }
        os_log("Exited geofence: %{public}@", log: log, type: .info, location.name)

        if location.triggerType == .onExit || location.triggerType == .both {
            activatePreset(for: location)
        }

        // Deactivate on exit if configured (for entry-triggered presets)
        if location.triggerType == .onEntry && location.deactivateOnExit {
            deactivatePreset(for: location)
        }
    }

    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async { [weak self] in
            self?.authorizationStatus = manager.authorizationStatus
            // Auto-start if we just got Always authorization and feature is enabled
            if manager.authorizationStatus == .authorizedAlways, self?.isEnabled == true {
                self?.startMonitoring()
            }
        }
    }

    public func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        os_log("Geofence monitoring failed for region %{public}@: %{public}@",
               log: log, type: .error,
               region?.identifier ?? "unknown", error.localizedDescription)
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        os_log("Location manager error: %{public}@", log: log, type: .error, error.localizedDescription)
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // One-shot location updates handled by the view via notification
        if let location = locations.last {
            NotificationCenter.default.post(
                name: .autoPresetsGeofenceLocationUpdated,
                object: nil,
                userInfo: ["location": location]
            )
        }
    }

    // MARK: - Preset Activation

    private func activatePreset(for location: AutoPresetsGeofenceLocation) {
        guard let presetUUID = UUID(uuidString: location.presetId) else {
            os_log("No preset configured for geofence %{public}@", log: log, type: .error, location.name)
            return
        }

        let coordinator = AutoPresets_Coordinator.shared

        // Don't override a manually-set preset
        if let currentOverride = coordinator.currentOverride(),
           activatedByGeofence[location.id.uuidString] == nil {
            os_log("Override already active (not from geofence), skipping", log: log, type: .info)
            return
        }

        guard let preset = coordinator.availablePresets().first(where: { $0.id == presetUUID }) else {
            os_log("Preset UUID %{public}@ not found in available presets", log: log, type: .error, location.presetId)
            return
        }

        activatedByGeofence[location.id.uuidString] = presetUUID
        coordinator.delegate?.autoPresets(coordinator, shouldActivatePreset: preset)

        lastTriggeredLocation = location.name

        // Log the event
        let storage = AutoPresets_Storage()
        storage.addLogEntry(event: .presetActivated, activityType: nil, presetName: "\(preset.name) (📍 \(location.name))")

        NotificationCenter.default.post(
            name: .autoPresetsPresetActivated,
            object: nil,
            userInfo: ["activityType": "geofence", "presetName": preset.name]
        )

        os_log("Geofence activated preset '%{public}@' for location '%{public}@'",
               log: log, type: .info, preset.name, location.name)
    }

    private func deactivatePreset(for location: AutoPresetsGeofenceLocation) {
        guard let presetUUID = activatedByGeofence[location.id.uuidString] else {
            os_log("No geofence-activated preset to deactivate for %{public}@", log: log, type: .debug, location.name)
            return
        }

        let coordinator = AutoPresets_Coordinator.shared

        guard let preset = coordinator.availablePresets().first(where: { $0.id == presetUUID }) else {
            activatedByGeofence.removeValue(forKey: location.id.uuidString)
            return
        }

        activatedByGeofence.removeValue(forKey: location.id.uuidString)
        coordinator.delegate?.autoPresets(coordinator, shouldDeactivatePreset: preset)

        let storage = AutoPresets_Storage()
        storage.addLogEntry(event: .presetDeactivated, activityType: nil, presetName: "\(preset.name) (📍 \(location.name))")

        NotificationCenter.default.post(
            name: .autoPresetsPresetDeactivated,
            object: nil,
            userInfo: ["activityType": "geofence", "presetName": preset.name]
        )

        os_log("Geofence deactivated preset '%{public}@' for location '%{public}@'",
               log: log, type: .info, preset.name, location.name)
    }

    // MARK: - Helpers

    private func locationForRegion(_ region: CLRegion) -> AutoPresetsGeofenceLocation? {
        let prefix = "AutoPresets_"
        guard region.identifier.hasPrefix(prefix) else { return nil }
        let uuidString = String(region.identifier.dropFirst(prefix.count))
        guard let uuid = UUID(uuidString: uuidString) else { return nil }
        return locations.first { $0.id == uuid && $0.isEnabled }
    }

    // MARK: - Persistence

    private func loadLocations() {
        guard let data = defaults.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([AutoPresetsGeofenceLocation].self, from: data)
        else {
            locations = []
            return
        }
        locations = decoded
    }

    private func saveLocations() {
        if let data = try? JSONEncoder().encode(locations) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }

    /// Log helper (reuses existing AutoPresets log event system)
    private func logEvent(_ event: AutoPresetsLogEvent, presetName: String?) {
        let storage = AutoPresets_Storage()
        storage.addLogEntry(event: event, activityType: nil, presetName: presetName)
    }
}

// MARK: - Notification

extension Notification.Name {
    static let autoPresetsGeofenceLocationUpdated = Notification.Name("com.loopkit.Loop.autoPresetsGeofenceLocationUpdated")
}
