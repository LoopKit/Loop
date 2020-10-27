//
//  TimeComponents.swift
//  Learn
//
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import Foundation


struct TimeComponents: Equatable, Hashable {
    let hour: Int
    let minute: Int

    init(hour: Int, minute: Int) {
        if hour >= 24, minute >= 60 {
            assertionFailure("Invalid time components: \(hour):\(minute)")
        }

        self.hour = hour
        self.minute = minute
    }

    init?(dateComponents: DateComponents) {
        guard let hour = dateComponents.hour, let minute = dateComponents.minute else {
            return nil
        }

        self.init(hour: hour, minute: minute)
    }

    init(timeIntervalSinceMidnight timeInterval: TimeInterval) {
        self.init(hour: Int(timeInterval.hours), minute: Int(timeInterval.minutes) % 60)
    }

    var dateComponents: DateComponents {
        return DateComponents(hour: hour, minute: minute, second: 0)
    }

    var timeIntervalSinceMidnight: TimeInterval {
        return TimeInterval(hours: Double(hour)) + TimeInterval(minutes: Double(minute))
    }

    func floored(to timeInterval: TimeInterval) -> TimeComponents {
        let floored = floor(timeIntervalSinceMidnight / timeInterval) * timeInterval
        return TimeComponents(timeIntervalSinceMidnight: floored)
    }

    func bucket(withBucketSize bucketSize: TimeInterval) -> Range<TimeComponents> {
        let lowerBound = floored(to: bucketSize)
        return lowerBound..<(lowerBound + bucketSize)
    }

    private func adding(_ timeInterval: TimeInterval) -> TimeComponents {
        return TimeComponents(timeIntervalSinceMidnight: timeIntervalSinceMidnight + timeInterval)
    }
}

extension TimeComponents: Comparable {
    static func < (lhs: TimeComponents, rhs: TimeComponents) -> Bool {
        if lhs.hour == rhs.hour {
            return lhs.minute < rhs.minute
        } else {
            return lhs.hour < rhs.hour
        }
    }
}

extension TimeComponents {
    static func + (lhs: TimeComponents, rhs: TimeInterval) -> TimeComponents {
        return lhs.adding(rhs)
    }
}
