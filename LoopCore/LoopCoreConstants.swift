//
//  LoopCoreConstants.swift
//  LoopCore
//
//  Created by Pete Schwamb on 10/16/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit

public typealias DefaultAbsorptionTimes = (fast: TimeInterval, medium: TimeInterval, slow: TimeInterval)

public enum LoopCoreConstants {
    /// The amount of time in the future a glucose value should be considered valid
    public static let futureGlucoseDataInterval = TimeInterval(minutes: 5)

    /// How old glucose and pump data can be for the algorithm to run; matches LoopAlgorithm's limit
    public static let inputDataRecencyInterval = TimeInterval(minutes: 15)

    /// The longest a carb entry can take to absorb; matches LoopAlgorithm's limit
    public static let maximumCarbAbsorptionTimeInterval = TimeInterval(hours: 10)

    public static let defaultCarbAbsorptionTimes: DefaultAbsorptionTimes = (fast: .minutes(30), medium: .hours(3), slow: .hours(5))

    /// How much historical glucose to include in a dosing decision
    /// Somewhat arbitrary, but typical maximum visible in bolus glucose preview
    public static let dosingDecisionHistoricalGlucoseInterval = TimeInterval(hours: 2)
}
