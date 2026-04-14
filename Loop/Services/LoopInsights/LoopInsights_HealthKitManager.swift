//
//  LoopInsights_HealthKitManager.swift
//  Loop
//
//  Concept & design by Taylor Patterson. Coded & tested by Claude Code in February 2026.
//  Copyright (c) 2025-2026 LoopKit Authors. All rights reserved.
//

import Foundation
import HealthKit

/// Standalone HealthKit manager for LoopInsights biometric data.
/// Read-only — never writes to HealthKit. Uses its own HKHealthStore instance
/// and requests authorization independently of Loop's existing HealthKit access.
final class LoopInsights_HealthKitManager: ObservableObject {

    private let healthStore = HKHealthStore()

    /// The biometric types we request read access to
    private static let biometricTypes: Set<HKObjectType> = {
        var types = Set<HKObjectType>()
        if let hr = HKQuantityType.quantityType(forIdentifier: .heartRate) { types.insert(hr) }
        if let hrv = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) { types.insert(hrv) }
        if let steps = HKQuantityType.quantityType(forIdentifier: .stepCount) { types.insert(steps) }
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { types.insert(sleep) }
        if let energy = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) { types.insert(energy) }
        if let weight = HKQuantityType.quantityType(forIdentifier: .bodyMass) { types.insert(weight) }
        if let caffeine = HKQuantityType.quantityType(forIdentifier: .dietaryCaffeine) { types.insert(caffeine) }
        // Menstrual cycle data from Apple Health Cycle Tracker
        if let menstrualFlow = HKObjectType.categoryType(forIdentifier: .menstrualFlow) { types.insert(menstrualFlow) }
        if let ovulation = HKObjectType.categoryType(forIdentifier: .ovulationTestResult) { types.insert(ovulation) }
        // Core diabetes data types (Loop writes these — we read them for longer analysis periods)
        if let glucose = HKQuantityType.quantityType(forIdentifier: .bloodGlucose) { types.insert(glucose) }
        if let insulin = HKQuantityType.quantityType(forIdentifier: .insulinDelivery) { types.insert(insulin) }
        if let carbs = HKQuantityType.quantityType(forIdentifier: .dietaryCarbohydrates) { types.insert(carbs) }
        return types
    }()

    /// Whether HealthKit is available on this device
    static var isHealthDataAvailable: Bool {
        return HKHealthStore.isHealthDataAvailable()
    }

    private static let authRequestedKey = "LoopInsights_biometricAuthRequested"

    /// Whether we have requested authorization (persisted to UserDefaults so it survives view recreation)
    @Published private(set) var authorizationRequested = UserDefaults.standard.bool(forKey: authRequestedKey)

    // MARK: - Authorization

    /// Request read-only authorization for biometric types.
    /// iOS will show a separate HealthKit authorization sheet for these new types.
    func requestAuthorization() async throws {
        guard Self.isHealthDataAvailable else {
            throw LoopInsightsError.insufficientData("HealthKit is not available on this device")
        }

        try await healthStore.requestAuthorization(toShare: [], read: Self.biometricTypes)

        await MainActor.run {
            authorizationRequested = true
            UserDefaults.standard.set(true, forKey: Self.authRequestedKey)
        }
    }

    /// NOTE: HealthKit intentionally hides read authorization status for privacy.
    /// `authorizationStatus(for:)` only reports *write/share* status. Since LoopInsights
    /// is read-only (toShare: []), we cannot determine per-type read permission.
    /// We track only whether authorization has been requested.

    // MARK: - Fetch All Biometrics

    /// Fetch all biometric data for the given date range. Each sub-stat is optional —
    /// if a type isn't authorized or has no data, that sub-stat is nil.
    func fetchAllBiometrics(start: Date, end: Date) async throws -> LoopInsightsAggregatedStats.BiometricStats {
        // P1: Run all 6 HealthKit queries in parallel instead of sequentially
        async let hr = fetchHeartRateSafe(start: start, end: end)
        async let hrv = fetchHRVSafe(start: start, end: end)
        async let steps = fetchStepSafe(start: start, end: end)
        async let sleep = fetchSleepSafe(start: start, end: end)
        async let energy = fetchEnergySafe(start: start, end: end)
        async let weight = fetchWeightSafe(start: start, end: end)
        async let menstrual = fetchMenstrualCycleSafe(start: start, end: end)

        return await LoopInsightsAggregatedStats.BiometricStats(
            heartRate: hr,
            hrv: hrv,
            steps: steps,
            sleep: sleep,
            activeEnergy: energy,
            weight: weight,
            stressScore: nil,  // Computed by AdvancedAnalyzers in DataAggregator
            menstrualCycle: menstrual
        )
    }

    private func safeFetch<T>(_ label: String, _ fetch: () async throws -> T?) async -> T? {
        do { return try await fetch() }
        catch { LoopInsights_FeatureFlags.log.error("HK \(label) error: \(error)"); return nil }
    }

    private func fetchHeartRateSafe(start: Date, end: Date) async -> LoopInsightsAggregatedStats.HeartRateStats? {
        await safeFetch("heart rate") { try await fetchHeartRateStats(start: start, end: end) }
    }

    private func fetchHRVSafe(start: Date, end: Date) async -> LoopInsightsAggregatedStats.HRVStats? {
        await safeFetch("HRV") { try await fetchHRVStats(start: start, end: end) }
    }

    private func fetchStepSafe(start: Date, end: Date) async -> LoopInsightsAggregatedStats.StepStats? {
        await safeFetch("steps") { try await fetchStepStats(start: start, end: end) }
    }

    private func fetchSleepSafe(start: Date, end: Date) async -> LoopInsightsAggregatedStats.SleepStats? {
        await safeFetch("sleep") { try await fetchSleepStats(start: start, end: end) }
    }

    private func fetchEnergySafe(start: Date, end: Date) async -> LoopInsightsAggregatedStats.ActiveEnergyStats? {
        await safeFetch("active energy") { try await fetchActiveEnergyStats(start: start, end: end) }
    }

    private func fetchWeightSafe(start: Date, end: Date) async -> LoopInsightsAggregatedStats.WeightStats? {
        await safeFetch("weight") { try await fetchWeightStats(start: start, end: end) }
    }

    private func fetchMenstrualCycleSafe(start: Date, end: Date) async -> LoopInsightsMenstrualCycleStats? {
        await safeFetch("menstrual cycle") { try await fetchMenstrualCycleStats(start: start, end: end) }
    }

    // MARK: - Heart Rate

    private func fetchHeartRateStats(start: Date, end: Date) async throws -> LoopInsightsAggregatedStats.HeartRateStats? {
        guard let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return nil }

        let samples = try await querySamples(type: hrType, start: start, end: end)
        guard !samples.isEmpty else { return nil }

        let bpmUnit = HKUnit.count().unitDivided(by: .minute())
        let calendar = Calendar.current

        var restingValues: [Double] = []
        var activeValues: [Double] = []
        var hourlyBuckets: [Int: [Double]] = [:]

        for sample in samples {
            let bpm = sample.quantity.doubleValue(for: bpmUnit)
            let hour = calendar.component(.hour, from: sample.startDate)
            hourlyBuckets[hour, default: []].append(bpm)

            // Heuristic: resting = samples between 11PM-6AM or HR < 80
            let isResting = (hour >= 23 || hour < 6) || bpm < 80
            if isResting {
                restingValues.append(bpm)
            } else {
                activeValues.append(bpm)
            }
        }

        let avgResting = restingValues.isEmpty ? 0 : restingValues.reduce(0, +) / Double(restingValues.count)
        let avgActive = activeValues.isEmpty ? 0 : activeValues.reduce(0, +) / Double(activeValues.count)
        let hourlyAvgs = hourlyBuckets.mapValues { $0.reduce(0, +) / Double($0.count) }

        return LoopInsightsAggregatedStats.HeartRateStats(
            averageRestingHR: avgResting,
            averageActiveHR: avgActive,
            hourlyAverages: hourlyAvgs
        )
    }

    // MARK: - HRV

    private func fetchHRVStats(start: Date, end: Date) async throws -> LoopInsightsAggregatedStats.HRVStats? {
        guard let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else { return nil }

        let samples = try await querySamples(type: hrvType, start: start, end: end)
        guard !samples.isEmpty else { return nil }

        let msUnit = HKUnit.secondUnit(with: .milli)
        let values = samples.map { $0.quantity.doubleValue(for: msUnit) }
        let average = values.reduce(0, +) / Double(values.count)

        // Trend: compare first half to second half
        let midpoint = values.count / 2
        let firstHalf = Array(values.prefix(midpoint))
        let secondHalf = Array(values.suffix(from: midpoint))
        let firstAvg = firstHalf.isEmpty ? average : firstHalf.reduce(0, +) / Double(firstHalf.count)
        let secondAvg = secondHalf.isEmpty ? average : secondHalf.reduce(0, +) / Double(secondHalf.count)
        let trend = secondAvg - firstAvg

        return LoopInsightsAggregatedStats.HRVStats(
            averageSDNN: average,
            trend: trend
        )
    }

    // MARK: - Steps

    private func fetchStepStats(start: Date, end: Date) async throws -> LoopInsightsAggregatedStats.StepStats? {
        guard let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return nil }

        // Use HKStatisticsCollectionQuery with .cumulativeSum so HealthKit deduplicates
        // overlapping sources (iPhone + Apple Watch) the same way the Health app does.
        // Raw HKSampleQuery returns samples from every source without deduplication,
        // which inflates step counts when multiple devices are recording simultaneously.
        let calendar = Calendar.current
        let countUnit = HKUnit.count()
        let anchorDate = calendar.startOfDay(for: start)
        let daily = DateComponents(day: 1)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        let statistics: [HKStatistics] = try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: stepType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum,
                anchorDate: anchorDate,
                intervalComponents: daily
            )
            query.initialResultsHandler = { _, results, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: results?.statistics() ?? [])
                }
            }
            healthStore.execute(query)
        }

        var dailyTotals: [String: Double] = [:]
        for stat in statistics {
            guard let sum = stat.sumQuantity()?.doubleValue(for: countUnit), sum > 0 else { continue }
            dailyTotals[Self.dayKey(for: stat.startDate, calendar: calendar)] = sum
        }
        guard !dailyTotals.isEmpty else { return nil }

        let avgDaily = dailyTotals.values.reduce(0, +) / Double(dailyTotals.count)

        // Query 2: Raw samples for hourly distribution (relative pattern only).
        // Double-counting bias from multiple sources is uniform across all hours so it
        // doesn't distort the shape — peak hour and glucose correlation remain valid.
        let rawSamples = try await querySamples(type: stepType, start: start, end: end)
        var hourlyBuckets: [Int: [Double]] = [:]
        for sample in rawSamples {
            let count = sample.quantity.doubleValue(for: countUnit)
            let hour = calendar.component(.hour, from: sample.startDate)
            hourlyBuckets[hour, default: []].append(count)
        }
        let hourlyAvgs = hourlyBuckets.mapValues { $0.reduce(0, +) / Double($0.count) }

        return LoopInsightsAggregatedStats.StepStats(
            averageDailySteps: avgDaily,
            hourlyAverages: hourlyAvgs
        )
    }

    // MARK: - Sleep

    private func fetchSleepStats(start: Date, end: Date) async throws -> LoopInsightsAggregatedStats.SleepStats? {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return nil }

        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let samples: [HKCategorySample] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, results, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: (results as? [HKCategorySample]) ?? [])
                }
            }
            healthStore.execute(query)
        }

        // Filter to inBed or asleep categories (exclude awake/inBed transitions)
        let sleepSamples = samples.filter { sample in
            let value = HKCategoryValueSleepAnalysis(rawValue: sample.value)
            if value == .inBed { return true }
            if #available(iOS 16.0, *) {
                if value == .asleepUnspecified || value == .asleepCore ||
                   value == .asleepDeep || value == .asleepREM {
                    return true
                }
            }
            return false
        }

        guard !sleepSamples.isEmpty else { return nil }

        let calendar = Calendar.current

        // Group sleep samples by night (use the date of the start as the night key)
        var nightlyDurations: [String: TimeInterval] = [:]
        var bedtimes: [Double] = []
        var wakeTimes: [Double] = []

        for sample in sleepSamples {
            let duration = sample.endDate.timeIntervalSince(sample.startDate)
            let nightKey = Self.dayKey(for: sample.startDate, calendar: calendar)
            nightlyDurations[nightKey, default: 0] += duration

            let bedComponents = calendar.dateComponents([.hour, .minute], from: sample.startDate)
            let bedSeconds = Double(bedComponents.hour ?? 0) * 3600 + Double(bedComponents.minute ?? 0) * 60
            bedtimes.append(bedSeconds)

            let wakeComponents = calendar.dateComponents([.hour, .minute], from: sample.endDate)
            let wakeSeconds = Double(wakeComponents.hour ?? 0) * 3600 + Double(wakeComponents.minute ?? 0) * 60
            wakeTimes.append(wakeSeconds)
        }

        let avgDuration = nightlyDurations.isEmpty ? 0 : nightlyDurations.values.reduce(0, +) / Double(nightlyDurations.count) / 3600
        let avgBedtime = bedtimes.isEmpty ? 0 : bedtimes.reduce(0, +) / Double(bedtimes.count)
        let avgWakeTime = wakeTimes.isEmpty ? 0 : wakeTimes.reduce(0, +) / Double(wakeTimes.count)

        return LoopInsightsAggregatedStats.SleepStats(
            averageDurationHours: avgDuration,
            averageBedtime: avgBedtime,
            averageWakeTime: avgWakeTime
        )
    }

    // MARK: - Active Energy

    private func fetchActiveEnergyStats(start: Date, end: Date) async throws -> LoopInsightsAggregatedStats.ActiveEnergyStats? {
        guard let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else { return nil }

        let samples = try await querySamples(type: energyType, start: start, end: end)
        guard !samples.isEmpty else { return nil }

        let kcalUnit = HKUnit.kilocalorie()
        let calendar = Calendar.current

        var dailyTotals: [String: Double] = [:]
        var hourlyBuckets: [Int: [Double]] = [:]
        for sample in samples {
            let kcal = sample.quantity.doubleValue(for: kcalUnit)
            let dayKey = Self.dayKey(for: sample.startDate, calendar: calendar)
            dailyTotals[dayKey, default: 0] += kcal

            let hour = calendar.component(.hour, from: sample.startDate)
            hourlyBuckets[hour, default: []].append(kcal)
        }

        let avgDaily = dailyTotals.isEmpty ? 0 : dailyTotals.values.reduce(0, +) / Double(dailyTotals.count)
        let hourlyAvgs = hourlyBuckets.mapValues { $0.reduce(0, +) / Double($0.count) }

        return LoopInsightsAggregatedStats.ActiveEnergyStats(
            averageDailyCalories: avgDaily,
            hourlyAverages: hourlyAvgs
        )
    }

    // MARK: - Weight

    private func fetchWeightStats(start: Date, end: Date) async throws -> LoopInsightsAggregatedStats.WeightStats? {
        guard let weightType = HKQuantityType.quantityType(forIdentifier: .bodyMass) else { return nil }

        let samples = try await querySamples(type: weightType, start: start, end: end)
        guard !samples.isEmpty else { return nil }

        let kgUnit = HKUnit.gramUnit(with: .kilo)
        let values = samples.map { $0.quantity.doubleValue(for: kgUnit) }

        let latest = values.last ?? 0
        let earliest = values.first ?? latest
        let trend = latest - earliest

        return LoopInsightsAggregatedStats.WeightStats(
            latestWeight: latest,
            weightTrend: trend
        )
    }

    // MARK: - Core Diabetes Data (from HealthKit)

    /// Fetch blood glucose samples from HealthKit for the given date range.
    /// Returns (timestamp, mg/dL) tuples. Loop writes CGM data to HealthKit,
    /// so this provides access to historical data beyond Loop's local store retention.
    func fetchGlucoseSamples(start: Date, end: Date) async throws -> [(date: Date, mgdl: Double)] {
        guard let glucoseType = HKQuantityType.quantityType(forIdentifier: .bloodGlucose) else { return [] }

        let samples = try await querySamples(type: glucoseType, start: start, end: end)
        let mgdlUnit = HKUnit.gramUnit(with: .milli).unitDivided(by: HKUnit.literUnit(with: .deci))

        return samples.map { sample in
            (date: sample.startDate, mgdl: sample.quantity.doubleValue(for: mgdlUnit))
        }
    }

    /// Fetch insulin delivery samples from HealthKit for the given date range.
    /// Loop writes all doses (basal + bolus) to HealthKit.
    func fetchInsulinDelivery(start: Date, end: Date) async throws -> [(date: Date, units: Double, duration: TimeInterval, purpose: HKInsulinDeliveryReason?)] {
        guard let insulinType = HKQuantityType.quantityType(forIdentifier: .insulinDelivery) else { return [] }

        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        let samples: [HKQuantitySample] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: insulinType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, results, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: (results as? [HKQuantitySample]) ?? [])
                }
            }
            healthStore.execute(query)
        }

        let unitUnit = HKUnit.internationalUnit()
        return samples.map { sample in
            let purpose: HKInsulinDeliveryReason?
            if let meta = sample.metadata,
               let reasonRaw = meta[HKMetadataKeyInsulinDeliveryReason] as? NSNumber {
                purpose = HKInsulinDeliveryReason(rawValue: reasonRaw.intValue)
            } else {
                purpose = nil
            }
            return (
                date: sample.startDate,
                units: sample.quantity.doubleValue(for: unitUnit),
                duration: sample.endDate.timeIntervalSince(sample.startDate),
                purpose: purpose
            )
        }
    }

    /// Fetch dietary carbohydrate entries from HealthKit for the given date range.
    /// Loop writes carb entries to HealthKit.
    func fetchCarbEntries(start: Date, end: Date) async throws -> [(date: Date, grams: Double)] {
        guard let carbType = HKQuantityType.quantityType(forIdentifier: .dietaryCarbohydrates) else { return [] }

        let samples = try await querySamples(type: carbType, start: start, end: end)
        let gramUnit = HKUnit.gram()

        return samples.map { sample in
            (date: sample.startDate, grams: sample.quantity.doubleValue(for: gramUnit))
        }
    }

    // MARK: - Menstrual Cycle

    /// Fetch menstrual cycle data from Apple Health Cycle Tracker.
    /// Uses HKCategorySample queries for menstrualFlow to determine cycle phase,
    /// cycle length, and current cycle day. Returns nil if no data is found
    /// (user doesn't track cycles or hasn't granted access).
    private func fetchMenstrualCycleStats(start: Date, end: Date) async throws -> LoopInsightsMenstrualCycleStats? {
        guard let flowType = HKObjectType.categoryType(forIdentifier: .menstrualFlow) else { return nil }

        // Query flow samples — use a wider window (90 days back) to estimate cycle length
        let extendedStart = Date().addingTimeInterval(-90 * 86400)
        let predicate = HKQuery.predicateForSamples(withStart: extendedStart, end: end, options: .strictStartDate)

        let samples: [HKCategorySample] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: flowType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, results, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: (results as? [HKCategorySample]) ?? [])
                }
            }
            healthStore.execute(query)
        }

        guard !samples.isEmpty else {
            return LoopInsightsMenstrualCycleStats(
                currentPhase: .unknown, currentCycleDay: nil, averageCycleLength: nil,
                lastFlowStartDate: nil, flowDaysInLookback: 0, dataAvailable: false
            )
        }

        let calendar = Calendar.current

        // Group flow samples by day to find period start dates
        var flowDays: Set<String> = []
        var flowDates: [Date] = []
        for sample in samples {
            let dayKey = Self.dayKey(for: sample.startDate, calendar: calendar)
            if flowDays.insert(dayKey).inserted {
                flowDates.append(calendar.startOfDay(for: sample.startDate))
            }
        }
        flowDates.sort()

        // Identify period start dates (first flow day after a gap of 14+ days)
        var periodStarts: [Date] = []
        if let first = flowDates.first {
            periodStarts.append(first)
        }
        for i in 1..<flowDates.count {
            let gap = flowDates[i].timeIntervalSince(flowDates[i - 1])
            if gap > 14 * 86400 {
                // New period — gap too large to be consecutive flow days
                periodStarts.append(flowDates[i])
            }
        }

        // Average cycle length from consecutive period starts
        var cycleLengths: [Double] = []
        for i in 1..<periodStarts.count {
            let length = periodStarts[i].timeIntervalSince(periodStarts[i - 1]) / 86400
            if length >= 18 && length <= 45 {  // Filter physiologically plausible cycles
                cycleLengths.append(length)
            }
        }
        let avgCycleLength = cycleLengths.isEmpty ? nil : cycleLengths.reduce(0, +) / Double(cycleLengths.count)

        // Most recent period start
        let lastPeriodStart = periodStarts.last

        // Current cycle day (days since last period start + 1)
        let currentCycleDay: Int?
        if let lastStart = lastPeriodStart {
            let daysSincePeriod = Int(Date().timeIntervalSince(lastStart) / 86400) + 1
            currentCycleDay = daysSincePeriod
        } else {
            currentCycleDay = nil
        }

        // Estimate current phase from cycle day
        let phase: LoopInsightsMenstrualPhase
        let cycleLen = avgCycleLength ?? 28.0
        if let day = currentCycleDay {
            if day <= 5 {
                phase = .menstrual
            } else if day <= Int(cycleLen * 0.46) {  // ~day 13 of 28
                phase = .follicular
            } else if day <= Int(cycleLen * 0.57) {  // ~day 16 of 28
                phase = .ovulatory
            } else if Double(day) <= cycleLen {
                phase = .luteal
            } else {
                // Past expected cycle length — could be late period or irregular
                phase = .luteal  // Default to luteal since that's what happens pre-period
            }
        } else {
            phase = .unknown
        }

        // Count flow days within the analysis lookback period
        let lookbackFlowDays = flowDates.filter { $0 >= start && $0 <= end }.count

        return LoopInsightsMenstrualCycleStats(
            currentPhase: phase,
            currentCycleDay: currentCycleDay,
            averageCycleLength: avgCycleLength,
            lastFlowStartDate: lastPeriodStart,
            flowDaysInLookback: lookbackFlowDays,
            dataAvailable: true
        )
    }

    // MARK: - Caffeine

    /// Fetch dietary caffeine entries from HealthKit for the given date range.
    /// Returns LoopInsightsCaffeineEntry objects tagged with isFromHealthKit = true.
    func fetchCaffeineEntries(start: Date, end: Date) async throws -> [LoopInsightsCaffeineEntry] {
        guard let caffeineType = HKQuantityType.quantityType(forIdentifier: .dietaryCaffeine) else { return [] }

        let samples = try await querySamples(type: caffeineType, start: start, end: end)
        let mgUnit = HKUnit.gramUnit(with: .milli)

        return samples.map { sample in
            let mg = sample.quantity.doubleValue(for: mgUnit)
            let sourceName = sample.sourceRevision.source.name
            return LoopInsightsCaffeineEntry(
                timestamp: sample.startDate,
                milligrams: mg,
                source: sourceName,
                isFromHealthKit: true
            )
        }
    }

    // MARK: - Helpers

    /// Generic sample query wrapper
    private func querySamples(type: HKQuantityType, start: Date, end: Date) async throws -> [HKQuantitySample] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, results, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: (results as? [HKQuantitySample]) ?? [])
                }
            }
            healthStore.execute(query)
        }
    }

    /// Create a day-key string for grouping samples by date
    private static func dayKey(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
    }
}
