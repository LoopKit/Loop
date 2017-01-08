//
//  LoopError.swift
//  Loop
//
//  Created by Nate Racklyeft on 6/28/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation

enum LoopError: Error {
    // Failure during device communication
    case communicationError

    // Missing or unexpected configuration values
    case configurationError

    // No connected devices, or failure during device connection
    case connectionError

    // Missing required data to perform an action
    case missingDataError(String)

    // Glucose data is too old to perform action
    case glucoseTooOld(TimeInterval)

    // Pump data is too old to perform action
    case pumpDataTooOld(TimeInterval)

    // Recommendation Expired
    case recommendationExpired(TimeInterval)
}

extension LoopError: LocalizedError {

    public var errorDescription: String? {

        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute]

        switch self {
        case .communicationError:
            return NSLocalizedString("Communication Error", comment: "The error message displayed after a communication error.")
        case .configurationError:
            return NSLocalizedString("Configuration Error", comment: "The error message displayed for configuration errors.")
        case .connectionError:
            return NSLocalizedString("No connected devices, or failure during device connection", comment: "The error message displayed for device connection errors.")
        case .missingDataError(let details):
            return String(format: NSLocalizedString("Missing data: %1$@", comment: "The error message for missing data. (1: missing data details)"), details)
        case .glucoseTooOld(let age):
            let minutes = formatter.string(from: age) ?? "??"
            return String(format: NSLocalizedString("Glucose data is %1$@ minutes old", comment: "The error message when glucose data is too old to be used. (1: glucose data age in minutes)"), minutes)
        case .pumpDataTooOld(let age):
            let minutes = formatter.string(from: age) ?? "??"
            return String(format: NSLocalizedString("Pump data is %1$@ minutes old", comment: "The error message when pump data is too old to be used. (1: pump data age in minutes)"), minutes)
        case .recommendationExpired(let age):
            let minutes = formatter.string(from: age) ?? "??"
            return String(format: NSLocalizedString("Recommendation expired: %1$@ minutes old", comment: "The error message when a recommendation has expired. (1: age of recommendation in minutes)"), minutes)
        }
    }
}

