//
//  ChartPoint.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 2/19/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation
import LoopKit
import SwiftCharts


extension ChartPoint {
    static func pointsForGlucoseRangeSchedule(glucoseRangeSchedule: GlucoseRangeSchedule, xAxisValues: [ChartAxisValue]) -> [ChartPoint] {
        let targetRanges = glucoseRangeSchedule.between(
            ChartAxisValueDate.dateFromScalar(xAxisValues.first!.scalar),
            ChartAxisValueDate.dateFromScalar(xAxisValues.last!.scalar)
        )
        let dateFormatter = NSDateFormatter()

        var maxPoints: [ChartPoint] = []
        var minPoints: [ChartPoint] = []

        for (index, range) in targetRanges.enumerate() {
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

            let minValue = ChartAxisValueDouble(range.value.minValue)
            let maxValue = ChartAxisValueDouble(range.value.maxValue)

            maxPoints += [
                ChartPoint(x: startDate, y: maxValue),
                ChartPoint(x: endDate, y: maxValue)
            ]

            minPoints += [
                ChartPoint(x: startDate, y: minValue),
                ChartPoint(x: endDate, y: minValue)
            ]
        }

        return maxPoints + minPoints.reverse()
    }
}


