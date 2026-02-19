//
//  FoodFinder_AnalysisHistoryStore.swift
//  Loop
//
//  FoodFinder — Persistence and cleanup for AI analysis history records.
//
//  Idea by Taylor Patterson. Coded by Claude Code.
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Foundation

// MARK: - LoopInsights Notification
//
// Posted every time FoodFinder records a meal analysis. LoopInsights (or any
// future feature) can observe this to correlate meal events with BG data in
// real-time, without importing any FoodFinder view code.
//
// userInfo keys:
//   "recordID" — String, the FoodFinder_AnalysisRecord.id that was just saved.

extension Notification.Name {
    static let foodFinderMealLogged = Notification.Name("com.loopkit.Loop.foodFinderMealLogged")
}

// MARK: - MealDataProvider Protocol
//
// Clean query interface for LoopInsights to access FoodFinder meal history.
// FoodFinder_AnalysisHistoryStore conforms below so LoopInsights never needs
// to know about UserDefaults keys, pruning logic, or storage format.
//
// Key fields for LoopInsights tuning recommendations:
//   • originalAICarbs vs carbsGrams  → reveals systematic AI over/under-estimation
//   • aiConfidencePercent            → low-confidence meals can be weighted differently
//   • absorptionTime + foodType      → patterns in absorption accuracy by food category
//   • date                           → time-of-day and day-of-week trend analysis

protocol MealDataProvider {
    static func meals(from startDate: Date, to endDate: Date) -> [FoodFinder_AnalysisRecord]
}

enum FoodFinder_AnalysisHistoryStore {

    // MARK: - Record

    /// Append a new analysis record to the stored history.
    /// Also archives the record permanently for long-term LoopInsights analysis.
    static func record(_ record: FoodFinder_AnalysisRecord) {
        var records = allRecords()
        records.append(record)
        save(records)
        MealArchive.archive(record)
        #if DEBUG
        print("FoodFinder: Recorded analysis history — total: \(records.count)")
        #endif
    }

    // MARK: - Load (filtered by retention)

    /// Returns records that fall within the retention window.
    static func loadRecords(retentionDays: Int) -> [FoodFinder_AnalysisRecord] {
        let cutoff = Date().addingTimeInterval(-Double(retentionDays) * 86400)
        return allRecords()
            .filter { $0.date >= cutoff }
            .sorted { $0.date > $1.date }
    }

    // MARK: - Prune Expired

    /// Remove records older than the retention window and delete orphaned thumbnails.
    static func pruneExpired(retentionDays: Int) {
        let cutoff = Date().addingTimeInterval(-Double(retentionDays) * 86400)
        let all = allRecords()
        let (keep, expired) = all.reduce(into: ([FoodFinder_AnalysisRecord](), [FoodFinder_AnalysisRecord]())) { result, record in
            if record.date >= cutoff {
                result.0.append(record)
            } else {
                result.1.append(record)
            }
        }

        // Delete thumbnails for expired records
        for record in expired {
            if let thumbID = record.thumbnailID {
                FavoriteFoodImageStore.deleteThumbnail(id: thumbID)
            }
        }

        if expired.count > 0 {
            save(keep)
            #if DEBUG
            print("FoodFinder: Pruned \(expired.count) expired analysis records, \(keep.count) remain")
            #endif
        }
    }

    // MARK: - Private Helpers

    private static let key = FoodFinder_FeatureFlags.Keys.analysisHistory

    private static func allRecords() -> [FoodFinder_AnalysisRecord] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([FoodFinder_AnalysisRecord].self, from: data)) ?? []
    }

    private static func save(_ records: [FoodFinder_AnalysisRecord]) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

// MARK: - MealDataProvider Conformance
//
// Gives LoopInsights a clean way to query meal history by date range
// without knowing anything about FoodFinder's storage internals.

extension FoodFinder_AnalysisHistoryStore: MealDataProvider {
    static func meals(from startDate: Date, to endDate: Date) -> [FoodFinder_AnalysisRecord] {
        allRecords()
            .filter { $0.date >= startDate && $0.date <= endDate }
            .sorted { $0.date > $1.date }
    }
}

// MARK: - Long-Term Meal Archive
//
// Permanent archive of all meal analysis records for LoopInsights data mining.
// Unlike the 7-day analysis history (UserDefaults), this archive persists
// indefinitely as a JSON file on disk. Used for:
//   • Long-term AI carb estimation accuracy tracking
//   • Nutritional glucose response correlation (high-fat vs low-fat, etc.)
//   • Food pattern trend analysis across months
//   • Data mining for personalized meal insights

enum MealArchive {

    private static let filename = "FoodFinder_MealArchive.json"

    private static var archiveURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let dir = appSupport.appendingPathComponent("LoopInsights")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(filename)
    }

    /// Archive a single record (append to the JSON file on disk).
    /// Deduplicates by ID to avoid storing the same meal twice.
    static func archive(_ record: FoodFinder_AnalysisRecord) {
        var existing = loadAll()
        guard !existing.contains(where: { $0.id == record.id }) else { return }
        existing.append(record)
        saveAll(existing)
    }

    /// Load all archived records within a date range.
    static func meals(from startDate: Date, to endDate: Date) -> [FoodFinder_AnalysisRecord] {
        loadAll()
            .filter { $0.date >= startDate && $0.date <= endDate }
            .sorted { $0.date > $1.date }
    }

    /// Load the complete archive (all time).
    static func loadAll() -> [FoodFinder_AnalysisRecord] {
        guard FileManager.default.fileExists(atPath: archiveURL.path) else { return [] }
        guard let data = try? Data(contentsOf: archiveURL) else { return [] }
        return (try? JSONDecoder().decode([FoodFinder_AnalysisRecord].self, from: data)) ?? []
    }

    /// Total archived meal count.
    static var count: Int { loadAll().count }

    private static func saveAll(_ records: [FoodFinder_AnalysisRecord]) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: archiveURL, options: .atomic)
    }
}
