//
//  NSUserDefaults.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 8/30/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

import Foundation
import LoopKit
import HealthKit


extension UserDefaults {

    private enum Key: String {
        case basalRateSchedule = "com.loudnate.Naterade.BasalRateSchedule"
        case carbRatioSchedule = "com.loudnate.Naterade.CarbRatioSchedule"
        case insulinModelSettings = "com.loopkit.Loop.insulinModelSettings"
        case loopSettings = "com.loopkit.Loop.loopSettings"
        case insulinSensitivitySchedule = "com.loudnate.Naterade.InsulinSensitivitySchedule"
    }

    var basalRateSchedule: BasalRateSchedule? {
        get {
            if let rawValue = dictionary(forKey: Key.basalRateSchedule.rawValue) {
                return BasalRateSchedule(rawValue: rawValue)
            } else {
                return nil
            }
        }
        set {
            set(newValue?.rawValue, forKey: Key.basalRateSchedule.rawValue)
        }
    }

    var carbRatioSchedule: CarbRatioSchedule? {
        get {
            if let rawValue = dictionary(forKey: Key.carbRatioSchedule.rawValue) {
                return CarbRatioSchedule(rawValue: rawValue)
            } else {
                return nil
            }
        }
        set {
            set(newValue?.rawValue, forKey: Key.carbRatioSchedule.rawValue)
        }
    }

    var insulinModelSettings: InsulinModelSettings? {
        get {
            if let rawValue = dictionary(forKey: Key.insulinModelSettings.rawValue) {
                return InsulinModelSettings(rawValue: rawValue)
            } else {
                // Migrate the version 0 case
                let insulinActionDurationKey = "com.loudnate.Naterade.InsulinActionDuration"
                defer {
                    removeObject(forKey: insulinActionDurationKey)
                }

                let value = double(forKey: insulinActionDurationKey)
                return value > 0 ? .walsh(WalshInsulinModel(actionDuration: value)) : nil
            }
        }
        set {
            set(newValue?.rawValue, forKey: Key.insulinModelSettings.rawValue)
        }
    }

    var loopSettings: LoopSettings? {
        get {
            if let rawValue = dictionary(forKey: Key.loopSettings.rawValue) {
                return LoopSettings(rawValue: rawValue)
            } else {
                // Migrate the version 0 case
                defer {
                    removeObject(forKey: "com.loudnate.Naterade.DosingEnabled")
                    removeObject(forKey: "com.loudnate.Naterade.GlucoseTargetRangeSchedule")
                    removeObject(forKey: "com.loudnate.Naterade.MaximumBasalRatePerHour")
                    removeObject(forKey: "com.loudnate.Naterade.MaximumBolus")
                    removeObject(forKey: "com.loopkit.Loop.MinimumBGGuard")
                    removeObject(forKey: "com.loudnate.Loop.RetrospectiveCorrectionEnabled")
                }

                let glucoseTargetRangeSchedule: GlucoseRangeSchedule?
                if let rawValue = dictionary(forKey: "com.loudnate.Naterade.GlucoseTargetRangeSchedule") {
                    glucoseTargetRangeSchedule = GlucoseRangeSchedule(rawValue: rawValue)
                } else {
                    glucoseTargetRangeSchedule = nil
                }

                let suspendThreshold: GlucoseThreshold?
                if let rawValue = dictionary(forKey: "com.loopkit.Loop.MinimumBGGuard") {
                    suspendThreshold = GlucoseThreshold(rawValue: rawValue)
                } else {
                    suspendThreshold = nil
                }

                var maximumBasalRatePerHour: Double? = double(forKey: "com.loudnate.Naterade.MaximumBasalRatePerHour")
                if maximumBasalRatePerHour! <= 0 {
                    maximumBasalRatePerHour = nil
                }

                var maximumBolus: Double? = double(forKey: "com.loudnate.Naterade.MaximumBolus")
                if maximumBolus! <= 0 {
                    maximumBolus = nil
                }

                let settings = LoopSettings(
                    dosingEnabled: bool(forKey: "com.loudnate.Naterade.DosingEnabled"),
                    glucoseTargetRangeSchedule: glucoseTargetRangeSchedule,
                    maximumBasalRatePerHour: maximumBasalRatePerHour,
                    maximumBolus: maximumBolus,
                    suspendThreshold: suspendThreshold,
                    retrospectiveCorrectionEnabled: bool(forKey: "com.loudnate.Loop.RetrospectiveCorrectionEnabled")
                )
                self.loopSettings = settings

                return settings
            }
        }
        set {
            set(newValue?.rawValue, forKey: Key.loopSettings.rawValue)
        }
    }

    var insulinSensitivitySchedule: InsulinSensitivitySchedule? {
        get {
            if let rawValue = dictionary(forKey: Key.insulinSensitivitySchedule.rawValue) {
                return InsulinSensitivitySchedule(rawValue: rawValue)
            } else {
                return nil
            }
        }
        set {
            set(newValue?.rawValue, forKey: Key.insulinSensitivitySchedule.rawValue)
        }
    }
}
