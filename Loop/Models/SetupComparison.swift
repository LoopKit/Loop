//
//  SetupComparison.swift
//  Loop
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit

/// Outcomes since the last setup change, compared with the period before it.
struct SetupComparison: Equatable {
    struct Period: Equatable {
        let start: Date
        let end: Date
        let glucose: GlucoseStatistics
        /// Average insulin per day, or nil when the dose records don't cover the period.
        let insulinPerDay: Double?

        var days: Double { end.timeIntervalSince(start) / .days(1) }
        var timeInRange: Double? { glucose.timeInRange.isEmpty ? nil : glucose.timeInRange[.target, default: 0] }
        var timeBelowRange: Double? { glucose.timeInRange.isEmpty ? nil : glucose.timeInRange[.low, default: 0] + glucose.timeInRange[.veryLow, default: 0] }
    }

    static let beforeDuration = TimeInterval.days(14)
    static let suggestedDuration = TimeInterval.days(14)
    /// Less CGM data than this in a period makes its numbers unreliable.
    static let minimumCGMActive = 0.7
    static let minimumPeriod = TimeInterval.days(1)

    let before: Period?
    let after: Period

    /// The comparison is still settling until the setup has run for about two weeks.
    var isSettling: Bool { after.end.timeIntervalSince(after.start) < Self.suggestedDuration }

    init?(change: SetupChange,
          samples: [StoredGlucoseSample],
          insulinHistory: InsulinDeliveryHistory?,
          now: Date,
          calendar: Calendar = .current) {
        guard !change.isLowerBound, now.timeIntervalSince(change.date) >= Self.minimumPeriod else {
            return nil
        }
        func period(_ start: Date, _ end: Date) -> Period {
            Period(start: start,
                   end: end,
                   glucose: GlucoseStatistics(samples: samples, start: start, end: end, calendar: calendar),
                   insulinPerDay: Self.insulinPerDay(insulinHistory, from: start, to: end))
        }
        after = period(change.date, now)

        let beforeStart = max(change.date - Self.beforeDuration, change.previousDate ?? .distantPast)
        let candidate = period(beforeStart, change.date)
        before = change.date.timeIntervalSince(beforeStart) >= Self.minimumPeriod && candidate.glucose.percentActive >= Self.minimumCGMActive ? candidate : nil
    }

    private static func insulinPerDay(_ history: InsulinDeliveryHistory?, from start: Date, to end: Date) -> Double? {
        guard let history, history.coverageStart <= start, end <= history.end else {
            return nil
        }
        return history.totals(from: start, to: end).total / (end.timeIntervalSince(start) / .days(1))
    }
}
