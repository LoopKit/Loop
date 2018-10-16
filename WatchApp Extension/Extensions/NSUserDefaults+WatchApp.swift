//
//  NSUserDefaults.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 3/29/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation

enum Page: NSNumber {
    case Action = 0
    case Chart  = 1
    case Data   = 2
}

extension UserDefaults {
    private enum Key: String {
        case StartPage = "com.loudnate.Naterade.StartPage"
        case VisibleDuration = "com.loudnate.Naterade.VisibleDuration"
    }

    var startPage: Page {
        get {
            if let rawValue = object(forKey: Key.StartPage.rawValue) as? NSNumber, let page = Page(rawValue: rawValue) {
                return page
            }
            return .Action
        }
        set {
            set(newValue.rawValue, forKey: Key.StartPage.rawValue)
        }
    }

    var visibleDuration: TimeInterval  {
        get {
            if let rawValue = object(forKey: Key.VisibleDuration.rawValue) as? TimeInterval, let visibleDuration = TimeInterval(rawValue: rawValue) {
                return visibleDuration
            }
            return TimeInterval (hours: 6)
        }
        set {
            set(newValue.rawValue, forKey: Key.VisibleDuration.rawValue)
        }
    }
}
