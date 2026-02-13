//
//  LoopInsights_Coordinator.swift
//  Loop
//
//  Concept & design by Taylor Patterson. Coded & tested by Claude Code in February 2026.
//  Copyright (c) 2025-2026 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit
import LoopCore
import HealthKit

/// Closure type for writing therapy settings changes back to Loop.
/// Accepts a mutation block that modifies LoopSettings in place.
typealias LoopInsightsSettingsWriter = ((_ mutate: (inout LoopSettings) -> Void) -> Void)

/// Orchestrates all LoopInsights services and manages the feature lifecycle.
/// Created when LoopInsights is accessed from Settings. Owns the DataAggregator,
/// SuggestionStore, and AIAnalysis service, and provides the data access bridge
/// between Loop's stores and LoopInsights' analysis engine.
final class LoopInsights_Coordinator: ObservableObject {

    // MARK: - Services

    let dataAggregator: LoopInsights_DataAggregator
    let aiAnalysis: LoopInsights_AIAnalysis
    let suggestionStore: LoopInsights_SuggestionStore
    let goalStore: LoopInsights_GoalStore

    /// Background monitor for proactive suggestions (lazy-initialized)
    lazy var backgroundMonitor: LoopInsights_BackgroundMonitor = LoopInsights_BackgroundMonitor(coordinator: self)

    // MARK: - Data Provider Bridge

    private var dataProviderBridge: DataProviderBridge?

    /// Retained reference to test data provider (when using fixtures).
    private var testDataProvider: LoopInsights_TestDataProvider?

    /// Closure to write therapy settings back to Loop via LoopDataManager.mutateSettings
    var settingsWriter: LoopInsightsSettingsWriter?

    // MARK: - Initialization

    /// Initialize with Loop's existing store references.
    /// The coordinator only reads from these stores — it never writes glucose, dose, or carb data.
    init(
        glucoseStore: GlucoseStoreProtocol,
        doseStore: DoseStoreProtocol,
        carbStore: CarbStoreProtocol,
        settingsProvider: LatestStoredSettingsProvider,
        settingsWriter: LoopInsightsSettingsWriter? = nil
    ) {
        let bridge = DataProviderBridge(
            glucoseStore: glucoseStore,
            doseStore: doseStore,
            carbStore: carbStore,
            settingsProvider: settingsProvider
        )
        self.dataProviderBridge = bridge
        self.settingsWriter = settingsWriter
        self.dataAggregator = LoopInsights_DataAggregator(dataProvider: bridge)
        self.aiAnalysis = LoopInsights_AIAnalysis()
        self.suggestionStore = LoopInsights_SuggestionStore.shared
        self.goalStore = LoopInsights_GoalStore.shared
    }

    /// Initialize with test data fixtures (for simulator/developer mode).
    /// Loads JSON fixtures from Documents/LoopInsights/ or the app bundle.
    init(testDataProvider: LoopInsights_TestDataProvider) {
        self.testDataProvider = testDataProvider
        self.dataProviderBridge = nil
        self.settingsWriter = nil
        self.dataAggregator = LoopInsights_DataAggregator(dataProvider: testDataProvider)
        self.aiAnalysis = LoopInsights_AIAnalysis()
        self.suggestionStore = LoopInsights_SuggestionStore.shared
        self.goalStore = LoopInsights_GoalStore.shared
    }

    /// Factory method: creates a Coordinator with test data if available and enabled,
    /// otherwise returns nil (caller should fall back to real stores).
    static func withTestDataIfAvailable() -> LoopInsights_Coordinator? {
        guard LoopInsights_FeatureFlags.useTestData else { return nil }

        let provider = LoopInsights_TestDataProvider()
        guard provider.hasTestData else {
            print("[LoopInsights] Test data mode enabled but no fixtures found")
            return nil
        }

        print("[LoopInsights] Using test data: \(provider.dataSummary)")
        return LoopInsights_Coordinator(testDataProvider: provider)
    }

    // MARK: - Background Monitoring

    /// Start background monitoring if enabled and using real stores (not test data).
    func startBackgroundMonitoring() {
        guard dataProviderBridge != nil else {
            print("[LoopInsights] Skipping background monitor — test data mode")
            return
        }
        backgroundMonitor.start()
    }

