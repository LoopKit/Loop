//
//  PumpManager.swift
//  Loop
//
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit
import LoopKitUI
import MockKit
import MockKitUI

let staticPumpManagersByIdentifier: [String: PumpManagerUI.Type] = [
    MockPumpManager.pluginIdentifier : MockPumpManager.self
]

var availableStaticPumpManagers: [PumpManagerDescriptor] {
    if FeatureFlags.allowSimulators {
        return [
            PumpManagerDescriptor(identifier: MockPumpManager.pluginIdentifier, localizedTitle: MockPumpManager.localizedTitle)
        ]
    } else {
        return []
    }
}

extension PumpManager {

    typealias RawValue = [String: Any]
    
    var rawValue: RawValue {
        return [
            "managerIdentifier": self.pluginIdentifier,
            "state": self.rawState
        ]
    }
}
