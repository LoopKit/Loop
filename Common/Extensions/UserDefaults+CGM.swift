//
//  UserDefaults+CGM.swift
//  Loop
//
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit


extension UserDefaults {
    private enum Key: String {
        case cgmManagerState = "com.loopkit.Loop.CGMManagerState"
    }

    var cgmManagerState: CGMManager.RawStateValue? {
        get {
            return dictionary(forKey: Key.cgmManagerState.rawValue)
        }
        set {
            set(newValue, forKey: Key.cgmManagerState.rawValue)
        }
    }
}
