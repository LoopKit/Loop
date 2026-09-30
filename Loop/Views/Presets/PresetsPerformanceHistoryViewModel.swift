//
//  PresetsPerformanceHistoryViewModel.swift
//  Loop
//
//  Created by Cameron Ingham on 3/5/26.
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import LoopAlgorithm
import LoopKit

@MainActor
@Observable
class PresetsPerformanceHistoryViewModel {
    private let temporaryPresetsManager: TemporaryPresetsManager
    private let glucoseStore: GlucoseStoreProtocol
    private let carbStore: CarbStoreProtocol
    private let doseStore: DoseStoreProtocol
    private let automationHistory: () -> [AutomationHistoryEntry]
    
    private static let calendar = Calendar.current
    
    private static var timeFormatter: DateFormatter = {
        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short
        return timeFormatter
    }()
    
    private static var dayFormatter: DateFormatter = {
        let dayFormatter = DateFormatter()
        dayFormatter.setLocalizedDateFormatFromTemplate("EEEMd")
        return dayFormatter
    }()
    
    init(temporaryPresetsManager: TemporaryPresetsManager, glucoseStore: GlucoseStoreProtocol, carbStore: CarbStoreProtocol, doseStore: DoseStoreProtocol, automationHistory: @escaping () -> [AutomationHistoryEntry]) {
        self.temporaryPresetsManager = temporaryPresetsManager
        self.glucoseStore = glucoseStore
        self.carbStore = carbStore
        self.doseStore = doseStore
        self.automationHistory = automationHistory
    }

    func fetchData(from override: TemporaryScheduleOverride, add6Hours: Bool) async throws -> PerformanceData {
        let overallInsulin = override.settings.effectiveInsulinNeedsScaleFactor
        let correctionRange = override.settings.targetRange
        let startDate = override.startDate
        let endDate = override.actualEndDate
        
        let calculatedEndDate = add6Hours ? endDate.addingTimeInterval(.hours(6)) : endDate
        
        let allGlucoseValues = try await glucoseStore.getGlucoseSamples(start: startDate.addingTimeInterval(.minutes(-5)), end: calculatedEndDate)
        
        let totalCarbs = LoopQuantity(
            unit: .gram,
            doubleValue: try await carbStore.getCarbEntries(start: startDate, end: calculatedEndDate)
                .map({ $0.quantity.doubleValue(for: .gram) })
                .reduce(0, +)
        )
        
        let totalBolus = LoopQuantity(
            unit: .internationalUnit,
            doubleValue: try await ((doseStore as? DoseStore)?.insulinDeliveryStore.getBoluses(start: startDate, end: calculatedEndDate) ?? [])
                .map({ $0.deliveredUnits ?? 0 })
                .reduce(0, +)
        )
        
        let timeInAutomation = automationHistory()
            .toTimeline(from: startDate, to: calculatedEndDate)
            .percentageTrue(from: startDate, to: calculatedEndDate)
        
        return PerformanceData(
            overallInsulin: overallInsulin,
            correctionRange: correctionRange,
            startDate: startDate,
            endDate: calculatedEndDate,
            startingGlucose: allGlucoseValues.last(where: { $0.endDate < startDate })?.quantity,
            allGlucoseValues: Array(allGlucoseValues.drop(while: { $0.endDate < startDate })),
            totalCarbs: totalCarbs,
            totalBolus: totalBolus,
            timeInAutomation: timeInAutomation
        )
    }
    
    struct PerformanceData {
        enum GlucoseRange {
            case veryLow, low, normal, high, veryHigh
        }

        func classifyValue(_ value: Double) -> GlucoseRange {
            switch value {
            case ..<54:    return .veryLow
            case ..<70:    return .low
            case ..<181:   return .normal
            case ..<251:   return .high
            default:       return .veryHigh
            }
        }
        
