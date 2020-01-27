//
//  WatchContext.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 11/25/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

import Foundation
import HealthKit
import LoopKit


final class WatchContext: RawRepresentable {
    typealias RawValue = [String: Any]

    private let version = 4

    var preferredGlucoseUnit: HKUnit?

    var glucose: HKQuantity?
    var glucoseTrendRawValue: Int?
    var glucoseDate: Date?
    var glucoseSyncIdentifier: String?

    var predictedGlucose: WatchPredictedGlucose?
    var eventualGlucose: HKQuantity? {
        return predictedGlucose?.values.last?.quantity
    }

    var loopLastRunDate: Date?
    var lastNetTempBasalDose: Double?
    var lastNetTempBasalDate: Date?
    var recommendedBolusDose: Double?

    var cob: Double?
    var iob: Double?
    var reservoir: Double?
    var reservoirPercentage: Double?
    var batteryPercentage: Double?

    var cgmManagerState: CGMManager.RawStateValue?

    init() {}

    required init?(rawValue: RawValue) {
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

        glucoseTrendRawValue = rawValue["gt"] as? Int
        glucoseDate = rawValue["gd"] as? Date
        glucoseSyncIdentifier = rawValue["gs"] as? String
        iob = rawValue["iob"] as? Double
        reservoir = rawValue["r"] as? Double
        reservoirPercentage = rawValue["rp"] as? Double
        batteryPercentage = rawValue["bp"] as? Double

        loopLastRunDate = rawValue["ld"] as? Date
        lastNetTempBasalDose = rawValue["ba"] as? Double
        lastNetTempBasalDate = rawValue["bad"] as? Date
        recommendedBolusDose = rawValue["rbo"] as? Double
        cob = rawValue["cob"] as? Double

        cgmManagerState = rawValue["cgmManagerState"] as? CGMManager.RawStateValue

        if let rawValue = rawValue["pg"] as? WatchPredictedGlucose.RawValue {
            predictedGlucose = WatchPredictedGlucose(rawValue: rawValue)
        }
    }

    var rawValue: RawValue {
        var raw: [String: Any] = [
            "v": version
        ]

        raw["ba"] = lastNetTempBasalDose
        raw["bad"] = lastNetTempBasalDate
        raw["bp"] = batteryPercentage

        raw["cgmManagerState"] = cgmManagerState

        raw["cob"] = cob

        let unit = preferredGlucoseUnit ?? .milligramsPerDeciliter
        raw["gu"] = preferredGlucoseUnit?.unitString
        raw["gv"] = glucose?.doubleValue(for: unit)

        raw["gt"] = glucoseTrendRawValue
        raw["gd"] = glucoseDate
        raw["gs"] = glucoseSyncIdentifier
        raw["iob"] = iob
        raw["ld"] = loopLastRunDate
        raw["r"] = reservoir
        raw["rbo"] = recommendedBolusDose
        raw["rp"] = reservoirPercentage

        raw["pg"] = predictedGlucose?.rawValue

        return raw
    }
}


extension WatchContext {
    func shouldReplace(_ other: WatchContext) -> Bool {
        if let date = self.glucoseDate, let otherDate = other.glucoseDate {
            return date >= otherDate
        } else {
            return true
        }
    }
}

extension WatchContext {
    var newGlucoseSample: NewGlucoseSample? {
        if let quantity = glucose, let date = glucoseDate, let syncIdentifier = glucoseSyncIdentifier {
            return NewGlucoseSample(date: date, quantity: quantity, isDisplayOnly: false, syncIdentifier: syncIdentifier, syncVersion: 0)
        }
        return nil
    }
}
