//
//  LoopError.swift
//  Loop
//
//  Created by Nate Racklyeft on 6/28/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation
import LoopKit

enum ConfigurationErrorDetail: String, Codable {
    case pumpManager
    case basalRateSchedule
    case carbRatioSchedule
    case glucoseTargetRangeSchedule
    case insulinSensitivitySchedule
    case maximumBasalRatePerHour
    case maximumBolus
    
    func localized() -> String {
        switch self {
        case .pumpManager:
            return NSLocalizedString("Pump Manager", comment: "Details for configuration error when pump manager is missing")
        case .basalRateSchedule:
            return NSLocalizedString("Basal Rate Schedule", comment: "Details for configuration error when basal rate schedule is missing")
        case .carbRatioSchedule:
            return NSLocalizedString("Carb Ratio Schedule", comment: "Details for configuration error when carb ratio schedule is missing")
        case .glucoseTargetRangeSchedule:
            return NSLocalizedString("Glucose Target Range Schedule", comment: "Details for configuration error when glucose target range schedule is missing")
        case .insulinSensitivitySchedule:
            return NSLocalizedString("Insulin Sensitivity Schedule", comment: "Details for configuration error when insulin sensitivity schedule is missing")
        case .maximumBasalRatePerHour:
            return NSLocalizedString("Maximum Basal Rate Per Hour", comment: "Details for configuration error when maximum basal rate per hour is missing")
        case .maximumBolus:
            return NSLocalizedString("Maximum Bolus", comment: "Details for configuration error when maximum bolus is missing")
        }
    }
}

enum MissingDataErrorDetail: String, Codable {
    case glucose
    case momentumEffect
    case carbEffect
    case insulinEffect
    case activeInsulin
    case insulinEffectIncludingPendingInsulin
    
    var localizedDetail: String {
        switch self {
        case .glucose:
            return NSLocalizedString("Glucose data not available", comment: "Description of error when glucose data is missing")
        case .momentumEffect:
            return NSLocalizedString("Momentum effects", comment: "Details for missing data error when momentum effects are missing")
        case .carbEffect:
            return NSLocalizedString("Carb effects", comment: "Details for missing data error when carb effects are missing")
        case .insulinEffect:
            return NSLocalizedString("Insulin effects", comment: "Details for missing data error when insulin effects are missing")
        case .activeInsulin:
            return NSLocalizedString("Active Insulin", comment: "Details for missing data error when active insulin amount is missing")
        case .insulinEffectIncludingPendingInsulin:
            return NSLocalizedString("Insulin effects", comment: "Details for missing data error when insulin effects including pending insulin are missing")
        }
    }
    
    var localizedRecovery: String? {
        switch self {
        case .glucose:
            return NSLocalizedString("Check your CGM data source", comment: "Recovery suggestion when glucose data is missing")
        case .momentumEffect:
            return nil
        case .carbEffect:
            return nil
        case .insulinEffect, .activeInsulin, .insulinEffectIncludingPendingInsulin:
            return nil
        }
    }
}

enum LoopError: Error {
    // Missing or unexpected configuration values
    case configurationError(ConfigurationErrorDetail)

    // No connected devices, or failure during device connection
    case connectionError

    // Missing data required to perform an action
    case missingDataError(MissingDataErrorDetail)

    // Glucose data is too old to perform action
    case glucoseTooOld(date: Date)

    // Glucose data is in the future
    case invalidFutureGlucose(date: Date)

    // Pump data is too old to perform action
    case pumpDataTooOld(date: Date)

    // Recommendation Expired
    case recommendationExpired(date: Date)

    // Pump Suspended
    case pumpSuspended

    // Pump Manager Error
    case pumpManagerError(PumpManagerError)

    // Some other error
    case unknownError(Error)
}

extension LoopError {
    var issue: StoredDosingDecision.Issue {
        return StoredDosingDecision.Issue(id: issueId, details: issueDetails)
    }

