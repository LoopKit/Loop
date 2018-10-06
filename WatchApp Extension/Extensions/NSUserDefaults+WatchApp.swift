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
        case StartOnChartPage = "com.loudnate.Naterade.StartOnChartPage"
    }

    var startOnChartPage: Bool {
        get {
            return object(forKey: Key.StartOnChartPage.rawValue) as? Bool ?? false
        }
        set {
            set(newValue, forKey: Key.StartOnChartPage.rawValue)
        }
    }
}
