//
//  Date.swift
//  WatchApp Extension
//
//  Created by Bharat Mediratta on 6/26/18.
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import Foundation


extension Date {
    static var EarliestGlucoseCutoff: Date {
        return Date().addingTimeInterval(TimeInterval(hours: -3))
    }

    static var StaleGlucoseCutoff: Date {
        return Date().addingTimeInterval(-TimeInterval(minutes: 4.5))
    }
}
