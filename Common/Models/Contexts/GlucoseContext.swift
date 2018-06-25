//
//  GlucoseContext.swift
//  Loop
//
//  Created by Bharat Mediratta on 6/25/18.
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import Foundation
import HealthKit


struct GlucoseContext {
    let value: Double
    let unit: HKUnit
    let startDate: Date

    var quantity: HKQuantity {
        return HKQuantity(unit: unit, doubleValue: value)
    }
}
