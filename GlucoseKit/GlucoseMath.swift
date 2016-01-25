//
//  GlucoseMath.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 1/24/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation
import HealthKit


struct GlucoseValue {
    let startDate: NSDate
    let quantity: HKQuantity
}


struct GlucoseMath {
    static func momentumEffectForGlucoseEntries(
        entries: [GlucoseValue],
        duration: NSTimeInterval = NSTimeInterval(minutes: 30),
        delta: NSTimeInterval = NSTimeInterval(minutes: 5)
    ) {
        
    }
}
