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
}


extension ClosedRange where Bound == HKQuantity {
    func averageValue(for unit: HKUnit) -> Double {
        let minValue = lowerBound.doubleValue(for: unit)
        let maxValue = upperBound.doubleValue(for: unit)
        return (maxValue + minValue) / 2
    }
}
