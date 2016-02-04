//
//  InsulinMath.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 1/30/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation
import LoopKit


public struct InsulinValue {
    public let startDate: NSDate
    public let value: Double

    public init(startDate: NSDate, value: Double) {
        self.startDate = startDate
        self.value = value
    }
}


struct InsulinMath {

    /**
     Returns the percentage of total insulin effect remaining at a specified interval after delivery; also known as Insulin On Board (IOB).

     These are 4th-order polynomial fits of John Walsh's IOB curve plots, and they first appeared in GlucoDyn.

     See: https://github.com/kenstack/GlucoDyn

     - parameter time:           The interval after insulin delivery
     - parameter actionDuration: The total time of insulin effect

     - returns: The percentage of total insulin effect remaining
     */
    private static func walshPercentEffectRemainingAtTime(time: NSTimeInterval, actionDuration: NSTimeInterval) -> Double? {

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

    private static func insulinOnBoardForContinuousDose(dose: DoseEntry, atDate date: NSDate, actionDuration: NSTimeInterval, delay: NSTimeInterval, delta: NSTimeInterval) -> Double {

        let doseDuration = dose.endDate.timeIntervalSinceDate(dose.startDate)  // t1
        let time = date.timeIntervalSinceDate(dose.startDate)
        var iob: Double = 0
        var doseDate = NSTimeInterval(0)  // i

        repeat {
            let segment = max(0, min(doseDate + delta, doseDuration) - doseDate) / doseDuration
            iob += segment * walshPercentEffectRemainingAtTime(time - delay, actionDuration: actionDuration)!
            doseDate += delta
        } while doseDate <= min(floor((time + delay) / delta) * delta, doseDuration)

        return iob
    }

    private static func insulinOnBoardForDose(dose: DoseEntry, atDate date: NSDate, actionDuration: NSTimeInterval, delay: NSTimeInterval, delta: NSTimeInterval) -> Double {
        let time = date.timeIntervalSinceDate(dose.startDate)
        let iob: Double

        if time >= 0 {
            if dose.unit == .Units {
                iob = dose.value * walshPercentEffectRemainingAtTime(time - delay, actionDuration: actionDuration)!
            } else if dose.unit == .UnitsPerHour && dose.endDate.timeIntervalSinceDate(dose.startDate) <= 1.05 * delta {
                iob = dose.value * dose.endDate.timeIntervalSinceDate(dose.startDate) / NSTimeInterval(hours: 1) * walshPercentEffectRemainingAtTime(time - delay, actionDuration: actionDuration)!
            } else {
                iob = dose.value * dose.endDate.timeIntervalSinceDate(dose.startDate) / NSTimeInterval(hours: 1) * insulinOnBoardForContinuousDose(dose, atDate: date, actionDuration: actionDuration, delay: delay, delta: delta)
            }
        } else {
            iob = 0
        }

        return iob
    }

    /**
     It takes a MM pump about 40s to deliver 1 Unit while bolusing
     See: http://www.healthline.com/diabetesmine/ask-dmine-speed-insulin-pumps#3
     
     A basal rate of 30 U/hour (near-max) would deliver an additional 0.5 U/min.
     */
    private static let MaximumReservoirDropPerMinute = 2.0

    /**
     Converts a continuous sequence of reservoir values to a sequence of doses

     - parameter values: A collection of reservoir values, in chronological order

     - returns: An array of doses
     */
    static func doseEntriesFromReservoirValues<T: CollectionType where T.Generator.Element: ReservoirValue>(values: T) -> [DoseEntry] {

        var doses: [DoseEntry] = []
        var previousValue: T.Generator.Element?

        let numberFormatter = NSNumberFormatter()
        numberFormatter.numberStyle = .DecimalStyle
        numberFormatter.maximumFractionDigits = 3

        for value in values {
            if let previousValue = previousValue {
                let volumeDrop = previousValue.unitVolume - value.unitVolume
                let duration = value.startDate.timeIntervalSinceDate(previousValue.startDate)

                if duration > 0 && 0 <= volumeDrop && volumeDrop <= MaximumReservoirDropPerMinute * duration.minutes {
                    doses.append(DoseEntry(
                        startDate: previousValue.startDate,
                        endDate: value.startDate,
                        value: volumeDrop * NSTimeInterval(hours: 1) / duration,
                        unit: .UnitsPerHour,
                        description: "Reservoir decreased \(numberFormatter.stringFromNumber(volumeDrop) ?? String(volumeDrop))U over \(numberFormatter.stringFromNumber(duration.minutes) ?? String(duration.minutes))min"
                    ))
                }
            }

            previousValue = value
        }

        return doses
    }

    /**
     Calculates the total insulin delivery for a collection of doses

     - parameter values: A collection of doses

     - returns: The total insulin insulin, in Units
     */
    static func totalDeliveryForDoses<T: CollectionType where T.Generator.Element == DoseEntry>(doses: T) -> Double {
        var total: Double = 0

        for dose in doses {
            switch dose.unit {
            case .Units:
                total += dose.value
            case .UnitsPerHour:
                total += dose.value * dose.endDate.timeIntervalSinceDate(dose.startDate) / NSTimeInterval(hours: 1)
            }
        }

        return total
    }

    /**
     Calculates the timeline of insulin remaining for a collection of doses

     - parameter doses:          A collection of doses
     - parameter actionDuration: The total time of insulin effect
     - parameter fromDate:       The date to begin the timeline
     - parameter toDate:         The date to end the timeline
     - parameter delay:          The time to delay the dose effect
     - parameter delta:          The differential between timeline entries

     - returns: A sequence of insulin amount remaining
     */
    static func insulinOnBoardForDoses<T: CollectionType where T.Generator.Element == DoseEntry>(
        doses: T,
        actionDuration: NSTimeInterval,
        fromDate: NSDate? = nil,
        toDate: NSDate? = nil,
        delay: NSTimeInterval = NSTimeInterval(minutes: 10),
        delta: NSTimeInterval = NSTimeInterval(minutes: 5)
    ) -> [InsulinValue] {
        var validActionDuration = false

        for hours in 3...6 {
            if actionDuration == NSTimeInterval(hours: Double(hours)) {
                validActionDuration = true
                break
            }
        }

        guard validActionDuration, let (startDate, endDate) = LoopMath.simulationDateRangeForSamples(doses, fromDate: fromDate, toDate: toDate, duration: actionDuration, delay: delay, delta: delta) else {
            return []
        }

        var date = startDate
        var values = [InsulinValue]()

        repeat {
            let value = doses.reduce(0) { (value, dose) -> Double in
                return value + insulinOnBoardForDose(dose, atDate: date, actionDuration: actionDuration, delay: delay, delta: delta)
            }

            values.append(InsulinValue(startDate: date, value: value))
            date = date.dateByAddingTimeInterval(delta)
        } while date <= endDate

        return values
    }
}
