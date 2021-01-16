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

enum LoopConstants {
    
    // Input field bounds
    
    static let maxCarbEntryQuantity = HKQuantity(unit: .gram(), doubleValue: 250)
    
    static let validManualGlucoseEntryRange = HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 10)...HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 600)

    
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
    
    static let bolusPartialApplicationFactor = 0.4 // %

    /// The interval over which to aggregate changes in glucose for retrospective correction
    static let retrospectiveCorrectionGroupingInterval = TimeInterval(minutes: 30)

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
}
