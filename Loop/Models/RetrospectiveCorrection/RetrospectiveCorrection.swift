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
    ///   - startingAt: Initial glucose value
    ///   - retrospectiveGlucoseDiscrepanciesSummed: Timeline of past discepancies
    ///   - recencyInterval: how recent discrepancy data must be, otherwise effect will be cleared
    ///   - insulinSensitivitySchedule: Insulin sensitivity schedule
    ///   - basalRateSchedule: Basal rate schedule
    ///   - glucoseCorrectionRangeSchedule: Correction range schedule
    ///   - retrospectiveCorrectionGroupingInterval: Duration of discrepancy measurements
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
