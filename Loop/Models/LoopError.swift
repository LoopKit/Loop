//
//  LoopError.swift
//  Loop
//
//  Created by Nate Racklyeft on 6/28/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation
import RileyLinkKit


enum LoopError: Error {
    // A bolus failed to start
    case bolusCommand(SetBolusError)

    // Missing or unexpected configuration values
    case configurationError(String)

    // No connected devices, or failure during device connection
    case connectionError

    // Missing data required to perform an action
    case missingDataError(details: String, recovery: String?)

    // Glucose data is too old to perform action
    case glucoseTooOld(date: Date)

    // Pump data is too old to perform action
    case pumpDataTooOld(date: Date)

    // Recommendation Expired
    case recommendationExpired(date: Date)

    // Invalid Data
    case invalidData(details: String)
}


extension LoopError: LocalizedError {

    public var recoverySuggestion: String? {
        switch self {
        case .missingDataError(_, let recovery):
            return recovery;
        default:
            return nil;
        }
    }

    public var errorDescription: String? {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute]
        formatter.unitsStyle = .full

        switch self {
        case .bolusCommand(let error):
            return error.errorDescription
        case .configurationError(let details):
            return String(format: NSLocalizedString("Configuration Error: %1$@", comment: "The error message displayed for configuration errors. (1: configuration error details)"), details)
        case .connectionError:
            return NSLocalizedString("No connected devices, or failure during device connection", comment: "The error message displayed for device connection errors.")
        case .missingDataError(let details, _):
            return String(format: NSLocalizedString("Missing data: %1$@", comment: "The error message for missing data. (1: missing data details)"), details)
        case .glucoseTooOld(let date):
            let minutes = formatter.string(from: -date.timeIntervalSinceNow) ?? ""
            return String(format: NSLocalizedString("Glucose data is %1$@ old", comment: "The error message when glucose data is too old to be used. (1: glucose data age in minutes)"), minutes)
        case .pumpDataTooOld(let date):
            let minutes = formatter.string(from: -date.timeIntervalSinceNow) ?? ""
            return String(format: NSLocalizedString("Pump data is %1$@ old", comment: "The error message when pump data is too old to be used. (1: pump data age in minutes)"), minutes)
        case .recommendationExpired(let date):
            let minutes = formatter.string(from: -date.timeIntervalSinceNow) ?? ""
            return String(format: NSLocalizedString("Recommendation expired: %1$@ old", comment: "The error message when a recommendation has expired. (1: age of recommendation in minutes)"), minutes)
        case .invalidData(let details):
            return String(format: NSLocalizedString("Invalid data: %1$@", comment: "The error message when invalid data was encountered. (1: details of invalid data)"), details)

        }
    }
}


extension SetBolusError: LocalizedError {
    public func errorDescriptionWithUnits(_ units: Double) -> String {
        let format: String

        switch self {
        case .certain:
            format = NSLocalizedString("%1$@ U bolus failed", comment: "Describes a certain bolus failure (1: size of the bolus in units)")
        case .uncertain:
            format = NSLocalizedString("%1$@ U bolus may not have succeeded", comment: "Describes an uncertain bolus failure (1: size of the bolus in units)")
        }

        return String(format: format, NumberFormatter.localizedString(from: NSNumber(value: units), number: .decimal))
    }

    public var failureReason: String? {
        switch self {
        case .certain(let error):
            return error.failureReason
        case .uncertain(let error):
            return error.failureReason
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .certain:
            return NSLocalizedString("It is safe to retry.", comment: "Recovery instruction for a certain bolus failure")
        case .uncertain:
            return NSLocalizedString("Check your pump before retrying.", comment: "Recovery instruction for an uncertain bolus failure")
        }
    }
}


extension PumpCommsError: LocalizedError {
    public var failureReason: String? {
        switch self {
        case .bolusInProgress:
            return NSLocalizedString("A bolus is already in progress.", comment: "Communications error for a bolus currently running")
        case .crosstalk:
            return NSLocalizedString("Comms with another pump detected.", comment: "")
        case .noResponse:
            return NSLocalizedString("Pump did not respond.", comment: "")
        case .pumpSuspended:
            return NSLocalizedString("Pump is suspended.", comment: "")
        case .rfCommsFailure(let msg):
            return msg
        case .rileyLinkTimeout:
            return NSLocalizedString("RileyLink timed out.", comment: "")
        case .unexpectedResponse:
            return NSLocalizedString("Pump responded unexpectedly.", comment: "")
        case .unknownPumpModel:
            return NSLocalizedString("Unknown pump model.", comment: "")
        case .unknownResponse:
            return NSLocalizedString("Unknown response from pump.", comment: "")
        }
    }
}

