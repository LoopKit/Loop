//
//  ChartPoint.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 2/19/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation
import SwiftCharts


extension ChartPoint {
    static func pointsForDatedRanges(_ targetRanges: [DatedRangeContext], xAxisValues: [ChartAxisValue]) -> [ChartPoint] {
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

            let minValue = ChartAxisValueDouble(range.minValue)
            let maxValue = ChartAxisValueDouble(range.maxValue)

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

    static func pointsForDatedRangeOverrideDuration(_ override: DatedRangeContext, xAxisValues: [ChartAxisValue]) -> [ChartPoint] {
        let startDate = Date()

        guard override.endDate.timeIntervalSince(startDate) > 0,
            let lastXAxisValue = xAxisValues.last as? ChartAxisValueDate
        else {
            return []
        }

        let dateFormatter = DateFormatter()
        let startDateAxisValue = ChartAxisValueDate(date: startDate, formatter: dateFormatter)
        let endDateAxisValue = ChartAxisValueDate(date: min(lastXAxisValue.date, override.endDate), formatter: dateFormatter)
        let minValue = ChartAxisValueDouble(override.minValue)
        let maxValue = ChartAxisValueDouble(override.maxValue)

        return [
            ChartPoint(x: startDateAxisValue, y: maxValue),
            ChartPoint(x: endDateAxisValue, y: maxValue),
            ChartPoint(x: endDateAxisValue, y: minValue),
            ChartPoint(x: startDateAxisValue, y: minValue)
        ]
    }

    static func pointsForDatedRangeOverride(_ override: DatedRangeContext, xAxisValues: [ChartAxisValue]) -> [ChartPoint] {
        let startDate = Date()

        guard override.endDate.timeIntervalSince(startDate) > 0,
            let lastXAxisValue = xAxisValues.last as? ChartAxisValueDate
        else {
            return []
        }

        let dateFormatter = DateFormatter()
        let startDateAxisValue = ChartAxisValueDate(date: startDate, formatter: dateFormatter)
        let endDateAxisValue = ChartAxisValueDate(date: lastXAxisValue.date, formatter: dateFormatter)
        let minValue = ChartAxisValueDouble(override.minValue)
        let maxValue = ChartAxisValueDouble(override.maxValue)

        return [
            ChartPoint(x: startDateAxisValue, y: maxValue),
            ChartPoint(x: endDateAxisValue, y: maxValue),
            ChartPoint(x: endDateAxisValue, y: minValue),
            ChartPoint(x: startDateAxisValue, y: minValue)
        ]
    }

}
