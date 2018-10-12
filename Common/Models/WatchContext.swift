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


final class WatchContext: NSObject, RawRepresentable {
    typealias RawValue = [String: Any]

    private static let version = 4
    static let name = "WatchContext"

    let creationDate: Date

    var preferredGlucoseUnit: HKUnit?

    var glucose: HKQuantity?
    var glucoseTrendRawValue: Int?
    var glucoseDate: Date?

    var predictedGlucose: WatchPredictedGlucose?
    var eventualGlucose: HKQuantity? {
        return predictedGlucose?.values.last?.quantity
    }

    var loopLastRunDate: Date?
    var lastNetTempBasalDose: Double?
    var lastNetTempBasalDate: Date?
    var recommendedBolusDose: Double?

    var bolusSuggestion: BolusSuggestionUserInfo? {
        guard let recommended = recommendedBolusDose else { return nil }

        return BolusSuggestionUserInfo(recommendedBolus: recommended)
    }

    var cob: Double?
    var iob: Double?
    var reservoir: Double?
    var reservoirPercentage: Double?
    var batteryPercentage: Double?

    var cgmManagerState: CGMManager.RawStateValue?

    init(creationDate: Date = Date()) {
        self.creationDate = creationDate
    }

    required init?(rawValue: RawValue) {
        guard
            rawValue["v"] as? Int == WatchContext.version,
            rawValue["name"] as? String == WatchContext.name,
            let creationDate = rawValue["cd"] as? Date
        else {
            return nil
        }

        self.creationDate = creationDate
        super.init()

        if let unitString = rawValue["gu"] as? String {
            preferredGlucoseUnit = HKUnit(from: unitString)
        }
        let unit = preferredGlucoseUnit ?? .milligramsPerDeciliter
        if let glucoseValue = rawValue["gv"] as? Double {
            glucose = HKQuantity(unit: unit, doubleValue: glucoseValue)
        }

        glucoseTrendRawValue = rawValue["gt"] as? Int
        glucoseDate = rawValue["gd"] as? Date
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
            "v": WatchContext.version,
            "name": WatchContext.name,
            "cd": creationDate
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
        raw["iob"] = iob
        raw["ld"] = loopLastRunDate
        raw["r"] = reservoir
        raw["rbo"] = recommendedBolusDose
        raw["rp"] = reservoirPercentage

        raw["pg"] = predictedGlucose?.rawValue

        return raw
    }

    override var debugDescription: String {
        return """
        \(WatchContext.self)
        * creationDate: \(creationDate)
        * preferredGlucoseUnit: \(String(describing: preferredGlucoseUnit))
        * glucose: \(String(describing: glucose))
        * glucoseDate: \(String(describing: glucoseDate))
        * predictedGlucose: \(String(describing: predictedGlucose))
        * loopLastRunDate: \(String(describing: loopLastRunDate))
        * lastNetTempBasalDose: \(String(describing: lastNetTempBasalDose))
        * lastNetTempBasalDate: \(String(describing: lastNetTempBasalDate))
        * recommendedBolusDose: \(String(describing: recommendedBolusDose))
        * cob: \(String(describing: cob))
        * iob: \(String(describing: iob))
        * reservoir: \(String(describing: reservoir))
        * reservoirPercentage: \(String(describing: reservoirPercentage))
        * batteryPercentage: \(String(describing: batteryPercentage))
        * cgmManagerState: \(String(describing: cgmManagerState))
        """
    }
}


extension WatchContext {
    func shouldReplace(_ other: WatchContext) -> Bool {
        return creationDate >= other.creationDate
    }
}
