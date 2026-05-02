//
//  LoopInsights_BehaviorInsightsAnalyzer.swift
//  Loop
//
//  LoopInsights — Detects systematic user correction patterns in FoodFinder
//  meal data and surfaces actionable insights about AI estimation accuracy.
//
//  Idea by Taylor Patterson. Coded by Claude Code.
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Foundation

// MARK: - Correction Pattern

/// A detected pattern where the user consistently adjusts AI carb estimates
/// for a specific grouping (food type, location, time of day, confidence level).
struct LoopInsightsCorrectionPattern: Identifiable, Codable, Equatable {
    let id: UUID
    let groupingType: GroupingType
    let groupingValue: String
    let mealCount: Int
    let averageCorrectionGrams: Double   // positive = user adds carbs, negative = user removes
    let averageCorrectionPercent: Double  // relative to AI estimate
    let consistency: Double              // 0-1, how consistent the direction is
    let lastOccurrence: Date
    let detectedAt: Date

    /// Whether this pattern suggests the AI systematically under-estimates
    var isUnderestimation: Bool { averageCorrectionGrams > 0 }

    /// Whether this pattern suggests the AI systematically over-estimates
    var isOverestimation: Bool { averageCorrectionGrams < 0 }

    /// Human-readable summary of the pattern
    var summaryDescription: String {
        let direction = isUnderestimation ? "under-estimates" : "over-estimates"
        let absGrams = abs(averageCorrectionGrams)
        let absPercent = abs(averageCorrectionPercent)
        return String(format: "AI %@ %@ by ~%.0fg (%.0f%%) across %d meals",
                      direction, groupingValue, absGrams, absPercent, mealCount)
    }

    /// Recommended action text
    var recommendedAction: String {
        let absGrams = abs(averageCorrectionGrams)
        if isUnderestimation {
            return String(format: "Consider adding ~%.0fg to AI estimates for %@", absGrams, groupingValue)
        } else {
            return String(format: "Consider subtracting ~%.0fg from AI estimates for %@", absGrams, groupingValue)
        }
    }

    enum GroupingType: String, Codable {
        case foodType
        case location
        case timeOfDay
        case confidenceLevel

        var displayName: String {
            switch self {
            case .foodType: return "Food Type"
            case .location: return "Location"
            case .timeOfDay: return "Time of Day"
            case .confidenceLevel: return "AI Confidence"
            }
        }

        var systemImage: String {
            switch self {
            case .foodType: return "fork.knife"
            case .location: return "mappin.and.ellipse"
            case .timeOfDay: return "clock"
            case .confidenceLevel: return "gauge.with.dots.needle.33percent"
            }
        }
    }
}

// MARK: - Analyzer

/// Analyzes MealArchive data to detect systematic correction patterns.
/// Patterns are detected when a user consistently adjusts AI estimates
/// in the same direction for a given grouping.
enum LoopInsights_BehaviorInsightsAnalyzer {

    /// Minimum number of meals in a group to detect a pattern
    private static let minimumMealCount = 3

    /// Minimum consistency threshold (0-1) — at least this fraction of corrections
    /// must be in the same direction to qualify as a pattern
    private static let consistencyThreshold: Double = 0.7

    /// Minimum average correction magnitude (grams) to surface as a pattern
    private static let minimumCorrectionGrams: Double = 3.0

    /// Minimum average correction percentage to surface as a pattern
    private static let minimumCorrectionPercent: Double = 10.0

    // MARK: - Public API

    /// Analyze all meal records and return detected correction patterns
    static func analyzePatterns(meals: [FoodFinder_AnalysisRecord]? = nil) -> [LoopInsightsCorrectionPattern] {
        let records = meals ?? MealArchive.loadAll()

        // Filter to records that have both originalAICarbs and user-entered carbs
        let correctable = records.filter { record in
            guard let aiCarbs = record.originalAICarbs, aiCarbs > 0 else { return false }
            return abs(record.carbsGrams - aiCarbs) >= 1.0  // At least 1g difference
        }

        guard correctable.count >= minimumMealCount else { return [] }

        var patterns: [LoopInsightsCorrectionPattern] = []

        // Detect patterns by food type
        patterns.append(contentsOf: detectPatterns(
            records: correctable,
            groupingType: .foodType,
            groupBy: { $0.foodType }
        ))

        // Detect patterns by location
        patterns.append(contentsOf: detectPatterns(
            records: correctable,
            groupingType: .location,
            groupBy: { $0.locationName ?? "Unknown" }
        ).filter { $0.groupingValue != "Unknown" })

        // Detect patterns by time of day
        patterns.append(contentsOf: detectPatterns(
            records: correctable,
            groupingType: .timeOfDay,
            groupBy: { timeOfDayBucket(for: $0.date) }
        ))

        // Detect patterns by confidence level
        patterns.append(contentsOf: detectPatterns(
            records: correctable,
            groupingType: .confidenceLevel,
            groupBy: { confidenceBucket(for: $0.aiConfidencePercent) }
        ))

        // Sort by impact (highest correction magnitude first)
        return patterns.sorted { abs($0.averageCorrectionGrams) > abs($1.averageCorrectionGrams) }
    }

