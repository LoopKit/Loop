//
//  LoopConstants.swift
//  Loop
//
//  Created by Pete Schwamb on 10/7/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import Foundation
import HealthKit
import LoopKit
import UIKit

enum LoopConstants {
    
    // Input field bounds
    
    static let maxCarbEntryQuantity = HKQuantity(unit: .gram(), doubleValue: 250) // cannot exceed this value

    static let warningCarbEntryQuantity = HKQuantity(unit: .gram(), doubleValue: 99) // user is warned above this value
    
    static let validManualGlucoseEntryRange = HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 10)...HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 600)
    
    static let minCarbAbsorptionTime = TimeInterval(minutes: 30)
    static let maxCarbAbsorptionTime = TimeInterval(hours: 8)
    
    static let maxCarbEntryPastTime = TimeInterval(hours: (-12))
    static let maxCarbEntryFutureTime = TimeInterval(hours: 1)

    static let maxOverrideDurationTime = TimeInterval(hours: 24)
    
    // MARK - Display settings

    static let minimumChartWidthPerHour: CGFloat = 50

    static let statusChartMinimumHistoryDisplay: TimeInterval = .hours(1)

    static let glucoseChartDefaultDisplayBound =
        HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 100)...HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 175)

    static let glucoseChartDefaultDisplayRangeWide =
        HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 60)...HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 200)

    static let glucoseChartDefaultDisplayBoundClamped =
        HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 80)...HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 240)
    
    
    // Compile time configuration
   
    static let retrospectiveCorrectionEnabled = true
    
    // Percentage of recommended dose to apply as bolus when using automatic bolus dosing strategy
    static let bolusPartialApplicationFactor = 0.8

    /// Loop completion aging category limits
    static let completionFreshLimit = TimeInterval(minutes: 6)
    static let completionAgingLimit = TimeInterval(minutes: 16)
    static let completionStaleLimit = TimeInterval(hours: 12)
 
    static let batteryReplacementDetectionThreshold = 0.5
 
    static let defaultWatchCarbPickerValue = 15 // grams
    
    static let defaultWatchBolusPickerValue = 1.0 // %
    
    /// Missed Meal warning constants
    static let missedMealWarningGlucoseRiseThreshold = 3.0 // mg/dL/m
    static let missedMealWarningGlucoseRecencyWindow = TimeInterval(minutes: 20)
    static let missedMealWarningVelocitySampleMinDuration = TimeInterval(minutes: 12)
    
    // Bolus calculator warning thresholds
    static let simpleBolusCalculatorMinGlucoseBolusRecommendation = HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 70)
    static let simpleBolusCalculatorMinGlucoseMealBolusRecommendation = HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 55)
    static let simpleBolusCalculatorGlucoseWarningLimit = HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 70)
}
