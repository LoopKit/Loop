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
    var min: Double { get } // milligramsPerDeciliter
    var max: Double { get } // milligramsPerDeciliter

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


extension AbsoluteScheduleValue: GlucoseChartValueHashable where T == ClosedRange<HKQuantity> {
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

    var min: Double {
        return override.settings.targetRange!.minValue
    }

    var max: Double {
        return override.settings.targetRange!.maxValue
    }
}
