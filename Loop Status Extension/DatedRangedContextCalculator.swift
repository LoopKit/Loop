//
//  DateRangedContextCalculator.swift
//  Loop
//
//  Created by Bharat Mediratta on 3/21/17.
//  Copyright © 2017 LoopKit Authors. All rights reserved.
//

import Foundation
import SwiftCharts

import LoopUI

class DatedRangeContextCalculator: TargetPointsCalculator {

    var targetRanges: [DatedRangeContext]?
    var temporaryOverride: DatedRangeContext?

    var glucosePoints: [ChartPoint] = []
    var overridePoints: [ChartPoint] = []
    var overrideDurationPoints: [ChartPoint] = []

    init(targetRanges: [DatedRangeContext]?, temporaryOverride: DatedRangeContext?) {
        self.targetRanges = targetRanges
        self.temporaryOverride = temporaryOverride
    }

    func calculate(_ xAxisValues: [ChartAxisValue]?) {
        if let xAxisValues = xAxisValues, xAxisValues.count > 1,
            let targetRanges = targetRanges
        {
            glucosePoints = ChartPoint.pointsForDatedRanges(targetRanges, xAxisValues: xAxisValues)

            if let override = temporaryOverride {
                overridePoints = ChartPoint.pointsForDatedRangeOverride(override, xAxisValues: xAxisValues)
                overrideDurationPoints = ChartPoint.pointsForDatedRangeOverrideDuration(override, xAxisValues: xAxisValues)
            } else {
                overridePoints = []
                overrideDurationPoints = []
            }
        }
    }
}
