//
//  StandardRetrospectiveCorrection.swift
//  Loop
//
//  Created by Dragan Maksimovic on 10/27/18.
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import Foundation
import HealthKit
import LoopKit

/**
 Standard Retrospective Correction (RC) calculates a correction effect in glucose prediction based on the most recent discrepancy between observed glucose movement and movement expected based on insulin and carb models. Standard retrospective correction acts as a proportional (P) controller aimed at reducing modeling errors in glucose prediction.
 
 In the above summary, "discrepancy" is a difference between the actual glucose and the model predicted glucose over retrospective correction grouping interval (set to 30 min in LoopSettings)
 */
class StandardRetrospectiveCorrection: RetrospectiveCorrection {
    let retrospectionInterval = TimeInterval(minutes: 30)

    /// RetrospectiveCorrection protocol variables
    /// Standard effect duration
    let effectDuration: TimeInterval
    /// Overall retrospective correction effect
    var totalGlucoseCorrectionEffect: HKQuantity?

    /// All math is performed with glucose expressed in mg/dL
    private let unit = HKUnit.milligramsPerDeciliter

    init(effectDuration: TimeInterval) {
        self.effectDuration = effectDuration
    }

    func computeEffect(
        startingAt startingGlucose: GlucoseValue,
        retrospectiveGlucoseDiscrepanciesSummed: [GlucoseChange]?,
        recencyInterval: TimeInterval,
        insulinSensitivitySchedule: InsulinSensitivitySchedule?,
        basalRateSchedule: BasalRateSchedule?,
        glucoseCorrectionRangeSchedule: GlucoseRangeSchedule?,
        retrospectiveCorrectionGroupingInterval: TimeInterval
    ) -> [GlucoseEffect] {
        // Last discrepancy should be recent, otherwise clear the effect and return
        let glucoseDate = startingGlucose.startDate
        guard let currentDiscrepancy = retrospectiveGlucoseDiscrepanciesSummed?.last,
            glucoseDate.timeIntervalSince(currentDiscrepancy.endDate) <= recencyInterval
        else {
            totalGlucoseCorrectionEffect = nil
            return []
        }
        
        // Standard retrospective correction math
        let currentDiscrepancyValue = currentDiscrepancy.quantity.doubleValue(for: unit)
        totalGlucoseCorrectionEffect = HKQuantity(unit: unit, doubleValue: currentDiscrepancyValue)
        
        let retrospectionTimeInterval = currentDiscrepancy.endDate.timeIntervalSince(currentDiscrepancy.startDate)
        let discrepancyTime = max(retrospectionTimeInterval, retrospectiveCorrectionGroupingInterval)
        let velocity = HKQuantity(unit: unit.unitDivided(by: .second()), doubleValue: currentDiscrepancyValue / discrepancyTime)
        
        // Update array of glucose correction effects
        return startingGlucose.decayEffect(atRate: velocity, for: effectDuration)
    }

    var debugDescription: String {
        let report: [String] = [
            "## StandardRetrospectiveCorrection",
            ""
        ]

        return report.joined(separator: "\n")
    }
}
