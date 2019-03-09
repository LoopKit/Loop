//
//  UserDefaults+Loop.swift
//  Loop
//
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit


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
