//
//  BiometricsService.swift
//  Loop
//

import Foundation
import HealthKit
import Combine

struct BiometricSnapshot: Equatable {
    let sleepHours: Double?
    let stepCount: Double?
    let hrvSDNN: Double?
    let exerciseMinutes: Double?
    let heartRate: Double?
    let sampledAt: Date
}

enum BiometricsAuthorizationStatus: Equatable {
    case notDetermined
    case authorized
    case denied
    case restricted
}

protocol BiometricsServiceProtocol: AnyObject {
    var snapshotPublisher: AnyPublisher<BiometricSnapshot, Never> { get }
    var authorizationStatus: BiometricsAuthorizationStatus { get }
    func requestAuthorization() async throws
    func startPolling(interval: TimeInterval)
    func stopPolling()
    func fetchSnapshot() async -> BiometricSnapshot
}

final class BiometricsService: BiometricsServiceProtocol {

    private let healthStore: HKHealthStore
    private let irService: AppleHealthIRServiceProtocol
    private let snapshotSubject: CurrentValueSubject<BiometricSnapshot, Never>
    private var pollingTimer: AnyCancellable?
    private(set) var authorizationStatus: BiometricsAuthorizationStatus = .notDetermined

    var snapshotPublisher: AnyPublisher<BiometricSnapshot, Never> {
        snapshotSubject.eraseToAnyPublisher()
    }

    private static let readTypes: Set<HKSampleType> = [
        HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
        HKObjectType.quantityType(forIdentifier: .stepCount)!,
        HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!,
        HKObjectType.quantityType(forIdentifier: .appleExerciseTime)!,
        HKObjectType.quantityType(forIdentifier: .heartRate)!,
    ]

    init(healthStore: HKHealthStore = HKHealthStore(), irService: AppleHealthIRServiceProtocol) {
        self.healthStore = healthStore
        self.irService = irService
        self.snapshotSubject = CurrentValueSubject(
            BiometricSnapshot(sleepHours: nil, stepCount: nil, hrvSDNN: nil,
                              exerciseMinutes: nil, heartRate: nil, sampledAt: Date())
        )
    }

    func requestAuthorization() async throws {
        try await healthStore.requestAuthorization(toShare: [], read: Self.readTypes)
        authorizationStatus = .authorized
    }

    func startPolling(interval: TimeInterval = 900) {
        fetchAndUpdate()
        pollingTimer = Timer.publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.fetchAndUpdate() }
    }

    func stopPolling() {
        pollingTimer?.cancel()
        pollingTimer = nil
    }

    func fetchSnapshot() async -> BiometricSnapshot {
        let anchor = Date().addingTimeInterval(-86400)
        async let sleep = querySleep(anchor: anchor)
        async let steps = querySteps(anchor: anchor)
        async let hrv = queryHRV(anchor: anchor)
        async let exercise = queryExercise(anchor: anchor)
        async let hr = queryHeartRate(anchor: anchor)
        return BiometricSnapshot(
            sleepHours: await sleep,
            stepCount: await steps,
            hrvSDNN: await hrv,
            exerciseMinutes: await exercise,
            heartRate: await hr,
            sampledAt: Date()
        )
    }

    // MARK: - Private

    private func fetchAndUpdate() {
        Task { [weak self] in
            guard let self = self else { return }
            let snapshot = await self.fetchSnapshot()
            self.snapshotSubject.send(snapshot)
            self.irService.updateBiometrics(
                sleepHours: snapshot.sleepHours,
                stepCount: snapshot.stepCount,
                hrvSDNN: snapshot.hrvSDNN,
                exerciseMinutes: snapshot.exerciseMinutes,
                heartRate: snapshot.heartRate
            )
        }
    }

    private func querySleep(anchor: Date) async -> Double? {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: anchor, end: Date(), options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, _ in
                guard let samples = samples as? [HKCategorySample], !samples.isEmpty else {
                    continuation.resume(returning: nil)
                    return
                }
                // Exclude .inBed — it includes wakefulness; only count confirmed asleep stages
                let asleepValues: Set<Int>
                if #available(iOS 16, *) {
                    asleepValues = [
                        HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                        HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                        HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                        HKCategoryValueSleepAnalysis.asleepREM.rawValue,
                    ]
                } else {
                    asleepValues = [HKCategoryValueSleepAnalysis.asleep.rawValue]
                }
                let totalSeconds = samples
                    .filter { asleepValues.contains($0.value) }
                    .reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
                let hours = totalSeconds / 3600.0
                continuation.resume(returning: hours > 0 ? hours : nil)
            }
            healthStore.execute(query)
        }
    }

    private func querySteps(anchor: Date) async -> Double? {
        guard let stepsType = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: anchor, end: Date(), options: .strictStartDate)
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: stepsType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, _ in
                continuation.resume(returning: stats?.sumQuantity()?.doubleValue(for: .count()))
            }
            healthStore.execute(query)
        }
    }

    private func queryHRV(anchor: Date) async -> Double? {
        guard let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: anchor, end: Date(), options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: hrvType, predicate: predicate, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                guard let sample = (samples as? [HKQuantitySample])?.first else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: sample.quantity.doubleValue(for: HKUnit.secondUnit(with: .milli)))
            }
            healthStore.execute(query)
        }
    }

    private func queryExercise(anchor: Date) async -> Double? {
        guard let exerciseType = HKQuantityType.quantityType(forIdentifier: .appleExerciseTime) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: anchor, end: Date(), options: .strictStartDate)
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: exerciseType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, _ in
                continuation.resume(returning: stats?.sumQuantity()?.doubleValue(for: .minute()))
            }
            healthStore.execute(query)
        }
    }

    private func queryHeartRate(anchor: Date) async -> Double? {
        guard let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: anchor, end: Date(), options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: hrType, predicate: predicate, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                guard let sample = (samples as? [HKQuantitySample])?.first else {
                    continuation.resume(returning: nil)
                    return
                }
                let beatsPerMin = HKUnit.count().unitDivided(by: .minute())
                continuation.resume(returning: sample.quantity.doubleValue(for: beatsPerMin))
            }
            healthStore.execute(query)
        }
    }
}
