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

        return await LoopInsightsAggregatedStats.BiometricStats(
            heartRate: hr,
            hrv: hrv,
            steps: steps,
            sleep: sleep,
            activeEnergy: energy,
            weight: weight,
            stressScore: nil  // Computed by AdvancedAnalyzers in DataAggregator
        )
    }

    private func fetchHeartRateSafe(start: Date, end: Date) async -> LoopInsightsAggregatedStats.HeartRateStats? {
        do { return try await fetchHeartRateStats(start: start, end: end) }
        catch { print("[LoopInsights] HK heart rate error: \(error)"); return nil }
    }

    private func fetchHRVSafe(start: Date, end: Date) async -> LoopInsightsAggregatedStats.HRVStats? {
        do { return try await fetchHRVStats(start: start, end: end) }
        catch { print("[LoopInsights] HK HRV error: \(error)"); return nil }
    }

    private func fetchStepSafe(start: Date, end: Date) async -> LoopInsightsAggregatedStats.StepStats? {
        do { return try await fetchStepStats(start: start, end: end) }
        catch { print("[LoopInsights] HK steps error: \(error)"); return nil }
    }

    private func fetchSleepSafe(start: Date, end: Date) async -> LoopInsightsAggregatedStats.SleepStats? {
        do { return try await fetchSleepStats(start: start, end: end) }
        catch { print("[LoopInsights] HK sleep error: \(error)"); return nil }
    }

    private func fetchEnergySafe(start: Date, end: Date) async -> LoopInsightsAggregatedStats.ActiveEnergyStats? {
        do { return try await fetchActiveEnergyStats(start: start, end: end) }
        catch { print("[LoopInsights] HK active energy error: \(error)"); return nil }
    }

    private func fetchWeightSafe(start: Date, end: Date) async -> LoopInsightsAggregatedStats.WeightStats? {
        do { return try await fetchWeightStats(start: start, end: end) }
        catch { print("[LoopInsights] HK weight error: \(error)"); return nil }
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

        let samples = try await querySamples(type: stepType, start: start, end: end)
        guard !samples.isEmpty else { return nil }

        let calendar = Calendar.current
        let countUnit = HKUnit.count()

        var dailyTotals: [String: Double] = [:]
        var hourlyBuckets: [Int: [Double]] = [:]

        for sample in samples {
            let count = sample.quantity.doubleValue(for: countUnit)
            let dayKey = Self.dayKey(for: sample.startDate, calendar: calendar)
            dailyTotals[dayKey, default: 0] += count

            let hour = calendar.component(.hour, from: sample.startDate)
            hourlyBuckets[hour, default: []].append(count)
        }

        let avgDaily = dailyTotals.isEmpty ? 0 : dailyTotals.values.reduce(0, +) / Double(dailyTotals.count)
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
