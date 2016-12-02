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


struct DoseMath {
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
    private static func calculateTempBasalRateForGlucose(_ currentGlucose: HKQuantity, toTargetGlucose targetGlucose: HKQuantity, insulinSensitivity: HKQuantity, currentBasalRate: Double, maxBasalRate: Double, duration: TimeInterval) -> Double {
        let unit = HKUnit.milligramsPerDeciliterUnit()
        let doseUnits = (currentGlucose.doubleValue(for: unit) - targetGlucose.doubleValue(for: unit)) / insulinSensitivity.doubleValue(for: unit)

        let rate = min(maxBasalRate, max(0, doseUnits / (duration / TimeInterval(hours: 1)) + currentBasalRate))

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
    static func recommendTempBasalFromPredictedGlucose(_ glucose: [GlucoseValue],
        atDate date: Date = Date(),
        lastTempBasal: DoseEntry?,
        maxBasalRate: Double,
        glucoseTargetRange: GlucoseRangeSchedule,
        insulinSensitivity: InsulinSensitivitySchedule,
        basalRateSchedule: BasalRateSchedule,
        allowPredictiveTempBelowRange: Bool
    ) -> (rate: Double, duration: TimeInterval)? {
        guard glucose.count > 1 else {
            return nil
        }

        let eventualGlucose = glucose.last!
        let minGlucose = glucose.min { $0.quantity < $1.quantity }!

        let eventualGlucoseTargets = glucoseTargetRange.value(at: eventualGlucose.startDate)
        let minGlucoseTargets = glucoseTargetRange.value(at: minGlucose.startDate)
        let currentSensitivity = insulinSensitivity.quantity(at: date)
        let currentScheduledBasalRate = basalRateSchedule.value(at: date)

        var rate: Double?
        var duration = TimeInterval(minutes: 30)

        if minGlucose.quantity.doubleValue(for: glucoseTargetRange.unit) < minGlucoseTargets.minValue && (!allowPredictiveTempBelowRange || eventualGlucose.quantity.doubleValue(for: glucoseTargetRange.unit) <= eventualGlucoseTargets.minValue) {
            let targetGlucose = HKQuantity(unit: glucoseTargetRange.unit, doubleValue: (minGlucoseTargets.minValue + minGlucoseTargets.maxValue) / 2)
            rate = calculateTempBasalRateForGlucose(minGlucose.quantity,
                toTargetGlucose: targetGlucose,
                insulinSensitivity: currentSensitivity,
                currentBasalRate: currentScheduledBasalRate,
                maxBasalRate: maxBasalRate,
                duration: duration
            )
        } else if eventualGlucose.quantity.doubleValue(for: glucoseTargetRange.unit) > eventualGlucoseTargets.maxValue {
            var adjustedMaxBasalRate = maxBasalRate
            if minGlucose.quantity.doubleValue(for: glucoseTargetRange.unit) < minGlucoseTargets.minValue {
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

        if let determinedRate = rate, determinedRate == currentScheduledBasalRate {
            rate = nil
        }

        if let lastTempBasal = lastTempBasal, lastTempBasal.unit == .unitsPerHour && lastTempBasal.endDate > date {
            if let determinedRate = rate {
                // Ignore the dose if the current dose is the same rate and has more than 10 minutes remaining
                if determinedRate == lastTempBasal.value && lastTempBasal.endDate.timeIntervalSince(date) > TimeInterval(minutes: 11) {
                    rate = nil
                }
            } else {
                // If we prefer to not have a dose, cancel the one in progress
                rate = 0
                duration = TimeInterval(0)
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
    static func recommendBolusFromPredictedGlucose(_ glucose: [GlucoseValue],
        atDate date: Date = Date(),
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
        let minGlucose = glucose.min { $0.quantity < $1.quantity }!

        let eventualGlucoseTargets = glucoseTargetRange.value(at: eventualGlucose.startDate)
        // Use between to opt-out of the override.
        let minGlucoseTargets = glucoseTargetRange.between(start: minGlucose.startDate, end: minGlucose.startDate).first!.value

        guard minGlucose.quantity.doubleValue(for: glucoseTargetRange.unit) >= minGlucoseTargets.minValue else {
            return 0
        }

        let targetGlucose = eventualGlucoseTargets.maxValue
        let currentSensitivity = insulinSensitivity.quantity(at: date).doubleValue(for: glucoseTargetRange.unit)

        var doseUnits = (eventualGlucose.quantity.doubleValue(for: glucoseTargetRange.unit) - targetGlucose) / currentSensitivity

        if let lastTempBasal = lastTempBasal, lastTempBasal.unit == .unitsPerHour && lastTempBasal.endDate > date {
            let normalBasalRate = basalRateSchedule.value(at: date)
            let remainingTime = lastTempBasal.endDate.timeIntervalSince(date)
            let remainingUnits = (lastTempBasal.value - normalBasalRate) * remainingTime / TimeInterval(hours: 1)

            doseUnits -= max(0, remainingUnits)
        }

        doseUnits = round(doseUnits * 40) / 40

        return min(maxBolus, max(0, doseUnits))
    }
}
