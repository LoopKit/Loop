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

struct GlucoseDisplayableContext: GlucoseDisplayable {
    let isStateValid: Bool
    let stateDescription: String
    let trendType: GlucoseTrend?
    let trendRate: HKQuantity?
    let isLocal: Bool
    let glucoseRangeCategory: GlucoseRangeCategory?
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

struct DeviceStatusHighlightContext: DeviceStatusHighlight {
    var localizedMessage: String
    var imageName: String
    var state: DeviceStatusHighlightState
    
    init(localizedMessage: String,
         imageName: String,
         state: DeviceStatusHighlightState)
    {
        self.localizedMessage = localizedMessage
        self.imageName = imageName
        self.state = state
    }
    
    init?(from deviceStatusHighlight: DeviceStatusHighlight?) {
        guard let deviceStatusHighlight = deviceStatusHighlight else {
            return nil
        }
        
        self.init(localizedMessage: deviceStatusHighlight.localizedMessage,
                  imageName: deviceStatusHighlight.imageName,
                  state: deviceStatusHighlight.state)
    }
}

struct DeviceLifecycleProgressContext: DeviceLifecycleProgress {
    var percentComplete: Double
    var progressState: DeviceLifecycleProgressState
    
    init(percentComplete: Double,
         progressState: DeviceLifecycleProgressState)
    {
        self.percentComplete = percentComplete
        self.progressState = progressState
    }
    
    init?(from deviceLifecycleProgress: DeviceLifecycleProgress?) {
        guard let deviceLifecycleProgress = deviceLifecycleProgress else {
            return nil
        }
        
        self.init(percentComplete: deviceLifecycleProgress.percentComplete,
                  progressState: deviceLifecycleProgress.progressState)
    }
}

extension NetBasalContext: RawRepresentable {
    typealias RawValue = [String: Any]

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
    
    var rawValue: RawValue {
        var value: RawValue = [
            "rate": rate,
            "percentage": percentage,
            "start": start
        ]
        value["end"] = end
        return value
    }
}

extension GlucoseDisplayableContext: RawRepresentable {
    typealias RawValue = [String: Any]

    init(_ other: GlucoseDisplayable) {
        isStateValid = other.isStateValid
        stateDescription = other.stateDescription
        isLocal = other.isLocal
        trendType = other.trendType
        trendRate = other.trendRate
        glucoseRangeCategory = other.glucoseRangeCategory
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
        
        if let trendRateUnit = rawValue["trendRateUnit"] as? String, let trendRateValue = rawValue["trendRateValue"] as? Double {
            trendRate = HKQuantity(unit: HKUnit(from: trendRateUnit), doubleValue: trendRateValue)
        } else {
            trendRate = nil
        }

        if let glucoseRangeCategoryRawValue = rawValue["glucoseRangeCategory"] as? GlucoseRangeCategory.RawValue {
            glucoseRangeCategory = GlucoseRangeCategory(rawValue: glucoseRangeCategoryRawValue)
        } else {
            glucoseRangeCategory = nil
        }
    }
    
    var rawValue: RawValue {
        var raw: RawValue = [
            "isStateValid": isStateValid,
            "stateDescription": stateDescription,
            "isLocal": isLocal
        ]
        raw["trendType"] = trendType?.rawValue
        if let trendRate = trendRate {
            raw["trendRateUnit"] = HKUnit.milligramsPerDeciliterPerMinute.unitString
            raw["trendRateValue"] = trendRate.doubleValue(for: HKUnit.milligramsPerDeciliterPerMinute)
        }
        raw["glucoseRangeCategory"] = glucoseRangeCategory?.rawValue

        return raw
    }
}

extension PredictedGlucoseContext: RawRepresentable {
    typealias RawValue = [String: Any]

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
    
    var rawValue: RawValue {
        return [
            "values": values,
            "unit": unit.unitString,
            "startDate": startDate,
            "interval": interval
        ]
    }
}

extension DeviceStatusHighlightContext: RawRepresentable {
    typealias RawValue = [String: Any]

    init?(rawValue: RawValue) {
        guard let localizedMessage = rawValue["localizedMessage"] as? String,
            let imageName = rawValue["imageName"] as? String,
            let rawState = rawValue["state"] as? DeviceStatusHighlightState.RawValue,
            let state = DeviceStatusHighlightState(rawValue: rawState) else
        {
            return nil
        }

        self.localizedMessage = localizedMessage
        self.imageName = imageName
        self.state = state
    }
    
    var rawValue: RawValue {
        return [
            "localizedMessage": localizedMessage,
            "imageName": imageName,
            "state": state.rawValue,
        ]
    }
}

extension DeviceLifecycleProgressContext: RawRepresentable {
    typealias RawValue = [String: Any]

    init?(rawValue: RawValue) {
        guard let percentComplete = rawValue["percentComplete"] as? Double,
            let rawProgressState = rawValue["progressState"] as? DeviceLifecycleProgressState.RawValue,
            let progressState = DeviceLifecycleProgressState(rawValue: rawProgressState) else
        {
            return nil
        }

        self.percentComplete = percentComplete
        self.progressState = progressState
    }
    
