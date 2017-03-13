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

            if let glucoseValue = rawValue["gv"] as? Double {
                glucose = HKQuantity(unit: unit, doubleValue: glucoseValue)
            }

            if let glucoseValue = rawValue["egv"] as? Double {
                eventualGlucose = HKQuantity(unit: unit, doubleValue: glucoseValue)
            }
        }

        glucoseTrendRawValue = rawValue["gt"] as? Int
        glucoseDate = rawValue["gd"] as? Date

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
    }

    var rawValue: RawValue {
        var raw: [String: Any] = [
            "v": version
        ]

        raw["ba"] = lastNetTempBasalDose
        raw["bad"] = lastNetTempBasalDate
        raw["bp"] = batteryPercentage
        raw["cob"] = COB

        if let unit = preferredGlucoseUnit {
            raw["egv"] = eventualGlucose?.doubleValue(for: unit)
            raw["gu"] = unit.unitString
            raw["gv"] = glucose?.doubleValue(for: unit)
        }

        raw["gt"] = glucoseTrendRawValue
        raw["gd"] = glucoseDate
        raw["iob"] = IOB
        raw["ld"] = loopLastRunDate
        raw["mb"] = maxBolus
        raw["r"] = reservoir
        raw["rbo"] = recommendedBolusDose
        raw["rp"] = reservoirPercentage

        return raw
    }
}
