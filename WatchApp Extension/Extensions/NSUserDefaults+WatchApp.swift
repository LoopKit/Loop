//
//  NSUserDefaults.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 3/29/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation

enum Page: Int8 {
    case Action = 0
    case Chart = 1
    case Data = 2
}

extension UserDefaults {
    private enum Key: String {
        case StartPage = "com.loudnate.Naterade.StartPage"
    }

    var startPage: Page {
        get {
            return object(forKey: Key.StartPage.rawValue) as? Page ?? .Action
        }
        set {
            set(newValue, forKey: Key.StartPage.rawValue)
        }
    }
}
