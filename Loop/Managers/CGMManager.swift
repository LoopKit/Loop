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

let staticCGMManagersByIdentifier: [String: CGMManager.Type] = [
    MockCGMManager.managerIdentifier: MockCGMManager.self
]

let availableStaticCGMManagers = [
    AvailableDevice(identifier: MockCGMManager.managerIdentifier, localizedTitle: MockCGMManager.localizedTitle, providesOnboarding: false)
]

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
            "managerIdentifier": managerIdentifier,
            "state": self.rawState
        ]
    }
}
