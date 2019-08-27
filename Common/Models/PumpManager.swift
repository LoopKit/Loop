//
//  PumpManager.swift
//  Loop
//
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit
import MockKit

public struct AvailableDevice {
    let identifier: String
    let localizedTitle: String
}


let staticPumpManagers: [PumpManager.Type] = [
    MockPumpManager.self,
]

let staticPumpManagersByIdentifier: [String: PumpManager.Type] = staticPumpManagers.reduce(into: [:]) { (map, Type) in
    map[Type.managerIdentifier] = Type
}

let availableStaticPumpManagers = staticPumpManagers.map { (Type) -> AvailableDevice in
    return AvailableDevice(identifier: Type.managerIdentifier, localizedTitle: Type.localizedTitle)
}

extension PumpManager {
    var rawValue: [String: Any] {
        return [
            "managerIdentifier": type(of: self).managerIdentifier,
            "state": self.rawState
        ]
    }
}
