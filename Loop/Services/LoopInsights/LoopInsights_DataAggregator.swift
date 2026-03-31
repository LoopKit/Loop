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
    private var healthKitManager: LoopInsights_HealthKitManager?

    /// P3: Cached raw data from last aggregation, available for reuse (supplemental context)
    private(set) var lastFetchedGlucoseSamples: [StoredGlucoseSample] = []
    private(set) var lastFetchedCarbEntries: [StoredCarbEntry] = []

    /// Best available glucose data for AGP chart (Loop store or HealthKit, whichever has more samples for the period)
    private(set) var lastGlucoseForAGP: [(date: Date, mgdl: Double)] = []

    init(dataProvider: LoopInsightsDataProviderProtocol, healthKitManager: LoopInsights_HealthKitManager? = nil) {
        self.dataProvider = dataProvider
        self.healthKitManager = healthKitManager
    }

    // MARK: - Public API

    /// Aggregate all data for the specified analysis period
    func aggregateData(period: LoopInsightsAnalysisPeriod) async throws -> LoopInsightsAggregatedStats {
        guard let dataProvider = dataProvider else {
            throw LoopInsightsError.insufficientData("Data provider not available")
        }

        let endDate = Date()
        let startDate = endDate.addingTimeInterval(-period.timeInterval)

        // P3: Fetch all raw data in parallel — each type fetched exactly once
        async let rawGlucose = dataProvider.getGlucoseSamples(start: startDate, end: endDate)
        async let rawDoses = dataProvider.getNormalizedDoseEntries(start: startDate, end: endDate)
        async let rawCarbs = dataProvider.getCarbEntries(start: startDate, end: endDate)
        async let biometrics = fetchBiometricsIfEnabled(start: startDate, end: endDate)

        let glucoseSamples = try await rawGlucose
        let doseEntries = try await rawDoses
        let carbEntries = try await rawCarbs
        let resolvedBiometrics = try await biometrics

        // P3: Store for external reuse (supplemental context)
        self.lastFetchedGlucoseSamples = glucoseSamples
        self.lastFetchedCarbEntries = carbEntries
        // Initial AGP cache from Loop store; computeGlucoseStats may upgrade to HealthKit if HK has more
        self.lastGlucoseForAGP = glucoseSamples.map {
            (date: $0.startDate, mgdl: $0.quantity.doubleValue(for: .milligramsPerDeciliter))
        }

        // Compute stats from pre-fetched data (each may still supplement with HK data)
        // NOTE: computeGlucoseStats returns AGP data alongside stats to avoid writing to
        // self.lastGlucoseForAGP from a concurrent async let context (data race crash).
        async let glucoseStatsTask = computeGlucoseStats(loopSamples: glucoseSamples, start: startDate, end: endDate)
        async let insulinStatsTask = computeInsulinStats(loopDoses: doseEntries, start: startDate, end: endDate)
        async let carbStatsTask = computeCarbStats(loopEntries: carbEntries, start: startDate, end: endDate)

        let glucoseResult = try await glucoseStatsTask
        let resolvedGlucoseStats = glucoseResult.stats
        if let agpData = glucoseResult.agpData {
            self.lastGlucoseForAGP = agpData
        }
        var resolvedInsulinStats = try await insulinStatsTask
        let resolvedCarbStats = try await carbStatsTask

        // Phase 5: Compute negative basal stats if circadian flag is enabled
        // P3: Reuses pre-fetched doses and glucose — no duplicate fetches
        if LoopInsights_FeatureFlags.circadianEnabled {
            do {
                let snapshot = try captureTherapySnapshot()
                let negBasal = LoopInsights_AdvancedAnalyzers.computeNegativeBasalStats(
                    doses: doseEntries,
                    scheduledBasalItems: snapshot.basalRateItems,
                    periodDays: period.rawValue,
                    glucoseSamples: glucoseSamples
                )
                resolvedInsulinStats = LoopInsightsAggregatedStats.InsulinStats(
                    totalDailyDose: resolvedInsulinStats.totalDailyDose,
                    basalPercentage: resolvedInsulinStats.basalPercentage,
                    bolusPercentage: resolvedInsulinStats.bolusPercentage,
                    hourlyBasalAverages: resolvedInsulinStats.hourlyBasalAverages,
                    correctionBolusCount: resolvedInsulinStats.correctionBolusCount,
                    negativeBasalStats: negBasal,
                    dailyBreakdown: resolvedInsulinStats.dailyBreakdown,
                    tddMin: resolvedInsulinStats.tddMin,
                    tddMax: resolvedInsulinStats.tddMax,
                    tddVariabilityCV: resolvedInsulinStats.tddVariabilityCV,
                    tddWeekOverWeekChange: resolvedInsulinStats.tddWeekOverWeekChange
                )
                LoopInsights_FeatureFlags.log.debug("Phase 5: Negative basal stats computed — \(negBasal.suspensionCount) suspensions")
            } catch {
                LoopInsights_FeatureFlags.log.error("Phase 5: Negative basal stats error — \(error)")
            }
        }

        // Phase 5: Compute stress score if circadian flag enabled + biometrics available
        var enrichedBiometrics = resolvedBiometrics
        if LoopInsights_FeatureFlags.circadianEnabled, let bio = resolvedBiometrics {
            let stressScore = LoopInsights_AdvancedAnalyzers.computeStressScore(
                hrvStats: bio.hrv,
                glucoseStats: resolvedGlucoseStats
            )
            if stressScore != nil {
                enrichedBiometrics = LoopInsightsAggregatedStats.BiometricStats(
                    heartRate: bio.heartRate,
                    hrv: bio.hrv,
                    steps: bio.steps,
                    sleep: bio.sleep,
                    activeEnergy: bio.activeEnergy,
                    weight: bio.weight,
                    stressScore: stressScore,
                    menstrualCycle: bio.menstrualCycle
                )
                if let score = stressScore {
                    LoopInsights_FeatureFlags.log.debug("Phase 5: Stress score computed — \(String(format: "%.0f", score.overallScore))/100")
                }
            }
        }

        return LoopInsightsAggregatedStats(
            period: period,
            glucoseStats: resolvedGlucoseStats,
            insulinStats: resolvedInsulinStats,
            carbStats: resolvedCarbStats,
            biometricStats: enrichedBiometrics,
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

        let insulinTypeName = settings.insulinType?.title
        let insulinDiaHours = settings.defaultRapidActingModel.map { $0.actionDuration / 3600.0 }

        return LoopInsightsTherapySnapshot(
            basalRateItems: basalItems,
            insulinSensitivityItems: isfItems,
            carbRatioItems: crItems,
            insulinTypeName: insulinTypeName,
            insulinDiaHours: insulinDiaHours,
            capturedAt: Date()
        )
    }

    // MARK: - Biometrics

    private func fetchBiometricsIfEnabled(start: Date, end: Date) async throws -> LoopInsightsAggregatedStats.BiometricStats? {
        guard LoopInsights_FeatureFlags.biometricsEnabled else {
            LoopInsights_FeatureFlags.log.debug("Biometrics: flag is disabled, skipping")
            return nil
        }
        // Use the injected manager, or create one on the fly. This handles the case
        // where the Coordinator was created before biometrics was enabled.
        let manager = healthKitManager ?? LoopInsights_HealthKitManager()
        LoopInsights_FeatureFlags.log.debug("Biometrics: fetching from HealthKit (start: \(start), end: \(end))")
        do {
            let result = try await manager.fetchAllBiometrics(start: start, end: end)
            LoopInsights_FeatureFlags.log.debug("Biometrics: HR=\(result.heartRate != nil), HRV=\(result.hrv != nil), steps=\(result.steps != nil), sleep=\(result.sleep != nil), energy=\(result.activeEnergy != nil), weight=\(result.weight != nil)")
            // If every sub-stat is nil, return nil so the AI prompt doesn't get an empty section
            if result.heartRate == nil && result.hrv == nil && result.steps == nil &&
               result.sleep == nil && result.activeEnergy == nil && result.weight == nil {
                LoopInsights_FeatureFlags.log.debug("Biometrics: all sub-stats nil — no HealthKit data available")
                return nil
            }
            return result
        } catch {
            LoopInsights_FeatureFlags.log.error("Biometrics: fetch error — \(error)")
            return nil
        }
    }

    // MARK: - Glucose Stats

    /// Result type for computeGlucoseStats — returns stats + optional AGP data upgrade.
    /// Using a struct avoids writing to `self` from concurrent async let contexts (data race).
    private struct GlucoseStatsResult {
        let stats: LoopInsightsAggregatedStats.GlucoseStats
        /// Non-nil when HealthKit had more samples than Loop store — caller should update lastGlucoseForAGP.
        let agpData: [(date: Date, mgdl: Double)]?
    }

    /// P3: Accepts pre-fetched Loop samples to avoid duplicate fetching.
    /// Still supplements with HealthKit data for longer periods when HK has more samples.
    private func computeGlucoseStats(loopSamples: [StoredGlucoseSample], start: Date, end: Date) async throws -> GlucoseStatsResult {
        // Supplement with HealthKit data when Loop's Core Data cache has gaps.
        // Always attempt HK supplementation — Core Data cache is short-lived (~1 hour)
        // so most historical data lives in HealthKit.
        let hkManager = healthKitManager ?? LoopInsights_HealthKitManager()
        do {
            let hkGlucose = try await hkManager.fetchGlucoseSamples(start: start, end: end)
            if hkGlucose.count > loopSamples.count {
                LoopInsights_FeatureFlags.log.debug("HealthKit glucose: \(hkGlucose.count) samples vs Loop store \(loopSamples.count) — using HealthKit data")
                let hkValues = hkGlucose.map { (date: $0.date, mgdl: $0.mgdl) }
                let stats = computeGlucoseStatsFromValues(
                    values: hkValues,
                    start: start, end: end
                )
                return GlucoseStatsResult(stats: stats, agpData: hkValues)
            }
        } catch {
            LoopInsights_FeatureFlags.log.error("HealthKit glucose fetch error (continuing with Loop store data): \(error)")
        }

        guard !loopSamples.isEmpty else {
            throw LoopInsightsError.insufficientData("No glucose data available for the selected period")
        }

        // P9: Pre-convert all glucose values once
        let glucoseValues = loopSamples.map { $0.quantity.doubleValue(for: .milligramsPerDeciliter) }
        let count = Double(glucoseValues.count)

        let average = glucoseValues.reduce(0, +) / count
        let variance = glucoseValues.reduce(0) { $0 + pow($1 - average, 2) } / count
        let stdDev = sqrt(variance)
        let cv = (stdDev / average) * 100

        // P2: Single-pass 5-zone TIR counting (replaces 5 separate .filter() passes)
        let tightUpper = LoopInsights_FeatureFlags.tightRangeUpperBound
        var veryHighCount = 0, highCount = 0, inRangeCount = 0, lowCount = 0, veryLowCount = 0
        var tightRangeCount = 0
        for value in glucoseValues {
            if value > 250 { veryHighCount += 1 }
            else if value > 180 { highCount += 1 }
            else if value >= 70 { inRangeCount += 1 }
            else if value >= 54 { lowCount += 1 }
            else { veryLowCount += 1 }
            // TITR counted independently of 5-zone model
            if value >= 70 && value <= Double(tightUpper) {
                tightRangeCount += 1
            }
        }

        let tir = (Double(inRangeCount) / count) * 100
        let titr = (Double(tightRangeCount) / count) * 100
        let tvh = (Double(veryHighCount) / count) * 100
        let th = (Double(highCount) / count) * 100
        let tl = (Double(lowCount) / count) * 100
        let tvl = (Double(veryLowCount) / count) * 100

        let gmi = 3.31 + (0.02392 * average)

        // P9: Hourly averages using pre-converted values
        var hourlyBuckets: [Int: [Double]] = [:]
        let calendar = Calendar.current
        for (i, sample) in loopSamples.enumerated() {
            let hour = calendar.component(.hour, from: sample.startDate)
            hourlyBuckets[hour, default: []].append(glucoseValues[i])
        }
        let hourlyAverages = hourlyBuckets.mapValues { values in
            values.reduce(0, +) / Double(values.count)
        }

        return GlucoseStatsResult(
            stats: LoopInsightsAggregatedStats.GlucoseStats(
                averageGlucose: average,
                standardDeviation: stdDev,
                coefficientOfVariation: cv,
                timeInRange: tir,
                timeInTightRange: titr,
                tightRangeUpperBound: tightUpper,
                timeVeryHigh: tvh,
                timeHigh: th,
                timeLow: tl,
                timeVeryLow: tvl,
                gmi: gmi,
                sampleCount: glucoseValues.count,
                hourlyAverages: hourlyAverages
            ),
            agpData: nil
        )
    }

    /// Compute glucose stats from raw (date, mg/dL) tuples — used for HealthKit-sourced data
    private func computeGlucoseStatsFromValues(values: [(date: Date, mgdl: Double)], start: Date, end: Date) -> LoopInsightsAggregatedStats.GlucoseStats {
        let glucoseValues = values.map { $0.mgdl }
        let count = Double(glucoseValues.count)

        let average = glucoseValues.reduce(0, +) / count
        let variance = glucoseValues.reduce(0) { $0 + pow($1 - average, 2) } / count
        let stdDev = sqrt(variance)
        let cv = (stdDev / average) * 100

        // P2: Single-pass 5-zone TIR counting
        let tightUpper = LoopInsights_FeatureFlags.tightRangeUpperBound
        var veryHighCount = 0, highCount = 0, inRangeCount = 0, lowCount = 0, veryLowCount = 0
        var tightRangeCount = 0
        for value in glucoseValues {
            if value > 250 { veryHighCount += 1 }
            else if value > 180 { highCount += 1 }
            else if value >= 70 { inRangeCount += 1 }
            else if value >= 54 { lowCount += 1 }
            else { veryLowCount += 1 }
            // TITR counted independently of 5-zone model
            if value >= 70 && value <= Double(tightUpper) {
                tightRangeCount += 1
            }
        }
        let tir = (Double(inRangeCount) / count) * 100
        let titr = (Double(tightRangeCount) / count) * 100
        let tvh = (Double(veryHighCount) / count) * 100
        let th = (Double(highCount) / count) * 100
        let tl = (Double(lowCount) / count) * 100
        let tvl = (Double(veryLowCount) / count) * 100
        let gmi = 3.31 + (0.02392 * average)

        var hourlyBuckets: [Int: [Double]] = [:]
        let calendar = Calendar.current
        for v in values {
            let hour = calendar.component(.hour, from: v.date)
            hourlyBuckets[hour, default: []].append(v.mgdl)
        }
        let hourlyAverages = hourlyBuckets.mapValues { $0.reduce(0, +) / Double($0.count) }

        return LoopInsightsAggregatedStats.GlucoseStats(
            averageGlucose: average,
            standardDeviation: stdDev,
            coefficientOfVariation: cv,
            timeInRange: tir,
            timeInTightRange: titr,
            tightRangeUpperBound: tightUpper,
            timeVeryHigh: tvh,
            timeHigh: th,
            timeLow: tl,
            timeVeryLow: tvl,
            gmi: gmi,
            sampleCount: glucoseValues.count,
            hourlyAverages: hourlyAverages
        )
    }

    // MARK: - Insulin Stats

    /// P3: Accepts pre-fetched Loop doses to avoid duplicate fetching.
    private func computeInsulinStats(loopDoses: [DoseEntry], start: Date, end: Date) async throws -> LoopInsightsAggregatedStats.InsulinStats {
        // Supplement with HealthKit insulin delivery — Core Data cache is short-lived
        let hkManager = healthKitManager ?? LoopInsights_HealthKitManager()
        do {
            let hkInsulin = try await hkManager.fetchInsulinDelivery(start: start, end: end)
            if hkInsulin.count > loopDoses.count {
                LoopInsights_FeatureFlags.log.debug("HealthKit insulin: \(hkInsulin.count) entries vs Loop store \(loopDoses.count) — using HealthKit data")
                return computeInsulinStatsFromHK(hkInsulin, start: start, end: end)
            }
        } catch {
            LoopInsights_FeatureFlags.log.error("HealthKit insulin fetch error (continuing with Loop store data): \(error)")
        }

        let dayCount = max(1, end.timeIntervalSince(start) / (24 * 60 * 60))

        var totalBasal: Double = 0
        var totalBolus: Double = 0
        var hourlyBasalBuckets: [Int: [Double]] = [:]
        var correctionCount = 0
        let calendar = Calendar.current

        for dose in loopDoses {
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

        // Daily TDD breakdown
        var dailyBasal: [Date: Double] = [:]
        var dailyBolus: [Date: Double] = [:]
        for dose in loopDoses {
            let units = dose.deliveredUnits ?? dose.programmedUnits
            let dayStart = calendar.startOfDay(for: dose.startDate)
            switch dose.type {
            case .basal, .tempBasal, .suspend:
                dailyBasal[dayStart, default: 0] += units
            case .bolus:
                dailyBolus[dayStart, default: 0] += units
            default: break
            }
        }
        let (breakdown, tddMin, tddMax, tddCV, weekChange) = Self.computeTDDMetrics(
            dailyBasal: dailyBasal, dailyBolus: dailyBolus, start: start, end: end
        )

        return LoopInsightsAggregatedStats.InsulinStats(
            totalDailyDose: tdd,
            basalPercentage: basalPercent,
            bolusPercentage: bolusPercent,
            hourlyBasalAverages: hourlyBasalAverages,
            correctionBolusCount: correctionCount,
            negativeBasalStats: nil,
            dailyBreakdown: breakdown,
            tddMin: tddMin,
            tddMax: tddMax,
            tddVariabilityCV: tddCV,
            tddWeekOverWeekChange: weekChange
        )
    }

    /// Compute insulin stats from HealthKit insulin delivery tuples
    private func computeInsulinStatsFromHK(
        _ deliveries: [(date: Date, units: Double, duration: TimeInterval, purpose: HKInsulinDeliveryReason?)],
        start: Date, end: Date
    ) -> LoopInsightsAggregatedStats.InsulinStats {
        let dayCount = max(1, end.timeIntervalSince(start) / (24 * 60 * 60))
        let calendar = Calendar.current

        var totalBasal: Double = 0
        var totalBolus: Double = 0
        var hourlyBasalBuckets: [Int: [Double]] = [:]
        var correctionCount = 0

        for delivery in deliveries {
            let hour = calendar.component(.hour, from: delivery.date)
            if delivery.purpose == .basal {
                totalBasal += delivery.units
                let durationHours = max(delivery.duration / 3600, 0.001)
                let rate = delivery.units / durationHours
                hourlyBasalBuckets[hour, default: []].append(rate)
            } else {
                totalBolus += delivery.units
                correctionCount += 1
            }
        }

        let totalInsulin = totalBasal + totalBolus
        let tdd = totalInsulin / dayCount
        let basalPercent = totalInsulin > 0 ? (totalBasal / totalInsulin) * 100 : 50
        let bolusPercent = totalInsulin > 0 ? (totalBolus / totalInsulin) * 100 : 50
        let hourlyBasalAverages = hourlyBasalBuckets.mapValues { $0.reduce(0, +) / Double($0.count) }

        // Daily TDD breakdown
        var dailyBasalMap: [Date: Double] = [:]
        var dailyBolusMap: [Date: Double] = [:]
        for delivery in deliveries {
            let dayStart = calendar.startOfDay(for: delivery.date)
            if delivery.purpose == .basal {
                dailyBasalMap[dayStart, default: 0] += delivery.units
            } else {
                dailyBolusMap[dayStart, default: 0] += delivery.units
            }
        }
        let (breakdown, tddMin, tddMax, tddCV, weekChange) = Self.computeTDDMetrics(
            dailyBasal: dailyBasalMap, dailyBolus: dailyBolusMap, start: start, end: end
        )

        return LoopInsightsAggregatedStats.InsulinStats(
            totalDailyDose: tdd,
            basalPercentage: basalPercent,
            bolusPercentage: bolusPercent,
            hourlyBasalAverages: hourlyBasalAverages,
            correctionBolusCount: correctionCount,
            negativeBasalStats: nil,
            dailyBreakdown: breakdown,
            tddMin: tddMin,
            tddMax: tddMax,
            tddVariabilityCV: tddCV,
            tddWeekOverWeekChange: weekChange
        )
    }

    // MARK: - TDI Metrics

    /// Shared helper to compute daily TDD breakdown, min/max, CV, and week-over-week change
    private static func computeTDDMetrics(
        dailyBasal: [Date: Double],
        dailyBolus: [Date: Double],
        start: Date,
        end: Date
    ) -> (
        breakdown: [LoopInsightsAggregatedStats.DailyInsulinBreakdown],
        tddMin: Double,
        tddMax: Double,
        tddCV: Double,
        weekChange: Double?
    ) {
        let allDays = Set(dailyBasal.keys).union(dailyBolus.keys).sorted()
        var breakdown: [LoopInsightsAggregatedStats.DailyInsulinBreakdown] = []

        for day in allDays {
            let basal = dailyBasal[day] ?? 0
            let bolus = dailyBolus[day] ?? 0
            breakdown.append(LoopInsightsAggregatedStats.DailyInsulinBreakdown(
                date: day,
                totalDailyDose: basal + bolus,
                basalUnits: basal,
                bolusUnits: bolus
            ))
        }

        let tddValues = breakdown.map(\.totalDailyDose)
        let tddMin = tddValues.min() ?? 0
        let tddMax = tddValues.max() ?? 0

        // Coefficient of variation
        let tddCV: Double
        if tddValues.count > 1 {
            let mean = tddValues.reduce(0, +) / Double(tddValues.count)
            if mean > 0 {
                let variance = tddValues.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(tddValues.count)
                tddCV = (variance.squareRoot() / mean) * 100
            } else {
                tddCV = 0
            }
        } else {
            tddCV = 0
        }

        // Week-over-week change (requires ≥14 days)
        let weekChange: Double?
        if breakdown.count >= 14 {
            let recent7 = breakdown.suffix(7).map(\.totalDailyDose)
            let prior7 = breakdown.dropLast(7).suffix(7).map(\.totalDailyDose)
            let recentAvg = recent7.reduce(0, +) / Double(recent7.count)
            let priorAvg = prior7.reduce(0, +) / Double(prior7.count)
            if priorAvg > 0 {
                weekChange = ((recentAvg - priorAvg) / priorAvg) * 100
            } else {
                weekChange = nil
            }
        } else {
            weekChange = nil
        }

        return (breakdown, tddMin, tddMax, tddCV, weekChange)
    }

    // MARK: - Carb Stats

    /// P3: Accepts pre-fetched Loop carb entries to avoid duplicate fetching.
    private func computeCarbStats(loopEntries: [StoredCarbEntry], start: Date, end: Date) async throws -> LoopInsightsAggregatedStats.CarbStats {
        // Supplement with HealthKit carb data — Core Data cache is short-lived
        let hkManager = healthKitManager ?? LoopInsights_HealthKitManager()
        do {
            let hkCarbs = try await hkManager.fetchCarbEntries(start: start, end: end)
            if hkCarbs.count > loopEntries.count {
                LoopInsights_FeatureFlags.log.debug("HealthKit carbs: \(hkCarbs.count) entries vs Loop store \(loopEntries.count) — using HealthKit data")
                return computeCarbStatsFromHK(hkCarbs, start: start, end: end)
            }
        } catch {
            LoopInsights_FeatureFlags.log.error("HealthKit carbs fetch error (continuing with Loop store data): \(error)")
        }

        let dayCount = max(1, end.timeIntervalSince(start) / (24 * 60 * 60))
        let totalCarbs = loopEntries.reduce(0.0) { $0 + $1.quantity.doubleValue(for: .gram()) }
        let avgDaily = totalCarbs / dayCount
        let mealCount = loopEntries.count
        let avgPerMeal = mealCount > 0 ? totalCarbs / Double(mealCount) : 0

        // Hourly meal frequency
        var hourlyFrequency: [Int: Int] = [:]
        let calendar = Calendar.current
        for entry in loopEntries {
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

    /// Compute carb stats from HealthKit (date, grams) tuples
    private func computeCarbStatsFromHK(_ carbEntries: [(date: Date, grams: Double)], start: Date, end: Date) -> LoopInsightsAggregatedStats.CarbStats {
        let dayCount = max(1, end.timeIntervalSince(start) / (24 * 60 * 60))
        let totalCarbs = carbEntries.reduce(0.0) { $0 + $1.grams }
        let avgDaily = totalCarbs / dayCount
        let mealCount = carbEntries.count
        let avgPerMeal = mealCount > 0 ? totalCarbs / Double(mealCount) : 0

        var hourlyFrequency: [Int: Int] = [:]
        let calendar = Calendar.current
        for entry in carbEntries {
            let hour = calendar.component(.hour, from: entry.date)
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
