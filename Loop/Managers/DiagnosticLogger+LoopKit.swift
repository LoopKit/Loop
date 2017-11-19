//
//  DiagnosticLogger+LoopKit.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 3/25/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation
import HealthKit
import LoopKit


extension DiagnosticLogger {
    func addError(_ message: String, fromSource source: String) {
        let message = [
            "message": message
        ]

        forCategory(source).error(message)
    }

    func addError(_ message: Error, fromSource source: String) {
        forCategory(source).error(message)
    }
}
