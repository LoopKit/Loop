//
//  StatusChartsManager.swift
//  Loop
//
//  Created by Bharat Mediratta on 3/16/17.
//  Copyright © 2017 LoopKit Authors. All rights reserved.
//

import Foundation
import SwiftCharts

private var targetRangesAssociationKey: UInt8 = 0
private var temporaryOverrideAssociationKey: UInt8 = 0

extension StatusChartsManager {

    var targetRanges: [DatedRangeContext]? {
        get {
            return objc_getAssociatedObject(self, &targetRangesAssociationKey) as? [DatedRangeContext]
        }
        set(newValue) {
            objc_setAssociatedObject(self,
                                     &targetRangesAssociationKey,
                                     newValue,
                                     objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN)
            targetGlucosePoints = []
        }
    }

    var temporaryOverride: DatedRangeContext? {
        get {
            return objc_getAssociatedObject(self, &temporaryOverrideAssociationKey) as? DatedRangeContext
        }
        set(newValue) {
            objc_setAssociatedObject(self,
                                     &temporaryOverrideAssociationKey,
                                     newValue,
                                     objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN)
            targetOverridePoints = []
            targetOverrideDurationPoints = []
        }
    }

    func prerender() {
        if xAxisValues == nil {
            generateXAxisValues()
        }

        if let xAxisValues = xAxisValues, xAxisValues.count > 1,
            targetGlucosePoints.count == 0,
            let targetRanges = targetRanges
        {
            targetGlucosePoints = ChartPoint.pointsForDatedRanges(targetRanges, xAxisValues: xAxisValues)

            if let override = temporaryOverride {
                targetOverridePoints = ChartPoint.pointsForDatedRangeOverride(override, xAxisValues: xAxisValues)
                targetOverrideDurationPoints = ChartPoint.pointsForDatedRangeOverrideDuration(override, xAxisValues: xAxisValues)
            } else {
                targetOverridePoints = []
                targetOverrideDurationPoints = []
            }
        }
    }
}
