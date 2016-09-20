//
//  NSUserDefaults.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 3/29/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation


extension UserDefaults {
    private enum Key: String {
        case ComplicationDataLastRefreshed = "com.loudnate.Naterade.ComplicationDataLastRefreshed"
        case WatchContext = "com.loudnate.Naterade.WatchContext"
        case WatchContextReadyForComplication = "com.loudnate.Naterade.WatchContextReadyForComplication"
    }

    var complicationDataLastRefreshed: Date {
        get {
            return object(forKey: Key.ComplicationDataLastRefreshed.rawValue) as? Date ?? Date.distantPast
        }
        set {
            set(newValue, forKey: Key.ComplicationDataLastRefreshed.rawValue)
        }
    }

    var watchContext: WatchContext? {
        get {
            if let rawValue = dictionary(forKey: Key.WatchContext.rawValue) {
                return WatchContext(rawValue: rawValue as WatchContext.RawValue)
            } else {
                return nil
            }
        }
        set {
            set(newValue?.rawValue, forKey: Key.WatchContext.rawValue)

            watchContextReadyForComplication = newValue != nil
        }
    }

    var watchContextReadyForComplication: Bool {
        get {
            return bool(forKey: Key.WatchContextReadyForComplication.rawValue)
        }
        set {
            set(newValue, forKey: Key.WatchContextReadyForComplication.rawValue)
        }
    }
}
