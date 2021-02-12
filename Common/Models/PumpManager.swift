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

let staticPumpManagers: [PumpManagerUI.Type] = [
    MockPumpManager.self,
]

let staticPumpManagersByIdentifier: [String: PumpManagerUI.Type] = [
    MockPumpManager.managerIdentifier : MockPumpManager.self
]

let availableStaticPumpManagers = [
    PumpManagerDescriptor(identifier: MockPumpManager.managerIdentifier, localizedTitle: MockPumpManager.localizedTitle)
]

extension PumpManager {
    var rawValue: [String: Any] {
        return [
            "managerIdentifier": self.managerIdentifier,
            "state": self.rawState
        ]
    }
}