    /// Stop background monitoring.
    func stopBackgroundMonitoring() {
        backgroundMonitor.stop()
    }

    // MARK: - Therapy Settings Write Access

    /// Capture a snapshot of the current therapy settings
    func captureCurrentSnapshot() throws -> LoopInsightsTherapySnapshot {
        return try dataAggregator.captureTherapySnapshot()
    }

    /// Apply a suggestion's time block changes to the actual therapy settings.
    /// Returns true if the write succeeded.
    @discardableResult
    func applyTherapyChanges(suggestion: LoopInsightsSuggestion) -> Bool {
        guard let writer = settingsWriter else {
            print("[LoopInsights] Cannot apply: no settings writer available (test data mode?)")
            return false
        }

        let blocks = suggestion.timeBlocks
        guard !blocks.isEmpty else { return false }

        writer { settings in
            switch suggestion.settingType {
            case .carbRatio:
                guard let schedule = settings.carbRatioSchedule else { return }
                let updatedItems = Self.applyBlockChanges(blocks, to: schedule.items)
                if let newSchedule = CarbRatioSchedule(unit: schedule.unit, dailyItems: updatedItems, timeZone: schedule.timeZone) {
                    settings.carbRatioSchedule = newSchedule
                }

            case .insulinSensitivity:
                guard let schedule = settings.insulinSensitivitySchedule else { return }
                let updatedItems = Self.applyBlockChanges(blocks, to: schedule.items)
                if let newSchedule = InsulinSensitivitySchedule(unit: schedule.unit, dailyItems: updatedItems, timeZone: schedule.timeZone) {
                    settings.insulinSensitivitySchedule = newSchedule
                }

            case .basalRate:
                guard let schedule = settings.basalRateSchedule else { return }
                let updatedItems = Self.applyBlockChanges(blocks, to: schedule.items)
                if let newSchedule = BasalRateSchedule(dailyItems: updatedItems, timeZone: schedule.timeZone) {
                    settings.basalRateSchedule = newSchedule
                }
            }
        }

        print("[LoopInsights] Applied \(suggestion.settingType.displayName) changes: \(blocks.count) time block(s)")
        return true
    }

    /// Revert therapy settings to a previously captured snapshot.
    /// Restores all three schedule types (CR, ISF, Basal) from the snapshot.
    /// Returns true if the write succeeded.
    @discardableResult
    func revertToSnapshot(_ snapshot: LoopInsightsTherapySnapshot) -> Bool {
        guard let writer = settingsWriter else {
            print("[LoopInsights] Cannot revert: no settings writer available")
            return false
        }

        writer { settings in
            // Restore carb ratio schedule
            if !snapshot.carbRatioItems.isEmpty,
               let existingSchedule = settings.carbRatioSchedule {
                let items = snapshot.carbRatioItems.map {
                    RepeatingScheduleValue(startTime: $0.startTime, value: $0.value)
                }
                if let restored = CarbRatioSchedule(unit: existingSchedule.unit, dailyItems: items, timeZone: existingSchedule.timeZone) {
                    settings.carbRatioSchedule = restored
                }
            }

            // Restore insulin sensitivity schedule
            if !snapshot.insulinSensitivityItems.isEmpty,
               let existingSchedule = settings.insulinSensitivitySchedule {
                let items = snapshot.insulinSensitivityItems.map {
                    RepeatingScheduleValue(startTime: $0.startTime, value: $0.value)
                }
                if let restored = InsulinSensitivitySchedule(unit: existingSchedule.unit, dailyItems: items, timeZone: existingSchedule.timeZone) {
                    settings.insulinSensitivitySchedule = restored
                }
            }

            // Restore basal rate schedule
            if !snapshot.basalRateItems.isEmpty,
               let existingSchedule = settings.basalRateSchedule {
                let items = snapshot.basalRateItems.map {
                    RepeatingScheduleValue(startTime: $0.startTime, value: $0.value)
                }
                if let restored = BasalRateSchedule(dailyItems: items, timeZone: existingSchedule.timeZone) {
                    settings.basalRateSchedule = restored
                }
            }
        }

        print("[LoopInsights] Reverted settings to previous snapshot")
        return true
    }

