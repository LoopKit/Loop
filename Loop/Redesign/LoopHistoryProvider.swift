//
//  LoopHistoryProvider.swift
//  Loop
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Foundation
import HealthKit
import LoopKit
import LoopCore
import LoopAlgorithm
import os

/// Reads glucose, insulin, carbs and loop runs for the redesigned screens.
///
/// Loop keeps `LOOP_LOCAL_CACHE_DURATION_DAYS` (90 by default) days in its own stores. From the start of that window,
/// or from Loop's first record of a kind when that is later, everything comes from those stores, so manual and
/// automatic doses, temp basals and the schedule are known. Earlier days come from Apple Health, which has glucose,
/// carbs and insulin split into basal and bolus, and whether Loop gave a bolus automatically only for the doses Loop
/// wrote, but not the basal schedule.
final class LoopHistoryProvider {

    private let deviceManager: DeviceDataManager
    private let loopDataManager: LoopDataManager
    private let settingsManager: SettingsManager
    private let temporaryPresetsManager: TemporaryPresetsManager
    private let dosingDecisionStore: DosingDecisionStoreProtocol
    private let doseStore: DoseStore
    private let carbStore: CarbStore
    private let glucoseStore: GlucoseStore
    private let healthStore = HKHealthStore()
    private let log = OSLog(category: "LoopHistoryProvider")
    private let recordStartsCache = OSAllocatedUnfairLock<(fetched: Date, starts: LocalRecordStarts)?>(initialState: nil)

    @MainActor
    init(deviceManager: DeviceDataManager, loopDataManager: LoopDataManager, settingsManager: SettingsManager, temporaryPresetsManager: TemporaryPresetsManager) {
        self.deviceManager = deviceManager
        self.loopDataManager = loopDataManager
        self.settingsManager = settingsManager
        self.temporaryPresetsManager = temporaryPresetsManager
        self.dosingDecisionStore = loopDataManager.dosingDecisionStore
        self.doseStore = deviceManager.doseStore
        self.carbStore = deviceManager.carbStore
        self.glucoseStore = deviceManager.glucoseStore
    }

    @MainActor
    var unitStyle: GlucoseUnitStyle {
        GlucoseUnitStyle(unit: deviceManager.displayGlucosePreference.unit)
    }

    /// The start of what Loop keeps locally.
    var localHistoryStart: Date {
        Date().addingTimeInterval(-Bundle.main.localCacheDuration)
    }

    /// How many days Loop keeps in its own stores (`LOOP_LOCAL_CACHE_DURATION_DAYS`).
    var localHistoryDays: Int {
        Int((Bundle.main.localCacheDuration / 86400).rounded())
    }

    @MainActor
    var glucoseTargetRange: ClosedRange<Double>? {
        guard let range = temporaryPresetsManager.effectiveCorrectionRange() else { return nil }
        return range.lowerBound.doubleValue(for: .milligramsPerDeciliter)...range.upperBound.doubleValue(for: .milligramsPerDeciliter)
    }

    /// The median insulin delivered from midnight to this time of day over the last 14 days.
    func typicalInsulinByNow() async -> (typical: TypicalInsulinDelivery, at: Date)? {
        guard let history = try? await loopDataManager.insulinDeliveryHistory(days: 14),
              let typical = history.typicalDelivery(by: history.end) else { return nil }
        return (typical, history.end)
    }

    /// The targets that actually applied, including dated presets and changes to the stored profile.
    func glucoseTargetBands(in interval: DateInterval) async throws -> [TargetBand] {
        if let store = settingsManager.settingsStore {
            let previous = try await store.getStoredSettings(end: interval.start, limit: 1).first
            if previous?.glucoseTargetRangeSchedule == nil {
                let changes = try await store.getStoredSettings(start: interval.start, end: interval.end)
                // LoopKit's historical query requires at least one valid profile, even if settings records exist.
                guard changes.contains(where: { $0.glucoseTargetRangeSchedule != nil }) else { return [] }
            }
        }
        return try await loopDataManager.glucoseTargetBands(in: interval)
    }

    // MARK: - Days

