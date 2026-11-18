//
//  LoopConstants.swift
//  Loop
//
//  Created by Pete Schwamb on 10/7/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit
import UIKit

public enum LoopConstants {
    
    // Input field bounds
    
    public static let maxCarbEntryQuantity = LoopQuantity(unit: .gram, doubleValue: 250) // cannot exceed this value

    public static let warningCarbEntryQuantity = LoopQuantity(unit: .gram, doubleValue: 99) // user is warned above this value
    
    public static let validManualGlucoseEntryRange = LoopQuantity(unit: .milligramsPerDeciliter, doubleValue: 10)...LoopQuantity(unit: .milligramsPerDeciliter, doubleValue: 600)
    
    public static let minCarbAbsorptionTime = TimeInterval(minutes: 30)
    public static let maxCarbAbsorptionTime = TimeInterval(hours: 8)
    
    public static let maxCarbEntryPastTime = TimeInterval(hours: (-12))
    public static let maxCarbEntryFutureTime = TimeInterval(hours: 1)

    public static let maxOverrideDurationTime = TimeInterval(hours: 24)
    
    // MARK - Display settings

    public static let minimumChartWidthPerHour: CGFloat = 50

    public static let statusChartMinimumHistoryDisplay: TimeInterval = .hours(1)

    /// Chart width the time window options are sized for: a portrait iPhone.
    public static let statusChartReferenceWidth: CGFloat = 360

    public static let statusChartMaximumWidthScale: CGFloat = 2

    public static let chartMinimumWidthPerTimeLabel: CGFloat = 44

    public static let glucoseChartDefaultDisplayBound =
        LoopQuantity(unit: .milligramsPerDeciliter, doubleValue: 100)...LoopQuantity(unit: .milligramsPerDeciliter, doubleValue: 175)

    public static let glucoseChartDefaultDisplayRangeWide =
        LoopQuantity(unit: .milligramsPerDeciliter, doubleValue: 60)...LoopQuantity(unit: .milligramsPerDeciliter, doubleValue: 200)

    public static let glucoseChartDefaultDisplayBoundClamped =
        LoopQuantity(unit: .milligramsPerDeciliter, doubleValue: 80)...LoopQuantity(unit: .milligramsPerDeciliter, doubleValue: 240)
    
    
    // Compile time configuration
   
    public static let retrospectiveCorrectionEnabled = true
    
    /// Loop completion aging category limits
    public static let completionFreshLimit = TimeInterval(minutes: 6)
    public static let completionAgingLimit = TimeInterval(minutes: 16)
    public static let completionStaleLimit = TimeInterval(hours: 12)
 
    public static let batteryReplacementDetectionThreshold = 0.5
 
    public static let defaultWatchCarbPickerValue = 15 // grams
    
    public static let defaultWatchBolusPickerValue = 1.0 // %
    
    /// Missed Meal warning constants
    public static let missedMealWarningGlucoseRiseThreshold = 3.0 // mg/dL/m
    public static let missedMealWarningGlucoseRecencyWindow = TimeInterval(minutes: 19)
    
    // Bolus calculator warning thresholds
    public static let simpleBolusCalculatorMinGlucoseBolusRecommendation = LoopQuantity(unit: .milligramsPerDeciliter, doubleValue: 70)
    public static let simpleBolusCalculatorMinGlucoseMealBolusRecommendation = LoopQuantity(unit: .milligramsPerDeciliter, doubleValue: 55)
    public static let simpleBolusCalculatorGlucoseWarningLimit = LoopQuantity(unit: .milligramsPerDeciliter, doubleValue: 70)
}
