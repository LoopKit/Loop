//
//  LoopSettings.swift
//  Loop
//
//  Copyright © 2017 LoopKit Authors. All rights reserved.
//

import LoopKit


struct LoopSettings {
    var dosingEnabled = false

    let dynamicCarbAbsorptionEnabled = true

    var glucoseTargetRangeSchedule: GlucoseRangeSchedule?

    var maximumBasalRatePerHour: Double?

    var maximumBolus: Double?

    var suspendThreshold: GlucoseThreshold? = nil

    var retrospectiveCorrectionEnabled = true

    let retrospectiveCorrectionInterval = TimeInterval(minutes: 30)

    /// The amount of time since a given date that data should be considered valid
    let recencyInterval = TimeInterval(minutes: 15)

    // MARK - Display settings

    let minimumChartWidthPerHour: CGFloat = 50

    let statusChartMinimumHistoryDisplay: TimeInterval = .hours(1)
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

        if let rawValue = rawValue["glucoseTargetRangeSchedule"] as? GlucoseRangeSchedule.RawValue {
            self.glucoseTargetRangeSchedule = GlucoseRangeSchedule(rawValue: rawValue)
        }

        self.maximumBasalRatePerHour = rawValue["maximumBasalRatePerHour"] as? Double

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
            "retrospectiveCorrectionEnabled": retrospectiveCorrectionEnabled
        ]

        raw["glucoseTargetRangeSchedule"] = glucoseTargetRangeSchedule?.rawValue
        raw["maximumBasalRatePerHour"] = maximumBasalRatePerHour
        raw["maximumBolus"] = maximumBolus
        raw["minimumBGGuard"] = suspendThreshold?.rawValue

        return raw
    }
}
