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
    let sensor: SensorDisplayableContext?

    var quantity: HKQuantity {
        return HKQuantity(unit: unit, doubleValue: value)
    }
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
        var raw: RawValue = [
            "value": value,
            "unit": unit.unitString,
            "startDate": startDate
        ]
        raw["sensor"] = sensor?.rawValue

        return raw
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

        if let rawValue = rawValue["sensor"] as? SensorDisplayableContext.RawValue {
            self.sensor = SensorDisplayableContext(rawValue: rawValue)
        } else {
            self.sensor = nil
        }
    }
}

struct StatusExtensionContext: RawRepresentable {
    typealias RawValue = [String: Any]
    private let version = 2

    var latestGlucose: GlucoseContext?
    var reservoir: ReservoirContext?
    var loop: LoopContext?
    var netBasal: NetBasalContext?
    var batteryPercentage: Double?
    var eventualGlucose: GlucoseContext?
    
    init() { }
    
    init?(rawValue: RawValue) {
        guard let version = rawValue["version"] as? Int, version == self.version else {
            return nil
        }

        if let rawValue = rawValue["latestGlucose"] as? GlucoseContext.RawValue {
            latestGlucose = GlucoseContext(rawValue: rawValue)
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

        if let rawValue = rawValue["eventualGlucose"] as? GlucoseContext.RawValue {
            eventualGlucose = GlucoseContext(rawValue: rawValue)
        }
    }
    
    var rawValue: RawValue {
        var raw: RawValue = [
            "version": version
        ]
        raw["latestGlucose"] = latestGlucose?.rawValue
        raw["reservoir"] = reservoir?.rawValue
        raw["loop"] = loop?.rawValue
        raw["netBasal"] = netBasal?.rawValue
        raw["batteryPercentage"] = batteryPercentage
        raw["eventualGlucose"] = eventualGlucose?.rawValue
        return raw
    }
}


extension StatusExtensionContext: CustomDebugStringConvertible {
    var debugDescription: String {
        return String(reflecting: rawValue)
    }
}
