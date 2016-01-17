//
//  CarbMath.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 1/16/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation
import HealthKit


struct GlucoseEffect {
    let startAt: NSDate
    let endAt: NSDate
    let amount: Double
    let unit: HKUnit
    let description: String

    var quantity: HKQuantity {
        return HKQuantity(unit: unit, doubleValue: amount)
    }
}


struct CarbMath {
    /**
     Returns the percentage of total carbohydrates absorbed as blood glucose at a specified interval after eating.

     This is the integral approximation of the Scheiner GI curve found in Think Like a Pancreas, Fig 7-8, which first appeared in [GlucoDyn](https://github.com/kenstack/GlucoDyn)

     - parameter time:           The interval after the carbs were eaten
     - parameter absorptionTime: The total time of carb absorption

     - returns: The percentage of the total carbohydrates that have been absorbed as blood glucose
     */
    private static func percentAbsorptionAtTime(time: NSTimeInterval, absorptionTime: NSTimeInterval) -> Double {
        switch time {
        case let t where t < 0:
            return 0
        case let t where t <= absorptionTime / 2:
            return 2 / pow(absorptionTime, 2) * pow(t, 2)
        case let t where t < absorptionTime:
            return -1 + 4 / absorptionTime * (t - pow(t, 2) / (2 * absorptionTime))
        default:
            return 1
        }
    }

    private static func absorbedCarbs(carbs: Double, atTime time: NSTimeInterval, absorptionTime: NSTimeInterval) -> Double {
        return carbs * percentAbsorptionAtTime(time, absorptionTime: absorptionTime)
    }

    private static func unabsorbedCarbs(carbs: Double, atTime time: NSTimeInterval, absorptionTime: NSTimeInterval) -> Double {
        return carbs * (1 - percentAbsorptionAtTime(time, absorptionTime: absorptionTime))
    }

    static func glucoseEffectForCarbEntry(entry: CarbEntry, atDate date: NSDate, carbRatio: HKQuantity, insulinSensitivity: HKQuantity, defaultAbsorptionTime: NSTimeInterval) -> GlucoseEffect {
        let time = date.timeIntervalSinceDate(entry.startDate)
        let amount = insulinSensitivity.doubleValueForUnit(HKUnit.milligramsPerDeciliter()) / carbRatio.doubleValueForUnit(HKUnit.gramUnit()) * absorbedCarbs(entry.amount, atTime: time, absorptionTime: entry.absorptionTime ?? defaultAbsorptionTime)

        let unit = HKUnit.milligramsPerDeciliter()  // mg/dL / g * g

        return GlucoseEffect(startAt: date, endAt: date, amount: amount, unit: unit, description: String(format: "%.0fg @ %.0fmin", entry.amount, time.minutes))
    }

    static func glucoseEffectsForCarbEntries(entries: [CarbEntry], carbRatio: Double, insulinSensitivity: Double, defaultAbsorptionTime: NSTimeInterval) {

    }
}
