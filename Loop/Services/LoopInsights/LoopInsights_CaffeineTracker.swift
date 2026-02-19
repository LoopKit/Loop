//
//  LoopInsights_CaffeineTracker.swift
//  Loop
//
//  Concept & design by Taylor Patterson. Coded & tested by Claude Code in February 2026.
//  Copyright (c) 2025-2026 LoopKit Authors. All rights reserved.
//

import Foundation
import HealthKit

/// Tracks caffeine intake with half-life decay model and provides prompt context.
/// Entries are persisted to UserDefaults. Uses a 5.7-hour half-life for caffeine metabolism.
/// Also reads dietary caffeine from HealthKit and merges with manual entries.
final class LoopInsights_CaffeineTracker: ObservableObject {

    static let shared = LoopInsights_CaffeineTracker()

    /// Caffeine half-life in seconds (5.7 hours)
    private static let halfLife: TimeInterval = 5.7 * 3600

    /// UserDefaults key for persisted entries
    private static let storageKey = "LoopInsights_caffeineEntries"

    @Published private(set) var entries: [LoopInsightsCaffeineEntry] = []

    /// HealthKit-sourced entries (not persisted to UserDefaults)
    private var healthKitEntries: [LoopInsightsCaffeineEntry] = []

    /// Reference to HealthKitManager for fetching caffeine data
    var healthKitManager: LoopInsights_HealthKitManager?

    init() {
        loadEntries()
    }

    // MARK: - HealthKit Integration

    /// Fetch caffeine entries from HealthKit and merge with manual entries.
    func syncFromHealthKit() async {
        guard let hkManager = healthKitManager else { return }

        let start = Date().addingTimeInterval(-48 * 3600)
        let end = Date()

        do {
            let hkEntries = try await hkManager.fetchCaffeineEntries(start: start, end: end)
            await MainActor.run {
                self.healthKitEntries = hkEntries
                self.rebuildMergedEntries()
            }
        } catch {
            LoopInsights_FeatureFlags.log.error("Failed to fetch HealthKit caffeine: \(error)")
        }
    }

    /// Merge manual + HealthKit entries, sorted by timestamp descending
    private func rebuildMergedEntries() {
        var manual = loadManualEntries()
        manual.append(contentsOf: healthKitEntries)
        manual.sort { $0.timestamp > $1.timestamp }
        entries = manual
    }

    // MARK: - Public API

    /// Log a caffeine intake
    func logCaffeine(milligrams: Double, source: String, at timestamp: Date = Date()) {
        let entry = LoopInsightsCaffeineEntry(
            timestamp: timestamp,
            milligrams: milligrams,
            source: source
        )
        var manual = loadManualEntries()
        manual.append(entry)
        saveManualEntries(manual)
        rebuildMergedEntries()
    }

    /// Remove an entry (only manual entries can be removed)
    func removeEntry(_ entry: LoopInsightsCaffeineEntry) {
        guard !entry.isFromHealthKit else { return }
        var manual = loadManualEntries()
        manual.removeAll { $0.id == entry.id }
        saveManualEntries(manual)
        rebuildMergedEntries()
    }

    /// Remove all manual entries
    func clearAllEntries() {
        saveManualEntries([])
        rebuildMergedEntries()
    }

    /// Update an existing manual entry
    func updateEntry(id: UUID, milligrams: Double, source: String, timestamp: Date) {
        var manual = loadManualEntries()
        guard let idx = manual.firstIndex(where: { $0.id == id }) else { return }
        manual[idx] = LoopInsightsCaffeineEntry(
            id: id,
            timestamp: timestamp,
            milligrams: milligrams,
            source: source
        )
        saveManualEntries(manual)
        rebuildMergedEntries()
    }