    /// Match time blocks to schedule items and apply proposed values.
    /// If no existing entry matches a block's start time, inserts new entries
    /// to split the schedule at the suggested time boundaries.
    private static func applyBlockChanges(
        _ blocks: [LoopInsightsTimeBlock],
        to items: [RepeatingScheduleValue<Double>]
    ) -> [RepeatingScheduleValue<Double>] {
        var updated = items

        for block in blocks {
            // Try to find an existing entry matching this block's start time
            let matchIndex = updated.firstIndex(where: { abs($0.startTime - block.startTime) < 60 })

            if let idx = matchIndex {
                // Exact match — update the value
                updated[idx] = RepeatingScheduleValue(startTime: updated[idx].startTime, value: block.proposedValue)
            } else {
                // No matching entry — insert a new entry at the block's start time
                // with the proposed value, and another at the block's end time to
                // restore the original value for the remainder of the period.
                let originalValue = valueAt(time: block.startTime, in: updated)

                updated.append(RepeatingScheduleValue(startTime: block.startTime, value: block.proposedValue))

                // Only insert an end-time entry if it doesn't already exist
                // and the block doesn't extend to end-of-day
                let endAlreadyExists = updated.contains(where: { abs($0.startTime - block.endTime) < 60 })
                let endOfDay: TimeInterval = 24 * 3600
                if !endAlreadyExists && block.endTime < endOfDay {
                    updated.append(RepeatingScheduleValue(startTime: block.endTime, value: originalValue))
                }
            }
        }

        // Sort by start time to maintain schedule order
        updated.sort { $0.startTime < $1.startTime }
        return updated
    }

    /// Find the effective value at a given time in a sorted schedule.
    /// Returns the value of the last entry whose startTime <= the given time.
    private static func valueAt(time: TimeInterval, in items: [RepeatingScheduleValue<Double>]) -> Double {
        let sorted = items.sorted { $0.startTime < $1.startTime }
        var result = sorted.first?.value ?? 0
        for item in sorted {
            if item.startTime <= time {
                result = item.value
            } else {
                break
            }
        }
        return result
    }
}

// MARK: - Data Provider Bridge

/// Bridges Loop's concrete store types to the LoopInsightsDataProviderProtocol.
/// This keeps LoopInsights decoupled from the specific store implementations.
private final class DataProviderBridge: LoopInsightsDataProviderProtocol {

    private let glucoseStore: GlucoseStoreProtocol
    private let doseStore: DoseStoreProtocol
    private let carbStore: CarbStoreProtocol
    fileprivate let settingsProvider: LatestStoredSettingsProvider

    init(
        glucoseStore: GlucoseStoreProtocol,
        doseStore: DoseStoreProtocol,
        carbStore: CarbStoreProtocol,
        settingsProvider: LatestStoredSettingsProvider
    ) {
        self.glucoseStore = glucoseStore
        self.doseStore = doseStore
        self.carbStore = carbStore
        self.settingsProvider = settingsProvider
    }

    func getGlucoseSamples(start: Date, end: Date) async throws -> [StoredGlucoseSample] {
        return try await withCheckedThrowingContinuation { continuation in
            glucoseStore.getGlucoseSamples(start: start, end: end) { result in
                continuation.resume(with: result)
            }
        }
    }

    func getCarbEntries(start: Date, end: Date) async throws -> [StoredCarbEntry] {
        // CarbStoreProtocol doesn't expose getCarbEntries; cast to concrete CarbStore
        guard let store = carbStore as? CarbStore else {
            throw LoopInsightsError.insufficientData("CarbStore not available")
        }
        return try await withCheckedThrowingContinuation { continuation in
            store.getCarbEntries(start: start, end: end) { result in
                switch result {
                case .success(let entries):
                    continuation.resume(returning: entries)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func getNormalizedDoseEntries(start: Date, end: Date) async throws -> [DoseEntry] {
        return try await withCheckedThrowingContinuation { continuation in
            doseStore.getNormalizedDoseEntries(start: start, end: end) { result in
                switch result {
                case .success(let entries):
                    continuation.resume(returning: entries)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func getLatestStoredSettings() -> StoredSettings {
        return settingsProvider.latestSettings
    }
}
