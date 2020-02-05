//
//  CGMManager.swift
//  Loop
//
//  Copyright © 2017 LoopKit Authors. All rights reserved.
//

import LoopKit
import MockKit

// TODO: Need a flag other than Debug for including MockCGMManager
let staticCGMManagers: [CGMManager.Type] = [MockCGMManager.self]

let staticCGMManagersByIdentifier: [String: CGMManager.Type] = staticCGMManagers.reduce(into: [:]) { (map, Type) in
    map[Type.managerIdentifier] = Type
}

let availableStaticCGMManagers = staticCGMManagers.map { (Type) -> AvailableDevice in
    return AvailableDevice(identifier: Type.managerIdentifier, localizedTitle: Type.localizedTitle)
}

func CGMManagerFromRawValue(_ rawValue: [String: Any]) -> CGMManager? {
    guard let managerIdentifier = rawValue["managerIdentifier"] as? String,
        let rawState = rawValue["state"] as? CGMManager.RawStateValue,
        let Manager = staticCGMManagersByIdentifier[managerIdentifier]
    else {
        return nil
    }
    
    return Manager.init(rawState: rawState)
}

extension CGMManager {
    var rawValue: [String: Any] {
        return [
            "managerIdentifier": type(of: self).managerIdentifier,
            "state": self.rawState
        ]
    }
}
