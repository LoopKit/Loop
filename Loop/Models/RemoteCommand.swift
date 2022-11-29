//
//  RemoteCommand.swift
//  Loop
//
//  Created by Pete Schwamb on 9/16/19.
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit
import HealthKit

public enum RemoteCommandError: LocalizedError {
    case expired
    case invalidOTP
    case missingMaxBolus
    case exceedsMaxBolus
    case exceedsMaxCarbs
    case invalidCarbs
    
    public var errorDescription: String? {
        get {
            switch  self {
            case .expired:
                return NSLocalizedString("Expired", comment: "Remote command error description: expired.")
            case .invalidOTP:
                return NSLocalizedString("Invalid OTP", comment: "Remote command error description: invalid OTP.")
            case .missingMaxBolus:
                return NSLocalizedString("Missing maximum allowed bolus in settings", comment: "Remote command error description: missing maximum bolus in settings.")
            case .exceedsMaxBolus:
                return NSLocalizedString("Exceeds maximum allowed bolus in settings", comment: "Remote command error description: bolus exceeds maximum bolus in settings.")
            case .exceedsMaxCarbs:
                return NSLocalizedString("Exceeds maximum allowed carbs", comment: "Remote command error description: carbs exceed maximum amount.")
            case .invalidCarbs:
                return NSLocalizedString("Invalid carb amount", comment: "Remote command error description: invalid carb amount.")
            }
        }
    }
}


enum RemoteCommand {
    case temporaryScheduleOverride(TemporaryScheduleOverride)
    case cancelTemporaryOverride
    case bolusEntry(Double)
    case carbsEntry(NewCarbEntry)
}


// Push Notifications
extension RemoteCommand {
    static func createRemoteCommand(notification: [String: Any], allowedPresets: [TemporaryScheduleOverridePreset], defaultAbsorptionTime: TimeInterval, nowDate: Date = Date()) -> Result<RemoteCommand, RemoteCommandParseError> {
        if let overrideName = notification["override-name"] as? String,
            let preset = allowedPresets.first(where: { $0.name == overrideName }),
            let remoteAddress = notification["remote-address"] as? String
        {
            var override = preset.createOverride(enactTrigger: .remote(remoteAddress))
            if let overrideDurationMinutes = notification["override-duration-minutes"] as? Double {
                override.duration = .finite(TimeInterval(minutes: overrideDurationMinutes))
            }
            return .success(.temporaryScheduleOverride(override))
        } else if let _ = notification["cancel-temporary-override"] as? String {
            return .success(.cancelTemporaryOverride)
        }  else if let bolusValue = notification["bolus-entry"] as? Double {
            return .success(.bolusEntry(bolusValue))
        } else if let carbsValue = notification["carbs-entry"] as? Double {

            let minAbsorptionTime = TimeInterval(hours: 0.5)
            let maxAbsorptionTime = LoopConstants.maxCarbAbsorptionTime
            
            var absorptionTime = defaultAbsorptionTime
            if let absorptionOverrideInHours = notification["absorption-time"] as? Double {
                absorptionTime = TimeInterval(hours: absorptionOverrideInHours)
            }
            
            if absorptionTime < minAbsorptionTime || absorptionTime > maxAbsorptionTime {
                return .failure(RemoteCommandParseError.invalidAbsorptionSeconds(absorptionTime))
            }
            
            let quantity = HKQuantity(unit: .gram(), doubleValue: carbsValue)
            
            var startDate = nowDate
            if let notificationStartTimeString = notification["start-time"] as? String {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions =  [.withInternetDateTime, .withFractionalSeconds]
                if let notificationStartDate = formatter.date(from: notificationStartTimeString) {
                    startDate = notificationStartDate
                } else {
                    return .failure(RemoteCommandParseError.invalidStartTime(notificationStartTimeString))
                }
            }

            let newEntry = NewCarbEntry(quantity: quantity, startDate: startDate, foodType: "", absorptionTime: absorptionTime)
            return .success(.carbsEntry(newEntry))
        } else {
            return .failure(RemoteCommandParseError.unhandledNotication("\(notification)"))
        }
    }
    
    enum RemoteCommandParseError: LocalizedError {
        case invalidStartTime(String)
        case invalidAbsorptionSeconds(Double)
        case unhandledNotication(String)
    }
}
