//
//  DailyQuantitySchedule.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 2/12/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation
import HealthKit


public class DailyQuantitySchedule: DailyValueSchedule<Double> {
    public let unit: HKUnit

    init?(unit: HKUnit, dailyItems: [RepeatingScheduleValue<Double>], timeZone: NSTimeZone?) {
        self.unit = unit

        super.init(dailyItems: dailyItems, timeZone: timeZone)
    }

    public required convenience init?(rawValue: RawValue) {
        guard let
            rawUnit = rawValue["unit"] as? String,
            timeZoneName = rawValue["timeZone"] as? String,
            rawItems = rawValue["items"] as? [RepeatingScheduleValue.RawValue] else
        {
            return nil
        }

        self.init(unit: HKUnit(fromString: rawUnit), dailyItems: rawItems.flatMap { RepeatingScheduleValue(rawValue: $0) }, timeZone: NSTimeZone(name: timeZoneName))
    }

    public override var rawValue: RawValue {
        var rawValue = super.rawValue

        rawValue["unit"] = unit.unitString

        return rawValue
    }

    public func quantityAt(time: NSDate) -> HKQuantity {
        return HKQuantity(unit: unit, doubleValue: valueAt(time))
    }

    func averageValue() -> Double {
        var total: Double = 0

        for (index, item) in items.enumerate() {
            var endTime = maxTimeInterval

            if index < items.endIndex - 1 {
                endTime = items[index + 1].startTime
            }

            total += (endTime - item.startTime) * item.value
        }

        return total / repeatInterval
    }

    public func averageQuantity() -> HKQuantity {
        return HKQuantity(unit: unit, doubleValue: averageValue())
    }
}
