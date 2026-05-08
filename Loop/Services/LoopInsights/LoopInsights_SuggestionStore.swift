//
//  LoopInsights_SuggestionStore.swift
//  Loop
//
//  Concept & design by Taylor Patterson. Coded & tested by Claude Code in February 2026.
//  Copyright (c) 2025-2026 LoopKit Authors. All rights reserved.
//

import Foundation

// MARK: - DataLayer Notification
//
// Posted when an AI suggestion lifecycle event occurs. DataLayer_Coordinator
// observes this to record events without direct coupling between modules.
//
// userInfo keys:
//   "action"            — String: "generated", "applied", "dismissed", "reverted"
//   "settingType"       — String (LoopInsightsSettingType.rawValue)
//   "timeBlockCount"    — Int
//   "confidenceLevel"   — String (LoopInsightsConfidence.rawValue)
//   "applyMode"         — String? (LoopInsightsApplyMode.rawValue, only for "applied")
//   "analysisPeriodDays" — Int

extension Notification.Name {
    static let loopInsightsSuggestionEvent = Notification.Name("com.loopkit.Loop.loopInsightsSuggestionEvent")
}

/// Persists suggestion history to UserDefaults as JSON.
/// All suggestions (pending, applied, dismissed, auto-applied) are stored here
/// so users can review their full history of AI recommendations.
final class LoopInsights_SuggestionStore: ObservableObject {

    static let shared = LoopInsights_SuggestionStore()

    private static let storageKey = "LoopInsights_SuggestionHistory"
    private let defaults = UserDefaults.standard
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    @Published private(set) var records: [LoopInsightsSuggestionRecord] = []

    private init() {
        loadRecords()
    }

    // MARK: - Read

    /// All records sorted by creation date (newest first)
    var allRecords: [LoopInsightsSuggestionRecord] {
        return records.sorted { $0.createdAt > $1.createdAt }
    }

    /// Only pending (unresolved) records
    var pendingRecords: [LoopInsightsSuggestionRecord] {
        return records.filter { $0.status == .pending }.sorted { $0.createdAt > $1.createdAt }
    }

    /// Only resolved records (applied, dismissed, auto-applied)
    var resolvedRecords: [LoopInsightsSuggestionRecord] {
        return records.filter { $0.status.isResolved }.sorted { $0.createdAt > $1.createdAt }
    }

    /// Find a record by ID
    func record(withID id: UUID) -> LoopInsightsSuggestionRecord? {
        return records.first { $0.id == id }
    }

    // MARK: - Write

    /// Add a new suggestion as a pending record
    func addSuggestion(_ suggestion: LoopInsightsSuggestion) -> LoopInsightsSuggestionRecord {
        let record = LoopInsightsSuggestionRecord(suggestion: suggestion)
        records.append(record)
        saveRecords()

        // Notify DataLayer (separate module — uses notification decoupling)
        postSuggestionNotification(action: "generated", suggestion: suggestion, applyMode: nil)

        return record
    }

    /// Add multiple suggestions as pending records
    func addSuggestions(_ suggestions: [LoopInsightsSuggestion]) -> [LoopInsightsSuggestionRecord] {
        let newRecords = suggestions.map { LoopInsightsSuggestionRecord(suggestion: $0) }
        records.append(contentsOf: newRecords)
        saveRecords()
        return newRecords
    }

    /// Mark a record as applied
    func markApplied(recordID: UUID, mode: LoopInsightsApplyMode, snapshotBefore: LoopInsightsTherapySnapshot?, snapshotAfter: LoopInsightsTherapySnapshot?, glucoseStats: LoopInsightsGlucoseStatsSnapshot? = nil) {
        guard let index = records.firstIndex(where: { $0.id == recordID }) else { return }
        records[index].markApplied(mode: mode, snapshotBefore: snapshotBefore, snapshotAfter: snapshotAfter, glucoseStats: glucoseStats)
        saveRecords()

        // Notify DataLayer
        postSuggestionNotification(action: "applied", suggestion: records[index].suggestion, applyMode: mode.rawValue)
    }

    /// Mark a record as dismissed
    func markDismissed(recordID: UUID) {
        guard let index = records.firstIndex(where: { $0.id == recordID }) else { return }
        records[index].markDismissed()
        saveRecords()

        // Notify DataLayer
        postSuggestionNotification(action: "dismissed", suggestion: records[index].suggestion, applyMode: nil)
    }

    /// Set the outcome evaluation for an applied suggestion
    func setOutcomeEvaluation(recordID: UUID, evaluation: LoopInsightsOutcomeEvaluation) {
        guard let index = records.firstIndex(where: { $0.id == recordID }) else { return }
        records[index].outcomeEvaluation = evaluation
        saveRecords()
    }

    /// Mark a record as reverted (settings restored to pre-apply state)
    func markReverted(recordID: UUID) {
        guard let index = records.firstIndex(where: { $0.id == recordID }) else { return }
        records[index].markReverted()
        saveRecords()

        // Notify DataLayer
        postSuggestionNotification(action: "reverted", suggestion: records[index].suggestion, applyMode: nil)
    }

    /// Dismiss all pending records
    func dismissAllPending() {
        for index in records.indices where records[index].status == .pending {
            records[index].markDismissed()
        }
        saveRecords()
    }

    /// Delete a specific record
    func deleteRecord(withID id: UUID) {
        records.removeAll { $0.id == id }
        saveRecords()
    }

    /// Clear all history
    func clearAllHistory() {
        records.removeAll()
        saveRecords()
    }

    // MARK: - Persistence

    private func loadRecords() {
        guard let data = defaults.data(forKey: Self.storageKey) else {
            records = []
            return
        }

        do {
            records = try decoder.decode([LoopInsightsSuggestionRecord].self, from: data)
        } catch {
            LoopInsights_FeatureFlags.log.error("Failed to decode suggestion history: \(error)")
            records = []
        }
    }

    private func saveRecords() {
        do {
            let data = try encoder.encode(records)
            defaults.set(data, forKey: Self.storageKey)
        } catch {
            LoopInsights_FeatureFlags.log.error("Failed to encode suggestion history: \(error)")
        }
    }

    // MARK: - DataLayer Notification Helper

    private func postSuggestionNotification(action: String, suggestion: LoopInsightsSuggestion, applyMode: String?) {
        var userInfo: [String: Any] = [
            "action": action,
            "settingType": suggestion.settingType.rawValue,
            "timeBlockCount": suggestion.timeBlocks.count,
            "confidenceLevel": suggestion.confidence.rawValue,
            "analysisPeriodDays": LoopInsights_FeatureFlags.analysisPeriod.rawValue
        ]
        if let mode = applyMode {
            userInfo["applyMode"] = mode
        }
        NotificationCenter.default.post(
            name: .loopInsightsSuggestionEvent,
            object: nil,
            userInfo: userInfo
        )
    }
}
