//
//  LoopError.swift
//  Loop
//
//  Created by Nate Racklyeft on 6/28/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation
import LoopKit

public enum ConfigurationErrorDetail: String, Codable {
    case pumpManager
    case basalRateSchedule
    case carbRatioSchedule
    case glucoseTargetRangeSchedule
    case insulinSensitivitySchedule
    case maximumBasalRatePerHour
    case maximumBolus
    case suspendThreshold

    public func localized() -> String {
        switch self {
        case .pumpManager:
            return LocalizedString("Pump Manager", comment: "Details for configuration error when pump manager is missing")
        case .basalRateSchedule:
            return LocalizedString("Basal Rate Schedule", comment: "Details for configuration error when basal rate schedule is missing")
        case .carbRatioSchedule:
            return LocalizedString("Carb Ratio Schedule", comment: "Details for configuration error when carb ratio schedule is missing")
        case .glucoseTargetRangeSchedule:
            return LocalizedString("Glucose Target Range Schedule", comment: "Details for configuration error when glucose target range schedule is missing")
        case .insulinSensitivitySchedule:
            return LocalizedString("Insulin Sensitivity Schedule", comment: "Details for configuration error when insulin sensitivity schedule is missing")
        case .maximumBasalRatePerHour:
            return LocalizedString("Maximum Basal Rate Per Hour", comment: "Details for configuration error when maximum basal rate per hour is missing")
        case .maximumBolus:
            return LocalizedString("Maximum Bolus", comment: "Details for configuration error when maximum bolus is missing")
        case .suspendThreshold:
            return LocalizedString("Suspend Threshold", comment: "Details for configuration error when suspend threshold is missing")
        }
    }
}

public enum MissingDataErrorDetail: String, Codable {
    case glucose
    case momentumEffect
    case carbEffect
    case insulinEffect
    case activeInsulin
    case insulinEffectIncludingPendingInsulin

    public var localizedDetail: String {
        switch self {
        case .glucose:
            return LocalizedString("Glucose data not available", comment: "Description of error when glucose data is missing")
        case .momentumEffect:
            return LocalizedString("Momentum effects", comment: "Details for missing data error when momentum effects are missing")
        case .carbEffect:
            return LocalizedString("Carb effects", comment: "Details for missing data error when carb effects are missing")
        case .insulinEffect:
            return LocalizedString("Insulin effects", comment: "Details for missing data error when insulin effects are missing")
        case .activeInsulin:
            return LocalizedString("Active Insulin", comment: "Details for missing data error when active insulin amount is missing")
        case .insulinEffectIncludingPendingInsulin:
            return LocalizedString("Insulin effects", comment: "Details for missing data error when insulin effects including pending insulin are missing")
        }
    }
    
    public var localizedRecovery: String? {
        switch self {
        case .glucose:
            return LocalizedString("Check your CGM data source", comment: "Recovery suggestion when glucose data is missing")
        case .momentumEffect:
            return nil
        case .carbEffect:
            return nil
        case .insulinEffect, .activeInsulin, .insulinEffectIncludingPendingInsulin:
            return nil
        }
    }
}

public enum LoopError: Error {
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

    // Pump Failure
    case pumpInoperable

    // Pump Suspended
    case pumpSuspended

    // Pump is delivering a manual temporary basal rate
    case manualTempBasalRunning

    // Pump Manager Error
    case pumpManagerError(PumpManagerError)

    // Loop State loop in progress
    case loopInProgress

    // Some other error
    case unknownError(Error)
}

public extension LoopError {
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
        case .pumpInoperable:
            return "pumpInoperable"
        case .pumpSuspended:
            return "pumpSuspended"
        case .manualTempBasalRunning:
            return "manualTempBasalRunning"
        case .pumpManagerError:
            return "pumpManagerError"
        case .loopInProgress:
            return "loopInProgress"
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
            return String(format: LocalizedString("Configuration Error: %1$@", comment: "The error message displayed for configuration errors. (1: configuration error details)"), details.localized())
        case .connectionError:
            return LocalizedString("No connected devices, or failure during device connection", comment: "The error message displayed for device connection errors.")
        case .missingDataError(let details):
            return String(format: LocalizedString("Missing data: %1$@", comment: "The error message for missing data. (1: missing data details)"), details.localizedDetail)
        case .glucoseTooOld(let date):
            let minutes = formatter.string(from: -date.timeIntervalSinceNow) ?? ""
            return String(format: LocalizedString("Glucose data is %1$@ old", comment: "The error message when glucose data is too old to be used. (1: glucose data age in minutes)"), minutes)
        case .invalidFutureGlucose(let date):
            let minutes = formatter.string(from: -date.timeIntervalSinceNow) ?? ""
            return String(format: LocalizedString("Invalid glucose reading with a timestamp that is %1$@ in the future", comment: "The error message when glucose data is in the future. (1: glucose data time in future in minutes)"), minutes)
        case .pumpDataTooOld(let date):
            let minutes = formatter.string(from: -date.timeIntervalSinceNow) ?? ""
            return String(format: LocalizedString("Pump data is %1$@ old", comment: "The error message when pump data is too old to be used. (1: pump data age in minutes)"), minutes)
        case .recommendationExpired(let date):
            let minutes = formatter.string(from: -date.timeIntervalSinceNow) ?? ""
            return String(format: LocalizedString("Recommendation expired: %1$@ old", comment: "The error message when a recommendation has expired. (1: age of recommendation in minutes)"), minutes)
        case .pumpInoperable:
            return LocalizedString("Pump Inoperable. Automatic dosing is disabled.", comment: "The error message displayed for LoopError.pumpInoperable errors.")
        case .pumpSuspended:
            return LocalizedString("Pump Suspended. Automatic dosing is disabled.", comment: "The error message displayed for LoopError.pumpSuspended errors.")
        case .manualTempBasalRunning:
            return LocalizedString("Manual temporary basal in progress. Automatic dosing is disabled.", comment: "The error message displayed for LoopError.manualTempBasalRunning errors.")
        case .pumpManagerError(let pumpManagerError):
            return String(format: LocalizedString("Pump Manager Error: %1$@", comment: "The error message displayed for pump manager errors. (1: pump manager error)"), pumpManagerError.errorDescription!)
        case .loopInProgress:
            return LocalizedString("Loop is already looping.", comment: "The error message displayed for LoopError.loopInProgress errors.")
        case .unknownError(let error):
            return String(format: LocalizedString("Unknown Error: %1$@", comment: "The error message displayed for unknown LoopError errors. (1: unknown error)"), error.localizedDescription)
        }
    }
}
