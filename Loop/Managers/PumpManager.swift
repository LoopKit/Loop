//
//  PumpManager.swift
//  Loop
//
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit
import MinimedKit


let allPumpManagers: [PumpManager.Type] = [
    MinimedPumpManager.self
]

private let managersByIdentifier: [String: PumpManager.Type] = allPumpManagers.reduce(into: [:]) { (map, Type) in
    map[Type.managerIdentifier] = Type
}

func PumpManagerTypeFromRawValue(_ rawValue: [String: Any]) -> PumpManager.Type? {
    guard let managerIdentifier = rawValue["managerIdentifier"] as? String else {
        return nil
    }

    return managersByIdentifier[managerIdentifier]
}

func PumpManagerFromRawValue(_ rawValue: [String: Any]) -> PumpManager? {
    guard let rawState = rawValue["state"] as? PumpManager.RawStateValue,
        let Manager = PumpManagerTypeFromRawValue(rawValue)
    else {
        return nil
    }

    return Manager.init(rawState: rawState)
}

extension PumpManager {
    var rawValue: [String: Any] {
        return [
            "managerIdentifier": type(of: self).managerIdentifier,
            "state": self.rawState
        ]
    }
}
