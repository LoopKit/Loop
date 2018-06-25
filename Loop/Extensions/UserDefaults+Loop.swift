//
//  UserDefaults+Loop.swift
//  Loop
//
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit
import MinimedKit


extension UserDefaults {
    static let appGroup: UserDefaults = {
        let shared = UserDefaults(suiteName: Bundle.main.appGroupSuiteName)
        let standard = UserDefaults.standard

        // Use an old key as a migration sentinel
        if let shared = shared, standard.basalRateSchedule != nil && shared.basalRateSchedule == nil {
            shared.basalRateSchedule = standard.basalRateSchedule
            shared.carbRatioSchedule = standard.carbRatioSchedule
            shared.cgm               = standard.cgm
            shared.connectedPeripheralIDs = standard.connectedPeripheralIDs
            shared.loopSettings      = standard.loopSettings
            shared.insulinModelSettings = standard.insulinModelSettings
            shared.insulinSensitivitySchedule = standard.insulinSensitivitySchedule
            shared.preferredInsulinDataSource = standard.preferredInsulinDataSource
            shared.batteryChemistry  = standard.batteryChemistry
        }

        shared?.removeObject(forKey: "com.loopkit.Loop.insulinCounteractionEffects")

        return shared ?? standard
    }()
}


extension UserDefaults {
    private enum Key: String {
        case batteryChemistry = "com.loopkit.Loop.BatteryChemistry"
        case preferredInsulinDataSource = "com.loudnate.Loop.PreferredInsulinDataSource"
    }

    var preferredInsulinDataSource: InsulinDataSource? {
        get {
            return InsulinDataSource(rawValue: integer(forKey: Key.preferredInsulinDataSource.rawValue))
        }
        set {
            if let preferredInsulinDataSource = newValue {
                set(preferredInsulinDataSource.rawValue, forKey: Key.preferredInsulinDataSource.rawValue)
            } else {
                removeObject(forKey: Key.preferredInsulinDataSource.rawValue)
            }
        }
    }

    var batteryChemistry: BatteryChemistryType? {
        get {
            return BatteryChemistryType(rawValue: integer(forKey: Key.batteryChemistry.rawValue))
        }
        set {
            if let batteryChemistry = newValue {
                set(batteryChemistry.rawValue, forKey: Key.batteryChemistry.rawValue)
            } else {
                removeObject(forKey: Key.batteryChemistry.rawValue)
            }
        }
    }
}
