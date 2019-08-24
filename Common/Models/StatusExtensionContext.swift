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
import LoopKitUI


struct NetBasalContext {
    let rate: Double
    let percentage: Double
    let start: Date
    let end: Date?
}

struct SensorDisplayableContext: SensorDisplayable {
    let isStateValid: Bool
    let stateDescription: String
    let trendType: GlucoseTrend?
    let isLocal: Bool
}

struct GlucoseContext: GlucoseValue {
    let value: Double
    let unit: HKUnit
    let startDate: Date

    var quantity: HKQuantity {
        return HKQuantity(unit: unit, doubleValue: value)
    }
}

struct PredictedGlucoseContext {
    let values: [Double]
    let unit: HKUnit
    let startDate: Date
    let interval: TimeInterval

    var samples: [GlucoseContext] {
        var result: [GlucoseContext] = []
        for (i, v) in values.enumerated() {
            result.append(GlucoseContext(value: v, unit: unit, startDate: startDate.addingTimeInterval(Double(i) * interval)))
        }
        return result
    }
}

extension NetBasalContext: RawRepresentable {
    typealias RawValue = [String: Any]

    var rawValue: RawValue {
        var value: RawValue = [
            "rate": rate,
            "percentage": percentage,
            "start": start
        ]
        value["end"] = end
        return value
    }

    init?(rawValue: RawValue) {
        guard
            let rate       = rawValue["rate"] as? Double,
            let percentage = rawValue["percentage"] as? Double,
            let start      = rawValue["start"] as? Date
        else {
            return nil
        }

        self.rate = rate
        self.percentage = percentage
        self.start = start
        self.end = rawValue["end"] as? Date
    }
}

extension SensorDisplayableContext: RawRepresentable {
    typealias RawValue = [String: Any]

    var rawValue: RawValue {
        var raw: RawValue = [
            "isStateValid": isStateValid,
            "stateDescription": stateDescription,
            "isLocal": isLocal
        ]
        raw["trendType"] = trendType?.rawValue

        return raw
    }

    init(_ other: SensorDisplayable) {
        isStateValid = other.isStateValid
        stateDescription = other.stateDescription
        isLocal = other.isLocal
        trendType = other.trendType
    }

    init?(rawValue: RawValue) {
        guard
            let isStateValid     = rawValue["isStateValid"] as? Bool,
            let stateDescription = rawValue["stateDescription"] as? String,
            let isLocal          = rawValue["isLocal"] as? Bool
        else {
            return nil
        }

        self.isStateValid = isStateValid
        self.stateDescription = stateDescription
        self.isLocal = isLocal

        if let rawValue = rawValue["trendType"] as? GlucoseTrend.RawValue {
            trendType = GlucoseTrend(rawValue: rawValue)
        } else {
            trendType = nil
        }
    }
}

extension PredictedGlucoseContext: RawRepresentable {
    typealias RawValue = [String: Any]

    var rawValue: RawValue {
        return [
            "values": values,
            "unit": unit.unitString,
            "startDate": startDate,
            "interval": interval
        ]
    }

    init?(rawValue: RawValue) {
        guard
            let values = rawValue["values"] as? [Double],
            let unitString = rawValue["unit"] as? String,
            let startDate = rawValue["startDate"] as? Date,
            let interval = rawValue["interval"] as? TimeInterval
        else {
            return nil
        }

        self.values = values
        self.unit = HKUnit(from: unitString)
        self.startDate = startDate
        self.interval = interval
    }
}

struct PumpManagerHUDViewsContext: RawRepresentable {
    typealias RawValue = [String: Any]

    let pumpManagerHUDViewsRawValue: PumpManagerHUDViewsRawValue

    init(pumpManagerHUDViewsRawValue: PumpManagerHUDViewsRawValue) {
        self.pumpManagerHUDViewsRawValue = pumpManagerHUDViewsRawValue
    }
    
    init?(rawValue: RawValue) {
        if let pumpManagerHUDViewsRawValue = rawValue["pumpManagerHUDViewsRawValue"] as? PumpManagerHUDViewsRawValue {
            self.pumpManagerHUDViewsRawValue = pumpManagerHUDViewsRawValue
        } else {
            return nil
        }
    }
    
    var rawValue: RawValue {
        return ["pumpManagerHUDViewsRawValue": pumpManagerHUDViewsRawValue]
    }
}

struct StatusExtensionContext: RawRepresentable {
    typealias RawValue = [String: Any]
    private let version = 5

    var predictedGlucose: PredictedGlucoseContext?
    var lastLoopCompleted: Date?
    var netBasal: NetBasalContext?
    var batteryPercentage: Double?
    var reservoirCapacity: Double?
    var sensor: SensorDisplayableContext?
    var pumpManagerHUDViewsContext: PumpManagerHUDViewsContext?
    
    init() { }
    
    init?(rawValue: RawValue) {
        guard let version = rawValue["version"] as? Int, version == self.version else {
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
        reservoirCapacity = rawValue["reservoirCapacity"] as? Double

        if let rawValue = rawValue["sensor"] as? SensorDisplayableContext.RawValue {
            sensor = SensorDisplayableContext(rawValue: rawValue)
        }
        
        if let rawPumpManagerHUDViewsContext = rawValue["pumpManagerHUDViewsContext"] as? PumpManagerHUDViewsContext.RawValue {
            pumpManagerHUDViewsContext = PumpManagerHUDViewsContext(rawValue: rawPumpManagerHUDViewsContext)
        }
    }
    
    var rawValue: RawValue {
        var raw: RawValue = [
            "version": version
        ]

        raw["predictedGlucose"] = predictedGlucose?.rawValue
        raw["lastLoopCompleted"] = lastLoopCompleted
        raw["netBasal"] = netBasal?.rawValue
        raw["batteryPercentage"] = batteryPercentage
        raw["reservoirCapacity"] = reservoirCapacity
        raw["sensor"] = sensor?.rawValue
        raw["pumpManagerHUDViewsContext"] = pumpManagerHUDViewsContext?.rawValue
        
        return raw
    }
}


extension StatusExtensionContext: CustomDebugStringConvertible {
    var debugDescription: String {
        return String(reflecting: rawValue)
    }
}
