//
//  LoopSettings.swift
//  Loop
//
//  Copyright © 2017 LoopKit Authors. All rights reserved.
//

import LoopKit
import CarbKit


struct LoopSettings {
    var dosingEnabled = false

    var defaultAbsorptionTimes: CarbStore.DefaultAbsorptionTimes = (
        fast: TimeInterval(hours: 2),
        medium: TimeInterval(hours: 3),
        slow: TimeInterval(hours: 4)
    )

    var glucoseTargetRangeSchedule: GlucoseRangeSchedule?

    var maximumBasalRatePerHour: Double?

    var maximumBolus: Double?

    var minimumBGGuard: GlucoseThreshold? = nil

    var retrospectiveCorrectionEnabled = false

}


extension LoopSettings {
    var enabledEffects: PredictionInputEffect {
        var inputs = PredictionInputEffect.all
        if !retrospectiveCorrectionEnabled {
            inputs.remove(.retrospection)
        }
        return inputs
    }
}


extension LoopSettings: RawRepresentable {
    typealias RawValue = [String: Any]
    private static let version = 1

    init?(rawValue: RawValue) {
        guard
            let version = rawValue["version"] as? Int,
            version == LoopSettings.version
        else {
            return nil
        }

        if let dosingEnabled = rawValue["dosingEnabled"] as? Bool {
            self.dosingEnabled = dosingEnabled
        }

        if let defaultAbsorptionTimesDict = rawValue["defaultAbsorptionTimes"] as? [String : TimeInterval] {
            self.defaultAbsorptionTimes = (fast: defaultAbsorptionTimesDict["fast"],
                                           medium: defaultAbsorptionTimesDict["medium"],
                                           slow: defaultAbsorptionTimesDict["slow"]) as! CarbStore.DefaultAbsorptionTimes
        }

        if let rawValue = rawValue["glucoseTargetRangeSchedule"] as? GlucoseRangeSchedule.RawValue {
            self.glucoseTargetRangeSchedule = GlucoseRangeSchedule(rawValue: rawValue)
        }

        self.maximumBasalRatePerHour = rawValue["maximumBasalRatePerHour"] as? Double

        self.maximumBolus = rawValue["maximumBolus"] as? Double

        if let rawThreshold = rawValue["minimumBGGuard"] as? GlucoseThreshold.RawValue {
            self.minimumBGGuard = GlucoseThreshold(rawValue: rawThreshold)
        }

        if let retrospectiveCorrectionEnabled = rawValue["retrospectiveCorrectionEnabled"] as? Bool {
            self.retrospectiveCorrectionEnabled = retrospectiveCorrectionEnabled
        }
    }

    var rawValue: RawValue {
        var raw: RawValue = [
            "version": LoopSettings.version,
            "dosingEnabled": dosingEnabled,
            "retrospectiveCorrectionEnabled": retrospectiveCorrectionEnabled
        ]

        raw["defaultAbsorptionTimes"] = [
            "fast": defaultAbsorptionTimes.fast,
            "medium": defaultAbsorptionTimes.medium,
            "slow": defaultAbsorptionTimes.slow,
        ]
        
        raw["glucoseTargetRangeSchedule"] = glucoseTargetRangeSchedule?.rawValue
        raw["maximumBasalRatePerHour"] = maximumBasalRatePerHour
        raw["maximumBolus"] = maximumBolus
        raw["minimumBGGuard"] = minimumBGGuard?.rawValue

        return raw
    }
}
