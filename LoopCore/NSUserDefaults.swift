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
        case overrideHistory = "com.loopkit.overrideHistory"
        case lastBedtimeQuery = "com.loopkit.Loop.lastBedtimeQuery"
        case bedtime = "com.loopkit.Loop.bedtime"
        case lastProfileExpirationAlertDate = "com.loopkit.Loop.lastProfileExpirationAlertDate"
        case allowDebugFeatures = "com.loopkit.Loop.allowDebugFeatures"
        case allowSimulators = "com.loopkit.Loop.allowSimulators"
    }

    public static let appGroup = UserDefaults(suiteName: Bundle.main.appGroupSuiteName)

    public var legacyBasalRateSchedule: BasalRateSchedule? {
        get {
            if let rawValue = dictionary(forKey: "com.loudnate.Naterade.BasalRateSchedule") {
                return BasalRateSchedule(rawValue: rawValue)
            } else {
                return nil
            }
        }
    }

    public var legacyCarbRatioSchedule: CarbRatioSchedule? {
        get {
            if let rawValue = dictionary(forKey: "com.loudnate.Naterade.CarbRatioSchedule") {
                return CarbRatioSchedule(rawValue: rawValue)
            } else {
                return nil
            }
        }
    }

    public var legacyDefaultRapidActingModel: ExponentialInsulinModelPreset? {
        get {
            if let rawValue = string(forKey: "com.loopkit.Loop.defaultRapidActingModel") {
                return ExponentialInsulinModelPreset(rawValue: rawValue)
            }
            
            return nil
        }
    }

    public var legacyLoopSettings: LoopSettings? {
        get {
            if let rawValue = dictionary(forKey: "com.loopkit.Loop.loopSettings") {
                return LoopSettings(rawValue: rawValue)
            } else {
                return nil
            }
        }
    }

    public var legacyInsulinSensitivitySchedule: InsulinSensitivitySchedule? {
        get {
            if let rawValue = dictionary(forKey: "com.loudnate.Naterade.InsulinSensitivitySchedule") {
                return InsulinSensitivitySchedule(rawValue: rawValue)
            } else {
                return nil
            }
        }
    }

    public var overrideHistory: TemporaryScheduleOverrideHistory? {
        get {
            if let rawValue = object(forKey: Key.overrideHistory.rawValue) as? TemporaryScheduleOverrideHistory.RawValue {
                return TemporaryScheduleOverrideHistory(rawValue: rawValue)
            } else {
                return nil
            }
        }
        set {
            set(newValue?.rawValue, forKey: Key.overrideHistory.rawValue)
        }
    }
    
    public var lastBedtimeQuery: Date? {
        get {
            return object(forKey: Key.lastBedtimeQuery.rawValue) as? Date
        }
        set {
            set(newValue, forKey: Key.lastBedtimeQuery.rawValue)
        }
    }
    
    public var bedtime: Date? {
        get {
            return object(forKey: Key.bedtime.rawValue) as? Date
        }
        set {
            set(newValue, forKey: Key.bedtime.rawValue)
        }
    }
    
    public var lastProfileExpirationAlertDate: Date? {
        get {
            return object(forKey: Key.lastProfileExpirationAlertDate.rawValue) as? Date
        }
        set {
            set(newValue, forKey: Key.lastProfileExpirationAlertDate.rawValue)
        }
    }
    
    public var allowDebugFeatures: Bool {
        return bool(forKey: Key.allowDebugFeatures.rawValue)
    }

    public var allowSimulators: Bool {
        return bool(forKey: Key.allowSimulators.rawValue)
    }

    public func removeLegacyLoopSettings() {
        removeObject(forKey: "com.loudnate.Naterade.BasalRateSchedule")
        removeObject(forKey: "com.loudnate.Naterade.CarbRatioSchedule")
        removeObject(forKey: "com.loudnate.Naterade.InsulinSensitivitySchedule")
        removeObject(forKey: "com.loopkit.Loop.defaultRapidActingModel")
        removeObject(forKey: "com.loopkit.Loop.loopSettings")
    }
}
