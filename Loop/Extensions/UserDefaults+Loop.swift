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

    var pumpManagerRawValue: [String: Any]? {
        get {
            return dictionary(forKey: Key.pumpManagerState.rawValue)
        }
        set {
            set(newValue, forKey: Key.pumpManagerState.rawValue)
        }
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
