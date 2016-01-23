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


public protocol SampleValue {
    var startDate: NSDate { get }
    var value: Double { get }
    var unit: HKUnit { get }
}

extension SampleValue {
    var quantity: HKQuantity {
        return HKQuantity(unit: unit, doubleValue: value)
    }
}


public struct CarbValue: SampleValue {
    public let startDate: NSDate
    public let value: Double
    public let unit: HKUnit = HKUnit.gramUnit()
}


struct GlucoseEffect: SampleValue {
    let startDate: NSDate
    let value: Double
    let unit: HKUnit
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
            value = unabsorbedCarbs(entry.value, atTime: time - delay, absorptionTime: entry.absorptionTime ?? defaultAbsorptionTime)
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

        if time >= 0 {
            value = insulinSensitivity.doubleValueForUnit(HKUnit.milligramsPerDeciliterUnit()) / carbRatio.doubleValueForUnit(HKUnit.gramUnit()) * absorbedCarbs(entry.value, atTime: time - delay, absorptionTime: entry.absorptionTime ?? defaultAbsorptionTime)
        } else {
            value = 0
        }

        return value
    }

    private static func simulationDateRangeForCarbEntries(
        entries: [CarbEntry],
        fromDate: NSDate?,
        toDate: NSDate?,
        defaultAbsorptionTime: NSTimeInterval,
        delay: NSTimeInterval,
        delta: NSTimeInterval
    ) -> (NSDate, NSDate)? {
        guard entries.count > 0 else {
            return nil
        }

        let startDate: NSDate
        let endDate: NSDate

        if let fromDate = fromDate, toDate = toDate {
            startDate = fromDate
            endDate = toDate
        } else {
            var minDate = entries.first!.startDate
            var maxDate = minDate
            var maxAbsorptionTime = defaultAbsorptionTime

            for entry in entries {
                if entry.startDate < minDate {
                    minDate = entry.startDate
                }

                if entry.startDate > maxDate {
                    maxDate = entry.startDate
                }

                if let absorptionTime = entry.absorptionTime where absorptionTime > maxAbsorptionTime {
                    maxAbsorptionTime = absorptionTime
                }
            }

            startDate = fromDate ?? minDate.dateFlooredToTimeInterval(delta)
            endDate = toDate ?? maxDate.dateByAddingTimeInterval(maxAbsorptionTime + delay).dateCeiledToTimeInterval(delta)
        }
        
        return (startDate, endDate)
    }

    static func carbsOnBoardForCarbEntries(
        entries: [CarbEntry],
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

            values.append(CarbValue(startDate: date, value: value))
            date = date.dateByAddingTimeInterval(delta)
        } while date <= endDate

        return values
    }

    static func glucoseEffectsForCarbEntries(
        entries: [CarbEntry],
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

            values.append(GlucoseEffect(startDate: date, value: value, unit: unit))
            date = date.dateByAddingTimeInterval(delta)
        } while date <= endDate

        return values
    }

    static func totalCarbsForCarbEntries(entries: [CarbEntry]) -> CarbValue? {
        guard entries.count > 0 else {
            return nil
        }

        var startDate = NSDate.distantFuture()
        var totalGrams: Double = 0

        for entry in entries {
            totalGrams += entry.value

            if entry.startDate < startDate {
                startDate = entry.startDate
            }
        }

        return CarbValue(startDate: startDate, value: totalGrams)
    }
}
