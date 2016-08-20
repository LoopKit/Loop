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
    typealias RawValue = [String: AnyObject]

    private let version = 2

    var preferredGlucoseUnit: HKUnit?

    var glucose: HKQuantity?
    var glucoseTrend: GlucoseTrend?
    var eventualGlucose: HKQuantity?
    var glucoseDate: NSDate?

    var loopLastRunDate: NSDate?
    var lastNetTempBasalDose: Double?
    var lastNetTempBasalDate: NSDate?
    var recommendedBolusDose: Double?

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
            let unit = HKUnit(fromString: unitString)
            preferredGlucoseUnit = unit

            if let glucoseValue = rawValue["gv"] as? Double {
                glucose = HKQuantity(unit: unit, doubleValue: glucoseValue)
            }

            if let glucoseValue = rawValue["egv"] as? Double {
                eventualGlucose = HKQuantity(unit: unit, doubleValue: glucoseValue)
            }
        }

        if let rawTrend = rawValue["gt"] as? Int {
            glucoseTrend = GlucoseTrend(rawValue: rawTrend)
        }
        glucoseDate = rawValue["gd"] as? NSDate

        IOB = rawValue["iob"] as? Double
        reservoir = rawValue["r"] as? Double
        reservoirPercentage = rawValue["rp"] as? Double
        batteryPercentage = rawValue["bp"] as? Double

        loopLastRunDate = rawValue["ld"] as? NSDate
        lastNetTempBasalDose = rawValue["ba"] as? Double
        lastNetTempBasalDate = rawValue["bad"] as? NSDate
        recommendedBolusDose = rawValue["rbo"] as? Double
        COB = rawValue["cob"] as? Double
    }

    var rawValue: RawValue {
        var raw: [String: AnyObject] = [
            "v": version
        ]

        raw["ba"] = lastNetTempBasalDose
        raw["bad"] = lastNetTempBasalDate
        raw["bp"] = batteryPercentage
        raw["cob"] = COB

        if let unit = preferredGlucoseUnit {
            raw["egv"] = eventualGlucose?.doubleValueForUnit(unit)
            raw["gu"] = unit.unitString
            raw["gv"] = glucose?.doubleValueForUnit(unit)
        }

        raw["gt"] = glucoseTrend?.rawValue
        raw["gd"] = glucoseDate
        raw["iob"] = IOB
        raw["ld"] = loopLastRunDate
        raw["r"] = reservoir
        raw["rbo"] = recommendedBolusDose
        raw["rp"] = reservoirPercentage

        return raw
    }
}
