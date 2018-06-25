//
//  WatchContext.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 11/25/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

import Foundation
import HealthKit

final class WatchContext: NSObject, RawRepresentable {
    typealias RawValue = [String: Any]

    private let version = 3

    var preferredGlucoseUnit: HKUnit?
    var maxBolus: Double?

    var glucose: HKQuantity?
    var glucoseTrendRawValue: Int?
    var eventualGlucose: HKQuantity?
    var glucoseDate: Date?

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

    var cgm: CGM?

    override init() {
        super.init()
    }

    required init?(rawValue: RawValue) {
        super.init()

        guard rawValue["v"] as? Int == version else {
            return nil
        }

        if let unitString = rawValue["gu"] as? String {
            let unit = HKUnit(from: unitString)
            preferredGlucoseUnit = unit
        }

        if let glucoseValue = rawValue["gv"] as? Double {
            glucose = HKQuantity(unit: preferredGlucoseUnit ?? .milligramsPerDeciliter, doubleValue: glucoseValue)
        }

        if let glucoseValue = rawValue["egv"] as? Double {
            eventualGlucose = HKQuantity(unit: preferredGlucoseUnit ?? .milligramsPerDeciliter, doubleValue: glucoseValue)
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

        if let cgmRawValue = rawValue["cgm"] as? CGM.RawValue {
            cgm = CGM(rawValue: cgmRawValue)
        }
    }

    var rawValue: RawValue {
        var raw: [String: Any] = [
            "v": version
        ]

        raw["ba"] = lastNetTempBasalDose
        raw["bad"] = lastNetTempBasalDate
        raw["bp"] = batteryPercentage

        raw["cgm"] = cgm?.rawValue

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

        return raw
    }
}
