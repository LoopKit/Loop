//
//  DosingDecisionStore.swift
//  Loop
//
//  Created by Darin Krauss on 10/22/21.
//  Copyright © 2021 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit

public extension StoredDosingDecision {
    mutating func appendWarning(_ warning: LoopWarning) { warnings.append(warning.issue) }
    mutating func appendWarnings(_ warnings: [LoopWarning]) { warnings.forEach{ appendWarning($0) } }

    mutating func appendError(_ error: LoopError) { errors.append(error.issue) }
    mutating func appendErrors(_ errors: [LoopError]) { errors.forEach{ appendError($0) } }
}

public enum StoredDosingDecisionIssue {
    public static func description(for error: Error?) -> String? {
        guard let error = error else {
            return nil
        }
        if let localizedError = error as? LocalizedError {
            return localizedError.errorDescription ?? String(describing: error)
        } else {
            return String(describing: error)
        }
    }

    public static func description(for date: Date?) -> String? {
        guard let date = date else {
            return nil
        }
        return Self.dateFormatter.string(from: date)
    }

    public static var dateFormatter: ISO8601DateFormatter = {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return dateFormatter
    }()
}
