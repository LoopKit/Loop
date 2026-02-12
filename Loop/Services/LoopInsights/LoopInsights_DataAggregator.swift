//
//  LoopInsights_DataAggregator.swift
//  Loop
//
//  Concept & design by Taylor Patterson. Coded & tested by Claude Code in February 2026.
//  Copyright (c) 2025-2026 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit
import HealthKit

/// Protocol for providing data store access to the aggregator.
/// Decouples LoopInsights from concrete store implementations.
protocol LoopInsightsDataProviderProtocol: AnyObject {
    func getGlucoseSamples(start: Date, end: Date) async throws -> [StoredGlucoseSample]
    func getCarbEntries(start: Date, end: Date) async throws -> [StoredCarbEntry]
    func getNormalizedDoseEntries(start: Date, end: Date) async throws -> [DoseEntry]
    func getLatestStoredSettings() -> StoredSettings
}

/// Reads from Loop's existing data stores (GlucoseStore, DoseStore, CarbStore)
/// and computes aggregated statistics for AI analysis.
///
/// This class is read-only — it never writes to any Loop data store.
final class LoopInsights_DataAggregator {

    private weak var dataProvider: LoopInsightsDataProviderProtocol?

    init(dataProvider: LoopInsightsDataProviderProtocol) {
        self.dataProvider = dataProvider
    }

    // MARK: - Public API

    /// Aggregate all data for the specified analysis period
    func aggregateData(period: LoopInsightsAnalysisPeriod) async throws -> LoopInsightsAggregatedStats {
        guard let dataProvider = dataProvider else {
            throw LoopInsightsError.insufficientData("Data provider not available")
        }

        let endDate = Date()
        let startDate = endDate.addingTimeInterval(-period.timeInterval)

        async let glucoseStats = computeGlucoseStats(provider: dataProvider, start: startDate, end: endDate)
        async let insulinStats = computeInsulinStats(provider: dataProvider, start: startDate, end: endDate)
        async let carbStats = computeCarbStats(provider: dataProvider, start: startDate, end: endDate)

        return LoopInsightsAggregatedStats(
            period: period,
            glucoseStats: try await glucoseStats,
            insulinStats: try await insulinStats,
            carbStats: try await carbStats,
            generatedAt: Date()
        )
    }

    /// Capture a snapshot of current therapy settings
    func captureTherapySnapshot() throws -> LoopInsightsTherapySnapshot {
        guard let dataProvider = dataProvider else {
            throw LoopInsightsError.insufficientData("Data provider not available")
        }

        let settings = dataProvider.getLatestStoredSettings()

        let basalItems = settings.basalRateSchedule?.items.map {
            LoopInsightsTherapySnapshot.LoopInsightsScheduleItem(startTime: $0.startTime, value: $0.value)
        } ?? []

        let isfItems = settings.insulinSensitivitySchedule?.items.map {
            LoopInsightsTherapySnapshot.LoopInsightsScheduleItem(startTime: $0.startTime, value: $0.value)
        } ?? []

        let crItems = settings.carbRatioSchedule?.items.map {
            LoopInsightsTherapySnapshot.LoopInsightsScheduleItem(startTime: $0.startTime, value: $0.value)
        } ?? []

        return LoopInsightsTherapySnapshot(
            basalRateItems: basalItems,
            insulinSensitivityItems: isfItems,
            carbRatioItems: crItems,
            capturedAt: Date()
        )
    }

    // MARK: - Glucose Stats

