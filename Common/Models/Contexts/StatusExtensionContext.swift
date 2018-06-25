//
//  StatusExtensionContext.swift
//  Loop Status Extension
//
//  Created by Bharat Mediratta on 11/25/16.
//  Copyright © 2016 LoopKit Authors. All rights reserved.
//
//  This class allows Loop to pass context data to the Loop Status Extension.

import Foundation
import HealthKit
import LoopKit


struct StatusExtensionContext: RawRepresentable {
    var predictedGlucose: PredictedGlucoseContext?
    var lastLoopCompleted: Date?
    var netBasal: NetBasalContext?
    var batteryPercentage: Double?
    var sensor: SensorDisplayableContext?
}


extension StatusExtensionContext {
    typealias RawValue = [String: Any]
    static let version = 4

    init?(rawValue: RawValue) {
        guard let version = rawValue["version"] as? Int, version == type(of: self).version else {
            return nil
        }

        if let rawValue = rawValue["predictedGlucose"] as? PredictedGlucoseContext.RawValue {
            predictedGlucose = PredictedGlucoseContext(rawValue: rawValue)
        }

        if let rawValue = rawValue["netBasal"] as? NetBasalContext.RawValue {
            netBasal = NetBasalContext(rawValue: rawValue)
        }

        lastLoopCompleted = rawValue["lastLoopCompleted"] as? Date
        batteryPercentage = rawValue["batteryPercentage"] as? Double

        if let rawValue = rawValue["sensor"] as? SensorDisplayableContext.RawValue {
            sensor = SensorDisplayableContext(rawValue: rawValue)
        }
    }
    
    var rawValue: RawValue {
        var raw: RawValue = [
            "version": type(of: self).version
        ]

        raw["predictedGlucose"] = predictedGlucose?.rawValue
        raw["lastLoopCompleted"] = lastLoopCompleted
        raw["netBasal"] = netBasal?.rawValue
        raw["batteryPercentage"] = batteryPercentage
        raw["sensor"] = sensor?.rawValue
        return raw
    }
}

extension StatusExtensionContext: CustomDebugStringConvertible {
    var debugDescription: String {
        return String(reflecting: rawValue)
    }
}