    /// Current caffeine state computed from all entries
    func currentState(at now: Date = Date()) -> LoopInsightsCaffeineState {
        var currentLevel: Double = 0
        var peakToday: Double = 0
        var totalLast24h: Double = 0
        var entriesLast24h = 0
        var lastIntake: Date?

        let twentyFourHoursAgo = now.addingTimeInterval(-24 * 3600)
        let startOfToday = Calendar.current.startOfDay(for: now)

        for entry in entries {
            // Compute remaining caffeine from this entry
            let elapsed = now.timeIntervalSince(entry.timestamp)
            guard elapsed >= 0 else { continue }

            let remaining = entry.milligrams * pow(0.5, elapsed / Self.halfLife)
            if remaining > 0.1 {
                currentLevel += remaining
            }

            // Track 24h stats
            if entry.timestamp >= twentyFourHoursAgo {
                totalLast24h += entry.milligrams
                entriesLast24h += 1
            }

            // Track last intake
            if lastIntake == nil || entry.timestamp > (lastIntake ?? .distantPast) {
                lastIntake = entry.timestamp
            }

            // Track peak today (sum of remaining at time of each entry today)
            if entry.timestamp >= startOfToday {
                var levelAtEntry: Double = 0
                for other in entries where other.timestamp <= entry.timestamp {
                    let otherElapsed = entry.timestamp.timeIntervalSince(other.timestamp)
                    levelAtEntry += other.milligrams * pow(0.5, otherElapsed / Self.halfLife)
                }
                peakToday = max(peakToday, levelAtEntry)
            }
        }

        return LoopInsightsCaffeineState(
            currentLevelMg: currentLevel,
            peakLevelToday: peakToday,
            lastIntakeTime: lastIntake,
            entriesLast24h: entriesLast24h,
            totalMgLast24h: totalLast24h
        )
    }

    // MARK: - Prompt Context

    /// Build prompt context string for AI analysis
    func buildCaffeinePromptContext(at now: Date = Date()) -> String {
        let state = currentState(at: now)
        guard state.entriesLast24h > 0 else { return "" }

        var ctx = "## Caffeine Intake\n"
        ctx += "- Current estimated caffeine level: \(String(format: "%.0f", state.currentLevelMg)) mg\n"
        ctx += "- Total caffeine last 24h: \(String(format: "%.0f", state.totalMgLast24h)) mg (\(state.entriesLast24h) intake(s))\n"
        if let lastTime = state.lastIntakeTime {
            let minutesAgo = Int(now.timeIntervalSince(lastTime) / 60)
            if minutesAgo < 60 {
                ctx += "- Last intake: \(minutesAgo) minutes ago\n"
            } else {
                ctx += "- Last intake: \(minutesAgo / 60)h \(minutesAgo % 60)m ago\n"
            }
        }
        ctx += "- Peak caffeine level today: \(String(format: "%.0f", state.peakLevelToday)) mg\n"

        if state.currentLevelMg > 200 {
            ctx += "** HIGH CAFFEINE: Current level >200mg may significantly affect insulin sensitivity and glucose variability **\n"
        } else if state.currentLevelMg > 100 {
            ctx += "** MODERATE CAFFEINE: May influence glucose response, especially post-meal **\n"
        }

        // List recent entries
        let recentEntries = entries.filter { $0.timestamp >= now.addingTimeInterval(-24 * 3600) }
        if !recentEntries.isEmpty {
            ctx += "- Recent entries: "
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            ctx += recentEntries.prefix(5).map { "\(formatter.string(from: $0.timestamp)) \($0.source) (\(String(format: "%.0f", $0.milligrams))mg)" }.joined(separator: "; ")
            ctx += "\n"
        }

        return ctx
    }

    // MARK: - Persistence

    private func loadEntries() {
        entries = loadManualEntries()
    }

    /// Load manual entries from UserDefaults
    private func loadManualEntries() -> [LoopInsightsCaffeineEntry] {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([LoopInsightsCaffeineEntry].self, from: data) else {
            return []
        }
        let cutoff = Date().addingTimeInterval(-48 * 3600)
        return decoded.filter { $0.timestamp >= cutoff }.sorted { $0.timestamp > $1.timestamp }
    }

    /// Save manual entries to UserDefaults (excludes HealthKit entries)
    private func saveManualEntries(_ manual: [LoopInsightsCaffeineEntry]) {
        let cutoff = Date().addingTimeInterval(-48 * 3600)
        let pruned = manual.filter { !$0.isFromHealthKit && $0.timestamp >= cutoff }
        if let data = try? JSONEncoder().encode(pruned) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}
