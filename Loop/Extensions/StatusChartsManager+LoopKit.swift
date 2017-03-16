//
//  StatusChartManager+LoopKit.swift
//  Loop
//
//  Created by Bharat Mediratta on 3/16/17.
//  Copyright © 2017 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit
import SwiftCharts

private var glucoseTargetRangeScheduleAssociationKey: UInt8 = 0

extension StatusChartsManager {

    var glucoseTargetRangeSchedule: GlucoseRangeSchedule? {
        get {
            return objc_getAssociatedObject(self, &glucoseTargetRangeScheduleAssociationKey) as? GlucoseRangeSchedule
        }
        set(newValue) {
            objc_setAssociatedObject(self,
                                     &glucoseTargetRangeScheduleAssociationKey,
                                     newValue,
                                     objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN)
            targetGlucosePoints = []
        }
    }

    /// Runs any necessary steps before rendering charts
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
