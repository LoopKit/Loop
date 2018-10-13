//
//  DailyScheduleTime.swift
//  Loop
//
//  Created by Michael Pangburn on 10/12/18.
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import Foundation


private func isValidHour(_ hour: Int) -> Bool {
    return (0..<24).contains(hour)
}

private func isValidMinute(_ minute: Int) -> Bool {
    return (0..<60).contains(minute)
}

/// Represents a time on a daily schedule.
struct DailyScheduleTime: Hashable {
    let hour: Int
    let minute: Int

    init(hour: Int, minute: Int = 0) {
        precondition(isValidHour(hour), "The hour component of a daily schedule time must fall in the range 0..<24")
        precondition(isValidMinute(minute), "The minute component of a daily schedule time must fall in the range 0..<60")
        self.hour = hour
        self.minute = minute
    }

    init(of date: Date, calendar: Calendar = .current) {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        self.init(dateComponents: components)!
    }

    init?(dateComponents: DateComponents) {
        guard let hour = dateComponents.hour, let minute = dateComponents.minute else {
            return nil
        }
        self.init(hour: hour, minute: minute)
    }

    static func hour(_ hour: Int) -> DailyScheduleTime {
        return self.init(hour: hour)
    }

    var dateComponents: DateComponents {
        return DateComponents(hour: hour, minute: minute)
    }

    func relative(toDayOf date: Date, calendar: Calendar = .current) -> Date? {
        let startOfDay = calendar.startOfDay(for: date)
        return calendar.nextDate(after: startOfDay, matching: dateComponents, matchingPolicy: .nextTime)
    }
}

extension DailyScheduleTime: Comparable {
    static func < (lhs: DailyScheduleTime, rhs: DailyScheduleTime) -> Bool {
        return (lhs.hour, lhs.minute) < (rhs.hour, rhs.minute)
    }
}

extension DailyScheduleTime: RawRepresentable {
    typealias RawValue = [Int]

    init?(rawValue: RawValue) {
        guard
            rawValue.count == 2,
            case let (hour, minute) = (rawValue[0], rawValue[1]),
            isValidHour(hour), isValidMinute(minute)
        else {
            return nil
        }

        self.init(hour: hour, minute: minute)
    }

    var rawValue: [Int] {
        return [hour, minute]
    }
}
