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
        let info = [
            "source": source,
            "message": message,
            "reportedAt": DateFormatter.ISO8601StrictDateFormatter().string(from: Date())
        ]

        addMessage(info, toCollection: "errors")
    }

    func addError(_ message: Error, fromSource source: String) {
        addError(String(describing: message), fromSource: source)
    }
}
