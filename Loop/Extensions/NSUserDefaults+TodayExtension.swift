//
//  NSUserDefaults+TodayExtension.swift
//  Loop
//
//  Created by Bharat Mediratta on 11/27/16.
//  Copyright © 2016 LoopKit Authors. All rights reserved.
//

import Foundation

extension UserDefaults {
    
    private enum Key: String {
        case TodayExtensionContext = "com.loudnate.Loop.TodayExtensionContext"
    }

    static func shared() -> UserDefaults? {
        return UserDefaults(suiteName: "group.com.loudnate.Loop")
    }

    var todayExtensionContext: TodayExtensionContext? {
        get {
            if let rawValue = dictionary(forKey: Key.TodayExtensionContext.rawValue) {
                return TodayExtensionContext(rawValue: rawValue)
            } else {
                return nil
            }
        }
        set {
            set(newValue?.rawValue, forKey: Key.TodayExtensionContext.rawValue)
        }
    }
}
