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

    var configuredOverrideContexts: [GlucoseRangeSchedule.Override.Context] {
        var contexts: [GlucoseRangeSchedule.Override.Context] = []
        for (context, range) in overrideRanges where !range.isZero {
            contexts.append(context)
        }

        return contexts
    }
}


extension Range where Bound == HKQuantity {
    func averageValue(for unit: HKUnit) -> Double {
        let minValue = lowerBound.doubleValue(for: unit)
        let maxValue = upperBound.doubleValue(for: unit)
        return (maxValue + minValue) / 2
    }
}
