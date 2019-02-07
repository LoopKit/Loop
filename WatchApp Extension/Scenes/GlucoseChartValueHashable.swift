//
//  GlucoseChartValueHashable.swift
//  WatchApp Extension
//
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import LoopKit
import HealthKit


protocol GlucoseChartValueHashable {
    var start: Date { get }
    var end: Date { get }
    var min: Double { get }
    var max: Double { get }

    var chartHashValue: Int { get }
}

extension GlucoseChartValueHashable {
    var chartHashValue: Int {
        var hashValue = start.timeIntervalSinceReferenceDate.hashValue
        hashValue ^= end.timeIntervalSince(start).hashValue
        hashValue ^= min.hashValue
        if min != max {
            hashValue ^= max.hashValue
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


extension AbsoluteScheduleValue: GlucoseChartValueHashable where T == Range<HKQuantity> {
    var start: Date {
        return startDate
    }

    var end: Date {
        return endDate
    }

    var min: Double {
        return value.lowerBound.doubleValue(for: .milligramsPerDeciliter)
    }

    var max: Double {
        return value.upperBound.doubleValue(for: .milligramsPerDeciliter)
    }
}


extension TemporaryScheduleOverride: GlucoseChartValueHashable {
    var start: Date {
        return activeInterval.start
    }

    var end: Date {
        return activeInterval.end
    }

    var min: Double {
        return settings.targetRange.minValue
    }

    var max: Double {
        return settings.targetRange.maxValue
    }
}
