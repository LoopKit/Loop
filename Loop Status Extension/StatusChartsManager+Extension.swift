//
//  StatusChartsManager.swift
//  Loop
//
//  Created by Bharat Mediratta on 3/16/17.
//  Copyright © 2017 LoopKit Authors. All rights reserved.
//

import Foundation

extension StatusChartsManager {
    func prerender() {
        if xAxisValues == nil {
            generateXAxisValues()
        }

        if  let xAxisValues = xAxisValues, xAxisValues.count > 1,
            targetGlucosePoints.count == 0,
            let targets = glucoseTargetRangeSchedule
        {
            targetGlucosePoints = ChartPoint.pointsForGlucoseRangeSchedule(targets, xAxisValues: xAxisValues)

            if let override = targets.temporaryOverride {
                targetOverridePoints = ChartPoint.pointsForGlucoseRangeScheduleOverride(override, xAxisValues: xAxisValues)

                targetOverrideDurationPoints = ChartPoint.pointsForGlucoseRangeScheduleOverrideDuration(override, xAxisValues: xAxisValues)
            } else {
                targetOverridePoints = []
                targetOverrideDurationPoints = []
            }
        }
    }
    }
}
