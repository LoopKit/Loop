//
//  LoopConstants.swift
//  Loop
//
//  Created by Pete Schwamb on 10/7/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopAlgorithm
import LoopKit
import UIKit

enum LoopConstants {
    
    // Input field bounds
    
    static let maxCarbEntryQuantity = LoopQuantity(unit: .gram, doubleValue: 250) // cannot exceed this value

    static let warningCarbEntryQuantity = LoopQuantity(unit: .gram, doubleValue: 99) // user is warned above this value
    
    static let validManualGlucoseEntryRange = LoopQuantity(unit: .milligramsPerDeciliter, doubleValue: 10)...LoopQuantity(unit: .milligramsPerDeciliter, doubleValue: 600)
    
    static let minCarbAbsorptionTime = TimeInterval(minutes: 30)
    static let maxCarbAbsorptionTime = TimeInterval(hours: 8)
    
    static let maxCarbEntryPastTime = TimeInterval(hours: (-12))
    static let maxCarbEntryFutureTime = TimeInterval(hours: 1)

    static let maxOverrideDurationTime = TimeInterval(hours: 24)
    
    // MARK - Display settings

    static let minimumChartWidthPerHour: CGFloat = 50

    static let statusChartMinimumHistoryDisplay: TimeInterval = .hours(1)

    static let glucoseChartDefaultDisplayBound =
        LoopQuantity(unit: .milligramsPerDeciliter, doubleValue: 100)...LoopQuantity(unit: .milligramsPerDeciliter, doubleValue: 175)

    static let glucoseChartDefaultDisplayRangeWide =
        LoopQuantity(unit: .milligramsPerDeciliter, doubleValue: 60)...LoopQuantity(unit: .milligramsPerDeciliter, doubleValue: 200)

    static let glucoseChartDefaultDisplayBoundClamped =
        LoopQuantity(unit: .milligramsPerDeciliter, doubleValue: 80)...LoopQuantity(unit: .milligramsPerDeciliter, doubleValue: 240)
    
    
    // Compile time configuration
   
    static let retrospectiveCorrectionEnabled = true
    
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
    static let simpleBolusCalculatorMinGlucoseBolusRecommendation = LoopQuantity(unit: .milligramsPerDeciliter, doubleValue: 70)
    static let simpleBolusCalculatorMinGlucoseMealBolusRecommendation = LoopQuantity(unit: .milligramsPerDeciliter, doubleValue: 55)
    static let simpleBolusCalculatorGlucoseWarningLimit = LoopQuantity(unit: .milligramsPerDeciliter, doubleValue: 70)
}
