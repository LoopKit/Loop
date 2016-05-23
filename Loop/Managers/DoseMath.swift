//
//  DoseMath.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 3/8/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation
import HealthKit
import InsulinKit
import LoopKit


class DoseMath {
    /// The allowed precision
    static let basalStrokes: Double = 40

    /**
     Calculates the necessary temporary basal rate to transform a glucose value to a target.
     
     This assumes a constant insulin sensitivity, independent of current glucose or insulin-on-board.

     - parameter currentGlucose:     The current glucose
     - parameter targetGlucose:      The desired glucose
     - parameter insulinSensitivity: The insulin sensitivity, in Units of insulin per glucose-unit
     - parameter currentBasalRate:   The normally-scheduled basal rate
     - parameter maxBasalRate:       The maximum basal rate, used to constrain the output
     - parameter duration:           The temporary duration to run the basal

     - returns: The determined basal rate, in Units/hour
     */
    private static func calculateTempBasalRateForGlucose(currentGlucose: HKQuantity, toTargetGlucose targetGlucose: HKQuantity, insulinSensitivity: HKQuantity, currentBasalRate: Double, maxBasalRate: Double, duration: NSTimeInterval) -> Double {
        let unit = HKUnit.milligramsPerDeciliterUnit()
        let doseUnits = (currentGlucose.doubleValueForUnit(unit) - targetGlucose.doubleValueForUnit(unit)) / insulinSensitivity.doubleValueForUnit(unit)

        let rate = min(maxBasalRate, max(0, doseUnits / (duration / NSTimeInterval(hours: 1)) + currentBasalRate))

        return round(rate * basalStrokes) / basalStrokes
    }

    /**
     Recommends a temporary basal rate to conform a glucose prediction timeline to a target range

     Returns nil if the normal scheduled basal, or active temporary basal, is sufficient.

     - parameter glucose:                       The ascending timeline of predicted glucose values
     - parameter date:                          The date at which the temporary basal rate would start. Defaults to the current date.
     - parameter lastTempBasal:                 The last-set temporary basal
     - parameter maxBasalRate:                  The maximum basal rate, in Units/hour, used to constrain the output
     - parameter glucoseTargetRange:            The schedule of target glucose ranges
     - parameter insulinSensitivity:            The schedule of insulin sensitivities, in Units of insulin per glucose-unit
     - parameter basalRateSchedule:             The schedule of basal rates
     - parameter allowPredictiveTempBelowRange: Whether to allow a higher basal rate, up to the normal scheduled rate, than is necessary to correct the lowest predicted value, if the eventual predicted value is in or above the target range. Defaults to false.

     - returns: The recommended basal rate and duration
     */
    static func recommendTempBasalFromPredictedGlucose(glucose: [GlucoseValue],
        atDate date: NSDate = NSDate(),
        lastTempBasal: DoseEntry?,
        maxBasalRate: Double,
        glucoseTargetRange: GlucoseRangeSchedule,
        insulinSensitivity: InsulinSensitivitySchedule,
        basalRateSchedule: BasalRateSchedule,
        allowPredictiveTempBelowRange: Bool = false
    ) -> (rate: Double, duration: NSTimeInterval)? {
        guard glucose.count > 1 else {
            return nil
        }

        let eventualGlucose = glucose.last!
        let minGlucose = glucose.minElement { $0.quantity < $1.quantity }!

        let eventualGlucoseTargets = glucoseTargetRange.valueAt(eventualGlucose.startDate)
        let minGlucoseTargets = glucoseTargetRange.valueAt(minGlucose.startDate)
        let currentSensitivity = insulinSensitivity.quantityAt(date)
        let currentScheduledBasalRate = basalRateSchedule.valueAt(date)

        var rate: Double?
        var duration = NSTimeInterval(minutes: 30)

        if minGlucose.quantity.doubleValueForUnit(glucoseTargetRange.unit) < minGlucoseTargets.minValue && (!allowPredictiveTempBelowRange || eventualGlucose.quantity.doubleValueForUnit(glucoseTargetRange.unit) <= eventualGlucoseTargets.minValue) {
            let targetGlucose = HKQuantity(unit: glucoseTargetRange.unit, doubleValue: (minGlucoseTargets.minValue + minGlucoseTargets.maxValue) / 2)
            rate = calculateTempBasalRateForGlucose(minGlucose.quantity,
                toTargetGlucose: targetGlucose,
                insulinSensitivity: currentSensitivity,
                currentBasalRate: currentScheduledBasalRate,
                maxBasalRate: maxBasalRate,
                duration: duration
            )
        } else if eventualGlucose.quantity.doubleValueForUnit(glucoseTargetRange.unit) > eventualGlucoseTargets.maxValue {
            var adjustedMaxBasalRate = maxBasalRate
            if minGlucose.quantity.doubleValueForUnit(glucoseTargetRange.unit) < minGlucoseTargets.minValue {
                adjustedMaxBasalRate = currentScheduledBasalRate
            }

            let targetGlucose = HKQuantity(unit: glucoseTargetRange.unit, doubleValue: (eventualGlucoseTargets.minValue + eventualGlucoseTargets.maxValue) / 2)
            rate = calculateTempBasalRateForGlucose(eventualGlucose.quantity,
                toTargetGlucose: targetGlucose,
                insulinSensitivity: currentSensitivity,
                currentBasalRate: currentScheduledBasalRate,
                maxBasalRate: adjustedMaxBasalRate,
                duration: duration
            )
        }

        if let determinedRate = rate where determinedRate == currentScheduledBasalRate {
            rate = nil
        }

        if let lastTempBasal = lastTempBasal where lastTempBasal.unit == .UnitsPerHour && lastTempBasal.endDate > date {
            if let determinedRate = rate {
                // Ignore the dose if the current dose is the same rate and has more than 10 minutes remaining
                if determinedRate == lastTempBasal.value && lastTempBasal.endDate.timeIntervalSinceDate(date) > NSTimeInterval(minutes: 11) {
                    rate = nil
                }
            } else {
                // If we prefer to not have a dose, cancel the one in progress
                rate = 0
                duration = NSTimeInterval(0)
            }
        }

        if let rate = rate {
            return (rate: rate, duration: duration)
        } else {
            return nil
        }
    }

