//
//  GlucoseRangeSchedule.swift
//  Loop
//
//  Copyright © 2017 LoopKit Authors. All rights reserved.
//

import LoopKit
import HealthKit


extension GlucoseRangeSchedule {
    func minQuantity(at date: Date) -> HKQuantity {
        return HKQuantity(unit: unit, doubleValue: value(at: date).minValue)
    }
    func maxQuantity(at date: Date) -> HKQuantity {
        return HKQuantity(unit: unit, doubleValue: value(at: date).maxValue)
    }
}
