//
//  CarbMath.swift
//  CarbKit
//
//  Created by Nathan Racklyeft on 1/16/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation
import HealthKit
import LoopKit


public struct CarbValue: SampleValue {
    public let startDate: NSDate
    public let quantity: HKQuantity
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

    private static func carbsOnBoardForCarbEntry(entry: CarbEntry, atDate date: NSDate, defaultAbsorptionTime: NSTimeInterval, delay: NSTimeInterval) -> Double {
        let time = date.timeIntervalSinceDate(entry.startDate)
        let value: Double

        if time >= 0 {
            value = unabsorbedCarbs(entry.quantity.doubleValueForUnit(HKUnit.gramUnit()), atTime: time - delay, absorptionTime: entry.absorptionTime ?? defaultAbsorptionTime)
        } else {
            value = 0
        }

        return value
    }

    // mg/dL / g * g
    private static func glucoseEffectForCarbEntry(
        entry: CarbEntry,
        atDate date: NSDate,
        carbRatio: HKQuantity,
        insulinSensitivity: HKQuantity,
        defaultAbsorptionTime: NSTimeInterval,
        delay: NSTimeInterval
    ) -> Double {
        let time = date.timeIntervalSinceDate(entry.startDate)
        let value: Double
        let unit = HKUnit.gramUnit()

        if time >= 0 {
            value = insulinSensitivity.doubleValueForUnit(HKUnit.milligramsPerDeciliterUnit()) / carbRatio.doubleValueForUnit(unit) * absorbedCarbs(entry.quantity.doubleValueForUnit(unit), atTime: time - delay, absorptionTime: entry.absorptionTime ?? defaultAbsorptionTime)
        } else {
            value = 0
        }

        return value
    }

    private static func simulationDateRangeForCarbEntries<T: CollectionType where T.Generator.Element: CarbEntry>(
        entries: T,
        fromDate: NSDate?,
        toDate: NSDate?,
        defaultAbsorptionTime: NSTimeInterval,
        delay: NSTimeInterval,
        delta: NSTimeInterval
    ) -> (NSDate, NSDate)? {
        var maxAbsorptionTime = defaultAbsorptionTime

        for entry in entries {
            if let absorptionTime = entry.absorptionTime where absorptionTime > maxAbsorptionTime {
                maxAbsorptionTime = absorptionTime
            }
        }

        return LoopMath.simulationDateRangeForSamples(entries, fromDate: fromDate, toDate: toDate, duration: maxAbsorptionTime, delay: delay, delta: delta)
    }

    static func carbsOnBoardForCarbEntries<T: CollectionType where T.Generator.Element: CarbEntry>(
        entries: T,
        fromDate: NSDate? = nil,
        toDate: NSDate? = nil,
        defaultAbsorptionTime: NSTimeInterval,
        delay: NSTimeInterval = NSTimeInterval(minutes: 10),
        delta: NSTimeInterval = NSTimeInterval(minutes: 5)
    ) -> [CarbValue] {
        guard let (startDate, endDate) = simulationDateRangeForCarbEntries(entries, fromDate: fromDate, toDate: toDate, defaultAbsorptionTime: defaultAbsorptionTime, delay: delay, delta: delta) else {
            return []
        }

        var date = startDate
        var values = [CarbValue]()

        repeat {
            let value = entries.reduce(0.0) { (value, entry) -> Double in
                return value + carbsOnBoardForCarbEntry(entry, atDate: date, defaultAbsorptionTime: defaultAbsorptionTime, delay: delay)
            }

            values.append(CarbValue(startDate: date, quantity: HKQuantity(unit: HKUnit.gramUnit(), doubleValue: value)))
            date = date.dateByAddingTimeInterval(delta)
        } while date <= endDate

        return values
    }

    static func glucoseEffectsForCarbEntries<T: CollectionType where T.Generator.Element: CarbEntry>(
        entries: T,
        fromDate: NSDate? = nil,
        toDate: NSDate? = nil,
        carbRatios: CarbRatioSchedule,
        insulinSensitivities: InsulinSensitivitySchedule,
        defaultAbsorptionTime: NSTimeInterval,
        delay: NSTimeInterval = NSTimeInterval(minutes: 10),
        delta: NSTimeInterval = NSTimeInterval(minutes: 5)
    ) -> [GlucoseEffect] {
        guard let (startDate, endDate) = simulationDateRangeForCarbEntries(entries, fromDate: fromDate, toDate: toDate, defaultAbsorptionTime: defaultAbsorptionTime, delay: delay, delta: delta) else {
            return []
        }

        var date = startDate
        var values = [GlucoseEffect]()
        let unit = HKUnit.milligramsPerDeciliterUnit()

        repeat {
            let value = entries.reduce(0.0) { (value, entry) -> Double in
                return value + glucoseEffectForCarbEntry(entry, atDate: date, carbRatio: carbRatios.at(entry.startDate), insulinSensitivity: insulinSensitivities.at(entry.startDate), defaultAbsorptionTime: defaultAbsorptionTime, delay: delay)
            }

            values.append(GlucoseEffect(startDate: date, quantity: HKQuantity(unit: unit, doubleValue: value)))
            date = date.dateByAddingTimeInterval(delta)
        } while date <= endDate

        return values
    }

    static func totalCarbsForCarbEntries(entries: [CarbEntry]) -> CarbValue? {
        guard entries.count > 0 else {
            return nil
        }

        let unit = HKUnit.gramUnit()
        var startDate = NSDate.distantFuture()
        var totalGrams: Double = 0

        for entry in entries {
            totalGrams += entry.quantity.doubleValueForUnit(unit)

            if entry.startDate < startDate {
                startDate = entry.startDate
            }
        }

        return CarbValue(startDate: startDate, quantity: HKQuantity(unit: unit, doubleValue: totalGrams))
    }
}
