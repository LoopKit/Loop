//
//  ChartPoint.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 2/19/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation
import HealthKit
import LoopKit
import SwiftCharts
import LoopUI


extension ChartPoint {
    static func pointsForGlucoseRangeSchedule(_ glucoseRangeSchedule: GlucoseRangeSchedule, xAxisValues: [ChartAxisValue]) -> [ChartPoint] {
        let targetRanges = glucoseRangeSchedule.between(
            start: ChartAxisValueDate.dateFromScalar(xAxisValues.first!.scalar),
            end: ChartAxisValueDate.dateFromScalar(xAxisValues.last!.scalar)
        ).map { (scheduleValue) -> DatedRangeContext in
            let range = scheduleValue.value.rangeWithMinimumIncremement(glucoseRangeSchedule.unit.chartableIncrement)

            return DatedRangeContext(
                startDate: scheduleValue.startDate,
                endDate: scheduleValue.endDate,
                minValue: range.minValue,
                maxValue: range.maxValue
            )
        }

        return ChartPoint.pointsForDatedRanges(targetRanges, xAxisValues: xAxisValues)
    }

    static func pointsForGlucoseRangeScheduleOverrideDuration(_ override: GlucoseRangeSchedule.Override, unit: HKUnit, xAxisValues: [ChartAxisValue]) -> [ChartPoint] {
        let range = override.value.rangeWithMinimumIncremement(unit.chartableIncrement)

        return ChartPoint.pointsForDatedRangeOverrideDuration(
            DatedRangeContext(startDate: override.start, endDate: override.end ?? .distantFuture, minValue: range.minValue, maxValue: range.maxValue),
            xAxisValues: xAxisValues)
    }

    static func pointsForGlucoseRangeScheduleOverride(_ override: GlucoseRangeSchedule.Override, unit: HKUnit, xAxisValues: [ChartAxisValue]) -> [ChartPoint] {
        let range = override.value.rangeWithMinimumIncremement(unit.chartableIncrement)

        return ChartPoint.pointsForDatedRangeOverride(
            DatedRangeContext(startDate: override.start, endDate: override.end ?? .distantFuture, minValue: range.minValue, maxValue: range.maxValue),
            xAxisValues: xAxisValues)
    }
}



extension ChartPoint: TimelineValue {
    public var startDate: Date {
        if let dateValue = x as? ChartAxisValueDate {
            return dateValue.date
        } else {
            return Date.distantPast
        }
    }
}


private extension DoubleRange {
    func rangeWithMinimumIncremement(_ increment: Double) -> DoubleRange {
        var minValue = self.minValue
        var maxValue = self.maxValue

        if (maxValue - minValue) < .ulpOfOne {
            minValue -= increment
            maxValue += increment
        }

        return DoubleRange(minValue: minValue, maxValue: maxValue)
    }
}
