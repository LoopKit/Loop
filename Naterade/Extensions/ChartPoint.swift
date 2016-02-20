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
    static func pointsForGlucoseRangeSchedule(glucoseRangeSchedule: GlucoseRangeSchedule, onAxisValues xAxisValues: [ChartAxisValue], dateFormatter: NSDateFormatter) -> [ChartPoint] {
        let targetRanges = glucoseRangeSchedule.between(
            ChartAxisValueDate.dateFromScalar(xAxisValues.first!.scalar),
            ChartAxisValueDate.dateFromScalar(xAxisValues.last!.scalar)
        )

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

            maxPoints += [
                ChartPoint(
                    x: startDate,
                    y: ChartAxisValueDouble(range.value.maxValue)
                ),
                ChartPoint(
                    x: endDate,
                    y: ChartAxisValueDouble(range.value.maxValue)
                )
            ]

            minPoints += [
                ChartPoint(
                    x: startDate,
                    y: ChartAxisValueDouble(range.value.minValue)
                ),
                ChartPoint(
                    x: endDate,
                    y: ChartAxisValueDouble(range.value.minValue)
                )
            ]
        }

        return maxPoints + minPoints.reverse()
    }
}


