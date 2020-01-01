//
//  RetrospectiveCorrection.swift
//  Loop
//
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import Foundation
import HealthKit
import LoopKit


/// Derives a continued glucose effect from recent prediction discrepancies
protocol RetrospectiveCorrection: CustomDebugStringConvertible {
    /// The maximum interval of historical glucose discrepancies that should be provided to the computation
    var retrospectionInterval: TimeInterval { get }

    /// Overall retrospective correction effect
    var totalGlucoseCorrectionEffect: HKQuantity? { get }

    /// Calculates overall correction effect based on timeline of discrepancies, and updates glucoseCorrectionEffect
    ///
    /// - Parameters:
    ///   - glucose: Most recent glucose
    ///   - retrospectiveGlucoseDiscrepanciesSummed: Timeline of past discepancies
    /// - Returns: Glucose correction effects
    func computeEffect(
        startingAt startingGlucose: GlucoseValue,
        retrospectiveGlucoseDiscrepanciesSummed: [GlucoseChange]?,
        recencyInterval: TimeInterval,
        insulinSensitivitySchedule: InsulinSensitivitySchedule?,
        basalRateSchedule: BasalRateSchedule?,
        glucoseCorrectionRangeSchedule: GlucoseRangeSchedule?,
        retrospectiveCorrectionGroupingInterval: TimeInterval
    ) -> [GlucoseEffect]
}
