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
import LoopUI

struct ReservoirContext {
    let startDate: Date
    let unitVolume: Double
    let capacity: Int
}

struct LoopContext {
    let dosingEnabled: Bool
    let lastCompleted: Date?
}

struct NetBasalContext {
    let rate: Double
    let percentage: Double
    let startDate: Date
}

struct SensorDisplayableContext: SensorDisplayable {
    let isStateValid: Bool
    let stateDescription: String
    let trendType: GlucoseTrend?
    let isLocal: Bool
}

struct GlucoseContext {
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

struct DatedRangeContext {
    let startDate: Date
    let endDate: Date
    let minValue: Double
    let maxValue: Double
}

extension ReservoirContext: RawRepresentable {
    typealias RawValue = [String: Any]

    var rawValue: RawValue {
        return [
            "startDate": startDate,
            "unitVolume": unitVolume,
            "capacity": capacity
        ]
    }

    init?(rawValue: RawValue) {
        guard
            let startDate = rawValue["startDate"] as? Date,
            let unitVolume = rawValue["unitVolume"] as? Double,
            let capacity = rawValue["capacity"] as? Int
        else {
            return nil
        }

        self.startDate = startDate
        self.unitVolume = unitVolume
        self.capacity = capacity
    }
}

extension LoopContext: RawRepresentable {
    typealias RawValue = [String: Any]

    var rawValue: RawValue {
        var raw: RawValue = [
            "dosingEnabled": dosingEnabled
        ]
        raw["lastCompleted"] = lastCompleted
        return raw
    }

    init?(rawValue: RawValue) {
        guard let dosingEnabled = rawValue["dosingEnabled"] as? Bool
        else {
            return nil
        }

        self.dosingEnabled = dosingEnabled
        self.lastCompleted = rawValue["lastCompleted"] as? Date
    }
}

extension NetBasalContext: RawRepresentable {
    typealias RawValue = [String: Any]

    var rawValue: RawValue {
        return [
            "rate": rate,
            "percentage": percentage,
            "startDate": startDate
        ]
    }

    init?(rawValue: RawValue) {
        guard
            let rate       = rawValue["rate"] as? Double,
            let percentage = rawValue["percentage"] as? Double,
            let startDate  = rawValue["startDate"] as? Date
        else {
            return nil
        }

        self.rate = rate
        self.percentage = percentage
        self.startDate = startDate
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

extension GlucoseContext: RawRepresentable {
    typealias RawValue = [String: Any]

    var rawValue: RawValue {
        return [
            "value": value,
            "unit": unit.unitString,
            "startDate": startDate
        ]
    }

    init?(rawValue: RawValue) {
        guard
            let value = rawValue["value"] as? Double,
            let unitString = rawValue["unit"] as? String,
            let startDate = rawValue["startDate"] as? Date
        else {
            return nil
        }

        self.value = value
        self.unit = HKUnit(from: unitString)
        self.startDate = startDate
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

extension DatedRangeContext: RawRepresentable {
    typealias RawValue = [String: Any]

    var rawValue: RawValue {
        return [
            "startDate": startDate,
            "endDate": endDate,
            "minValue": minValue,
            "maxValue": maxValue
        ]
    }

    init?(rawValue: RawValue) {
        guard
            let startDate = rawValue["startDate"] as? Date,
            let endDate = rawValue["endDate"] as? Date,
            let minValue = rawValue["minValue"] as? Double,
            let maxValue = rawValue["maxValue"] as? Double
        else {
            return nil
        }

        self.startDate = startDate
        self.endDate = endDate
        self.minValue = minValue
        self.maxValue = maxValue
    }
}

struct StatusExtensionContext: RawRepresentable {
    typealias RawValue = [String: Any]
    private let version = 3

    var glucose: [GlucoseContext]?
    var predictedGlucose: PredictedGlucoseContext?
    var reservoir: ReservoirContext?
    var loop: LoopContext?
    var netBasal: NetBasalContext?
    var batteryPercentage: Double?
    var targetRanges: [DatedRangeContext]?
    var temporaryOverride: DatedRangeContext?
    var sensor: SensorDisplayableContext?
    
    init() { }
    
    init?(rawValue: RawValue) {
        guard let version = rawValue["version"] as? Int, version == self.version else {
            return nil
        }

        if let rawValue = rawValue["glucose"] as? [GlucoseContext.RawValue] {
            glucose = rawValue.flatMap({return GlucoseContext(rawValue: $0)})
        }

        if let rawValue = rawValue["predictedGlucose"] as? PredictedGlucoseContext.RawValue {
            predictedGlucose = PredictedGlucoseContext(rawValue: rawValue)
        }

        if let rawValue = rawValue["reservoir"] as? ReservoirContext.RawValue {
            reservoir = ReservoirContext(rawValue: rawValue)
        }

        if let rawValue = rawValue["loop"] as? LoopContext.RawValue {
            loop = LoopContext(rawValue: rawValue)
        }

        if let rawValue = rawValue["netBasal"] as? NetBasalContext.RawValue {
            netBasal = NetBasalContext(rawValue: rawValue)
        }

        batteryPercentage = rawValue["batteryPercentage"] as? Double

        if let rawValue = rawValue["targetRanges"] as? [DatedRangeContext.RawValue] {
            targetRanges = rawValue.flatMap({return DatedRangeContext(rawValue: $0)})
        }

        if let rawValue = rawValue["temporaryOverride"] as? DatedRangeContext.RawValue {
            temporaryOverride = DatedRangeContext(rawValue: rawValue)
        }

        if let rawValue = rawValue["sensor"] as? SensorDisplayableContext.RawValue {
            sensor = SensorDisplayableContext(rawValue: rawValue)
        }
    }
    
    var rawValue: RawValue {
        var raw: RawValue = [
            "version": version
        ]

        raw["glucose"] = glucose?.map({return $0.rawValue})
        raw["predictedGlucose"] = predictedGlucose?.rawValue
        raw["reservoir"] = reservoir?.rawValue
        raw["loop"] = loop?.rawValue
        raw["netBasal"] = netBasal?.rawValue
        raw["batteryPercentage"] = batteryPercentage
        raw["targetRanges"] = targetRanges?.map({return $0.rawValue})
        raw["temporaryOverride"] = temporaryOverride?.rawValue
        raw["sensor"] = sensor?.rawValue
        return raw
    }
}


extension StatusExtensionContext: CustomDebugStringConvertible {
    var debugDescription: String {
        return String(reflecting: rawValue)
    }
}
