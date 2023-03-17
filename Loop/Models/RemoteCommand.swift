//
//  RemoteCommand.swift
//  Loop
//
//  Created by Pete Schwamb on 9/16/19.
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit

// Push Notifications
struct RemoteCommand {
    static func createRemoteAction(notification: [String: Any]) -> Result<Action, RemoteCommandParseError> {
        if let overrideName = notification["override-name"] as? String,
            let remoteAddress = notification["remote-address"] as? String
        {
            var overrideTime: TimeInterval? = nil
            if let overrideDurationMinutes = notification["override-duration-minutes"] as? Double {
                overrideTime = TimeInterval(minutes: overrideDurationMinutes)
            }
            return .success(.temporaryScheduleOverride(OverrideAction(name: overrideName, durationTime: overrideTime, remoteAddress: remoteAddress)))
        } else if let _ = notification["cancel-temporary-override"] as? String,
                  let remoteAddress = notification["remote-address"] as? String
        {
            return .success(.cancelTemporaryOverride(OverrideCancelAction(remoteAddress: remoteAddress)))
        }  else if let bolusValue = notification["bolus-entry"] as? Double {
            return .success(.bolusEntry(BolusAction(amountInUnits: bolusValue)))
        } else if let carbsValue = notification["carbs-entry"] as? Double {
            
            var absorptionTime: TimeInterval? = nil
            if let absorptionOverrideInHours = notification["absorption-time"] as? Double {
                absorptionTime = TimeInterval(hours: absorptionOverrideInHours)
            }
            
            var foodType = notification["food-type"] as? String ?? nil
            
            var startDate: Date? = nil
            if let notificationStartTimeString = notification["start-time"] as? String {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions =  [.withInternetDateTime, .withFractionalSeconds]
                if let notificationStartDate = formatter.date(from: notificationStartTimeString) {
                    startDate = notificationStartDate
                } else {
                    return .failure(RemoteCommandParseError.invalidStartTime(notificationStartTimeString))
                }
            }

            return .success(.carbsEntry(CarbAction(amountInGrams: carbsValue, absorptionTime: absorptionTime, foodType: foodType, startDate: startDate)))
        } else {
            return .failure(RemoteCommandParseError.unhandledNotication("\(notification)"))
        }
    }
    
    enum RemoteCommandParseError: LocalizedError {
        case invalidStartTime(String)
        case unhandledNotication(String)
    }
}
