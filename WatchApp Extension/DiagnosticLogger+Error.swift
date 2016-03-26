//
//  DiagnosticLogger+Error.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 3/25/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation


extension DiagnosticLogger {
    func addError(message: String, fromSource source: String) {
        let info = [
            "source": source,
            "message": message,
            "reportedAt": NSDateFormatter.ISO8601StrictDateFormatter().stringFromDate(NSDate())
        ]

        addMessage(info, toCollection: "errors")
    }
}