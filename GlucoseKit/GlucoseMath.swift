//
//  GlucoseMath.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 1/24/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation
import HealthKit
import LoopKit


struct GlucoseValue: SampleValue {
    let startDate: NSDate
    let quantity: HKQuantity
}


/// To determine if we have a contiguous set of values, we require readings to be an average of 5 minutes apart
private let ContinuousGlucoseInterval = NSTimeInterval(minutes: 5)

/// The unit to use during calculation
private let CalculationUnit = HKUnit.milligramsPerDeciliterUnit()


struct GlucoseMath {

    private static func linearRegression(array: [(xValue: Double, yValue: Double)]) -> (slope: Double, intercept: Double) {
        var sumX = 0.0
        var sumY = 0.0
        var sumXY = 0.0
        var sumX2 = 0.0
        var sumY2 = 0.0
        let numberOfItems = Double(array.count)

        for arrayItem in array  {
            sumX += arrayItem.xValue
            sumY += arrayItem.yValue
            sumXY += (arrayItem.xValue * arrayItem.yValue)
            sumX2 += (arrayItem.xValue * arrayItem.xValue)
            sumY2 += (arrayItem.yValue * arrayItem.yValue)
        }
        let slope = ((numberOfItems * sumXY) - (sumX * sumY)) / ((numberOfItems * sumX2) - (sumX * sumX))
        let intercept = (sumY * sumX2 - (sumX * sumXY)) / (numberOfItems * sumX2 - (sumX * sumX))

        return (slope: slope, intercept: intercept)
    }

    static func momentumEffectForGlucoseEntries(
        samples: [GlucoseValue],  // Chronological order for now
        duration: NSTimeInterval = NSTimeInterval(minutes: 30),
        delta: NSTimeInterval = NSTimeInterval(minutes: 5)
    ) -> [GlucoseEffect] {
        guard
            samples.count > 1,
            let firstSample = samples.first,
                lastSample = samples.last,
                (startDate, endDate) = LoopMath.simulationDateRangeForSamples([lastSample], duration: duration, delta: delta)
            where
                // Ensure that the entries are contiguous
                abs(firstSample.startDate.timeIntervalSinceDate(lastSample.startDate)) < ContinuousGlucoseInterval * Double(samples.count)
            else {
            return []
        }

        let xy = samples.map { (xValue: $0.startDate.timeIntervalSinceDate(firstSample.startDate), yValue: $0.quantity.doubleValueForUnit(CalculationUnit)) }

        let (slope: slope, intercept: _) = linearRegression(xy)

        var date = startDate
        var values = [GlucoseEffect]()

        repeat {
            let value = max(0, date.timeIntervalSinceDate(lastSample.startDate)) * slope

            values.append(GlucoseEffect(startDate: date, quantity: HKQuantity(unit: CalculationUnit, doubleValue: value)))
            date = date.dateByAddingTimeInterval(delta)
        } while date <= endDate

        return values
    }
}