    /// Glucose, insulin and carbs in `window`. Each kind comes from Apple Health before Loop's own records of it
    /// begin, and from Loop's stores after, so a Loop younger than its cache still shows what Health has for the
    /// days before it.
    func dayHistory(_ window: DateInterval) async throws -> DayHistory {
        var history = DayHistory(window: window)
        let starts = try await localRecordStarts()
        let now = Date(), localStart = localHistoryStart
        let boundary = { LoopHistoryMath.healthBoundary(localHistoryStart: localStart, firstLocalRecord: $0, now: now) }
        let glucoseBoundary = boundary(starts.glucose), insulinBoundary = boundary(starts.insulin), carbBoundary = boundary(starts.carbs)
        let glucose = LoopHistoryMath.split(window, at: glucoseBoundary)
        let insulin = LoopHistoryMath.split(window, at: insulinBoundary)
        let carbs = LoopHistoryMath.split(window, at: carbBoundary)

        async let localGlucose = localGlucose(glucose.local)
        async let localInsulin = localInsulin(insulin.local, recordsStart: starts.insulin)
        async let localCarbs = localCarbs(carbs.local)
        async let healthGlucose = healthGlucose(glucose.health)
        async let healthInsulin = healthInsulin(insulin.health)
        async let healthCarbs = healthCarbs(carbs.health)

        let (localBoluses, localBasal, scheduled) = try await localInsulin
        let (healthBoluses, healthBasal) = try await healthInsulin
        history.glucose = try await healthGlucose + localGlucose
        history.boluses = healthBoluses + localBoluses
        history.basal = healthBasal + localBasal
        history.scheduledBasal = scheduled
        history.carbs = try await healthCarbs + localCarbs
        history.localInsulinStart = insulinBoundary
        if window.end <= min(glucoseBoundary, insulinBoundary, carbBoundary) {
            history.source = .health
        }
        try Task.checkCancellation()
        return history
    }

    /// Where Loop's own records of each kind begin, inside its local history; nil for a kind it has none of.
    struct LocalRecordStarts: Equatable {
        var glucose: Date?
        var insulin: Date?
        var carbs: Date?
    }

    /// A found start is kept for a few minutes, so each period doesn't search again. A kind with no records yet is
    /// searched every time, because its first record can arrive at any moment.
    func localRecordStarts() async throws -> LocalRecordStarts {
        let now = Date(), start = localHistoryStart
        let cached = recordStartsCache.withLock { $0 }.flatMap { now.timeIntervalSince($0.fetched) < 300 ? $0 : nil }
        var starts = cached?.starts ?? LocalRecordStarts()
        let glucoseStore = self.glucoseStore, doseStore = self.doseStore
        if starts.glucose == nil {
            starts.glucose = try await Self.firstRecord(from: start, to: now) { chunk in
                try await glucoseStore.getGlucoseSamples(start: chunk.start, end: chunk.end).filter { !$0.isDisplayOnly }.map(\.startDate)
            }
        }
        if starts.insulin == nil {
            starts.insulin = try await Self.firstRecord(from: start, to: now) { chunk in
                try await doseStore.getNormalizedDoseEntries(start: chunk.start, end: chunk.end).map(\.startDate)
            }
        }
        if starts.carbs == nil {
            starts.carbs = try await carbStore.getCarbEntries(start: start, end: now, dateAscending: true, fetchLimit: 1).first?.startDate
        }
        let found = starts
        recordStartsCache.withLock { $0 = (fetched: cached?.fetched ?? now, starts: found) }
        return found
    }

    /// The earliest date `dates` gives from `start` to `end`, read a week at a time so that finding it doesn't load
    /// all of the local history.
    private static func firstRecord(from start: Date, to end: Date, _ dates: (DateInterval) async throws -> [Date]) async throws -> Date? {
        var chunkStart = start
        while chunkStart < end {
            let chunk = DateInterval(start: chunkStart, end: min(end, chunkStart.addingTimeInterval(.days(7))))
            if let first = try await dates(chunk).min() {
                return first
            }
            chunkStart = chunk.end
        }
        return nil
    }

    // MARK: - Loop runs

