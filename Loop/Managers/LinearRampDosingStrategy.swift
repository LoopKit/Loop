//
//  LinearRampDosingStrategy.swift
//  Loop
//
//  Created by Jonas Björkert on 2023-06-03.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import Foundation
import HealthKit
import LoopKit
import LoopCore

struct LinearRampDosingStrategy: DosingStrategy {
    func calculateDosingFactor(
        for glucose: HKQuantity,
        correctionRangeSchedule: GlucoseRangeSchedule,
        settings: LoopSettings
    ) -> Double {
        // Calculate current glucose and lower bound target
        let currentGlucose = glucose.doubleValue(for: .milligramsPerDeciliter)
        let correctionRange = correctionRangeSchedule.quantityRange(at: Date())
        let lowerBoundTarget = correctionRange.lowerBound.doubleValue(for: .milligramsPerDeciliter)

        // Calculate minimum glucose sliding scale and scaling fraction
        let minGlucoseSlidingScale = LoopConstants.minGlucoseDeltaSlidingScale + lowerBoundTarget
        let scalingFraction = (LoopConstants.maxPartialApplicationFactor - LoopConstants.minPartialApplicationFactor) / (LoopConstants.maxGlucoseSlidingScale - minGlucoseSlidingScale)
        let scalingGlucose = max(currentGlucose - minGlucoseSlidingScale, 0.0)

        // Calculate effectiveBolusApplicationFactor
        let effectiveBolusApplicationFactor = min(LoopConstants.minPartialApplicationFactor + scalingGlucose * scalingFraction, LoopConstants.maxPartialApplicationFactor)

        return effectiveBolusApplicationFactor
    }
}

