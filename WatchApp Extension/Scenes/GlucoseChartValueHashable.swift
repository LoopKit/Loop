//
//  GlucoseChartValueHashable.swift
//  WatchApp Extension
//
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import LoopKit
import LoopAlgorithm


protocol GlucoseChartValueHashable {
    var start: Date { get }
    var end: Date { get }
    var min: LoopQuantity { get }
    var max: LoopQuantity { get }

    var chartHashValue: Int { get }
}

extension GlucoseChartValueHashable {
    var chartHashValue: Int {
        var hashValue = start.timeIntervalSinceReferenceDate.hashValue
        hashValue ^= end.timeIntervalSince(start).hashValue
        // HKQuantity.hashValue returns 0, so we need to convert
        hashValue ^= min.doubleValue(for: .milligramsPerDeciliter).hashValue
        if min != max {
            hashValue ^= max.doubleValue(for: .milligramsPerDeciliter).hashValue
        }
        return hashValue
    }
}


extension SampleValue {
    var start: Date {
        return startDate
    }

    var end: Date {
        return endDate
    }

    var min: Double {
        return quantity.doubleValue(for: .milligramsPerDeciliter)
    }

    var max: Double {
        return quantity.doubleValue(for: .milligramsPerDeciliter)
    }

    var chartHashValue: Int {
        var hashValue = start.timeIntervalSinceReferenceDate.hashValue
        hashValue ^= end.timeIntervalSince(start).hashValue
        hashValue ^= min.hashValue
        return hashValue
    }
}


extension AbsoluteScheduleValue: GlucoseChartValueHashable where T == ClosedRange<LoopQuantity> {
    var start: Date {
        return startDate
    }

    var end: Date {
        return endDate
    }

    var min: LoopQuantity {
        return value.lowerBound
    }

    var max: LoopQuantity {
        return value.upperBound
    }
}

struct TemporaryScheduleOverrideHashable: GlucoseChartValueHashable {
    let override: TemporaryScheduleOverride

    init?(_ override: TemporaryScheduleOverride) {
        guard override.settings.targetRange != nil else {
            return nil
        }
        self.override = override
    }

    var start: Date {
        return override.activeInterval.start
    }

    var end: Date {
        return override.activeInterval.end
    }

    var min: LoopQuantity {
        return override.settings.targetRange!.lowerBound
    }

    var max: LoopQuantity {
        return override.settings.targetRange!.upperBound
    }
}
