//
//  DailyScheduleInterval.swift
//  Loop
//
//  Created by Michael Pangburn on 9/24/18.
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import Foundation


/// Represents a time on a daily schedule as an offset from midnight.
/// Only values in seconds between 0 and 24 hours are valid.
typealias DailyScheduleTime = TimeInterval

private extension DailyScheduleTime {
    var isValid: Bool {
        let validRange = 0..<TimeInterval(hours: 24)
        return validRange.contains(self)
    }

    func relative(to date: Date, calendar: Calendar = .current) -> Date {
        let startOfDay = calendar.startOfDay(for: date)
        return startOfDay.addingTimeInterval(self)
    }
}

private func assertValid(_ time: DailyScheduleTime) {
    assert(time.isValid, "DailyScheduleTime values must represent a number of seconds between 0 and 24 hours.")
}

/// Represents a daily schedule interval relative to a specific date.
enum DateRelativeDailyScheduleInterval {
    case closed(DateInterval)
    case disjoint(morning: DateInterval, evening: DateInterval)

    func contains(_ date: Date) -> Bool {
        switch self {
        case .closed(let interval):
            return interval.contains(date)
        case .disjoint(morning: let morning, evening: let evening):
            return morning.contains(date) || evening.contains(date)
        }
    }

    var duration: TimeInterval {
        switch self {
        case .closed(let interval):
            return interval.duration
        case .disjoint(morning: let morning, evening: let evening):
            return morning.duration + evening.duration
        }
    }
}

/// Represents a continuous interval of time in a daily schedule.
/// The interval may cross midnight, in which case the value models the combination of
/// an interval in the morning and an interval in the evening.
///
/// The following diagram demonstrates the two types of intervals
/// that can be modeled by `DailySchedulePeriod`:
/// ```
/// 1) Closed interval within the day
///       ●────────────────●
///            6am-10pm
///
/// 2) Disjoint intervals overlapping days
///  ─────●                ●──
///            10pm-6am
///
///  ◆───────────◆───────────◆
/// 12am        12pm       12am
/// ```
enum DailyScheduleInterval {
    case closed(ClosedRange<DailyScheduleTime>)
    case disjoint(morning: PartialRangeThrough<DailyScheduleTime>, evening: PartialRangeFrom<DailyScheduleTime>)

    var startTime: DailyScheduleTime {
        get {
            switch self {
            case .closed(let range):
                return range.lowerBound
            case .disjoint(morning: _, evening: let evening):
                return evening.lowerBound
            }
        }
        set {
            self = DailyScheduleInterval(startTime: newValue, endTime: endTime)
        }
    }

    var endTime: DailyScheduleTime {
        get {
            switch self {
            case .closed(let range):
                return range.upperBound
            case .disjoint(morning: let morning, evening: _):
                return morning.upperBound
            }
        }
        set {
            self = DailyScheduleInterval(startTime: startTime, endTime: newValue)
        }
    }

    init(startTime: DailyScheduleTime, endTime: DailyScheduleTime) {
        assertValid(startTime); assertValid(endTime)
        if startTime > endTime {
            self = .disjoint(morning: ...endTime, evening: startTime...)
        } else {
            self = .closed(startTime...endTime)
        }
    }

    func contains(_ time: DailyScheduleTime) -> Bool {
        assertValid(time)
        switch self {
        case .closed(let range):
            return range.contains(time)
        case .disjoint(morning: let morning, evening: let evening):
            return morning.contains(time) || evening.contains(time)
        }
    }

    /// Returns the date interval(s) corresponding to the daily schedule interval
    /// on the given date.
    /// ```
    /// 1) Closed interval
    ///       ●────────────────●
    ///            6am-10pm
    ///
    /// 2) Disjoint intervals
    ///  ●────●                ●─●
    ///            10pm-6am
    ///
    ///  ◆───────────◆───────────◆
    /// 12am        12pm       12am
    /// ```
    func relative(to date: Date, calendar: Calendar = .current) -> DateRelativeDailyScheduleInterval {
        switch self {
        case .closed(let range):
            return .closed(DateInterval(start: range.lowerBound.relative(to: date, calendar: calendar), end: range.upperBound.relative(to: date, calendar: calendar)))
        case .disjoint(morning: let morning, evening: let evening):
            guard let dayInterval = calendar.dateInterval(of: .day, for: date) else {
                preconditionFailure("Unable to get day interval for \(date)")
            }
            return .disjoint(
                morning: DateInterval(start: dayInterval.start, end: morning.upperBound.relative(to: date, calendar: calendar)),
                evening: DateInterval(start: evening.lowerBound.relative(to: date, calendar: calendar), end: dayInterval.end)
            )
        }
    }