        let overallInsulin: Double
        let correctionRange: ClosedRange<LoopQuantity>?
        let startDate: Date
        let endDate: Date
        let startingGlucose: LoopQuantity?
        let allGlucoseValues: [StoredGlucoseSample]
        let totalCarbs: LoopQuantity
        let totalBolus: LoopQuantity
        let timeInAutomation: Double
        
        var averageGlucose: LoopQuantity? {
            guard !allGlucoseValues.isEmpty else { return nil }
            return LoopQuantity(
                unit: .milligramsPerDeciliter,
                doubleValue: (
                    allGlucoseValues
                        .map({ $0.quantity.doubleValue(for: .milligramsPerDeciliter) })
                        .reduce(0, +) / Double(allGlucoseValues.count)
                )
            )
        }
        
        var timeInRange: [GlucoseRange: Double] {
            guard allGlucoseValues.count > 0 else { return [:] }
            
            let sorted = allGlucoseValues.sorted { $0.startDate < $1.startDate }
            var durations: [GlucoseRange: TimeInterval] = [:]
            
            for (index, sample) in sorted.enumerated() {
                let nextDate = index + 1 < sorted.count ? sorted[index + 1].startDate : endDate
                let duration = nextDate.timeIntervalSince(sample.startDate)
                let range = classifyValue(sample.quantity.doubleValue(for: .milligramsPerDeciliter))
                durations[range, default: 0] += duration
            }
            
            let total = durations.values.reduce(0, +)
            return durations.mapValues { $0 / total }
        }
        
        @MainActor
        func dateRange(overrideEndDate: Date? = nil) -> String {
            PresetsPerformanceHistoryViewModel.dateRange(from: startDate, to: overrideEndDate ?? endDate)
        }
        
        var minimalData: Bool {
            let sorted = allGlucoseValues.sorted(by: { $0.startDate < $1.startDate })
            guard let first = sorted.first, let last = sorted.last, first != last else {
                return true
            }
            
            return abs(first.startDate.timeIntervalSince(last.startDate)) < .minutes(30)
        }
    }
    
    static func dateRange(from startDate: Date, to endDate: Date) -> String {
        let startIsToday = calendar.isDateInToday(startDate)
        let endIsToday = calendar.isDateInToday(endDate)
        let sameDay = calendar.isDate(startDate, inSameDayAs: endDate)
        
        let startTime = timeFormatter.string(from: startDate)
        let endTime = timeFormatter.string(from: endDate)
        
        if startIsToday && endIsToday {
            // Today: "Today, 1:32 PM - 2:32 PM"
            return String(format: NSLocalizedString("Today, %1$@ - %2$@", comment: "The format string for the same day date range (1: start date)(2: end date)"), startTime, endTime)
            
        } else if sameDay {
            // Single Day: "Sun 5/21, 1:32 PM - 2:32 PM"
            return "\(dayFormatter.string(from: startDate)), \(startTime) - \(endTime)"
            
        } else {
            // Multi Day: "Sun 5/21 2:05 PM – Mon 5/22 4:45 PM"
            let startDay = dayFormatter.string(from: startDate)
            let endDay = dayFormatter.string(from: endDate)
            return "\(startDay) \(startTime) – \(endDay) \(endTime)"
        }
    }
}

private extension [AbsoluteScheduleValue<Bool>] {
    func percentageTrue(from windowStart: Date, to windowEnd: Date) -> Double {
        let windowDuration = windowEnd.timeIntervalSince(windowStart)
        guard windowDuration > 0 else { return 0 }

        var totalTrueTime: TimeInterval = 0
        for entry in self {
            let overlapStart = Swift.max(entry.startDate, windowStart)
            let overlapEnd = Swift.min(entry.endDate, windowEnd)
            let overlap = Swift.max(0, overlapEnd.timeIntervalSince(overlapStart))
            if entry.value {
                totalTrueTime += overlap
            }
        }

        return totalTrueTime / windowDuration
    }
}
