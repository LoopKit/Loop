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

    var activeOverride: GlucoseRangeSchedule.Override? {
        guard let override = override, override.isActive() else {
            return nil
        }

        return override
    }

    var activeOverrideContext: GlucoseRangeSchedule.Override.Context? {
        return activeOverride?.context
    }

    var activeOverrideQuantityRange: Range<HKQuantity>? {
        guard let activeOverride = activeOverride else {
            return nil
        }

        let lowerBound = HKQuantity(unit: unit, doubleValue: activeOverride.value.minValue)
        let upperBound = HKQuantity(unit: unit, doubleValue: activeOverride.value.maxValue)
        return lowerBound..<upperBound
    }

    var configuredOverrideContexts: [GlucoseRangeSchedule.Override.Context] {
        var contexts: [GlucoseRangeSchedule.Override.Context] = []
        for (context, range) in overrideRanges where !range.isZero {
            contexts.append(context)
        }

        return contexts
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
