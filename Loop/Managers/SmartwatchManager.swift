//
//  SmartwatchManager.swift
//  Loop
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import LoopKit

extension SmartwatchManager {

    typealias RawValue = [String: Any]

    var rawValue: [String: Any] {
        return [
            "managerIdentifier": pluginIdentifier,
            "state": self.rawState
        ]
    }
}
