//
//  QuantitySchedule.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 1/18/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation
import HealthKit


public struct ScheduleItem {
    let startTime: NSTimeInterval
    let value: Double
}


public class DailyQuantitySchedule {
    private let referenceTimeInterval: NSTimeInterval
    private let repeatInterval = NSTimeInterval(hours: 24)

    public let unit: HKUnit
    public let items: [ScheduleItem]
    public let timeZone: NSTimeZone

    init?(unit: HKUnit, dailyItems: [ScheduleItem], timeZone: NSTimeZone?) {
        self.unit = unit
        self.items = dailyItems.sort { $0.startTime < $1.startTime }
        self.timeZone = timeZone ?? NSTimeZone.localTimeZone()

        guard let firstItem = self.items.first else {
            referenceTimeInterval = 0
            return nil
        }

        referenceTimeInterval = firstItem.startTime
    }

    public func at(time: NSDate) -> HKQuantity {
        let interval = time.timeIntervalSinceReferenceDate + NSTimeInterval(timeZone.secondsFromGMTForDate(time))

        let scheduleOffset = ((interval - referenceTimeInterval) % repeatInterval) + referenceTimeInterval

        var value: Double!

        for item in items {
            if item.startTime > scheduleOffset {
                break
            }
            value = item.value
        }

        return HKQuantity(unit: unit, doubleValue: value)
    }
}


public class InsulinSensitivitySchedule: DailyQuantitySchedule {
    public override init?(unit: HKUnit, dailyItems: [ScheduleItem], timeZone: NSTimeZone? = nil) {
        super.init(unit: unit, dailyItems: dailyItems, timeZone: timeZone)

        guard unit == HKUnit.milligramsPerDeciliterUnit() || unit == HKUnit.millimolesPerLiterUnit() else {
            return nil
        }
    }
}


public class CarbRatioSchedule: DailyQuantitySchedule {
    public override init?(unit: HKUnit, dailyItems: [ScheduleItem], timeZone: NSTimeZone? = nil) {
        super.init(unit: unit, dailyItems: dailyItems, timeZone: timeZone)

        guard unit == HKUnit.gramUnit() else {
            return nil
        }
    }
}
