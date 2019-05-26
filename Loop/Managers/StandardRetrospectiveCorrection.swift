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
import LoopCore

/**
 Standard Retrospective Correction (RC) calculates a correction effect in glucose prediction based on the most recent discrepancy between observed glucose movement and movement expected based on insulin and carb models. Standard retrospective correction acts as a proportional (P) controller aimed at reducing modeling errors in glucose prediction.
 
 In the above summary, "discrepancy" is a difference between the actual glucose and the model predicted glucose over retrospective correction grouping interval (set to 30 min in LoopSettings)
 */
class StandardRetrospectiveCorrection: RetrospectiveCorrection {

    /// RetrospectiveCorrection protocol variables
    /// Standard effect duration
    let standardEffectDuration: TimeInterval
    /// Overall retrospective correction effect
    var totalGlucoseCorrectionEffect: HKQuantity?

    /// All math is performed with glucose expressed in mg/dL
    private let unit = HKUnit.milligramsPerDeciliter
    
    /**
     Initialize standard retrospective correction based on settings
     
     - Parameters:
        - settings: User settings
        - standardEffectDuration: Correction effect duration
     
     - Returns: Standard Retrospective Correction with user settings
     */
    init(_ standardEffectDuration: TimeInterval) {
        self.standardEffectDuration = standardEffectDuration
    }
    
    /**
     Calculates glucose correction effects based on the most recent discrepany, and updates overall correction effect totalGlucoseCorrectionEffect
     
     - Parameters:
        - glucose: Most recent glucose
        - retrospectiveGlucoseDiscrepanciesSummed: Timeline of past discepancies
     
     - Returns:
        - glucoseCorrectionEffect: Glucose correction effects
     */
    func updateRetrospectiveCorrectionEffect(_ glucose: GlucoseValue, _ retrospectiveGlucoseDiscrepanciesSummed: [GlucoseChange]?) -> [GlucoseEffect] {
        
        // Loop settings
        let settings = UserDefaults.appGroup?.loopSettings ?? LoopSettings()

        var glucoseCorrectionEffect: [GlucoseEffect] = []
        
        // Last discrepancy should be recent, otherwise clear the effect and return
        let glucoseDate = glucose.startDate
        guard let currentDiscrepancy = retrospectiveGlucoseDiscrepanciesSummed?.last,
            glucoseDate.timeIntervalSince(currentDiscrepancy.endDate) <= settings.recencyInterval
            else {
                totalGlucoseCorrectionEffect = nil
                return( [] )
        }
        
        // Standard retrospective correction math
        let currentDiscrepancyValue = currentDiscrepancy.quantity.doubleValue(for: unit)
        totalGlucoseCorrectionEffect = HKQuantity(unit: unit, doubleValue: currentDiscrepancyValue)
        
        let retrospectionTimeInterval = currentDiscrepancy.endDate.timeIntervalSince(currentDiscrepancy.startDate)
        let discrepancyTime = max(retrospectionTimeInterval, settings.retrospectiveCorrectionGroupingInterval)
        let velocity = HKQuantity(unit: unit.unitDivided(by: .second()), doubleValue: currentDiscrepancyValue / discrepancyTime)
        
        // Update array of glucose correction effects
        glucoseCorrectionEffect = glucose.decayEffect(atRate: velocity, for: standardEffectDuration)
        
        // Return glucose correction effects
        return( glucoseCorrectionEffect )
    }
}