    var rawValue: RawValue {
        return [
            "percentComplete": percentComplete,
            "progressState": progressState.rawValue,
        ]
    }
}

struct PumpManagerHUDViewContext: RawRepresentable {
    typealias RawValue = [String: Any]

    let pumpManagerHUDViewRawValue: PumpManagerHUDViewRawValue

    init(pumpManagerHUDViewRawValue: PumpManagerHUDViewRawValue) {
        self.pumpManagerHUDViewRawValue = pumpManagerHUDViewRawValue
    }
    
    init?(rawValue: RawValue) {
        if let pumpManagerHUDViewRawValue = rawValue["pumpManagerHUDViewRawValue"] as? PumpManagerHUDViewRawValue {
            self.pumpManagerHUDViewRawValue = pumpManagerHUDViewRawValue
        } else {
            return nil
        }
    }
    
    var rawValue: RawValue {
        return ["pumpManagerHUDViewRawValue": pumpManagerHUDViewRawValue]
    }
}

struct StatusExtensionContext: RawRepresentable {
    typealias RawValue = [String: Any]
    private let version = 5

    var predictedGlucose: PredictedGlucoseContext?
    var lastLoopCompleted: Date?
    var createdAt: Date?
    var isClosedLoop: Bool?
    var netBasal: NetBasalContext?
    var batteryPercentage: Double?
    var reservoirCapacity: Double?
    var glucoseDisplay: GlucoseDisplayableContext?
    var pumpManagerHUDViewContext: PumpManagerHUDViewContext?
    var pumpStatusHighlightContext: DeviceStatusHighlightContext?
    var pumpLifecycleProgressContext: DeviceLifecycleProgressContext?
    var cgmStatusHighlightContext: DeviceStatusHighlightContext?
    var cgmLifecycleProgressContext: DeviceLifecycleProgressContext?
    var carbsOnBoard: Double?
    
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
        createdAt = rawValue["createdAt"] as? Date
        isClosedLoop = rawValue["isClosedLoop"] as? Bool
        batteryPercentage = rawValue["batteryPercentage"] as? Double
        reservoirCapacity = rawValue["reservoirCapacity"] as? Double
        carbsOnBoard = rawValue["carbsOnBoard"] as? Double

        if let rawValue = rawValue["glucoseDisplay"] as? GlucoseDisplayableContext.RawValue {
            glucoseDisplay = GlucoseDisplayableContext(rawValue: rawValue)
        }
        
        if let rawPumpManagerHUDViewContext = rawValue["pumpManagerHUDViewContext"] as? PumpManagerHUDViewContext.RawValue {
            pumpManagerHUDViewContext = PumpManagerHUDViewContext(rawValue: rawPumpManagerHUDViewContext)
        }
        
        if let rawPumpStatusHighlightContext = rawValue["pumpStatusHighlightContext"] as? DeviceStatusHighlightContext.RawValue {
            pumpStatusHighlightContext = DeviceStatusHighlightContext(rawValue: rawPumpStatusHighlightContext)
        }
        
        if let rawPumpLifecycleProgressContext = rawValue["pumpLifecycleProgressContext"] as? DeviceLifecycleProgressContext.RawValue {
            pumpLifecycleProgressContext = DeviceLifecycleProgressContext(rawValue: rawPumpLifecycleProgressContext)
        }
        
        if let rawCGMStatusHighlightContext = rawValue["cgmStatusHighlightContext"] as? DeviceStatusHighlightContext.RawValue {
            cgmStatusHighlightContext = DeviceStatusHighlightContext(rawValue: rawCGMStatusHighlightContext)
        }
        
        if let rawCGMLifecycleProgressContext = rawValue["cgmLifecycleProgressContext"] as? DeviceLifecycleProgressContext.RawValue {
            cgmLifecycleProgressContext = DeviceLifecycleProgressContext(rawValue: rawCGMLifecycleProgressContext)
        }
    }
    
    var rawValue: RawValue {
        var raw: RawValue = [
            "version": version
        ]

        raw["predictedGlucose"] = predictedGlucose?.rawValue
        raw["lastLoopCompleted"] = lastLoopCompleted
        raw["createdAt"] = createdAt
        raw["isClosedLoop"] = isClosedLoop
        raw["netBasal"] = netBasal?.rawValue
        raw["batteryPercentage"] = batteryPercentage
        raw["reservoirCapacity"] = reservoirCapacity
        raw["glucoseDisplay"] = glucoseDisplay?.rawValue
        raw["pumpManagerHUDViewContext"] = pumpManagerHUDViewContext?.rawValue
        raw["pumpStatusHighlightContext"] = pumpStatusHighlightContext?.rawValue
        raw["pumpLifecycleProgressContext"] = pumpLifecycleProgressContext?.rawValue
        raw["cgmStatusHighlightContext"] = cgmStatusHighlightContext?.rawValue
        raw["cgmLifecycleProgressContext"] = cgmLifecycleProgressContext?.rawValue
        raw["carbsOnBoard"] = carbsOnBoard
        
        return raw
    }
}


extension StatusExtensionContext: CustomDebugStringConvertible {
    var debugDescription: String {
        return String(reflecting: rawValue)
    }
}
