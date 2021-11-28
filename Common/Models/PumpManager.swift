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
    MockPumpManager.managerIdentifier : MockPumpManager.self
]

var availableStaticPumpManagers: [PumpManagerDescriptor] {
    if FeatureFlags.allowSimulators {
        return [
            PumpManagerDescriptor(identifier: MockPumpManager.managerIdentifier, localizedTitle: MockPumpManager.localizedTitle)
        ]
    } else {
        return []
    }
}

extension PumpManager {
    var rawValue: [String: Any] {
        return [
            "managerIdentifier": self.managerIdentifier,
            "state": self.rawState
        ]
    }
}
