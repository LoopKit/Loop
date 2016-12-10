//
//  NSUserDefaults.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 8/30/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

import Foundation
import LoopKit
import MinimedKit

extension UserDefaults {

    private enum Key: String {
        case BasalRateSchedule = "com.loudnate.Naterade.BasalRateSchedule"
        case CarbRatioSchedule = "com.loudnate.Naterade.CarbRatioSchedule"
        case ConnectedPeripheralIDs = "com.loudnate.Naterade.ConnectedPeripheralIDs"
        case DosingEnabled = "com.loudnate.Naterade.DosingEnabled"
        case InsulinActionDuration = "com.loudnate.Naterade.InsulinActionDuration"
        case InsulinSensitivitySchedule = "com.loudnate.Naterade.InsulinSensitivitySchedule"
        case G4ReceiverEnabled = "com.loudnate.Loop.G4ReceiverEnabled"
        case G5TransmitterID = "com.loudnate.Naterade.TransmitterID"
        case GlucoseTargetRangeSchedule = "com.loudnate.Naterade.GlucoseTargetRangeSchedule"
        case MaximumBasalRatePerHour = "com.loudnate.Naterade.MaximumBasalRatePerHour"
        case MaximumBolus = "com.loudnate.Naterade.MaximumBolus"
        case PreferredInsulinDataSource = "com.loudnate.Loop.PreferredInsulinDataSource"
        case PumpID = "com.loudnate.Naterade.PumpID"
        case PumpModelNumber = "com.loudnate.Naterade.PumpModelNumber"
        case PumpRegion = "com.loopkit.Loop.PumpRegion"
        case PumpTimeZone = "com.loudnate.Naterade.PumpTimeZone"
        case RetrospectiveCorrectionEnabled = "com.loudnate.Loop.RetrospectiveCorrectionEnabled"
        case BatteryChemistry = "com.loopkit.Loop.BatteryChemistry"
    }

    var basalRateSchedule: BasalRateSchedule? {
        get {
            if let rawValue = dictionary(forKey: Key.BasalRateSchedule.rawValue) {
                return BasalRateSchedule(rawValue: rawValue)
            } else {
                return nil
            }
        }
        set {
            set(newValue?.rawValue, forKey: Key.BasalRateSchedule.rawValue)
        }
    }

    var carbRatioSchedule: CarbRatioSchedule? {
        get {
            if let rawValue = dictionary(forKey: Key.CarbRatioSchedule.rawValue) {
                return CarbRatioSchedule(rawValue: rawValue)
            } else {
                return nil
            }
        }
        set {
            set(newValue?.rawValue, forKey: Key.CarbRatioSchedule.rawValue)
        }
    }

    var connectedPeripheralIDs: [String] {
        get {
            return array(forKey: Key.ConnectedPeripheralIDs.rawValue) as? [String] ?? []
        }
        set {
            set(newValue, forKey: Key.ConnectedPeripheralIDs.rawValue)
        }
    }

    var dosingEnabled: Bool {
        get {
            return bool(forKey: Key.DosingEnabled.rawValue)
        }
        set {
            set(newValue, forKey: Key.DosingEnabled.rawValue)
        }
    }

    var insulinActionDuration: TimeInterval? {
        get {
            let value = double(forKey: Key.InsulinActionDuration.rawValue)

            return value > 0 ? value : nil
        }
        set {
            if let insulinActionDuration = newValue {
                set(insulinActionDuration, forKey: Key.InsulinActionDuration.rawValue)
            } else {
                removeObject(forKey: Key.InsulinActionDuration.rawValue)
            }
        }
    }

    var insulinSensitivitySchedule: InsulinSensitivitySchedule? {
        get {
            if let rawValue = dictionary(forKey: Key.InsulinSensitivitySchedule.rawValue) {
                return InsulinSensitivitySchedule(rawValue: rawValue)
            } else {
                return nil
            }
        }
        set {
            set(newValue?.rawValue, forKey: Key.InsulinSensitivitySchedule.rawValue)
        }
    }

