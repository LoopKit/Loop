//
//  LoopInsights_SuggestionStore.swift
//  Loop
//
//  Concept & design by Taylor Patterson. Coded & tested by Claude Code in February 2026.
//  Copyright (c) 2025-2026 LoopKit Authors. All rights reserved.
//

import Foundation

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
    func markApplied(recordID: UUID, mode: LoopInsightsApplyMode, snapshotBefore: LoopInsightsTherapySnapshot?, snapshotAfter: LoopInsightsTherapySnapshot?) {
        guard let index = records.firstIndex(where: { $0.id == recordID }) else { return }
        records[index].markApplied(mode: mode, snapshotBefore: snapshotBefore, snapshotAfter: snapshotAfter)
        saveRecords()
    }

    /// Mark a record as dismissed
    func markDismissed(recordID: UUID) {
        guard let index = records.firstIndex(where: { $0.id == recordID }) else { return }
        records[index].markDismissed()
        saveRecords()
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
            print("[LoopInsights] Failed to decode suggestion history: \(error)")
            records = []
        }
    }

    private func saveRecords() {
        do {
            let data = try encoder.encode(records)
            defaults.set(data, forKey: Self.storageKey)
        } catch {
            print("[LoopInsights] Failed to encode suggestion history: \(error)")
        }
    }
}