    var issueId: String {
        switch self {
        case .configurationError:
            return "configurationError"
        case .connectionError:
            return "connectionError"
        case .missingDataError:
            return "missingDataError"
        case .glucoseTooOld:
            return "glucoseTooOld"
        case .invalidFutureGlucose:
            return "invalidFutureGlucose"
        case .pumpDataTooOld:
            return "pumpDataTooOld"
        case .recommendationExpired:
            return "recommendationExpired"
        case .pumpSuspended:
            return "pumpSuspended"
        case .pumpManagerError:
            return "pumpManagerError"
        case .unknownError:
            return "unknownError"
        }
    }

    var issueDetails: [String: String] {
        var details: [String: String] = [:]
        switch self {
        case .configurationError(let detail):
            details["detail"] = detail.rawValue
        case .missingDataError(let detail):
            details["detail"] = detail.rawValue
        case .glucoseTooOld(let date):
            details["date"] = StoredDosingDecisionIssue.description(for: date)
        case .invalidFutureGlucose(let date):
            details["date"] = StoredDosingDecisionIssue.description(for: date)
        case .pumpDataTooOld(let date):
            details["date"] = StoredDosingDecisionIssue.description(for: date)
        case .recommendationExpired(let date):
            details["date"] = StoredDosingDecisionIssue.description(for: date)
        case .pumpManagerError(let pumpManagerError):
            details = pumpManagerError.issueDetails
        case .unknownError(let error):
            details["error"] = StoredDosingDecisionIssue.description(for: error)
        default:
            break
        }
        return details
    }
}

extension LoopError: LocalizedError {

    public var recoverySuggestion: String? {
        switch self {
        case .missingDataError(let detail):
            return detail.localizedRecovery
        default:
            return nil
        }
    }

    public var errorDescription: String? {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute]
        formatter.unitsStyle = .full

        switch self {
        case .configurationError(let details):
            return String(format: NSLocalizedString("Configuration Error: %1$@", comment: "The error message displayed for configuration errors. (1: configuration error details)"), details.localized())
        case .connectionError:
            return NSLocalizedString("No connected devices, or failure during device connection", comment: "The error message displayed for device connection errors.")
        case .missingDataError(let details):
            return String(format: NSLocalizedString("Missing data: %1$@", comment: "The error message for missing data. (1: missing data details)"), details.localizedDetail)
        case .glucoseTooOld(let date):
            let minutes = formatter.string(from: -date.timeIntervalSinceNow) ?? ""
            return String(format: NSLocalizedString("Glucose data is %1$@ old", comment: "The error message when glucose data is too old to be used. (1: glucose data age in minutes)"), minutes)
        case .invalidFutureGlucose(let date):
            let minutes = formatter.string(from: -date.timeIntervalSinceNow) ?? ""
            return String(format: NSLocalizedString("Invalid glucose reading with a timestamp that is %1$@ in the future", comment: "The error message when glucose data is in the future. (1: glucose data time in future in minutes)"), minutes)
        case .pumpDataTooOld(let date):
            let minutes = formatter.string(from: -date.timeIntervalSinceNow) ?? ""
            return String(format: NSLocalizedString("Pump data is %1$@ old", comment: "The error message when pump data is too old to be used. (1: pump data age in minutes)"), minutes)
        case .recommendationExpired(let date):
            let minutes = formatter.string(from: -date.timeIntervalSinceNow) ?? ""
            return String(format: NSLocalizedString("Recommendation expired: %1$@ old", comment: "The error message when a recommendation has expired. (1: age of recommendation in minutes)"), minutes)
        case .pumpSuspended:
            return NSLocalizedString("Pump Suspended. Automatic dosing is disabled.", comment: "The error message displayed for pumpSuspended errors.")
        case .pumpManagerError(let pumpManagerError):
            return String(format: NSLocalizedString("Pump Manager Error: %1$@", comment: "The error message displayed for pump manager errors. (1: pump manager error)"), pumpManagerError.errorDescription!)
        case .unknownError(let error):
            return String(format: NSLocalizedString("Unknown Error: %1$@", comment: "The error message displayed for unknown errors. (1: unknown error)"), error.localizedDescription)
        }
    }
}
