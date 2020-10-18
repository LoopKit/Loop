//
//  UserDefaults+LoopIntents.swift
//  Loop Intent Extension
//
//  Created by Anna Quinlan on 10/17/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import Foundation

extension UserDefaults {
    
    private enum Key: String {
        case IntentExtensionContext = "com.loopkit.Loop.IntentExtensionContext"
    }
    
    var intentExtensionInfo: IntentExtensionInfo? {
        get {
            if let rawValue = dictionary(forKey: Key.IntentExtensionContext.rawValue) {
                return IntentExtensionInfo(rawValue: rawValue)
            } else {
                return nil
            }
        }
        set {
            set(newValue?.rawValue, forKey: Key.IntentExtensionContext.rawValue)
        }
    }
}

