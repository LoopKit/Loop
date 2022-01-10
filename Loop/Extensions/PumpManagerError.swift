//
//  PumpManagerError.swift
//  Loop
//
//  Created by Darin Krauss on 5/8/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import LoopKit

extension PumpManagerError {
    var issueId: String {
        switch self {
        case .configuration:
            return "configuration"
        case .connection:
            return "connection"
        case .communication:
            return "communication"
        case .deviceState:
            return "deviceState"
        case .uncertainDelivery:
            return "uncertainDelivery"
        }
    }

    var issueDetails: [String: String] {
        var details = ["detail": issueId]
        switch self {
        case .configuration(let localizedError),
             .connection(let localizedError),
             .communication(let localizedError),
             .deviceState(let localizedError):
            details["error"] = StoredDosingDecisionIssue.description(for: localizedError)
        default:
            break
        }
        return details
    }
}
