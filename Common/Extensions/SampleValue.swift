//
//  SampleValue.swift
//  Loop
//
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import LoopKit

extension SampleValue {
    /// A glucose value entered by hand, such as a fingerstick or calibration.
    var isManualGlucose: Bool {
        guard let sample = self as? GlucoseSampleValue else { return false }
        return sample.wasUserEntered && !sample.isDisplayOnly
    }
}

extension Collection where Element == SampleValue {
    /// O(n)
    var quantityRange: ClosedRange<LoopQuantity>? {
        var lowest: LoopQuantity?
        var highest: LoopQuantity?

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
