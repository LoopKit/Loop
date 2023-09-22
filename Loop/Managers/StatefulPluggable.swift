//
//  StatefulPluggable.swift
//  Loop
//
//  Created by Nathaniel Hamming on 2023-09-13.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import LoopKit

extension StatefulPluggable {
    typealias RawValue = [String: Any]

    var rawValue: RawValue {
        return [
            "statefulPluginIdentifier": pluginIdentifier,
            "state": rawState
        ]
    }
}
