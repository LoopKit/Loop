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
import MockKitUI

private let managersByIdentifier: [String: PumpManagerUI.Type] = staticPumpManagers.compactMap{ $0 as? PumpManagerUI.Type}.reduce(into: [:]) { (map, Type) in
    map[Type.managerIdentifier] = Type
}

typealias PumpManagerHUDViewRawValue = [String: Any]

func PumpManagerHUDViewFromRawValue(_ rawValue: PumpManagerHUDViewRawValue, pluginManager: PluginManager) -> LevelHUDView? {
    guard
        let identifier = rawValue["managerIdentifier"] as? String,
        let rawState = rawValue["hudProviderView"] as? HUDProvider.HUDViewRawState,
        let manager = pluginManager.getPumpManagerTypeByIdentifier(identifier) ?? staticPumpManagersByIdentifier[identifier] as? PumpManagerUI.Type else
    {
        return nil
    }
    return manager.createHUDView(rawValue: rawState)
}

func PumpManagerHUDViewRawValueFromHUDProvider(_ hudProvider: HUDProvider) -> PumpManagerHUDViewRawValue {
    return [
        "managerIdentifier": hudProvider.managerIdentifier,
        "hudProviderView": hudProvider.hudViewRawState
    ]
}
