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
    public let startTime: NSTimeInterval
    public let value: Double

    public init(startTime: NSTimeInterval, value: Double) {
        self.startTime = startTime
        self.value = value
    }
}

extension ScheduleItem: Equatable {
}

public func ==(lhs: ScheduleItem, rhs: ScheduleItem) -> Bool {
    return lhs.startTime == rhs.startTime && lhs.value == rhs.value
}


public class DailyValueSchedule {
    private let referenceTimeInterval: NSTimeInterval
    private let repeatInterval = NSTimeInterval(hours: 24)

    public let items: [ScheduleItem]
    public let timeZone: NSTimeZone

    init?(dailyItems: [ScheduleItem], timeZone: NSTimeZone?) {
        self.items = dailyItems.sort { $0.startTime < $1.startTime }
        self.timeZone = timeZone ?? NSTimeZone.localTimeZone()

        guard let firstItem = self.items.first else {
            referenceTimeInterval = 0
            return nil
        }

        referenceTimeInterval = firstItem.startTime
    }

    private var maxTimeInterval: NSTimeInterval {
        return referenceTimeInterval + repeatInterval
    }

    /**
     Returns the time interval for a given date normalized to the span of the schedule items

     - parameter date: The date to convert
     */
    private func scheduleOffsetForDate(date: NSDate) -> NSTimeInterval {
        // The time interval since a reference date in the specified time zone
        let interval = date.timeIntervalSinceReferenceDate + NSTimeInterval(timeZone.secondsFromGMTForDate(date))

        // The offset of the time interval since the last occurence of the reference time + n * repeatIntervals.
        // If the repeat interval was 1 day, this is the fractional amount of time since the most recent repeat interval starting at the reference time
        return ((interval - referenceTimeInterval) % repeatInterval) + referenceTimeInterval
    }

    /**
     Returns a slice of schedule items that occur between two dates

     - parameter startDate: The start date of the range
     - parameter endDate:   The end date of the range

     - returns: A slice of `ScheduleItem` values
     */
    public func between(startDate: NSDate, _ endDate: NSDate) -> ArraySlice<ScheduleItem> {
        guard startDate <= endDate else {
            return []
        }

        let startOffset = scheduleOffsetForDate(startDate)
        let endOffset = startOffset + endDate.timeIntervalSinceDate(startDate)

        guard endOffset <= maxTimeInterval else {
            let boundaryDate = startDate.dateByAddingTimeInterval(maxTimeInterval - startOffset)

            return between(startDate, boundaryDate) + between(boundaryDate, endDate)
        }

        var startIndex = 0
        var endIndex = items.count

        for (index, item) in items.enumerate() {
            if startOffset >= item.startTime {
                startIndex = index
            }
            if endOffset < item.startTime {
                endIndex = index
                break
            }
        }

        return items[startIndex..<endIndex]
    }

    public func at(time: NSDate) -> Double {
        return between(time, time).first!.value
    }
}


public class DailyQuantitySchedule: DailyValueSchedule {
    public let unit: HKUnit

    public init?(unit: HKUnit, dailyItems: [ScheduleItem], timeZone: NSTimeZone?) {
        self.unit = unit

        super.init(dailyItems: dailyItems, timeZone: timeZone)
    }

    public func at(time: NSDate) -> HKQuantity {
        return HKQuantity(unit: unit, doubleValue: at(time))
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


public class BasalRateSchedule: DailyValueSchedule {
    public override init?(dailyItems: [ScheduleItem], timeZone: NSTimeZone? = nil) {
        super.init(dailyItems: dailyItems, timeZone: timeZone)
    }
}
