//
//  GlucoseRangeSchedule.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 2/13/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation
import HealthKit


public struct DoubleRange {
    public let minValue: Double
    public let maxValue: Double
}


extension DoubleRange: RawRepresentable {
    public typealias RawValue = NSArray

    public init?(rawValue: RawValue) {
        guard rawValue.count == 2 else {
            return nil
        }

        minValue = rawValue[0].doubleValue
        maxValue = rawValue[1].doubleValue
    }

    public var rawValue: RawValue {
        let raw: NSArray = [
            NSNumber(double: minValue),
            NSNumber(double: maxValue)
        ]

        return raw
    }
}


public class GlucoseRangeSchedule: DailyQuantitySchedule<DoubleRange> {
    public override init?(unit: HKUnit, dailyItems: [RepeatingScheduleValue<DoubleRange>], timeZone: NSTimeZone? = nil) {
        super.init(unit: unit, dailyItems: dailyItems, timeZone: timeZone)
    }

    public override func valueAt(time: NSDate) -> DoubleRange {
        return super.valueAt(time)
    }
}
