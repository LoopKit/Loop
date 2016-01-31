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
    /**
     Calculates slope and intercept using linear regression
     
     This implementation is not suited for large datasets.

     - parameter points: An array of tuples containing x and y values

     - returns: A tuple of slope and intercept values
     */
    private static func linearRegression(points: [(x: Double, y: Double)]) -> (slope: Double, intercept: Double) {
        var sumX = 0.0
        var sumY = 0.0
        var sumXY = 0.0
        var sumX² = 0.0
        var sumY² = 0.0
        let count = Double(points.count)

        for point in points  {
            sumX += point.x
            sumY += point.y
            sumXY += (point.x * point.y)
            sumX² += (point.x * point.x)
            sumY² += (point.y * point.y)
        }

        let slope = ((count * sumXY) - (sumX * sumY)) / ((count * sumX²) - (sumX * sumX))
        let intercept = (sumY * sumX² - (sumX * sumXY)) / (count * sumX² - (sumX * sumX))

        return (slope: slope, intercept: intercept)
    }

    /**
     Calculates the short-term predicted trend of a sequence of glucose values using linear regression

     - parameter samples:  The sequence of glucose, in chronological order
     - parameter duration: The trend duration to return
     - parameter delta:    The time differential for the returned values

     - returns: An array of glucose effects
     */
    static func linearMomentumEffectForGlucoseEntries(
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

        let xy = samples.map { (
            x: $0.startDate.timeIntervalSinceDate(firstSample.startDate),
            y: $0.quantity.doubleValueForUnit(CalculationUnit)
        ) }

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
