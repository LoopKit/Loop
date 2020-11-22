//
//  LoopError.swift
//  Loop
//
//  Created by Nate Racklyeft on 6/28/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation
import LoopKit

enum ConfigurationErrorDetail {
    case pumpManager
    case basalRateSchedule
    case insulinModel
    case generalSettings
    
    func localized() -> String {
        switch self {
        case .pumpManager:
            return NSLocalizedString("Pump Manager", comment: "Details for configuration error when pump manager is missing")
        case .basalRateSchedule:
            return NSLocalizedString("Basal Rate Schedule", comment: "Details for configuration error when basal rate schedule is missing")
        case .insulinModel:
            return NSLocalizedString("Insulin Model", comment: "Details for configuration error when insulin model is missing")
        case .generalSettings:
            return NSLocalizedString("Check settings", comment: "Details for configuration error when one or more loop settings are missing")
        }
    }
}

enum MissingDataErrorDetail {
    case glucose
    case reservoir
    case momentumEffect
    case carbEffect
    case insulinEffect
    
    var localizedDetail: String {
        switch self {
        case .glucose:
            return NSLocalizedString("Glucose data not available", comment: "Description of error when glucose data is missing")
        case .reservoir:
            return NSLocalizedString("Reservoir", comment: "Details for missing data error when reservoir data is missing")
        case .momentumEffect:
            return NSLocalizedString("Momentum effects", comment: "Details for missing data error when momentum effects are missing")
        case .carbEffect:
            return NSLocalizedString("Carb effects", comment: "Details for missing data error when carb effects are missing")
        case .insulinEffect:
            return NSLocalizedString("Insulin effects", comment: "Details for missing data error when insulin effects are missing")
        }
    }
    
    var localizedRecovery: String? {
        switch self {
        case .glucose:
            return NSLocalizedString("Check your CGM data source", comment: "Recovery suggestion when glucose data is missing")
        case .reservoir:
            return NSLocalizedString("Check that your pump is in range", comment: "Recovery suggestion when reservoir data is missing")
        case .momentumEffect:
            return nil
        case .carbEffect:
            return nil
        case .insulinEffect:
            return nil
        }
    }
}

enum LoopError: Error {
    // A bolus failed to start
    case bolusCommand(SetBolusError)

    // Missing or unexpected configuration values
    case configurationError(ConfigurationErrorDetail)

    // No connected devices, or failure during device connection
    case connectionError

    // Missing data required to perform an action
    case missingDataError(MissingDataErrorDetail)

    // Glucose data is too old to perform action
    case glucoseTooOld(date: Date)

    // Pump data is too old to perform action
    case pumpDataTooOld(date: Date)

    // Recommendation Expired
    case recommendationExpired(date: Date)

    // Invalid Data
    case invalidData(details: String)
    
    // Pump Suspended
    case pumpSuspended
}


extension LoopError: LocalizedError {

    public var recoverySuggestion: String? {
        switch self {
        case .missingDataError(let detail):
            return detail.localizedRecovery;
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
            return String(format: NSLocalizedString("Configuration Error: %1$@", comment: "The error message displayed for configuration errors. (1: configuration error details)"), details.localized())
        case .connectionError:
            return NSLocalizedString("No connected devices, or failure during device connection", comment: "The error message displayed for device connection errors.")
        case .missingDataError(let details):
            return String(format: NSLocalizedString("Missing data: %1$@", comment: "The error message for missing data. (1: missing data details)"), details.localizedDetail)
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
        case .pumpSuspended:
            return NSLocalizedString("Pump Suspended", comment: "The error message when loop failed because the pump was encountered.")
        }
    }
}


