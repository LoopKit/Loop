//
//  SimpleBolusCalculator.swift
//  Loop
//
//  Created by Pete Schwamb on 9/28/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopCore
import HealthKit
import LoopKit

struct SimpleBolusCalculator {
    
    public static func recommendedInsulin(mealCarbs: HKQuantity?, manualGlucose: HKQuantity?, activeInsulin: HKQuantity, carbRatioSchedule: CarbRatioSchedule, correctionRangeSchedule: GlucoseRangeSchedule, sensitivitySchedule: InsulinSensitivitySchedule, at date: Date = Date()) -> HKQuantity {
        var recommendedBolus: Double = 0
        
        if let mealCarbs = mealCarbs {
            let carbRatio = carbRatioSchedule.quantity(at: date)
            recommendedBolus += mealCarbs.doubleValue(for: .gram()) / carbRatio.doubleValue(for: .gram())
        }
        
        if let manualGlucose = manualGlucose {
            let sensitivity = sensitivitySchedule.quantity(at: date).doubleValue(for: .milligramsPerDeciliter)
            let correctionRange = correctionRangeSchedule.quantityRange(at: date)
            if (!correctionRange.contains(manualGlucose)) {
                let correctionTarget = correctionRange.averageValue(for: .milligramsPerDeciliter)
                let correctionBolus = (manualGlucose.doubleValue(for: .milligramsPerDeciliter) - correctionTarget) / sensitivity
                if correctionBolus >= 0 {
                    let activeInsulin = max(0, activeInsulin.doubleValue(for: .internationalUnit()))
                    let correctionBolusMinusActiveInsulin = correctionBolus - activeInsulin
                    recommendedBolus += max(0, correctionBolusMinusActiveInsulin)
                } else {
                    recommendedBolus += correctionBolus
                }
            }
            
            let recommendationLimit = mealCarbs != nil ? LoopConstants.simpleBolusCalculatorMinGlucoseMealBolusRecommendation : LoopConstants.simpleBolusCalculatorMinGlucoseBolusRecommendation
            
            if manualGlucose < recommendationLimit {
                recommendedBolus = 0
            }
        }
        
        // No negative recommendation
        recommendedBolus = max(0, recommendedBolus)
        
        return HKQuantity(unit: .internationalUnit(), doubleValue: recommendedBolus)
    }
}
