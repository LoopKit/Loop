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

let staticPumpManagersByIdentifier: [String: PumpManagerUI.Type] = staticPumpManagers.reduce(into: [:]) { (map, Type) in
    map[Type.managerIdentifier] = Type
}

let availableStaticPumpManagers = staticPumpManagers.map { (Type) -> AvailableDevice in
    return AvailableDevice(identifier: Type.managerIdentifier, localizedTitle: Type.localizedTitle, providesOnboarding: false)
}

extension PumpManager {
    var rawValue: [String: Any] {
        return [
            "managerIdentifier": type(of: self).managerIdentifier,
            "state": self.rawState
        ]
    }
}