    var glucoseTargetRangeSchedule: GlucoseRangeSchedule? {
        get {
            if let rawValue = dictionary(forKey: Key.GlucoseTargetRangeSchedule.rawValue) {
                return GlucoseRangeSchedule(rawValue: rawValue)
            } else {
                return nil
            }
        }
        set {
            set(newValue?.rawValue, forKey: Key.GlucoseTargetRangeSchedule.rawValue)
        }
    }

    var maximumBasalRatePerHour: Double? {
        get {
            let value = double(forKey: Key.MaximumBasalRatePerHour.rawValue)

            return value > 0 ? value : nil
        }
        set {
            if let maximumBasalRatePerHour = newValue {
                set(maximumBasalRatePerHour, forKey: Key.MaximumBasalRatePerHour.rawValue)
            } else {
                removeObject(forKey: Key.MaximumBasalRatePerHour.rawValue)
            }
        }
    }

    var maximumBolus: Double? {
        get {
            let value = double(forKey: Key.MaximumBolus.rawValue)

            return value > 0 ? value : nil
        }
        set {
            if let maximumBolus = newValue {
                set(maximumBolus, forKey: Key.MaximumBolus.rawValue)
            } else {
                removeObject(forKey: Key.MaximumBolus.rawValue)
            }
        }
    }

    var preferredInsulinDataSource: InsulinDataSource? {
        get {
            return InsulinDataSource(rawValue: integer(forKey: Key.PreferredInsulinDataSource.rawValue))
        }
        set {
            if let preferredInsulinDataSource = newValue {
                set(preferredInsulinDataSource.rawValue, forKey: Key.PreferredInsulinDataSource.rawValue)
            } else {
                removeObject(forKey: Key.PreferredInsulinDataSource.rawValue)
            }
        }
    }

    var pumpID: String? {
        get {
            return string(forKey: Key.PumpID.rawValue)
        }
        set {
            set(newValue, forKey: Key.PumpID.rawValue)
        }
    }

    var pumpModelNumber: String? {
        get {
            return string(forKey: Key.PumpModelNumber.rawValue)
        }
        set {
            set(newValue, forKey: Key.PumpModelNumber.rawValue)
        }
    }

    var pumpRegion: PumpRegion? {
        get {
            // Defaults to 0 / northAmerica
            return PumpRegion(rawValue: integer(forKey: Key.PumpRegion.rawValue))
        }
        set {
            set(newValue?.rawValue, forKey: Key.PumpRegion.rawValue)
        }
    }

    var pumpTimeZone: TimeZone? {
        get {
            if let offset = object(forKey: Key.PumpTimeZone.rawValue) as? NSNumber {
                return TimeZone(secondsFromGMT: offset.intValue)
            } else {
                return nil
            }
        } set {
            if let value = newValue {
                set(NSNumber(value: value.secondsFromGMT() as Int), forKey: Key.PumpTimeZone.rawValue)
            } else {
                removeObject(forKey: Key.PumpTimeZone.rawValue)
            }
        }
    }

    var receiverEnabled: Bool {
        get {
            return bool(forKey: Key.G4ReceiverEnabled.rawValue)
        }
        set {
            set(newValue, forKey: Key.G4ReceiverEnabled.rawValue)
        }
    }

    var retrospectiveCorrectionEnabled: Bool {
        get {
            return bool(forKey: Key.RetrospectiveCorrectionEnabled.rawValue)
        }
        set {
            set(newValue, forKey: Key.RetrospectiveCorrectionEnabled.rawValue)
        }
    }

    var transmitterID: String? {
        get {
            return string(forKey: Key.G5TransmitterID.rawValue)
        }
        set {
            set(newValue, forKey: Key.G5TransmitterID.rawValue)
        }
    }
    
    var batteryChemistry: BatteryChemistryType? {
        get {
            return BatteryChemistryType(rawValue: integer(forKey: Key.BatteryChemistry.rawValue))
        }
        set {
            if let batteryChemistry = newValue {
                set(batteryChemistry.rawValue, forKey: Key.BatteryChemistry.rawValue)
            } else {
                removeObject(forKey: Key.BatteryChemistry.rawValue)
            }
        }
    }

}
