//
//  WatchDeviceManagers.swift
//  WatchApp Extension
//
//  The device managers the watch can be passed, by identifier: stock's static manager tables
//  (staticPumpManagersByIdentifier), for managers built from another controller's exported
//  configuration. The one place the watch names a device kit.
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import LoopKit
import OmnipodKit
import G7SensorKit

/// Keyed by each manager's `pluginIdentifier`, which is what its export carries.
let watchPumpManagersByIdentifier: [String: (PumpManager & DeviceConfigurationSharing).Type] = [
    "Omni": OmniPumpManager.self,
]

let watchCGMManagersByIdentifier: [String: (CGMManager & DeviceConfigurationSharing).Type] = [
    "G7CGMManager": G7CGMManager.self,
]

/// A pump manager built from another controller's export.
func watchPumpManager(adopting configuration: SharedDeviceConfiguration) -> PumpManager? {
    watchPumpManagersByIdentifier[configuration.managerIdentifier]?.init(adopting: configuration)
}

/// Whether taking control of this export here would have to find the device first.
func watchTakeControlNeedsSearch(adopting configuration: SharedDeviceConfiguration) -> Bool {
    let type = watchPumpManagersByIdentifier[configuration.managerIdentifier] as? ExclusiveDeviceControl.Type
    return type?.takeControlNeedsSearch(adopting: configuration) ?? false
}

/// A pump manager restored from its saved `managerIdentifier` and `state`, as stock restores one.
func watchPumpManager(rawValue: [String: Any]) -> PumpManager? {
    guard let identifier = rawValue["managerIdentifier"] as? String,
          let rawState = rawValue["state"] as? PumpManager.RawStateValue else { return nil }
    return watchPumpManagersByIdentifier[identifier]?.init(rawState: rawState)
}

/// A CGM manager built from another controller's export.
func watchCGMManager(adopting configuration: SharedDeviceConfiguration) -> CGMManager? {
    watchCGMManagersByIdentifier[configuration.managerIdentifier]?.init(adopting: configuration)
}

/// A CGM manager restored from its saved `managerIdentifier` and `state`.
func watchCGMManager(rawValue: [String: Any]) -> CGMManager? {
    guard let identifier = rawValue["managerIdentifier"] as? String,
          let rawState = rawValue["state"] as? CGMManager.RawStateValue else { return nil }
    return watchCGMManagersByIdentifier[identifier]?.init(rawState: rawState)
}

extension DeviceManager {
    /// What the watch saves, as stock saves a manager: `managerIdentifier` and `state`.
    var watchRawValue: [String: Any] {
        ["managerIdentifier": pluginIdentifier, "state": rawState]
    }
}
