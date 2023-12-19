//
//  PersistenceController.swift
//  LoopTests
//
//  Created by Pete Schwamb on 10/31/23.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit

extension PersistenceController {
    static func mock() -> PersistenceController {
        return PersistenceController(directoryURL: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true).appendingPathComponent(UUID().uuidString, isDirectory: true))
    }
}
