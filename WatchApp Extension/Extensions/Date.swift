//
//  Date.swift
//  WatchApp Extension
//
//  Created by Bharat Mediratta on 6/26/18.
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import Foundation


extension Date {
    static var earliestGlucoseCutoff: Date {
        return Date(timeIntervalSinceNow: .hours(-6))
    }

    static var staleGlucoseCutoff: Date {
        return Date(timeIntervalSinceNow: .minutes(-5))
    }
}
