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
    static let foodFinderMealAnalyzed = Notification.Name("com.loopkit.Loop.foodFinderMealAnalyzed")
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

    /// Append a new analysis record to the short-term analysis history (for re-entry).
    /// Does NOT archive to MealArchive — call `confirmMeal()` for that after the
    /// user commits to eating by continuing to the bolus screen.
    static func record(_ record: FoodFinder_AnalysisRecord) {
        var records = allRecords()
        // Replace existing record with the same name to avoid duplicates
        records.removeAll { $0.name == record.name }
        records.append(record)
        save(records)
        pendingRecord = record
        #if DEBUG
        print("FoodFinder: Recorded analysis history — total: \(records.count)")
        #endif

        // Notify DataLayer (separate module — uses notification decoupling)
        var mealInfo: [String: Any] = [
            "analysisType": record.analysisType.rawValue,
            "foodName": record.name,
            "carbsGrams": record.carbsGrams,
            "absorptionTimeHours": record.absorptionTime / 3600,
            "itemCount": record.analysisResult?.totalFoodPortions ?? 1
        ]
        if let v = record.originalAICarbs { mealInfo["originalAICarbs"] = v }
        if let v = record.aiConfidencePercent { mealInfo["aiConfidencePercent"] = v }
        if let v = record.analysisResult?.totalProtein { mealInfo["proteinGrams"] = v }
        if let v = record.analysisResult?.totalFat { mealInfo["fatGrams"] = v }
        if let v = record.analysisResult?.totalFiber { mealInfo["fiberGrams"] = v }
        if let v = record.analysisResult?.totalCalories { mealInfo["calories"] = v }
        if let v = record.locationName { mealInfo["locationName"] = v }
        NotificationCenter.default.post(name: .foodFinderMealAnalyzed, object: nil, userInfo: mealInfo)
    }

    // MARK: - Meal Confirmation

    /// The most recently analyzed record, waiting for user to confirm the meal.
    static var pendingRecord: FoodFinder_AnalysisRecord?

    /// Called when the user confirms they are eating (continues to bolus).
    /// Archives the pending record to MealArchive and posts the notification.
    static func confirmMeal() {
        guard let record = pendingRecord else { return }
        pendingRecord = nil
        MealArchive.archive(record)
        NotificationCenter.default.post(
            name: .foodFinderMealLogged,
            object: nil,
            userInfo: ["recordID": record.id]
        )
        #if DEBUG
        print("FoodFinder: Confirmed meal → archived to MealArchive: \(record.name)")
        #endif

        // Notify DataLayer for meal confirmation (piggybacks on existing .foodFinderMealLogged)
        // DataLayer_Coordinator observes .foodFinderMealLogged and reads these extra keys
        // Note: the .foodFinderMealLogged post above already happened — post a dedicated one
        var confirmInfo: [String: Any] = [
            "mealEventID": record.id,
            "finalCarbsGrams": record.carbsGrams
        ]
        if let delta = record.originalAICarbs.map({ record.carbsGrams - $0 }) {
            confirmInfo["carbDeltaFromAI"] = delta
        }
        NotificationCenter.default.post(
            name: Notification.Name("com.loopkit.Loop.foodFinderMealConfirmedForDataLayer"),
            object: nil,
            userInfo: confirmInfo
        )
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

    // MARK: - Clear All

    /// Remove all analysis history records and their thumbnails.
    static func clearAll() {
        let records = allRecords()
        for record in records {
            if let thumbID = record.thumbnailID {
                FavoriteFoodImageStore.deleteThumbnail(id: thumbID)
            }
        }
        save([])
        #if DEBUG
        print("FoodFinder: Cleared all \(records.count) analysis history records")
        #endif
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
    /// Deduplicates by ID and by date+foodType proximity to avoid storing the same meal twice.
    static func archive(_ record: FoodFinder_AnalysisRecord) {
        var existing = loadAll()
        // Skip if exact ID match
        guard !existing.contains(where: { $0.id == record.id }) else { return }
        // Skip if another record with same foodType exists within 5 minutes
        let isDuplicate = existing.contains { other in
            abs(other.date.timeIntervalSince(record.date)) < 300 &&
            other.foodType == record.foodType
        }
        guard !isDuplicate else { return }
        existing.append(record)
        saveAll(existing)
    }

    /// Load all archived records within a date range.
    static func meals(from startDate: Date, to endDate: Date) -> [FoodFinder_AnalysisRecord] {
        loadAll()
            .filter { $0.date >= startDate && $0.date <= endDate }
            .sorted { $0.date > $1.date }
    }

    /// Load the complete archive (all time), deduplicating in two passes:
    /// 1. Same-source dedup: date ±5min + carbs ±1g (collapses write-side duplicates).
    /// 2. Cross-source priority dedup: date ±2h + carbs ±5g across different sources.
    ///    Keeps the highest-priority source per the data primacy order:
    ///    Loop > FoodFinder (image/dictation/barcode) > External (mfpImport).
    static func loadAll() -> [FoodFinder_AnalysisRecord] {
        guard FileManager.default.fileExists(atPath: archiveURL.path) else { return [] }
        guard let data = try? Data(contentsOf: archiveURL) else { return [] }
        let raw = (try? JSONDecoder().decode([FoodFinder_AnalysisRecord].self, from: data)) ?? []

        // Pass 1: same-source dedup (tight window)
        var seen: [(date: Date, carbs: Double)] = []
        let pass1 = raw.filter { record in
            let isDup = seen.contains { existing in
                abs(existing.date.timeIntervalSince(record.date)) < 300 &&
                abs(existing.carbs - record.carbsGrams) < 1
            }
            guard !isDup else { return false }
            seen.append((record.date, record.carbsGrams))
            return true
        }

        // Pass 2: cross-source priority dedup (wider window)
        // When entries from different sources overlap (±2h, ±5g carbs),
        // keep the higher-priority source only.
        var result: [FoodFinder_AnalysisRecord] = []
        for record in pass1 {
            let dominated = result.contains { existing in
                existing.analysisType != record.analysisType &&
                abs(existing.date.timeIntervalSince(record.date)) < 7200 &&
                abs(existing.carbsGrams - record.carbsGrams) < 5 &&
                sourcePriority(existing.analysisType) >= sourcePriority(record.analysisType)
            }
            guard !dominated else { continue }

            // Also remove any existing lower-priority entry this record supersedes
            result.removeAll { existing in
                existing.analysisType != record.analysisType &&
                abs(existing.date.timeIntervalSince(record.date)) < 7200 &&
                abs(existing.carbsGrams - record.carbsGrams) < 5 &&
                sourcePriority(existing.analysisType) < sourcePriority(record.analysisType)
            }
            result.append(record)
        }

        return result
    }

    /// Data primacy: Loop > FoodFinder (image/dictation/barcode) > External (mfpImport).
    private static func sourcePriority(_ type: FoodFinder_AnalysisRecord.AnalysisType) -> Int {
        switch type {
        case .image:      return 3
        case .dictation:  return 2
        case .barcode:    return 1
        case .mfpImport:  return 0
        }
    }

    /// Total archived meal count.
    static var count: Int { loadAll().count }

    private static func saveAll(_ records: [FoodFinder_AnalysisRecord]) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: archiveURL, options: .atomic)
    }
}
