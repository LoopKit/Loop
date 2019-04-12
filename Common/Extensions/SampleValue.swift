//
//  SampleValue.swift
//  Loop
//
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import HealthKit
import LoopKit


extension Collection where Element == SampleValue {
    /// O(n)
    var quantityRange: ClosedRange<HKQuantity>? {
        var lowest: HKQuantity?
        var highest: HKQuantity?

        for sample in self {
            if let l = lowest {
                lowest = Swift.min(l, sample.quantity)
            } else {
                lowest = sample.quantity
            }

            if let h = highest {
                highest = Swift.max(h, sample.quantity)
            } else {
                highest = sample.quantity
            }
        }

        guard let l = lowest, let h = highest else {
            return nil
        }

        return l...h
    }
}
