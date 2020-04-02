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

public enum RemoteCommandError: Error {
    case expired
}


enum RemoteCommand {
    typealias RawValue = [String: Any]

    case temporaryScheduleOverride(TemporaryScheduleOverride)
    case cancelTemporaryOverride
    case bolusEntry(Double)
     case carbsEntry(NewCarbEntry)
}


// Push Notifications
extension RemoteCommand {
    init?(notification: [String: Any], allowedPresets: [TemporaryScheduleOverridePreset], otp: String) {
        
        // check OTP
        func checkOTP() -> Bool {
           var retVal: Bool = false
            
           if let otpIn = notification["otp"] as? String {
               print("OTP:   \(otp)")
               print("OTPIn: \(otpIn)")
               if (otpIn.count == 6 && otp.count == 6) {
                  if( otpIn == otp ) {
                      retVal = true
                  }
               }
           } else {
               retVal = false
           }
        
           if(retVal) {
              print("OTP Check Passed")
           } else {
              print("OTP Check Failed")
           }
        
           return retVal
        }
        
        if let overrideEnactName = notification["override-name"] as? String,
            let preset = allowedPresets.first(where: { $0.name == overrideEnactName }),
            let remoteAddress = notification["remote-address"] as? String
        {
            var override = preset.createOverride(enactTrigger: .remote(remoteAddress))
            if let overrideDurationMinutes = notification["override-duration-minutes"] as? Double {
                override.duration = .finite(TimeInterval(minutes: overrideDurationMinutes))
            }
            self = .temporaryScheduleOverride(override)
        } else if let _ = notification["cancel-temporary-override"] as? String {
            self = .cancelTemporaryOverride
        }  else if let bolusValue = notification["bolus-entry"] as? Double {
            if !checkOTP() { return nil }
            self = .bolusEntry(bolusValue)
        } else if let carbsValue = notification["carbs-entry"] as? Double {
            if !checkOTP() { return nil }
            // TODO: get default absorption value
            var absorptionTime = TimeInterval(hours: 3.0)
            if let absorptionOverride = notification["absorption-time"] as? Double {
                absorptionTime = TimeInterval(hours: absorptionOverride)
            }
            let quantity = HKQuantity(unit: .gram(), doubleValue: carbsValue)
            let newEntry = NewCarbEntry(quantity: quantity, startDate: Date(), foodType: "", absorptionTime: absorptionTime)
            self = .carbsEntry(newEntry)
        }
        else {
            return nil
        }
    }
}
