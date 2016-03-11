//
//  DoseMath.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 3/8/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation
import HealthKit
import LoopKit


struct TempBasalHistoryRecord {
    let rate: Double
    let startDate: NSDate
    let endDate: NSDate
}


class DoseMath {
    private static func calculateTempBasalRateForGlucose(currentGlucose: HKQuantity, toTargetGlucose targetGlucose: HKQuantity, insulinSensitivity: HKQuantity, currentBasalRate: Double, maxBasalRate: Double, duration: NSTimeInterval) -> Double {
        let unit = HKUnit.milligramsPerDeciliterUnit()
        let doseUnits = (currentGlucose.doubleValueForUnit(unit) - targetGlucose.doubleValueForUnit(unit)) / insulinSensitivity.doubleValueForUnit(unit)

        let rate = min(maxBasalRate, max(0, doseUnits / (duration / NSTimeInterval(hours: 1)) + currentBasalRate))

        return round(rate * basalStrokes) / basalStrokes
    }

    static let basalStrokes: Double = 40

    // Assumes absolute TempBasal
    static func recommendTempBasalFromPredictedGlucose(glucose: [GlucoseValue],
        atDate date: NSDate = NSDate(),
        lastTempBasal: TempBasalHistoryRecord?,
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

        if let lastTempBasal = lastTempBasal where lastTempBasal.endDate > date {
            if let determinedRate = rate {
                // Ignore the dose if the current dose is the same rate and has more than 10 minutes remaining
                if determinedRate == lastTempBasal.rate && lastTempBasal.endDate.timeIntervalSinceDate(date) > NSTimeInterval(minutes: 11) {
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
}