    /// Loop runs in the local window, oldest first, with when the record of them begins.
    func loopRuns() async throws -> (runs: [LoopHistoryMath.LoopRun], coverageStart: Date?) {
        let start = localHistoryStart
        var runs: [LoopHistoryMath.LoopRun]
        if let store = dosingDecisionStore as? DosingDecisionStore {
            // Decode only the fields a run needs, and only Loop's local window.
            runs = try await store.getDosingDecisions(start: start, end: Date(), as: LoopRunRecord.self)
                .filter { $0.reason == "loop" }
                .map { Self.run(date: $0.date, issues: ($0.errors ?? []).map(\.id)) }
        } else {
            runs = try await anchoredLoopRuns()
        }
        try Task.checkCancellation()
        runs = runs.filter { $0.date >= start }.sorted { $0.date < $1.date }
        return (runs, runs.first?.date)
    }

    private static func run(date: Date, issues: [String]) -> LoopHistoryMath.LoopRun {
        LoopHistoryMath.LoopRun(date: date, succeeded: issues.isEmpty, manualTempBasal: issues.first == "manualTempBasalRunning")
    }

    private struct LoopRunRecord: Decodable {
        struct Issue: Decodable { let id: String }
        let date: Date
        let reason: String
        let errors: [Issue]?
    }

    /// Fetch each snapshot independently: overlapping reloads must not append the same anchored page twice.
    private func anchoredLoopRuns() async throws -> [LoopHistoryMath.LoopRun] {
        var anchor: DosingDecisionStore.QueryAnchor?
        var runs: [LoopHistoryMath.LoopRun] = []
        while true {
            let page: (DosingDecisionStore.QueryAnchor, [StoredDosingDecision]) = try await withCheckedThrowingContinuation { continuation in
                dosingDecisionStore.executeDosingDecisionQuery(fromQueryAnchor: anchor, limit: 1000) { result in
                    switch result {
                    case .success(let anchor, let decisions): continuation.resume(returning: (anchor, decisions))
                    case .failure(let error): continuation.resume(throwing: error)
                    }
                }
            }
            try Task.checkCancellation()
            anchor = page.0
            runs += page.1.filter { $0.reason == "loop" }.map { Self.run(date: $0.date, issues: $0.errors.map(\.id)) }
            if page.1.count < 1000 { break }
        }
        return runs
    }

    /// When closed loop was switched on or off, from the settings Loop stores on every change: the setting in force at
    /// `interval.start`, then each change after it. Empty when Loop has no settings store.
    func loopModeChanges(in interval: DateInterval) async throws -> [LoopHistoryMath.ModeChange] {
        guard let store = settingsManager.settingsStore else { return [] }
        var changes: [LoopHistoryMath.ModeChange] = []
        if let previous = try await store.getStoredSettings(end: interval.start, limit: 1).first {
            changes.append(.init(date: interval.start, closedLoop: previous.dosingEnabled))
        }
        // Newest first from the store; every settings save is a record, so keep only the ones that switch the mode.
        for settings in try await store.getStoredSettings(start: interval.start, end: interval.end).reversed()
            where changes.last?.closedLoop != settings.dosingEnabled {
            changes.append(.init(date: settings.date, closedLoop: settings.dosingEnabled))
        }
        return changes
    }

    /// When manual temp basals ran in `interval`, from Loop's dose records, ended where the pump ended or cancelled
    /// them. Loop shows the loop as open while one runs.
    func manualTempBasals(in interval: DateInterval) async throws -> [DateInterval] {
        try await doseStore.getNormalizedDoseEntries(start: interval.start, end: interval.end)
            .filter { $0.type == .tempBasal && $0.automatic == false && $0.endDate > $0.startDate }
            .map { DateInterval(start: $0.startDate, end: $0.endDate) }
    }

    // MARK: - Loop's stores

    private func localGlucose(_ interval: DateInterval?) async throws -> [GlucosePoint] {
        guard let interval else { return [] }
        do {
            let samples = try await glucoseStore.getGlucoseSamples(start: interval.start, end: interval.end)
            return samples
                .filter { !$0.isDisplayOnly }
                .map { GlucosePoint(date: $0.startDate, mgdl: $0.quantity.doubleValue(for: .milligramsPerDeciliter), userEntered: $0.wasUserEntered) }
        } catch {
            os_log("Glucose fetch failed: %{public}@", log: log, type: .error, String(describing: error))
            throw error
        }
    }