    /// Quick check: are there any new patterns since the last check?
    /// Used for "alert upon discovery" — returns newly detected patterns
    /// that weren't in the previously stored set.
    static func detectNewPatterns(previousPatterns: [LoopInsightsCorrectionPattern]) -> [LoopInsightsCorrectionPattern] {
        let current = analyzePatterns()

        // A pattern is "new" if no previous pattern matches the same grouping type+value
        return current.filter { pattern in
            !previousPatterns.contains { prev in
                prev.groupingType == pattern.groupingType &&
                prev.groupingValue == pattern.groupingValue
            }
        }
    }

    /// Build a text summary of all patterns for inclusion in AI prompts
    static func buildPromptContext(patterns: [LoopInsightsCorrectionPattern]) -> String {
        guard !patterns.isEmpty else { return "" }

        var lines = ["USER CORRECTION PATTERNS (from meal history):"]
        for pattern in patterns.prefix(8) {
            lines.append("• \(pattern.summaryDescription) (consistency: \(Int(pattern.consistency * 100))%)")
        }
        lines.append("Consider these systematic biases when making recommendations.")
        return lines.joined(separator: "\n")
    }

    // MARK: - Pattern Detection Core

    private static func detectPatterns(
        records: [FoodFinder_AnalysisRecord],
        groupingType: LoopInsightsCorrectionPattern.GroupingType,
        groupBy: @escaping (FoodFinder_AnalysisRecord) -> String
    ) -> [LoopInsightsCorrectionPattern] {

        let grouped = Dictionary(grouping: records, by: groupBy)
        var patterns: [LoopInsightsCorrectionPattern] = []

        for (value, groupRecords) in grouped {
            guard groupRecords.count >= minimumMealCount else { continue }

            // Calculate corrections for each record
            let corrections: [(grams: Double, percent: Double)] = groupRecords.compactMap { record in
                guard let aiCarbs = record.originalAICarbs, aiCarbs > 0 else { return nil }
                let diffGrams = record.carbsGrams - aiCarbs
                let diffPercent = (diffGrams / aiCarbs) * 100
                return (grams: diffGrams, percent: diffPercent)
            }

            guard corrections.count >= minimumMealCount else { continue }

            // Calculate average correction
            let avgGrams = corrections.map(\.grams).reduce(0, +) / Double(corrections.count)
            let avgPercent = corrections.map(\.percent).reduce(0, +) / Double(corrections.count)

            // Calculate consistency (fraction of corrections in the dominant direction)
            let positiveCount = corrections.filter { $0.grams > 0 }.count
            let negativeCount = corrections.filter { $0.grams < 0 }.count
            let dominantCount = max(positiveCount, negativeCount)
            let consistency = Double(dominantCount) / Double(corrections.count)

            // Apply thresholds
            guard consistency >= consistencyThreshold,
                  abs(avgGrams) >= minimumCorrectionGrams,
                  abs(avgPercent) >= minimumCorrectionPercent else { continue }

            let lastDate = groupRecords.map(\.date).max() ?? Date()

            patterns.append(LoopInsightsCorrectionPattern(
                id: UUID(),
                groupingType: groupingType,
                groupingValue: value,
                mealCount: corrections.count,
                averageCorrectionGrams: avgGrams,
                averageCorrectionPercent: avgPercent,
                consistency: consistency,
                lastOccurrence: lastDate,
                detectedAt: Date()
            ))
        }

        return patterns
    }

    // MARK: - Bucketing Helpers

    private static func timeOfDayBucket(for date: Date) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 5..<9: return "Early Morning"
        case 9..<12: return "Late Morning"
        case 12..<14: return "Lunch"
        case 14..<17: return "Afternoon"
        case 17..<20: return "Dinner"
        case 20..<23: return "Evening"
        default: return "Night"
        }
    }

    private static func confidenceBucket(for percent: Int?) -> String {
        guard let pct = percent else { return "Unknown" }
        switch pct {
        case 0..<50: return "Low Confidence"
        case 50..<75: return "Medium Confidence"
        case 75..<90: return "High Confidence"
        default: return "Very High Confidence"
        }
    }
}

// MARK: - Persistence

/// Stores detected patterns to UserDefaults for "alert upon discovery" comparison
enum LoopInsights_BehaviorInsightsStore {

    private static let storageKey = "LoopInsights_BehaviorPatterns"
    private static let lastCheckKey = "LoopInsights_BehaviorLastCheck"

    static func loadStoredPatterns() -> [LoopInsightsCorrectionPattern] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let patterns = try? JSONDecoder().decode([LoopInsightsCorrectionPattern].self, from: data) else {
            return []
        }
        return patterns
    }

    static func storePatterns(_ patterns: [LoopInsightsCorrectionPattern]) {
        if let data = try? JSONEncoder().encode(patterns) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
        UserDefaults.standard.set(Date(), forKey: lastCheckKey)
    }

    static var lastCheckDate: Date? {
        UserDefaults.standard.object(forKey: lastCheckKey) as? Date
    }

    /// Check for new patterns and return any discoveries. Updates stored patterns.
    static func checkForNewDiscoveries() -> [LoopInsightsCorrectionPattern] {
        let previous = loadStoredPatterns()
        let current = LoopInsights_BehaviorInsightsAnalyzer.analyzePatterns()
        let newPatterns = LoopInsights_BehaviorInsightsAnalyzer.detectNewPatterns(previousPatterns: previous)

        // Always update stored patterns to current
        storePatterns(current)

        return newPatterns
    }
}
