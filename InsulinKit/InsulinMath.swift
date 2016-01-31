//
//  InsulinMath.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 1/30/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation
import LoopKit


struct InsulinMath {

    /**
     Returns the percentage of total insulin effect remaining at a specified interval after delivery; also known as Insulin On Board (IOB).

     These are 4th-order polynomial fits of John Walsh's IOB curve plots, and they first appeared in GlucoDyn.

     See: https://github.com/kenstack/GlucoDyn

     - parameter time:           The interval after insulin delivery
     - parameter actionDuration: The total time of insulin effect

     - returns: The percentage of total insulin effect remaining
     */
    static func walshPercentEffectRemainingAtTime(time: NSTimeInterval, actionDuration: NSTimeInterval) -> Double? {

        switch time {
        case let t where t <= 0:
            return 1
        case let t where t >= actionDuration:
            return 0
        default:
            switch actionDuration {
            case NSTimeInterval(hours: 3):
                return -3.2030e-9 * pow(time.minutes, 4) + 1.354e-6 * pow(time.minutes, 3) - 1.759e-4 * pow(time.minutes, 2) + 9.255e-4 * time.minutes + 0.99951
            case NSTimeInterval(hours: 4):
                return -3.310e-10 * pow(time.minutes, 4) + 2.530e-7 * pow(time.minutes, 3) - 5.510e-5 * pow(time.minutes, 2) - 9.086e-4 * time.minutes + 0.99950
            case NSTimeInterval(hours: 5):
                return -2.950e-10 * pow(time.minutes, 4) + 2.320e-7 * pow(time.minutes, 3) - 5.550e-5 * pow(time.minutes, 2) + 4.490e-4 * time.minutes + 0.99300
            case NSTimeInterval(hours: 6):
                return -1.493e-10 * pow(time.minutes, 4) + 1.413e-7 * pow(time.minutes, 3) - 4.095e-5 * pow(time.minutes, 2) + 6.365e-4 * time.minutes + 0.99700
            default:
                return nil
            }
        }

    }

    /**
     It takes a MM pump about 40s to deliver 1 Unit while bolusing
     See: http://www.healthline.com/diabetesmine/ask-dmine-speed-insulin-pumps#3
     
     A basal rate of 30 U/hour (near-max) would deliver an additional 0.5 U/min.
     */
    private static let MaximumReservoirDropPerMinute = 2.0

    /**
     Calculates the total usage for a continuous range of reservoir values

     - parameter values: An array of reservoir values, in chronological order

     - returns: The total insulin usage, in Units
     */
    static func totalUsageForReservoirValues<T: CollectionType where T.Generator.Element: ReservoirValue>(values: T) -> Double {
        var previousValue: T.Generator.Element?
        var total: Double = 0

        for value in values {
            if let previousValue = previousValue {
                let volumeDrop = previousValue.unitVolume - value.unitVolume
                let duration = value.startDate.timeIntervalSinceDate(previousValue.startDate)

                if 0 <= volumeDrop && volumeDrop <= MaximumReservoirDropPerMinute * duration.minutes {
                    total += volumeDrop
                }
            }

            previousValue = value
        }

        return total
    }

}
