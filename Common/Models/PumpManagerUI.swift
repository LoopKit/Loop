//
//  PumpManagerUI.swift
//  Loop
//
//  Created by Pete Schwamb on 10/18/18.
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit
import LoopKitUI

private let managersByIdentifier: [String: PumpManagerUI.Type] = staticPumpManagers.compactMap{ $0 as? PumpManagerUI.Type}.reduce(into: [:]) { (map, Type) in
    map[Type.managerIdentifier] = Type
}

typealias PumpManagerHUDViewsRawValue = [String: Any]

func PumpManagerHUDViewsFromRawValue(_ rawValue: PumpManagerHUDViewsRawValue, pluginManager: PluginManager) -> [BaseHUDView]? {
    guard
        let identifier = rawValue["managerIdentifier"] as? String,
        let rawState = rawValue["hudProviderViews"] as? HUDProvider.HUDViewsRawState,
        let manager = pluginManager.getPumpManagerTypeByIdentifier(identifier) ?? staticPumpManagersByIdentifier[identifier] as? PumpManagerUI.Type else
    {
        return nil
    }
    return manager.createHUDViews(rawValue: rawState)
}

func PumpManagerHUDViewsRawValueFromHUDProvider(_ hudProvider: HUDProvider) -> PumpManagerHUDViewsRawValue {
    return [
        "managerIdentifier": hudProvider.managerIdentifier,
        "hudProviderViews": hudProvider.hudViewsRawState
    ]
}
