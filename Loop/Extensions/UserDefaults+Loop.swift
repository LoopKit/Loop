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
        case legacyPumpManagerState = "com.loopkit.Loop.PumpManagerState"
        case legacyCGMManagerState = "com.loopkit.Loop.CGMManagerState"
        case servicesState = "com.loopkit.Loop.ServicesState"
    }

    var legacyPumpManagerRawValue: PumpManager.RawValue? {
        get {
            return dictionary(forKey: Key.legacyPumpManagerState.rawValue)
        }
        set {
            set(newValue, forKey: Key.legacyPumpManagerState.rawValue)
        }
    }

    var legacyCGMManagerRawValue: CGMManager.RawValue? {
        get {
            return dictionary(forKey: Key.legacyCGMManagerState.rawValue)
        }
        set {
            set(newValue, forKey: Key.legacyCGMManagerState.rawValue)
        }
    }

    var servicesState: [Service.RawStateValue] {
        get {
            return array(forKey: Key.servicesState.rawValue) as? [[String: Any]] ?? []
        }
        set {
            set(newValue, forKey: Key.servicesState.rawValue)
        }
    }

}
