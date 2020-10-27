//
//  GlucoseChartData.swift
//  WatchApp Extension
//
//  Created by Michael Pangburn on 10/17/18.
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import Foundation
import HealthKit
import LoopKit


struct GlucoseChartData {
    var unit: HKUnit?

    var correctionRange: GlucoseRangeSchedule?

    var scheduleOverride: TemporaryScheduleOverride?

    var historicalGlucose: [SampleValue]? {
        didSet {
            historicalGlucoseRange = historicalGlucose?.quantityRange
        }
    }

    private(set) var historicalGlucoseRange: ClosedRange<HKQuantity>?

    var predictedGlucose: [SampleValue]? {
        didSet {
            predictedGlucoseRange = predictedGlucose?.quantityRange
        }
    }

    private(set) var predictedGlucoseRange: ClosedRange<HKQuantity>?

    init(unit: HKUnit?, correctionRange: GlucoseRangeSchedule?, scheduleOverride: TemporaryScheduleOverride?, historicalGlucose: [SampleValue]?, predictedGlucose: [SampleValue]?) {
        self.unit = unit
        self.correctionRange = correctionRange
        self.scheduleOverride = scheduleOverride
        self.historicalGlucose = historicalGlucose
        self.historicalGlucoseRange = historicalGlucose?.quantityRange
        self.predictedGlucose = predictedGlucose
        self.predictedGlucoseRange = predictedGlucose?.quantityRange
    }

    func chartableGlucoseRange(from interval: DateInterval) -> ClosedRange<HKQuantity> {
        let unit = self.unit ?? .milligramsPerDeciliter

        // Defaults
        var min = unit.lowWatermark
        var max = unit.highWatermark

        for correction in correctionRange?.quantityBetween(start: interval.start, end: interval.end) ?? [] {
            min = Swift.min(min, correction.value.lowerBound.doubleValue(for: unit))
            max = Swift.max(max, correction.value.upperBound.doubleValue(for: unit))
        }

        if let override = activeScheduleOverride?.settings.targetRange {
            min = Swift.min(min, override.lowerBound.doubleValue(for: unit))
            max = Swift.max(max, override.upperBound.doubleValue(for: unit))
        }

        if let historicalGlucoseRange = historicalGlucoseRange {
            min = Swift.min(min, historicalGlucoseRange.lowerBound.doubleValue(for: unit))
            max = Swift.max(max, historicalGlucoseRange.upperBound.doubleValue(for: unit))
        }

        if let predictedGlucoseRange = predictedGlucoseRange {
            min = Swift.min(min, predictedGlucoseRange.lowerBound.doubleValue(for: unit))
            max = Swift.max(max, predictedGlucoseRange.upperBound.doubleValue(for: unit))
        }

        // Predicted glucose values can be below a concentration of 0,
        // but we want to let those fall off the graph since it's technically impossible
        min = Swift.max(0, min.floored(to: unit.axisIncrement))
        max = max.ceiled(to: unit.axisIncrement)

        let lowerBound = HKQuantity(unit: unit, doubleValue: min)
        let upperBound = HKQuantity(unit: unit, doubleValue: max)

        return lowerBound...upperBound
    }

    var activeScheduleOverride: TemporaryScheduleOverride? {
        guard let override = scheduleOverride, override.isActive() else {
            return nil
        }
        return override
    }
}

private extension HKUnit {
    var axisIncrement: Double {
        return chartableIncrement * 25
    }

    var highWatermark: Double {
        if self == .milligramsPerDeciliter {
            return 150
        } else {
            return 8
        }
    }

    var lowWatermark: Double {
        if self == .milligramsPerDeciliter {
            return 75
        } else {
            return 4
        }
    }
}
