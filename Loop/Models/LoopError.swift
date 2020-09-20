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

enum MissingDataErrorDetail: String, Codable {
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
}

extension LoopError: Codable {
    public init(from decoder: Decoder) throws {
        if let string = try? decoder.singleValueContainer().decode(String.self) {
            switch string {
            case CodableKeys.connectionError.rawValue:
                self = .connectionError
            default:
                throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "invalid enumeration"))
            }
        } else {
            let container = try decoder.container(keyedBy: CodableKeys.self)
            if let configurationError = try container.decodeIfPresent(ConfigurationError.self, forKey: .configurationError) {
                self = .configurationError(configurationError.configurationErrorDetail)
            } else if let missingDataError = try container.decodeIfPresent(MissingDataError.self, forKey: .missingDataError) {
                self = .missingDataError(missingDataError.missingDataErrorDetail)
            } else if let glucoseTooOld = try container.decodeIfPresent(GlucoseTooOld.self, forKey: .glucoseTooOld) {
                self = .glucoseTooOld(date: glucoseTooOld.date)
            } else if let pumpDataTooOld = try container.decodeIfPresent(PumpDataTooOld.self, forKey: .pumpDataTooOld) {
                self = .pumpDataTooOld(date: pumpDataTooOld.date)
            } else if let recommendationExpired = try container.decodeIfPresent(RecommendationExpired.self, forKey: .recommendationExpired) {
                self = .recommendationExpired(date: recommendationExpired.date)
            } else if let invalidData = try container.decodeIfPresent(InvalidData.self, forKey: .invalidData) {
                self = .invalidData(details: invalidData.details)
            } else {
                throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "invalid enumeration"))
            }
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        switch self {
        case .connectionError:
            var container = encoder.singleValueContainer()
            try container.encode(CodableKeys.connectionError.rawValue)
        case .configurationError(let configurationErrorDetail):
            var container = encoder.container(keyedBy: CodableKeys.self)
            try container.encode(ConfigurationError(configurationErrorDetail: configurationErrorDetail), forKey: .configurationError)
        case .missingDataError(let missingDataErrorDetail):
            var container = encoder.container(keyedBy: CodableKeys.self)
            try container.encode(MissingDataError(missingDataErrorDetail: missingDataErrorDetail), forKey: .missingDataError)
        case .glucoseTooOld(let date):
            var container = encoder.container(keyedBy: CodableKeys.self)
            try container.encode(GlucoseTooOld(date: date), forKey: .glucoseTooOld)
        case .pumpDataTooOld(let date):
            var container = encoder.container(keyedBy: CodableKeys.self)
            try container.encode(PumpDataTooOld(date: date), forKey: .pumpDataTooOld)
        case .recommendationExpired(let date):
            var container = encoder.container(keyedBy: CodableKeys.self)
            try container.encode(RecommendationExpired(date: date), forKey: .recommendationExpired)
        case .invalidData(let details):
            var container = encoder.container(keyedBy: CodableKeys.self)
            try container.encode(InvalidData(details: details), forKey: .invalidData)
        }
    }
    
    private struct ConfigurationError: Codable {
        let configurationErrorDetail: ConfigurationErrorDetail
    }
    
    private struct MissingDataError: Codable {
        let missingDataErrorDetail: MissingDataErrorDetail
    }
    
    private struct GlucoseTooOld: Codable {
        let date: Date
    }
    
    private struct PumpDataTooOld: Codable {
        let date: Date
    }
    
    private struct RecommendationExpired: Codable {
        let date: Date
    }
    
    private struct InvalidData: Codable {
        let details: String
    }
    
    private enum CodableKeys: String, CodingKey {
        case bolusCommand
        case configurationError
        case connectionError
        case missingDataError
        case glucoseTooOld
        case pumpDataTooOld
        case recommendationExpired
        case invalidData
    }
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

        }
    }
}


