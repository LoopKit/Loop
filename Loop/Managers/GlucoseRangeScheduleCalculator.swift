//
//  GlucoseRangeScheduleCalculator.swift
//  Loop
//
//  Created by Bharat Mediratta on 3/21/17.
//  Copyright © 2017 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit
import SwiftCharts
import LoopUI

class GlucoseRangeScheduleCalculator: TargetPointsCalculator {

    var schedule: GlucoseRangeSchedule?

    var glucosePoints: [ChartPoint] = []
    var overridePoints: [ChartPoint] = []
    var overrideDurationPoints: [ChartPoint] = []

    init(_ schedule: GlucoseRangeSchedule?) {
        self.schedule = schedule
    }

    func calculate(_ xAxisValues: [ChartAxisValue]?) {
        if  let xAxisValues = xAxisValues, xAxisValues.count > 1,
            let schedule = schedule
        {
            glucosePoints = ChartPoint.pointsForGlucoseRangeSchedule(schedule, xAxisValues: xAxisValues)

            if let override = schedule.temporaryOverride {
                overridePoints = ChartPoint.pointsForGlucoseRangeScheduleOverride(override, xAxisValues: xAxisValues)

                overrideDurationPoints = ChartPoint.pointsForGlucoseRangeScheduleOverrideDuration(override, xAxisValues: xAxisValues)
            } else {
                overridePoints = []
                overrideDurationPoints = []
            }
        }
    }
}
