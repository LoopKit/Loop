//
//  QuantitySchedule.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 1/18/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation
import HealthKit


public struct RepeatingScheduleValue<T: RawRepresentable where T.RawValue: AnyObject> {
    public let startTime: NSTimeInterval
    public let value: T

    public init(startTime: NSTimeInterval, value: T) {
        self.startTime = startTime
        self.value = value
    }
}

public struct AbsoluteScheduleValue<T>: TimelineValue {
    public let startDate: NSDate
    public let value: T
}

extension RepeatingScheduleValue: RawRepresentable {
    public typealias RawValue = [String: AnyObject]

    public init?(rawValue: RawValue) {
        guard let startTime = rawValue["startTime"] as? Double,
            value = rawValue["value"] as? T else {
                return nil
        }

        self.init(startTime: startTime, value: value)
    }

    public var rawValue: RawValue {
        return [
            "startTime": startTime,
            "value": value.rawValue
        ]
    }
}


public class DailyValueSchedule<T: RawRepresentable where T.RawValue: AnyObject>: RawRepresentable {
    public typealias RawValue = [String: AnyObject]

    private let referenceTimeInterval: NSTimeInterval
    let repeatInterval = NSTimeInterval(hours: 24)

    public let items: [RepeatingScheduleValue<T>]
    public let timeZone: NSTimeZone

    init?(dailyItems: [RepeatingScheduleValue<T>], timeZone: NSTimeZone?) {
        self.items = dailyItems.sort { $0.startTime < $1.startTime }
        self.timeZone = timeZone ?? NSTimeZone.localTimeZone()

        guard let firstItem = self.items.first else {
            referenceTimeInterval = 0
            return nil
        }

        referenceTimeInterval = firstItem.startTime
    }

    public required convenience init?(rawValue: RawValue) {
        guard let
            timeZoneName = rawValue["timeZone"] as? String,
            rawItems = rawValue["items"] as? [RepeatingScheduleValue.RawValue] else
        {
            return nil
        }

        self.init(dailyItems: rawItems.flatMap { RepeatingScheduleValue(rawValue: $0) }, timeZone: NSTimeZone(name: timeZoneName))
    }

    public var rawValue: RawValue {
        return [
            "timeZone": timeZone.name,
            "items": items.map { $0.rawValue }
        ]
    }

    var maxTimeInterval: NSTimeInterval {
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
    public func between(startDate: NSDate, _ endDate: NSDate) -> [AbsoluteScheduleValue<T>] {
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

        let referenceDate = startDate.dateByAddingTimeInterval(-startOffset)

        return items[startIndex..<endIndex].map {
            return AbsoluteScheduleValue(startDate: referenceDate.dateByAddingTimeInterval($0.startTime), value: $0.value)
        }
    }

    func valueAt(time: NSDate) -> T {
        return between(time, time).first!.value
    }

}