    /**
     Recommends a bolus to conform a glucose prediction timeline to a target range

     - parameter glucose:            The ascending timeline of predicted glucose values
     - parameter date:               The date at which the bolus would apply. Defaults to the current date.
     - parameter lastTempBasal:      The last-set temporary basal
     - parameter maxBolus:           The maximum bolus, used to constrain the output
     - parameter glucoseTargetRange: The schedule of target glucose ranges
     - parameter insulinSensitivity: The schedule of insulin sensitivities, in Units of insulin per glucose-unit
     - parameter basalRateSchedule:  The schedule of basal rates

     - returns: The recommended bolus
     */
    static func recommendBolusFromPredictedGlucose(glucose: [GlucoseValue],
        atDate date: NSDate = NSDate(),
        lastTempBasal: DoseEntry?,
        maxBolus: Double,
        glucoseTargetRange: GlucoseRangeSchedule,
        insulinSensitivity: InsulinSensitivitySchedule,
        basalRateSchedule: BasalRateSchedule
    ) -> Double {
        guard glucose.count > 1 else {
            return 0
        }

        let eventualGlucose = glucose.last!
        let minGlucose = glucose.minElement { $0.quantity < $1.quantity }!

        let eventualGlucoseTargets = glucoseTargetRange.valueAt(eventualGlucose.startDate)
        let minGlucoseTargets = glucoseTargetRange.valueAt(minGlucose.startDate)

        guard minGlucose.quantity.doubleValueForUnit(glucoseTargetRange.unit) >= minGlucoseTargets.minValue else {
            return 0
        }

        let targetGlucose = eventualGlucoseTargets.maxValue
        let currentSensitivity = insulinSensitivity.quantityAt(date).doubleValueForUnit(glucoseTargetRange.unit)

        var doseUnits = (eventualGlucose.quantity.doubleValueForUnit(glucoseTargetRange.unit) - targetGlucose) / currentSensitivity

        if let lastTempBasal = lastTempBasal where lastTempBasal.unit == .UnitsPerHour && lastTempBasal.endDate > date {
            let normalBasalRate = basalRateSchedule.valueAt(date)
            let remainingTime = lastTempBasal.endDate.timeIntervalSinceDate(date)
            let remainingUnits = (lastTempBasal.value - normalBasalRate) * remainingTime / NSTimeInterval(hours: 1)

            doseUnits -= max(0, remainingUnits)
        }

        return max(0, doseUnits)
    }
}
