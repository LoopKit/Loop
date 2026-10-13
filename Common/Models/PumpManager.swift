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
            PumpManagerDescriptor(
                identifier: MockPumpManager.managerIdentifier,
                localizedTitle: MockPumpManager.localizedTitle,
                subtitle: NSLocalizedString("For testing; delivers no insulin", comment: "Picker subtitle for the pump simulator"),
                manufacturer: "Simulator",
                image: MockPumpManager.pickerImage
            )
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