    var duration: TimeInterval {
        return relative(to: Date(timeIntervalSince1970: 0)).duration
    }

    func isInProgress(at date: Date = Date(), calendar: Calendar = .current) -> Bool {
        return relative(to: date, calendar: calendar).contains(date)
    }

    /// Returns a single date interval corresponding to the daily schedule interval
    /// beginning on the given date.
    /// ```
    /// 1) Closed interval within the day
    ///       ●────────────────●
    ///            6am-10pm
    ///
    /// 2) Interval overlapping days
    ///                        ●───────●
    ///                        10pm-6am
    ///
    ///  ◆───────────◆───────────◆───────────◆
    /// 12am        12pm       12am         12pm
    /// ```
    func dateInterval(beginningOnDayOf date: Date, calendar: Calendar = .current) -> DateInterval {
        switch relative(to: date) {
        case .closed(let interval):
            return interval
        case .disjoint(morning: let morning, evening: let evening):
            guard let nextMorning = calendar.date(byAdding: .day, value: 1, to: morning.end) else {
                preconditionFailure("Unable to compute the day after \(morning.end)")
            }
            return DateInterval(start: evening.start, end: nextMorning)
        }
    }

    /// Returns the next date after the given date on which the daily schedule interval begins.
    func nextStartDate(after date: Date, calendar: Calendar = .current) -> Date {
        let startDateOnDayOf = { self.dateInterval(beginningOnDayOf: $0, calendar: calendar).start }
        if case let startDate = startDateOnDayOf(date), startDate > date {
            return startDate
        } else {
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: date) else {
                preconditionFailure("Unable to compute the day after \(date)")
            }
            return startDateOnDayOf(nextDay)
        }
    }

    /// Returns the duration for which the daily schedule is in progress
    /// in the given date interval.
    /// - Precondition: The given interval must span no more than one day.
    func durationInProgress(in interval: DateInterval, calendar: Calendar = .current) -> TimeInterval {
        let oneDayAfterStart = calendar.date(byAdding: .day, value: 1, to: interval.start)!
        precondition(interval.end <= oneDayAfterStart, "End date must be within a day after start date.")
        let startDayInterval = dateInterval(beginningOnDayOf: interval.start)
        let endDayInterval = dateInterval(beginningOnDayOf: interval.end)
        let intersectionDuration = { interval.intersection(with: $0)?.duration ?? 0 }
        if startDayInterval == endDayInterval {
            // `interval` starts and ends on the same day; avoid double-counting intersection
            return intersectionDuration(startDayInterval)
        } else {
            return intersectionDuration(startDayInterval) + intersectionDuration(endDayInterval)
        }
    }

    /// Returns a pair of dates with times matching the interval start and end times.
    /// Do not rely on any property of these dates other than their offsets from midnight.
    func dayInsensitiveDates() -> (start: Date, end: Date) {
        let referenceDate = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 0))
        return (start: referenceDate + startTime, end: referenceDate + endTime)
    }

    /// Returns the complementary daily schedule interval for this interval.
    ///
    /// For example, 6am-10pm and 10pm-6am are complements.
    /// ```
    ///       ●────────────────●
    ///            6am-10pm
    ///
    ///  ─────●                ●──
    ///            10pm-6am
    ///
    ///  ◆───────────◆───────────◆
    /// 12am        12pm       12am
    /// ```
    func complement() -> DailyScheduleInterval {
        return DailyScheduleInterval(startTime: endTime, endTime: startTime)
    }
}

extension DailyScheduleInterval: CustomStringConvertible {
    var description: String {
        let descriptionFormat = NSLocalizedString("%1$@ – %2$@", comment: "Format string for daily schedule period. (1: Start time)(2: End time)")
        let formatDate = { DateFormatter.localizedString(from: $0, dateStyle: .none, timeStyle: .short) }
        let dates = dayInsensitiveDates()
        return String(format: descriptionFormat, formatDate(dates.start), formatDate(dates.end))
    }
}

extension DailyScheduleInterval: RawRepresentable {
    typealias RawValue = [DailyScheduleTime]

    init?(rawValue: RawValue) {
        guard
            rawValue.count == 2,
            rawValue.allSatisfy({ $0.isValid })
        else {
            return nil
        }

        self.init(startTime: rawValue[0], endTime: rawValue[1])
    }

    var rawValue: RawValue {
        return [startTime, endTime]
    }
}
