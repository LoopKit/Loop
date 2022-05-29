//
//  CGMManager.swift
//  Loop
//
//  Copyright © 2017 LoopKit Authors. All rights reserved.
//

import LoopKit
import LoopKitUI
import MockKit

let staticCGMManagersByIdentifier: [String: CGMManager.Type] = [
    MockCGMManager.managerIdentifier: MockCGMManager.self
]

var availableStaticCGMManagers: [CGMManagerDescriptor] {
    if FeatureFlags.allowSimulators {
        return [
            CGMManagerDescriptor(identifier: MockCGMManager.managerIdentifier, localizedTitle: MockCGMManager.localizedTitle)
        ]
    } else {
        return []
    }
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

    typealias RawValue = [String: Any]
    
    var rawValue: [String: Any] {
        return [
            "managerIdentifier": managerIdentifier,
            "state": self.rawState
        ]
    }
}
