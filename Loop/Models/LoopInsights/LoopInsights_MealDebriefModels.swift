//
//  LoopInsights_MealDebriefModels.swift
//  Loop
//
//  LoopInsights — Data models for AI Meal Debrief and Pre-Meal Advisor.
//
//  Idea by Taylor Patterson. Coded by Claude Code.
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Foundation

// MARK: - Prediction Snapshot

/// Captures Loop's predicted glucose trajectory at the moment a meal is logged.
/// This is the "what Loop thought would happen" half of the debrief comparison.
struct LoopInsights_PredictionSnapshot: Codable, Identifiable {
    let id: String                        // Matches the MealArchive record ID
    let capturedAt: Date                  // When the snapshot was taken
    let mealRecordID: String              // FoodFinder_AnalysisRecord.id
    let predictedValues: [Double]         // mg/dL values at each interval
    let intervalSeconds: TimeInterval     // Typically 300 (5 min)
    let startDate: Date                   // First prediction point (≈ current glucose)
    let preMealGlucose: Double            // mg/dL at capture time
}

// MARK: - Meal Debrief

/// The AI-generated analysis comparing predicted vs actual glucose response.
struct LoopInsights_MealDebrief: Codable, Identifiable {
    let id: String                        // Same as mealRecordID
    let mealRecordID: String
    let generatedAt: Date
    let effectiveCarbsEstimate: Double?   // "Behaved like Xg of carbs"
    let aiInterpretation: String          // Full AI text (≤5 sentences)
    let learnings: [String]               // Bullet-point takeaways
    let predictedPeakGlucose: Double?     // mg/dL — from snapshot
    let actualPeakGlucose: Double?        // mg/dL — from real data
    let peakTimingDeltaMinutes: Double?   // Actual peak - predicted peak (+ = later than predicted)
}

// MARK: - Debrief Context

/// Bundles all data needed to generate a debrief for a single meal.
struct LoopInsights_DebriefContext {
    let mealRecord: FoodFinder_AnalysisRecord
    let snapshot: LoopInsights_PredictionSnapshot
    let actualGlucoseTimeline: [(minutesAfter: Int, glucose: Double)]
    let foodPattern: LoopInsightsFoodResponsePattern?  // Historical pattern if available
}

// MARK: - Pre-Meal Advice

/// Instant pre-computed advice shown when user selects a familiar food type.
struct LoopInsights_PreMealAdvice: Identifiable {
    let id = UUID()
    let foodType: String
    let mealCount: Int
    let averageCarbs: Double              // g
    let averagePeakRise: Double           // mg/dL
    let averageTimeToPeak: Double         // minutes
    let summaryText: String               // Pre-computed instant summary
    var aiAdvice: String?                 // Async AI enhancement (nil until loaded)
    var isLoadingAI: Bool = false
}

// MARK: - Snapshot Store

/// Manages persistence of prediction snapshots to JSON file.
/// 90-day retention, pruned on every save.
enum LoopInsights_PredictionSnapshotStore {

    private static let fileName = "LoopInsights_PredictionSnapshots.json"
    private static let retentionDays: TimeInterval = 90 * 24 * 3600

    private static var fileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("LoopInsights", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(fileName)
    }

    static func loadAll() -> [LoopInsights_PredictionSnapshot] {
        guard let data = try? Data(contentsOf: fileURL),
              let snapshots = try? JSONDecoder().decode([LoopInsights_PredictionSnapshot].self, from: data) else {
            return []
        }
        return snapshots
    }

    static func save(_ snapshots: [LoopInsights_PredictionSnapshot]) {
        let cutoff = Date().addingTimeInterval(-retentionDays)
        let pruned = snapshots.filter { $0.capturedAt > cutoff }
        if let data = try? JSONEncoder().encode(pruned) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    static func snapshot(forMealID id: String) -> LoopInsights_PredictionSnapshot? {
        loadAll().first { $0.mealRecordID == id }
    }

    static func append(_ snapshot: LoopInsights_PredictionSnapshot) {
        var all = loadAll()
        // Don't duplicate
        guard !all.contains(where: { $0.mealRecordID == snapshot.mealRecordID }) else { return }
        all.append(snapshot)
        save(all)
    }

    /// Remove snapshots older than 90 days
    static func pruneStale() {
        let all = loadAll()
        save(all) // save() already prunes
    }
}

// MARK: - Debrief Cache

/// Manages persistence of generated debriefs to JSON file.
/// 90-day retention, immutable once generated.
enum LoopInsights_MealDebriefCache {

    private static let fileName = "LoopInsights_MealDebriefs.json"
    private static let retentionDays: TimeInterval = 90 * 24 * 3600

    private static var fileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("LoopInsights", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(fileName)
    }

    static func loadAll() -> [LoopInsights_MealDebrief] {
        guard let data = try? Data(contentsOf: fileURL),
              let debriefs = try? JSONDecoder().decode([LoopInsights_MealDebrief].self, from: data) else {
            return []
        }
        return debriefs
    }

    static func save(_ debriefs: [LoopInsights_MealDebrief]) {
        let cutoff = Date().addingTimeInterval(-retentionDays)
        let pruned = debriefs.filter { $0.generatedAt > cutoff }
        if let data = try? JSONEncoder().encode(pruned) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    static func debrief(forMealID id: String) -> LoopInsights_MealDebrief? {
        loadAll().first { $0.mealRecordID == id }
    }

    static func append(_ debrief: LoopInsights_MealDebrief) {
        var all = loadAll()
        guard !all.contains(where: { $0.mealRecordID == debrief.mealRecordID }) else { return }
        all.append(debrief)
        save(all)
    }

    /// Remove debriefs older than 90 days
    static func pruneStale() {
        let all = loadAll()
        save(all) // save() already prunes
    }
}
