//
//  PumpManagerUI.swift
//  Loop
//
//  Created by Pete Schwamb on 10/18/18.
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKitUI
import OmniKit
import OmniKitUI
import MinimedKit
import MinimedKitUI

let allPumpManagerUIs: [PumpManagerUI.Type] = [
    OmnipodPumpManager.self,
    MinimedPumpManager.self
]

private let managersByIdentifier: [String: PumpManagerUI.Type] = allPumpManagerUIs.reduce(into: [:]) { (map, Type) in
    map[Type.managerIdentifier] = Type
}

func PumpManagerUITypeFromRawValue(_ rawValue: [String: Any]) -> PumpManagerUI.Type? {
    guard let managerIdentifier = rawValue["managerIdentifier"] as? String else {
        return nil
    }
    
    return managersByIdentifier[managerIdentifier]
}

func PumpManagerHUDViewsFromRawValue(_ rawValue: [String: Any]) -> [BaseHUDView]? {
    guard let rawState = rawValue["pumpManagerHUDViews"] as? PumpManagerUI.PumpManagerHUDViewsRawState,
        let Manager = PumpManagerUITypeFromRawValue(rawValue)
        else {
            return nil
    }
    
    return Manager.instantiateHUDViews(rawValue: rawState)
}

extension PumpManagerUI {
    var rawPumpManagerHUDViewsValue: [String: Any] {
        return [
            "managerIdentifier": type(of: self).managerIdentifier,
            "pumpManagerHUDViews": self.hudViewsRawState
        ]
    }
}


