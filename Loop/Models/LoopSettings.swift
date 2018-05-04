//
//  LoopSettings.swift
//  Loop
//
//  Copyright © 2017 LoopKit Authors. All rights reserved.
//

import LoopKit
import RileyLinkBLEKit


struct LoopSettings {
    var dosingEnabled = false

    var bolusEnabled = false
    
    let dynamicCarbAbsorptionEnabled = true

    var glucoseTargetRangeSchedule: GlucoseRangeSchedule?

    var maximumBasalRatePerHour: Double?

    var maximumBolus: Double?
    
    var maximumInsulinOnBoard: Double?

    var suspendThreshold: GlucoseThreshold? = nil

    var retrospectiveCorrectionEnabled = true
    
    // Not configurable through UI
    let automatedBolusThreshold: Double = 0.2
    let automatedBolusRatio: Double = 0.7
    let automaticBolusInterval: TimeInterval = TimeInterval(minutes: 3)
    let absorptionRate: Double = 20
    
    let minimumRecommendedBolus: Double = 0.2
    let insulinIncrementPerUnit: Double = 10  // 0.1 steps in basal and bolus
    
    let absorptionTimeOverrun = 1.0

}


// MARK: - Static configuration
extension LoopSettings {
    static let idleListeningEnabledDefaults: RileyLinkDevice.IdleListeningState = .enabled(timeout: .minutes(4), channel: 0)
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
        
        if let bolusEnabled = rawValue["bolusEnabled"] as? Bool {
            self.bolusEnabled = bolusEnabled
        }

        if let rawValue = rawValue["glucoseTargetRangeSchedule"] as? GlucoseRangeSchedule.RawValue {
            self.glucoseTargetRangeSchedule = GlucoseRangeSchedule(rawValue: rawValue)
        }

        self.maximumBasalRatePerHour = rawValue["maximumBasalRatePerHour"] as? Double

        self.maximumInsulinOnBoard = rawValue["maximumInsulinOnBoard"] as? Double
        self.maximumBolus = rawValue["maximumBolus"] as? Double

        if let rawThreshold = rawValue["minimumBGGuard"] as? GlucoseThreshold.RawValue {
            self.suspendThreshold = GlucoseThreshold(rawValue: rawThreshold)
        }

        if let retrospectiveCorrectionEnabled = rawValue["retrospectiveCorrectionEnabled"] as? Bool {
            self.retrospectiveCorrectionEnabled = retrospectiveCorrectionEnabled
        }
    }

    var rawValue: RawValue {
        var raw: RawValue = [
            "version": LoopSettings.version,
            "dosingEnabled": dosingEnabled,
            "bolusEnabled": bolusEnabled,
            "retrospectiveCorrectionEnabled": retrospectiveCorrectionEnabled
        ]

        raw["glucoseTargetRangeSchedule"] = glucoseTargetRangeSchedule?.rawValue
        raw["maximumBasalRatePerHour"] = maximumBasalRatePerHour
        raw["maximumInsulinOnBoard"] = maximumInsulinOnBoard
        raw["maximumBolus"] = maximumBolus
        raw["minimumBGGuard"] = suspendThreshold?.rawValue

        return raw
    }
}
