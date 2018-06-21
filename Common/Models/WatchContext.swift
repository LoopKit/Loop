//
//  WatchContext.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 11/25/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

import Foundation
import HealthKit

struct WatchDatedRangeContext {
    public let startDate: Date
    public let endDate: Date
    public let minValue: Double
    public let maxValue: Double

    public init(startDate: Date, endDate: Date, minValue: Double, maxValue: Double) {
        self.startDate = startDate
        self.endDate = endDate
        self.minValue = minValue
        self.maxValue = maxValue
    }
}

struct WatchGlucoseContext {
    let value: Double
    let unit: HKUnit
    let startDate: Date

    var quantity: HKQuantity {
        return HKQuantity(unit: unit, doubleValue: value)
    }
}

struct WatchPredictedGlucoseContext {
    let values: [Double]
    let unit: HKUnit
    let startDate: Date
    let interval: TimeInterval

    var samples: [WatchGlucoseContext] {
        return values.enumerated().map { (i, v) in
            WatchGlucoseContext(value: v, unit: unit, startDate: startDate.addingTimeInterval(Double(i) * interval))
        }
    }
}

extension WatchDatedRangeContext: RawRepresentable {
    typealias RawValue = [String: Any]

    var rawValue: RawValue {
        return [
            "sd": startDate,
            "ed": endDate,
            "mi": minValue,
            "ma": maxValue
        ]
    }

    init?(rawValue: RawValue) {
        guard
            let startDate = rawValue["sd"] as? Date,
            let endDate = rawValue["ed"] as? Date,
            let minValue = rawValue["mi"] as? Double,
            let maxValue = rawValue["ma"] as? Double
            else {
                return nil
        }

        self.startDate = startDate
        self.endDate = endDate
        self.minValue = minValue
        self.maxValue = maxValue
    }
}

extension WatchGlucoseContext: RawRepresentable {
    typealias RawValue = [String: Any]

    var rawValue: RawValue {
        return [
            "v": value,
            "u": unit.unitString,
            "sd": startDate
        ]
    }

    init?(rawValue: RawValue) {
        guard
            let value = rawValue["v"] as? Double,
            let unitString = rawValue["u"] as? String,
            let startDate = rawValue["sd"] as? Date
            else {
                return nil
        }

        self.value = value
        self.unit = HKUnit(from: unitString)
        self.startDate = startDate
    }
}

extension WatchPredictedGlucoseContext: RawRepresentable {
    typealias RawValue = [String: Any]

    var rawValue: RawValue {
        return [
            "v": values,
            "u": unit.unitString,
            "sd": startDate,
            "i": interval
        ]
    }

    init?(rawValue: RawValue) {
        guard
            let values = rawValue["v"] as? [Double],
            let unitString = rawValue["u"] as? String,
            let startDate = rawValue["sd"] as? Date,
            let interval = rawValue["i"] as? TimeInterval
            else {
                return nil
        }

        self.values = values
        self.unit = HKUnit(from: unitString)
        self.startDate = startDate
        self.interval = interval
    }
}


final class WatchContext: NSObject, RawRepresentable {
    typealias RawValue = [String: Any]

    private let version = 4

    var preferredGlucoseUnit: HKUnit?
    var maxBolus: Double?

    var glucose: HKQuantity?
    var glucoseTrendRawValue: Int?
    var eventualGlucose: HKQuantity?
    var glucoseDate: Date?

    var targetRanges: [WatchDatedRangeContext]?
    var temporaryOverride: WatchDatedRangeContext?
    var glucoseRangeScheduleOverride: GlucoseRangeScheduleOverrideUserInfo?
    var configuredOverrideContexts: [GlucoseRangeScheduleOverrideUserInfo.Context] = []

    var loopLastRunDate: Date?
    var lastNetTempBasalDose: Double?
    var lastNetTempBasalDate: Date?
    var recommendedBolusDose: Double?

    var bolusSuggestion: BolusSuggestionUserInfo? {
        guard let recommended = recommendedBolusDose else { return nil }

        return BolusSuggestionUserInfo(recommendedBolus: recommended, maxBolus: maxBolus)
    }