    /// Doses, basal and the schedule for `interval`. `recordsStart` is Loop's earliest local dose: after it,
    /// unrecorded time runs at the pump's programmed rate.
    private func localInsulin(_ interval: DateInterval?, recordsStart: Date?) async throws -> ([BolusEvent], [BasalSegment], [ScheduledBasalPoint]) {
        guard let interval else { return ([], [], []) }
        let doses: [DoseEntry]
        do {
            doses = try await doseStore.getNormalizedDoseEntries(start: interval.start, end: interval.end)
        } catch {
            os_log("Dose fetch failed: %{public}@", log: log, type: .error, String(describing: error))
            throw error
        }

        let boluses = doses.compactMap { BolusEvent(dose: $0, in: interval) }

        let basalHistory = try await loopDataManager.settingsProvider.getBasalHistory(startDate: interval.start, endDate: interval.end)
        let temporaryPresetsManager = self.temporaryPresetsManager
        let overrides = await MainActor.run {
            temporaryPresetsManager.presetHistory.getOverrideHistory(startDate: interval.start, endDate: interval.end)
        }
        // A resolved daily schedule repeats recent presets on every day. Use the stored profile and dated overrides.
        let scheduleValues = overrides.applyBasal(over: basalHistory)
        let schedule = scheduleValues.map { LoopHistoryMath.ScheduleValue(start: $0.startDate, end: $0.endDate, rate: $0.value) }
        let deliveries = doses.compactMap { LoopHistoryMath.BasalDelivery(dose: $0) }
        let now = Date()
        let window = DateInterval(start: interval.start, end: max(interval.start, min(interval.end, now)))
        // As in Loop's insulin totals: after the first record, unrecorded time runs at the pump's programmed rate.
        let programmed = basalHistory.map { LoopHistoryMath.ScheduleValue(start: $0.startDate, end: $0.endDate, rate: $0.value) }
        let basal = window.duration > 0
            ? LoopHistoryMath.basalSegments(window: window, schedule: schedule, deliveries: deliveries,
                                            programmedRates: programmed, recordsStart: recordsStart)
            : []
        let scheduled = schedule.map { ScheduledBasalPoint(start: max($0.start, interval.start), end: min($0.end, interval.end), rate: $0.rate) }
        return (boluses, basal, scheduled)
    }

    private func localCarbs(_ interval: DateInterval?) async throws -> [CarbEvent] {
        guard let interval else { return [] }
        do {
            let entries = try await carbStore.getCarbEntries(start: interval.start, end: interval.end)
            return entries.map { entry in
                CarbEvent(id: entry.syncIdentifier ?? "\(entry.startDate.timeIntervalSince1970)",
                          date: entry.startDate,
                          grams: entry.quantity.doubleValue(for: .gram),
                          absorptionHours: entry.absorptionTime.map { $0 / 3600 },
                          foodType: entry.foodType,
                          createdByLoop: entry.createdByCurrentApp,
                          entry: entry)
            }
        } catch {
            os_log("Carb fetch failed: %{public}@", log: log, type: .error, String(describing: error))
            throw error
        }
    }

    // MARK: - Apple Health

