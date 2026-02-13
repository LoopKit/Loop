//
//  LoopInsights_FoodResponseAnalyzer.swift
//  Loop
//
//  Concept & design by Taylor Patterson. Coded & tested by Claude Code in February 2026.
//  Copyright (c) 2025-2026 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit
import HealthKit

/// Analyzes glucose responses to different food types by matching carb entries
/// with subsequent glucose data. Produces per-food statistics and meal events
/// for the Meal Insights view and AI prompt enrichment.
final class LoopInsights_FoodResponseAnalyzer {

    // MARK: - Deduplication

    /// Remove near-duplicate carb entries that share a similar timestamp and carb amount.
    /// Keeps the latest entry in each cluster (within 5 minutes and 20% carb tolerance).
    private static func deduplicateCarbEntries(_ entries: [StoredCarbEntry]) -> [StoredCarbEntry] {
        guard entries.count > 1 else { return entries }

        let sorted = entries.sorted { $0.startDate < $1.startDate }
        var kept: [StoredCarbEntry] = []

        for entry in sorted {
            let carbs = entry.quantity.doubleValue(for: .gram())
            let isDuplicate = kept.contains { existing in
                let existingCarbs = existing.quantity.doubleValue(for: .gram())
                let timeDiff = abs(entry.startDate.timeIntervalSince(existing.startDate))
                let carbDiff = carbs > 0 ? abs(carbs - existingCarbs) / carbs : abs(carbs - existingCarbs)
                return timeDiff < 300 && carbDiff < 0.2  // Within 5 min and 20% carbs
            }
            if !isDuplicate {
                kept.append(entry)
            }
        }

        return kept
    }

    // MARK: - Food Response Patterns

    /// Analyze food response patterns by grouping carb entries by foodType
    /// and matching with glucose samples 0-4h after each meal.
    static func analyzeFoodResponses(
        carbEntries: [StoredCarbEntry],
        glucoseSamples: [StoredGlucoseSample]
    ) -> [LoopInsightsFoodResponsePattern] {
        let dedupedEntries = deduplicateCarbEntries(carbEntries)

        // Group entries by foodType (skip entries with no foodType)
        var grouped: [String: [StoredCarbEntry]] = [:]
        for entry in dedupedEntries {
            let foodType = entry.foodType ?? "Unknown"
            guard !foodType.isEmpty else { continue }
            grouped[foodType, default: []].append(entry)
        }

        // Sort glucose samples by date for efficient lookup
        let sortedGlucose = glucoseSamples.sorted { $0.startDate < $1.startDate }

        var patterns: [LoopInsightsFoodResponsePattern] = []

        for (foodType, entries) in grouped {
            guard entries.count >= 2 else { continue }  // Need at least 2 meals for a pattern

            var peakRises: [Double] = []
            var timesToPeak: [Double] = []
            var aucs: [Double] = []
            var twoHourAvgs: [Double] = []
            var fourHourAvgs: [Double] = []
            var carbAmounts: [Double] = []

            for entry in entries {
                let mealDate = entry.startDate
                let carbs = entry.quantity.doubleValue(for: .gram())
                carbAmounts.append(carbs)

                // Get pre-meal glucose (30 min before to meal time)
                let preMealWindow = mealDate.addingTimeInterval(-1800)...mealDate
                let preMealSamples = sortedGlucose.filter { preMealWindow.contains($0.startDate) }
                guard !preMealSamples.isEmpty else { continue }
                let preMealAvg = preMealSamples.map { $0.quantity.doubleValue(for: .milligramsPerDeciliter) }.reduce(0, +) / Double(preMealSamples.count)

                // Get post-meal glucose (0-4h after meal)
                let postMealEnd = mealDate.addingTimeInterval(4 * 3600)
                let postMealSamples = sortedGlucose.filter {
                    $0.startDate > mealDate && $0.startDate <= postMealEnd
                }
                guard postMealSamples.count >= 4 else { continue }

                let postValues = postMealSamples.map { $0.quantity.doubleValue(for: .milligramsPerDeciliter) }

                // Peak rise
                let peak = postValues.max() ?? preMealAvg
                let peakRise = peak - preMealAvg
                peakRises.append(peakRise)

                // Time to peak
                if let peakSample = postMealSamples.max(by: { $0.quantity.doubleValue(for: .milligramsPerDeciliter) < $1.quantity.doubleValue(for: .milligramsPerDeciliter) }) {
                    let minutesToPeak = peakSample.startDate.timeIntervalSince(mealDate) / 60
                    timesToPeak.append(minutesToPeak)
                }

                // AUC (trapezoidal approximation, mg/dL * hours above pre-meal)
                var auc: Double = 0
                for i in 1..<postMealSamples.count {
                    let dt = postMealSamples[i].startDate.timeIntervalSince(postMealSamples[i-1].startDate) / 3600
                    let v1 = max(0, postMealSamples[i-1].quantity.doubleValue(for: .milligramsPerDeciliter) - preMealAvg)
                    let v2 = max(0, postMealSamples[i].quantity.doubleValue(for: .milligramsPerDeciliter) - preMealAvg)
                    auc += (v1 + v2) / 2 * dt
                }
                aucs.append(auc)

                // 2h and 4h post-meal averages
                let twoHourWindow = mealDate.addingTimeInterval(1.5 * 3600)...mealDate.addingTimeInterval(2.5 * 3600)
                let twoHourSamples = postMealSamples.filter { twoHourWindow.contains($0.startDate) }
                if !twoHourSamples.isEmpty {
                    let avg = twoHourSamples.map { $0.quantity.doubleValue(for: .milligramsPerDeciliter) }.reduce(0, +) / Double(twoHourSamples.count)
                    twoHourAvgs.append(avg)
                }

                let fourHourWindow = mealDate.addingTimeInterval(3.5 * 3600)...mealDate.addingTimeInterval(4.5 * 3600)
                let fourHourSamples = postMealSamples.filter { fourHourWindow.contains($0.startDate) }
                if !fourHourSamples.isEmpty {
                    let avg = fourHourSamples.map { $0.quantity.doubleValue(for: .milligramsPerDeciliter) }.reduce(0, +) / Double(fourHourSamples.count)
                    fourHourAvgs.append(avg)
                }
            }

            guard !peakRises.isEmpty else { continue }

            let avg: ([Double]) -> Double = { vals in
                vals.isEmpty ? 0 : vals.reduce(0, +) / Double(vals.count)
            }

            patterns.append(LoopInsightsFoodResponsePattern(
                foodType: foodType,
                mealCount: entries.count,
                averageCarbsPerMeal: avg(carbAmounts),
                peakGlucoseRise: avg(peakRises),
                timeToPeakMinutes: avg(timesToPeak),
                averageResponseAUC: avg(aucs),
                twoHourPostMealAvg: avg(twoHourAvgs),
                fourHourPostMealAvg: avg(fourHourAvgs)
            ))
        }

        // Sort by peak glucose rise (highest impact first)
        return patterns.sorted { $0.peakGlucoseRise > $1.peakGlucoseRise }
    }

