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
import MinimedKit
import MinimedKitUI

private let managersByIdentifier: [String: PumpManagerUI.Type] = allPumpManagers.compactMap{ $0 as? PumpManagerUI.Type}.reduce(into: [:]) { (map, Type) in
    map[Type.managerIdentifier] = Type
}

typealias PumpManagerHUDViewsRawValue = [String: Any]

func PumpManagerHUDViewsFromRawValue(_ rawValue: PumpManagerHUDViewsRawValue) -> [BaseHUDView]? {
    guard let rawState = rawValue["hudProviderViews"] as? HUDProvider.HUDViewsRawState,
        let managerIdentifier = rawValue["managerIdentifier"] as? String,
        let manager = managersByIdentifier[managerIdentifier]
        else {
            return nil
    }
    
    return manager.createHUDViews(rawValue: rawState)
}

func PumpManagerHUDViewsRawValueFromHudProvider(_ hudProvider: HUDProvider) -> PumpManagerHUDViewsRawValue {
    return [
        "managerIdentifier": hudProvider.managerIdentifier,
        "hudProviderViews": hudProvider.hudViewsRawState
    ]
}
