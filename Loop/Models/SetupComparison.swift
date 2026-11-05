//
//  SetupComparison.swift
//  Loop
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit

/// Outcomes from a setup change until now, compared with the weeks before it.
struct SetupComparison: Equatable {
    struct Period: Equatable {
        let start: Date
        let end: Date
        let glucose: GlucoseStatistics
        /// Average insulin per day, or nil when the dose records don't cover enough of the period.
        let insulinPerDay: Double?
        /// Set when the dose records start after the period does, and the average is from here.
        let insulinStart: Date?

        var days: Double { end.timeIntervalSince(start) / .days(1) }
        var timeInRange: Double? { glucose.timeInRange.isEmpty ? nil : glucose.timeInRange[.target, default: 0] }
        var timeBelowRange: Double? { glucose.timeInRange.isEmpty ? nil : glucose.timeInRange[.low, default: 0] + glucose.timeInRange[.veryLow, default: 0] }
    }

    static let beforeDuration = TimeInterval.days(21)
    static let suggestedDuration = TimeInterval.days(14)
    /// Less CGM data than this in a period makes its numbers unreliable.
    static let minimumCGMActive = 0.7
    static let minimumPeriod = TimeInterval.days(1)
    /// Insulin per day for part of a period needs at least this much of it.
    static let minimumInsulinCoverage = TimeInterval.days(14)

    let before: Period?
    let after: Period

    /// The comparison is still settling until about two weeks have passed since the change.
    var isSettling: Bool { after.days * .days(1) < Self.suggestedDuration }

    /// Compares the time from `change` until `now`, including any later changes, with the `beforeDuration` before it.
    init?(change: SetupChange,
          samples: [StoredGlucoseSample],
          insulinHistory: InsulinDeliveryHistory?,
          now: Date,
          calendar: Calendar = .current) {
        guard !change.isLowerBound, now.timeIntervalSince(change.date) >= Self.minimumPeriod else {
            return nil
        }
        func period(_ start: Date, _ end: Date) -> Period {
            let insulin = Self.insulinPerDay(insulinHistory, from: start, to: end)
            return Period(start: start,
                          end: end,
                          glucose: GlucoseStatistics(samples: samples, start: start, end: end, calendar: calendar),
                          insulinPerDay: insulin?.perDay,
                          insulinStart: insulin.flatMap { $0.start > start ? $0.start : nil })
        }
        after = period(change.date, now)

        let candidate = period(change.date - Self.beforeDuration, change.date)
        before = candidate.glucose.percentActive >= Self.minimumCGMActive ? candidate : nil
    }

    private static func insulinPerDay(_ history: InsulinDeliveryHistory?, from start: Date, to end: Date) -> (perDay: Double, start: Date)? {
        guard let history, end <= history.end else {
            return nil
        }
        let coveredStart = max(start, history.coverageStart)
        guard coveredStart < end else {
            return nil
        }
        if coveredStart > start && end.timeIntervalSince(coveredStart) < minimumInsulinCoverage {
            return nil
        }
        return (history.totals(from: coveredStart, to: end).total / (end.timeIntervalSince(coveredStart) / .days(1)), coveredStart)
    }
}