    // MARK: - Recent Meal Events

    /// Build recent meal events with glucose timeline for the meal debrief view.
    /// Returns up to `limit` most recent meals.
    static func buildRecentMealEvents(
        carbEntries: [StoredCarbEntry],
        glucoseSamples: [StoredGlucoseSample],
        limit: Int = 20
    ) -> [LoopInsightsMealEvent] {
        let dedupedEntries = deduplicateCarbEntries(carbEntries)
        let sortedEntries = dedupedEntries.sorted { $0.startDate > $1.startDate }
        let sortedGlucose = glucoseSamples.sorted { $0.startDate < $1.startDate }

        var events: [LoopInsightsMealEvent] = []

        for entry in sortedEntries.prefix(limit * 2) {  // Check extra in case some lack glucose
            let mealDate = entry.startDate
            let foodType = entry.foodType ?? "Unknown"
            let carbs = entry.quantity.doubleValue(for: .gram())

            // Pre-meal glucose
            let preMealWindow = mealDate.addingTimeInterval(-1800)...mealDate
            let preMealSamples = sortedGlucose.filter { preMealWindow.contains($0.startDate) }
            guard !preMealSamples.isEmpty else { continue }
            let preMealGlucose = preMealSamples.last!.quantity.doubleValue(for: .milligramsPerDeciliter)

            // Post-meal glucose (0-4h)
            let postEnd = mealDate.addingTimeInterval(4 * 3600)
            let postSamples = sortedGlucose.filter { $0.startDate > mealDate && $0.startDate <= postEnd }
            guard postSamples.count >= 4 else { continue }

            let postValues = postSamples.map { $0.quantity.doubleValue(for: .milligramsPerDeciliter) }
            let peakGlucose = postValues.max() ?? preMealGlucose

            // 2-hour glucose
            let twoHourWindow = mealDate.addingTimeInterval(1.5 * 3600)...mealDate.addingTimeInterval(2.5 * 3600)
            let twoHourSamples = postSamples.filter { twoHourWindow.contains($0.startDate) }
            let twoHourGlucose = twoHourSamples.isEmpty ? preMealGlucose :
                twoHourSamples.map { $0.quantity.doubleValue(for: .milligramsPerDeciliter) }.reduce(0, +) / Double(twoHourSamples.count)

            // Build timeline (every ~15 min)
            var timeline: [(minutesAfter: Int, glucose: Double)] = []
            timeline.append((0, preMealGlucose))
            for sample in postSamples {
                let minutes = Int(sample.startDate.timeIntervalSince(mealDate) / 60)
                let glucose = sample.quantity.doubleValue(for: .milligramsPerDeciliter)
                timeline.append((minutes, glucose))
            }

            events.append(LoopInsightsMealEvent(
                date: mealDate,
                foodType: foodType,
                carbs: carbs,
                preMealGlucose: preMealGlucose,
                peakGlucose: peakGlucose,
                twoHourGlucose: twoHourGlucose,
                glucoseTimeline: timeline
            ))

            if events.count >= limit { break }
        }

        return events
    }

    // MARK: - Prompt Context

    /// Build prompt context string from food response patterns
    static func buildFoodResponsePromptContext(_ patterns: [LoopInsightsFoodResponsePattern]) -> String {
        guard !patterns.isEmpty else { return "" }

        var ctx = "## Food-Type Response Patterns\n"
        for pattern in patterns.prefix(8) {
            ctx += "- **\(pattern.foodType)** (\(pattern.mealCount) meals, avg \(String(format: "%.0f", pattern.averageCarbsPerMeal))g): "
            ctx += "peak rise \(String(format: "%.0f", pattern.peakGlucoseRise)) mg/dL in \(String(format: "%.0f", pattern.timeToPeakMinutes)) min, "
            ctx += "2h post \(String(format: "%.0f", pattern.twoHourPostMealAvg)) mg/dL, "
            ctx += "4h post \(String(format: "%.0f", pattern.fourHourPostMealAvg)) mg/dL\n"
        }
        let highImpact = patterns.filter { $0.peakGlucoseRise > 60 }
        if !highImpact.isEmpty {
            ctx += "** HIGH IMPACT FOODS: \(highImpact.map { $0.foodType }.joined(separator: ", ")) cause >60 mg/dL glucose spikes **\n"
        }
        return ctx
    }
}