    private func computeGlucoseStats(provider: LoopInsightsDataProviderProtocol, start: Date, end: Date) async throws -> LoopInsightsAggregatedStats.GlucoseStats {
        let samples = try await provider.getGlucoseSamples(start: start, end: end)

        guard !samples.isEmpty else {
            throw LoopInsightsError.insufficientData("No glucose data available for the selected period")
        }

        let glucoseValues = samples.map { $0.quantity.doubleValue(for: .milligramsPerDeciliter) }
        let count = Double(glucoseValues.count)

        let average = glucoseValues.reduce(0, +) / count

        let variance = glucoseValues.reduce(0) { $0 + pow($1 - average, 2) } / count
        let stdDev = sqrt(variance)

        let cv = (stdDev / average) * 100

        // Time in range calculations (70-180 mg/dL standard range)
        let inRange = glucoseValues.filter { $0 >= 70 && $0 <= 180 }
        let belowRange = glucoseValues.filter { $0 < 70 }
        let aboveRange = glucoseValues.filter { $0 > 180 }

        let tir = (Double(inRange.count) / count) * 100
        let tbr = (Double(belowRange.count) / count) * 100
        let tar = (Double(aboveRange.count) / count) * 100

        // GMI (Glucose Management Indicator) = 3.31 + 0.02392 × mean glucose (mg/dL)
        let gmi = 3.31 + (0.02392 * average)

        // Hourly averages
        var hourlyBuckets: [Int: [Double]] = [:]
        let calendar = Calendar.current
        for sample in samples {
            let hour = calendar.component(.hour, from: sample.startDate)
            hourlyBuckets[hour, default: []].append(sample.quantity.doubleValue(for: .milligramsPerDeciliter))
        }
        let hourlyAverages = hourlyBuckets.mapValues { values in
            values.reduce(0, +) / Double(values.count)
        }

        return LoopInsightsAggregatedStats.GlucoseStats(
            averageGlucose: average,
            standardDeviation: stdDev,
            coefficientOfVariation: cv,
            timeInRange: tir,
            timeBelowRange: tbr,
            timeAboveRange: tar,
            gmi: gmi,
            sampleCount: glucoseValues.count,
            hourlyAverages: hourlyAverages
        )
    }

    // MARK: - Insulin Stats

    private func computeInsulinStats(provider: LoopInsightsDataProviderProtocol, start: Date, end: Date) async throws -> LoopInsightsAggregatedStats.InsulinStats {
        let doses = try await provider.getNormalizedDoseEntries(start: start, end: end)

        let dayCount = max(1, end.timeIntervalSince(start) / (24 * 60 * 60))

        var totalBasal: Double = 0
        var totalBolus: Double = 0
        var hourlyBasalBuckets: [Int: [Double]] = [:]
        var correctionCount = 0
        let calendar = Calendar.current

        for dose in doses {
            let units = dose.deliveredUnits ?? dose.programmedUnits

            switch dose.type {
            case .basal, .tempBasal, .suspend:
                totalBasal += units
                let hour = calendar.component(.hour, from: dose.startDate)
                // Approximate hourly rate from the dose
                let durationHours = max(dose.endDate.timeIntervalSince(dose.startDate) / 3600, 0.001)
                let rate = units / durationHours
                hourlyBasalBuckets[hour, default: []].append(rate)
            case .bolus:
                totalBolus += units
                // A bolus without a carb entry nearby is likely a correction
                // This is a simplified heuristic
                if dose.isMutable == false {
                    correctionCount += 1
                }
            default:
                break
            }
        }

        let totalInsulin = totalBasal + totalBolus
        let tdd = totalInsulin / dayCount

        let basalPercent = totalInsulin > 0 ? (totalBasal / totalInsulin) * 100 : 50
        let bolusPercent = totalInsulin > 0 ? (totalBolus / totalInsulin) * 100 : 50

        let hourlyBasalAverages = hourlyBasalBuckets.mapValues { values in
            values.reduce(0, +) / Double(values.count)
        }

        return LoopInsightsAggregatedStats.InsulinStats(
            totalDailyDose: tdd,
            basalPercentage: basalPercent,
            bolusPercentage: bolusPercent,
            hourlyBasalAverages: hourlyBasalAverages,
            correctionBolusCount: correctionCount
        )
    }

    // MARK: - Carb Stats

    private func computeCarbStats(provider: LoopInsightsDataProviderProtocol, start: Date, end: Date) async throws -> LoopInsightsAggregatedStats.CarbStats {
        let entries = try await provider.getCarbEntries(start: start, end: end)

        let dayCount = max(1, end.timeIntervalSince(start) / (24 * 60 * 60))
        let totalCarbs = entries.reduce(0.0) { $0 + $1.quantity.doubleValue(for: .gram()) }
        let avgDaily = totalCarbs / dayCount
        let mealCount = entries.count
        let avgPerMeal = mealCount > 0 ? totalCarbs / Double(mealCount) : 0

        // Hourly meal frequency
        var hourlyFrequency: [Int: Int] = [:]
        let calendar = Calendar.current
        for entry in entries {
            let hour = calendar.component(.hour, from: entry.startDate)
            hourlyFrequency[hour, default: 0] += 1
        }

        return LoopInsightsAggregatedStats.CarbStats(
            averageDailyCarbs: avgDaily,
            mealCount: mealCount,
            averageCarbsPerMeal: avgPerMeal,
            hourlyMealFrequency: hourlyFrequency
        )
    }
}
