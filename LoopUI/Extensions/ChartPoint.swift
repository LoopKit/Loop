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


extension ChartPoint {
    static func pointsForGlucoseRangeSchedule(_ glucoseRangeSchedule: GlucoseRangeSchedule, unit: HKUnit, xAxisValues: [ChartAxisValue]) -> [ChartPoint] {
        let targetRanges = glucoseRangeSchedule.quantityBetween(
            start: ChartAxisValueDate.dateFromScalar(xAxisValues.first!.scalar),
            end: ChartAxisValueDate.dateFromScalar(xAxisValues.last!.scalar)
        )

        let dateFormatter = DateFormatter()

        var maxPoints: [ChartPoint] = []
        var minPoints: [ChartPoint] = []

        for (index, range) in targetRanges.enumerated() {
            var startDate = ChartAxisValueDate(date: range.startDate, formatter: dateFormatter)
            var endDate: ChartAxisValueDate

            if index == targetRanges.startIndex, let firstDate = xAxisValues.first as? ChartAxisValueDate {
                startDate = firstDate
            }

            if index == targetRanges.endIndex - 1, let lastDate = xAxisValues.last as? ChartAxisValueDate {
                endDate = lastDate
            } else {
                endDate = ChartAxisValueDate(date: targetRanges[index + 1].startDate, formatter: dateFormatter)
            }

            let value = range.value.doubleRangeWithMinimumIncrement(in: unit)
            let minValue = ChartAxisValueDouble(value.minValue)
            let maxValue = ChartAxisValueDouble(value.maxValue)

            maxPoints += [
                ChartPoint(x: startDate, y: maxValue),
                ChartPoint(x: endDate, y: maxValue)
            ]

            minPoints += [
                ChartPoint(x: startDate, y: minValue),
                ChartPoint(x: endDate, y: minValue)
            ]
        }

        return maxPoints + minPoints.reversed()
    }

    static func pointsForGlucoseRangeScheduleOverride(_ override: TemporaryScheduleOverride, unit: HKUnit, xAxisValues: [ChartAxisValue], extendEndDateToChart: Bool = false) -> [ChartPoint] {
        guard let targetRange = override.settings.targetRange else {
            return []
        }
        
        return pointsForGlucoseRangeScheduleOverride(
            range: targetRange.doubleRangeWithMinimumIncrement(in: unit),
            activeInterval: override.activeInterval,
            unit: unit,
            xAxisValues: xAxisValues,
            extendEndDateToChart: extendEndDateToChart
        )
    }

    private static func pointsForGlucoseRangeScheduleOverride(range: DoubleRange, activeInterval: DateInterval, unit: HKUnit, xAxisValues: [ChartAxisValue], extendEndDateToChart: Bool) -> [ChartPoint] {
        guard let lastXAxisValue = xAxisValues.last as? ChartAxisValueDate else {
            return []
        }

        let dateFormatter = DateFormatter()
        let startDateAxisValue = ChartAxisValueDate(date: activeInterval.start, formatter: dateFormatter)
        let displayEndDate = min(lastXAxisValue.date, extendEndDateToChart ? .distantFuture : activeInterval.end)
        let endDateAxisValue = ChartAxisValueDate(date: displayEndDate, formatter: dateFormatter)
        let minValue = ChartAxisValueDouble(range.minValue)
        let maxValue = ChartAxisValueDouble(range.maxValue)

        return [
            ChartPoint(x: startDateAxisValue, y: maxValue),
            ChartPoint(x: endDateAxisValue, y: maxValue),
            ChartPoint(x: endDateAxisValue, y: minValue),
            ChartPoint(x: startDateAxisValue, y: minValue)
        ]
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


private extension ClosedRange where Bound == HKQuantity {
    func doubleRangeWithMinimumIncrement(in unit: HKUnit) -> DoubleRange {
        let increment = unit.chartableIncrement

        var minValue = self.lowerBound.doubleValue(for: unit)
        var maxValue = self.upperBound.doubleValue(for: unit)

        if (maxValue - minValue) < .ulpOfOne {
            minValue -= increment
            maxValue += increment
        }

        return DoubleRange(minValue: minValue, maxValue: maxValue)
    }
}
