//
//  GlucoseRangeSchedule.swift
//  Loop
//
//  Copyright © 2017 LoopKit Authors. All rights reserved.
//

import LoopKit
import HealthKit


extension GlucoseRangeSchedule {
    func overrideEnabledForContext(_ context: Override.Context) -> Bool? {
        guard let override = override, override.context == context else {
            guard let value = overrideRanges[context], !value.isZero else {
                // Unavailable to set
                return nil
            }

            return false
        }

        return override.isActive()
    }

    func minQuantity(at date: Date) -> HKQuantity {
        return HKQuantity(unit: unit, doubleValue: value(at: date).minValue)
    }
}


extension DoubleRange {
    var averageValue: Double {
        return (maxValue + minValue) / 2
    }
}
