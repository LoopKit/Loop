//
//  InsulinDeliveryHistory.swift
//  Loop
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit
import LoopAlgorithm

struct InsulinDeliveryTotals: Equatable {
    var basal: Double = 0
    var automaticBolus: Double = 0
    var manualBolus: Double = 0

    var bolus: Double { automaticBolus + manualBolus }
    var total: Double { basal + bolus }
}

struct DailyInsulinDelivery: Equatable, Identifiable {
    let start: Date
    let end: Date
    let totals: InsulinDeliveryTotals
    let isComplete: Bool

    var id: Date { start }
}

struct TypicalInsulinDelivery: Equatable {
    let median: Double
    let dayCount: Int
}

/// Insulin delivered over a span of time, from normalized doses. Time not covered by a basal
/// record is counted at the scheduled basal rate, since that is what the pump delivers on its own.
struct InsulinDeliveryHistory {
    let doses: [SimpleInsulinDose]
    let scheduledBasal: [AbsoluteScheduleValue<Double>]
    /// Earliest time the dose records can be trusted to cover.
    let coverageStart: Date
    let end: Date

    init(doses: [SimpleInsulinDose], scheduledBasal: [AbsoluteScheduleValue<Double>], coverageStart: Date, end: Date) {
        self.doses = doses.sorted { $0.startDate < $1.startDate }
        self.scheduledBasal = scheduledBasal.sorted { $0.startDate < $1.startDate }
        self.coverageStart = coverageStart
        self.end = end
    }

    func totals(from start: Date, to end: Date) -> InsulinDeliveryTotals {
        var totals = InsulinDeliveryTotals()
        guard start < end else { return totals }

        var basalCursor = start
        for dose in doses {
            switch dose.deliveryType {
            case .bolus:
                let units = dose.volume(from: start, to: end)
                if dose.automatic {
                    totals.automaticBolus += units
                } else {
                    totals.manualBolus += units
                }
            case .basal:
                let doseStart = max(dose.startDate, basalCursor)
                let doseEnd = min(dose.endDate, end)
                guard doseStart < doseEnd else { continue }
                totals.basal += scheduledUnits(from: basalCursor, to: doseStart)
                totals.basal += dose.volume(from: doseStart, to: doseEnd)
                basalCursor = doseEnd
            }
        }
        totals.basal += scheduledUnits(from: basalCursor, to: end)
        return totals
    }

    /// One entry per calendar day that the records fully cover, oldest first. The current day
    /// is included as an incomplete entry ending at `end`.
    func dailyTotals(calendar: Calendar = .current) -> [DailyInsulinDelivery] {
        var days: [DailyInsulinDelivery] = []
        var dayStart = calendar.startOfDay(for: coverageStart)
        if dayStart < coverageStart, let next = calendar.date(byAdding: .day, value: 1, to: dayStart) {
            dayStart = next
        }
        while dayStart < end, let next = calendar.date(byAdding: .day, value: 1, to: dayStart) {
            let dayEnd = min(next, end)
            days.append(DailyInsulinDelivery(
                start: dayStart,
                end: dayEnd,
                totals: totals(from: dayStart, to: dayEnd),
                isComplete: next <= end
            ))
            dayStart = next
        }
        return days
    }

    /// The median amount delivered between midnight and the same clock time as `date`, over the
    /// previous `days` days that the records cover.
    func typicalDelivery(by date: Date, days: Int = 14, minimumDays: Int = 3, calendar: Calendar = .current) -> TypicalInsulinDelivery? {
        let amounts: [Double] = (1...max(1, days)).compactMap { offset in
            guard let sameTime = calendar.date(byAdding: .day, value: -offset, to: date) else { return nil }
            let dayStart = calendar.startOfDay(for: sameTime)
            guard dayStart >= coverageStart else { return nil }
            return totals(from: dayStart, to: sameTime).total
        }
        guard amounts.count >= minimumDays else { return nil }
        return TypicalInsulinDelivery(median: amounts.median, dayCount: amounts.count)
    }

    private func scheduledUnits(from start: Date, to end: Date) -> Double {
        guard start < end else { return 0 }
        return scheduledBasal.reduce(0) { sum, entry in
            let overlapStart = max(start, entry.startDate)
            let overlapEnd = min(end, entry.endDate)
            guard overlapStart < overlapEnd else { return sum }
            return sum + entry.value * overlapEnd.timeIntervalSince(overlapStart).hours
        }
    }
}

extension SimpleInsulinDose {
    /// Units delivered within the interval. A dose with no duration counts only if it falls inside.
    fileprivate func volume(from start: Date, to end: Date) -> Double {
        let duration = endDate.timeIntervalSince(startDate)
        guard duration > 0 else {
            return startDate >= start && startDate < end ? volume : 0
        }
        let overlap = min(end, endDate).timeIntervalSince(max(start, startDate))
        return overlap > 0 ? volume * overlap / duration : 0
    }
}

extension Array where Element == Double {
    fileprivate var median: Double {
        let sorted = self.sorted()
        guard !sorted.isEmpty else { return 0 }
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
}