    var COB: Double?
    var IOB: Double?
    var reservoir: Double?
    var reservoirPercentage: Double?
    var batteryPercentage: Double?
    var predictedGlucose: WatchPredictedGlucoseContext?

    override init() {
        super.init()
    }

    required init?(rawValue: RawValue) {
        super.init()

        guard rawValue["v"] as? Int == version else {
            return nil
        }

        if let unitString = rawValue["gu"] as? String {
            preferredGlucoseUnit = HKUnit(from: unitString)
        }
        let unit = preferredGlucoseUnit ?? .milligramsPerDeciliter
        if let glucoseValue = rawValue["gv"] as? Double {
            glucose = HKQuantity(unit: unit, doubleValue: glucoseValue)
        }

        if let glucoseValue = rawValue["egv"] as? Double {
            eventualGlucose = HKQuantity(unit: unit, doubleValue: glucoseValue)
        }

        glucoseTrendRawValue = rawValue["gt"] as? Int
        glucoseDate = rawValue["gd"] as? Date

        if let overrideUserInfoRawValue = rawValue["grsoc"] as? GlucoseRangeScheduleOverrideUserInfo.RawValue,
            let overrideUserInfo = GlucoseRangeScheduleOverrideUserInfo(rawValue: overrideUserInfoRawValue)
        {
            glucoseRangeScheduleOverride = overrideUserInfo
        }

        if let configuredOverrideContextsRawValues = rawValue["coc"] as? [GlucoseRangeScheduleOverrideUserInfo.Context.RawValue] {
            configuredOverrideContexts = configuredOverrideContextsRawValues.compactMap(GlucoseRangeScheduleOverrideUserInfo.Context.init(rawValue:))
        }

        IOB = rawValue["iob"] as? Double
        reservoir = rawValue["r"] as? Double
        reservoirPercentage = rawValue["rp"] as? Double
        batteryPercentage = rawValue["bp"] as? Double

        loopLastRunDate = rawValue["ld"] as? Date
        lastNetTempBasalDose = rawValue["ba"] as? Double
        lastNetTempBasalDate = rawValue["bad"] as? Date
        recommendedBolusDose = rawValue["rbo"] as? Double
        COB = rawValue["cob"] as? Double
        maxBolus = rawValue["mb"] as? Double

        if let rawValue = rawValue["pg"] as? WatchPredictedGlucoseContext.RawValue {
            predictedGlucose = WatchPredictedGlucoseContext(rawValue: rawValue)
        }

        if let rawValue = rawValue["tr"] as? [WatchDatedRangeContext.RawValue] {
            targetRanges = rawValue.compactMap({return WatchDatedRangeContext(rawValue: $0)})
        }

        if let rawValue = rawValue["to"] as? WatchDatedRangeContext.RawValue {
            temporaryOverride = WatchDatedRangeContext(rawValue: rawValue)
        }
    }

    var rawValue: RawValue {
        var raw: [String: Any] = [
            "v": version
        ]

        raw["ba"] = lastNetTempBasalDose
        raw["bad"] = lastNetTempBasalDate
        raw["bp"] = batteryPercentage
        raw["cob"] = COB

        let unit = preferredGlucoseUnit ?? .milligramsPerDeciliter
        raw["egv"] = eventualGlucose?.doubleValue(for: unit)
        raw["gu"] = preferredGlucoseUnit?.unitString
        raw["gv"] = glucose?.doubleValue(for: unit)

        raw["gt"] = glucoseTrendRawValue
        raw["gd"] = glucoseDate
        raw["grsoc"] = glucoseRangeScheduleOverride?.rawValue
        raw["coc"] = configuredOverrideContexts.map { $0.rawValue }
        raw["iob"] = IOB
        raw["ld"] = loopLastRunDate
        raw["mb"] = maxBolus
        raw["r"] = reservoir
        raw["rbo"] = recommendedBolusDose
        raw["rp"] = reservoirPercentage

        raw["pg"] = predictedGlucose?.rawValue

        raw["tr"] = targetRanges?.map { $0.rawValue }
        raw["to"] = temporaryOverride?.rawValue

        return raw
    }
}
