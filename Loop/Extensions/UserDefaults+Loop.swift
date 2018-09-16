//
//  UserDefaults+Loop.swift
//  Loop
//
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit


extension UserDefaults {
    static let appGroup: UserDefaults = {
        let shared = UserDefaults(suiteName: Bundle.main.appGroupSuiteName)
        let standard = UserDefaults.standard

        // Use an old key as a migration sentinel
        if let shared = shared, standard.basalRateSchedule != nil && shared.basalRateSchedule == nil {
            shared.basalRateSchedule = standard.basalRateSchedule
            shared.carbRatioSchedule = standard.carbRatioSchedule
            shared.loopSettings      = standard.loopSettings
            shared.insulinModelSettings = standard.insulinModelSettings
            shared.insulinSensitivitySchedule = standard.insulinSensitivitySchedule
        }

        shared?.removeObject(forKey: "com.loopkit.Loop.insulinCounteractionEffects")
        shared?.removeObject(forKey: "com.loopkit.Loop.BatteryChemistry")
        shared?.removeObject(forKey: "com.loudnate.Loop.PreferredInsulinDataSource")
        shared?.removeObject(forKey: "com.loopkit.Loop.PumpState")
        shared?.removeObject(forKey: "com.loopkit.Loop.PumpSettings")
        shared?.removeObject(forKey: "com.loudnate.Naterade.ConnectedPeripheralIDs")
        shared?.removeObject(forKey: "com.loopkit.Loop.cgmSettings")

        return shared ?? standard
    }()
}


extension UserDefaults {
    private enum Key: String {
        case pumpManagerState = "com.loopkit.Loop.PumpManagerState"
    }

    var pumpManager: PumpManager? {
        get {
            guard let rawValue = dictionary(forKey: Key.pumpManagerState.rawValue) else {
                return nil
            }

            return PumpManagerFromRawValue(rawValue)
        }
        set {
            set(newValue?.rawValue, forKey: Key.pumpManagerState.rawValue)
        }
    }

    var isCGMManagerValidPumpManager: Bool {
        guard let rawValue = cgmManagerState else {
            return false
        }

        return PumpManagerTypeFromRawValue(rawValue) != nil
    }

    var cgmManager: CGMManager? {
        get {
            guard let rawValue = cgmManagerState else {
                return nil
            }

            return CGMManagerFromRawValue(rawValue)
        }
        set {
            cgmManagerState = newValue?.rawValue
        }
    }
}
