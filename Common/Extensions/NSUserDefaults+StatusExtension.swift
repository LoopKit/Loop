//
//  NSUserDefaults+StatusExtension.swift
//  Loop
//
//  Created by Bharat Mediratta on 11/27/16.
//  Copyright © 2016 LoopKit Authors. All rights reserved.
//

import Foundation

extension UserDefaults {
    
    private enum Key: String {
        case StatusExtensionContext = "com.loopkit.Loop.StatusExtensionContext"
    }

    var statusExtensionContextObservableKey: String {
        return Key.StatusExtensionContext.rawValue
    }
    
    var statusExtensionContext: StatusExtensionContext? {
        get {
            if let rawValue = dictionary(forKey: Key.StatusExtensionContext.rawValue) {
                return StatusExtensionContext(rawValue: rawValue)
            } else {
                return nil
            }
        }
        set {
            set(newValue?.rawValue, forKey: Key.StatusExtensionContext.rawValue)
        }
    }
}
