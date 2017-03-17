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
    static func pointsForGlucoseRangeSchedule(_ glucoseRangeSchedule: GlucoseRangeSchedule, xAxisValues: [ChartAxisValue]) -> [ChartPoint] {
        let targetRanges = glucoseRangeSchedule.between(
                start: ChartAxisValueDate.dateFromScalar(xAxisValues.first!.scalar),
                end: ChartAxisValueDate.dateFromScalar(xAxisValues.last!.scalar)
            ).map {
            return DatedRangeContext(
                startDate: $0.startDate,
                endDate: $0.endDate,
                minValue: $0.value.minValue,
                maxValue: $0.value.maxValue)
        }

        return ChartPoint.pointsForDatedRanges(targetRanges, xAxisValues: xAxisValues)
    }

    static func pointsForGlucoseRangeScheduleOverrideDuration(_ override: AbsoluteScheduleValue<DoubleRange>, xAxisValues: [ChartAxisValue]) -> [ChartPoint] {
        return ChartPoint.pointsForDatedRangeOverrideDuration(
            DatedRangeContext(startDate: override.startDate, endDate: override.endDate, minValue: override.value.minValue, maxValue: override.value.maxValue),
            xAxisValues: xAxisValues)
    }

    static func pointsForGlucoseRangeScheduleOverride(_ override: AbsoluteScheduleValue<DoubleRange>, xAxisValues: [ChartAxisValue]) -> [ChartPoint] {
        return ChartPoint.pointsForDatedRangeOverride(
            DatedRangeContext(startDate: override.startDate, endDate: override.endDate, minValue: override.value.minValue, maxValue: override.value.maxValue),
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


