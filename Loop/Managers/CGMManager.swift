//
//  CGMManager.swift
//  Loop
//
//  Copyright © 2017 LoopKit Authors. All rights reserved.
//

import LoopKit
import CGMBLEKit
import G4ShareSpy
import ShareClient
import MockKit

#if DEBUG
let staticCGMManagers: [CGMManager.Type] = [
    G6CGMManager.self,
    G5CGMManager.self,
    G4CGMManager.self,
    ShareClientManager.self,
    MockCGMManager.self,
]
#else
let staticCGMManagers: [CGMManager.Type] = [
    G6CGMManager.self,
    G5CGMManager.self,
    G4CGMManager.self,
    ShareClientManager.self,
]
#endif

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
