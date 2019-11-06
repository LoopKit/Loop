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
        case cgmManagerState = "com.loopkit.Loop.CGMManagerState"
    }

    var pumpManagerRawValue: [String: Any]? {
        get {
            return dictionary(forKey: Key.pumpManagerState.rawValue)
        }
        set {
            set(newValue, forKey: Key.pumpManagerState.rawValue)
        }
    }

    var cgmManagerRawValue: [String: Any]? {
        get {
            return dictionary(forKey: Key.cgmManagerState.rawValue)
        }
        set {
            set(newValue, forKey: Key.cgmManagerState.rawValue)
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
