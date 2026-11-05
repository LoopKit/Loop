//
//  WatchPumpManagers.swift
//  WatchApp Extension
//
//  The pump managers the watch can be passed, by identifier: stock's static manager tables
//  (staticPumpManagersByIdentifier), for managers built from another controller's exported
//  configuration. The CGM half is stock's `WatchDeviceManagers.swift`.
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import LoopKit
import OmnipodKit

/// Keyed by each manager's `pluginIdentifier`, which is what its export carries.
let watchPumpManagersByIdentifier: [String: (PumpManager & DeviceConfigurationSharing).Type] = [
    "Omni": OmniPumpManager.self,
]

/// A pump manager built from another controller's export and this watch's saved `localState`.
func watchPumpManager(adopting configuration: SharedDeviceConfiguration, localState: [String: Any]?) -> PumpManager? {
    watchPumpManagersByIdentifier[configuration.managerIdentifier]?.init(adopting: configuration, localState: localState)
}

/// Whether taking control of this export here would have to find the device first.
func watchTakeControlNeedsSearch(adopting configuration: SharedDeviceConfiguration, localState: [String: Any]?) -> Bool {
    let type = watchPumpManagersByIdentifier[configuration.managerIdentifier] as? ExclusiveDeviceControl.Type
    return type?.takeControlNeedsSearch(adopting: configuration, localState: localState) ?? false
}

/// A pump manager restored from its saved `managerIdentifier` and `state`, as stock restores one.
func watchPumpManager(rawValue: [String: Any]) -> PumpManager? {
    guard let identifier = rawValue["managerIdentifier"] as? String,
          let rawState = rawValue["state"] as? PumpManager.RawStateValue else { return nil }
    return watchPumpManagersByIdentifier[identifier]?.init(rawState: rawState)
}