    private func healthSamples(_ type: HKQuantityType, _ interval: DateInterval?, options: HKQueryOptions = .strictStartDate) async throws -> [HKQuantitySample] {
        guard let interval, interval.duration > 0 else { return [] }
        let log = self.log
        return try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: interval.start, end: interval.end, options: options)
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, error in
                if let error {
                    os_log("Health query for %{public}@ failed: %{public}@", log: log, type: .error, type.identifier, String(describing: error))
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: (samples as? [HKQuantitySample]) ?? [])
                }
            }
            healthStore.execute(query)
        }
    }

    /// Several apps can write the same CGM reading to Health; keep one reading per 2½ minutes.
    private func healthGlucose(_ interval: DateInterval?) async throws -> [GlucosePoint] {
        let samples = try await healthSamples(HKQuantityType(.bloodGlucose), interval)
        var points: [GlucosePoint] = []
        let own = HKSource.default().bundleIdentifier
        for sample in samples where !sample.isDisplayOnly
            && (FeatureFlags.observeHealthKitGlucoseSamplesFromOtherApps || sample.sourceRevision.source.bundleIdentifier == own) {
            if let last = points.last, sample.startDate.timeIntervalSince(last.date) < 150 { continue }
            points.append(GlucosePoint(date: sample.startDate, mgdl: sample.quantity.doubleValue(for: .milligramsPerDeciliter),
                                       userEntered: sample.wasUserEntered))
        }
        return points
    }

    private func healthInsulin(_ interval: DateInterval?) async throws -> ([BolusEvent], [BasalSegment]) {
        guard let interval else { return ([], []) }
        let samples = try await healthSamples(HKQuantityType(.insulinDelivery), interval, options: [])
        var boluses: [BolusEvent] = []
        var basal: [BasalSegment] = []
        let own = HKSource.default().bundleIdentifier
        for sample in samples where FeatureFlags.observeHealthKitDoseSamplesFromOtherApps || sample.sourceRevision.source.bundleIdentifier == own {
            let units = sample.quantity.doubleValue(for: .internationalUnit())
            let reason = (sample.metadata?[HKMetadataKeyInsulinDeliveryReason] as? NSNumber)?.intValue
            let automaticFlag = (sample.metadata?["com.loopkit.InsulinKit.MetadataKeyAutomaticallyIssued"] as? NSNumber)?.boolValue
            let automatic = automaticFlag ?? false
            if reason == HKInsulinDeliveryReason.basal.rawValue {
                if let segment = BasalSegment(healthSample: sample, in: interval) {
                    basal.append(segment)
                }
            } else if sample.startDate >= interval.start && sample.startDate < interval.end {
                boluses.append(BolusEvent(id: sample.uuid.uuidString, date: sample.startDate, units: units, automatic: automatic, manuallyEntered: false,
                                          automaticKnown: automaticFlag != nil))
            }
        }
        return (boluses, basal)
    }

    private func healthCarbs(_ interval: DateInterval?) async throws -> [CarbEvent] {
        let samples = try await healthSamples(HKQuantityType(.dietaryCarbohydrates), interval)
        let own = HKSource.default().bundleIdentifier
        return samples
            .filter { FeatureFlags.observeHealthKitCarbSamplesFromOtherApps || $0.sourceRevision.source.bundleIdentifier == own }
            .map { sample in
                CarbEvent(id: sample.uuid.uuidString, date: sample.startDate, grams: sample.quantity.doubleValue(for: .gram()),
                          absorptionHours: nil, foodType: sample.metadata?[HKMetadataKeyFoodType] as? String,
                          createdByLoop: sample.sourceRevision.source.bundleIdentifier == own)
            }
    }
}

// MARK: - Historical targets

extension LoopDataManager {
    /// A historical chart must use the profile and presets from that time, rather than repeat today's targets.
    func glucoseTargetBands(in interval: DateInterval) async throws -> [TargetBand] {
        guard settingsProvider.settings.glucoseTargetRangeSchedule != nil else { return [] }
        let schedule = try await settingsProvider.getTargetRangeHistory(startDate: interval.start, endDate: interval.end)
        var bands = schedule.map {
            TargetBand(start: max($0.startDate, interval.start), end: min($0.endDate, interval.end),
                       range: $0.value.lowerBound.doubleValue(for: .milligramsPerDeciliter)...$0.value.upperBound.doubleValue(for: .milligramsPerDeciliter))
        }
        let overrides = temporaryPresetsManager.presetHistory.getOverrideHistory(startDate: interval.start, endDate: interval.end)
        for override in overrides.sorted(by: { $0.startDate < $1.startDate }) {
            guard let target = override.settings.targetRange,
                  let active = override.activeInterval.intersection(with: interval), active.duration > 0 else { continue }
            bands = bands.flatMap { band -> [TargetBand] in
                var pieces: [TargetBand] = []
                if band.start < active.start {
                    pieces.append(TargetBand(start: band.start, end: min(band.end, active.start), range: band.range))
                }
                if band.end > active.end {
                    pieces.append(TargetBand(start: max(band.start, active.end), end: band.end, range: band.range))
                }
                return pieces
            } + [TargetBand(start: active.start, end: active.end,
                            range: target.lowerBound.doubleValue(for: .milligramsPerDeciliter)...target.upperBound.doubleValue(for: .milligramsPerDeciliter))]
        }
        return bands.filter { $0.end > $0.start }.sorted { $0.start < $1.start }
    }

}
