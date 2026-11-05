//
//  WatchDeviceManagers.swift
//  WatchApp Extension
//
//  The device managers the watch can be passed, by identifier, for managers built from another
//  controller's exported configuration: the device kits `WatchPluginManager` loads.
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import LoopKit

/// By the manager's `pluginIdentifier`, which is what its export carries.
private func watchCGMManagerType(_ identifier: String) -> (CGMManager & DeviceConfigurationSharing).Type? {
    WatchPluginManager.shared.cgmManagerType(withIdentifier: identifier) as? (CGMManager & DeviceConfigurationSharing).Type
}

/// A CGM manager built from another controller's export and this watch's saved `localState`.
func watchCGMManager(adopting configuration: SharedDeviceConfiguration, localState: [String: Any]?) -> CGMManager? {
    watchCGMManagerType(configuration.managerIdentifier)?.init(adopting: configuration, localState: localState)
}

/// A CGM manager restored from its saved `managerIdentifier` and `state`.
func watchCGMManager(rawValue: [String: Any]) -> CGMManager? {
    guard let identifier = rawValue["managerIdentifier"] as? String,
          let rawState = rawValue["state"] as? CGMManager.RawStateValue else { return nil }
    return watchCGMManagerType(identifier)?.init(rawState: rawState)
}

/// On a wake that is not the CGM's own, its acquisition re-checks itself.
func watchCGMRecheckAcquisition(_ manager: CGMManager?) {
    (manager as? DirectReadCGMManager)?.recheckAcquisition()
}

/// What the watch's CGM needs from the user (a code, or the app kept open while it searches), and the
/// notification posted when that changes.
func watchCGMStatusNote(_ manager: CGMManager?) -> String? {
    (manager as? DirectReadCGMManager)?.directReadStatusNote
}

let watchCGMStatusDidChange = Notification.Name.directReadCGMStatusDidChange

/// Whether the watch's CGM is searching for its sensor, which needs the app kept open.
func watchCGMIsSearching(_ manager: CGMManager?) -> Bool {
    (manager as? DirectReadCGMManager)?.isSearchingForSensor == true
}

func watchCGMSensorName(_ manager: CGMManager?) -> String? {
    (manager as? DirectReadCGMManager)?.sensorName
}

/// When the watch last had a link to the sensor, readings or not (none during warmup).
func watchCGMLastConnection(_ manager: CGMManager?) -> Date? {
    (manager as? DirectReadCGMManager)?.lastConnect ?? manager?.cgmManagerStatus.lastCommunicationDate
}

extension DeviceManager {
    /// What the watch saves, as stock saves a manager: `managerIdentifier` and `state`.
    var watchRawValue: [String: Any] {
        ["managerIdentifier": pluginIdentifier, "state": rawState]
    }
}
