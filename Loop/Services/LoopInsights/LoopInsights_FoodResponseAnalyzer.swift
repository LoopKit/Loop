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

        // P9: Pre-convert glucose values and sort for binary search (P4)
        let sortedGlucose = glucoseSamples.sorted { $0.startDate < $1.startDate }
        let sortedDates = sortedGlucose.map { $0.startDate }
        let sortedValues = sortedGlucose.map { $0.quantity.doubleValue(for: .milligramsPerDeciliter) }

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

                // P4: Binary search for pre-meal window (30 min before to meal time)
                let preMealStart = mealDate.addingTimeInterval(-1800)
                let preStartIdx = sortedDates.loopInsights_firstIndex(afterOrAt: preMealStart) { $0 }
                var preMealValues: [Double] = []
                for i in preStartIdx..<sortedDates.count {
                    if sortedDates[i] > mealDate { break }
                    preMealValues.append(sortedValues[i])
                }
                guard !preMealValues.isEmpty else { continue }
                let preMealAvg = preMealValues.reduce(0, +) / Double(preMealValues.count)

                // P4: Binary search for post-meal window (0-4h after meal)
                let postMealEnd = mealDate.addingTimeInterval(4 * 3600)
                let postStartIdx = sortedDates.loopInsights_firstIndex(afterOrAt: mealDate) { $0 }
                var postValues: [Double] = []
                var postDates: [Date] = []
                for i in postStartIdx..<sortedDates.count {
                    if sortedDates[i] > postMealEnd { break }
                    if sortedDates[i] > mealDate {
                        postValues.append(sortedValues[i])
                        postDates.append(sortedDates[i])
                    }
                }
                guard postValues.count >= 4 else { continue }

                // Peak rise
                let peak = postValues.max() ?? preMealAvg
                let peakRise = peak - preMealAvg
                peakRises.append(peakRise)

                // Time to peak
                if let peakIdx = postValues.firstIndex(of: peak) {
                    let minutesToPeak = postDates[peakIdx].timeIntervalSince(mealDate) / 60
                    timesToPeak.append(minutesToPeak)
                }

                // AUC (trapezoidal approximation, mg/dL * hours above pre-meal)
                var auc: Double = 0
                for i in 1..<postValues.count {
                    let dt = postDates[i].timeIntervalSince(postDates[i-1]) / 3600
                    let v1 = max(0, postValues[i-1] - preMealAvg)
                    let v2 = max(0, postValues[i] - preMealAvg)
                    auc += (v1 + v2) / 2 * dt
                }
                aucs.append(auc)

                // 2h and 4h post-meal averages using pre-converted values
                let twoHourStart = mealDate.addingTimeInterval(1.5 * 3600)
                let twoHourEnd = mealDate.addingTimeInterval(2.5 * 3600)
                var twoHourValues: [Double] = []
                for i in 0..<postDates.count {
                    if postDates[i] >= twoHourStart && postDates[i] <= twoHourEnd {
                        twoHourValues.append(postValues[i])
                    }
                }
                if !twoHourValues.isEmpty {
                    twoHourAvgs.append(twoHourValues.reduce(0, +) / Double(twoHourValues.count))
                }

                let fourHourStart = mealDate.addingTimeInterval(3.5 * 3600)
                let fourHourEnd = mealDate.addingTimeInterval(4.5 * 3600)
                var fourHourValues: [Double] = []
                for i in 0..<postDates.count {
                    if postDates[i] >= fourHourStart && postDates[i] <= fourHourEnd {
                        fourHourValues.append(postValues[i])
                    }
                }
                if !fourHourValues.isEmpty {
                    fourHourAvgs.append(fourHourValues.reduce(0, +) / Double(fourHourValues.count))
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

        // P4+P9: Pre-sort and pre-convert glucose for binary search + no repeated doubleValue
        let sortedGlucose = glucoseSamples.sorted { $0.startDate < $1.startDate }
        let sortedDates = sortedGlucose.map { $0.startDate }
        let sortedValues = sortedGlucose.map { $0.quantity.doubleValue(for: .milligramsPerDeciliter) }

        var events: [LoopInsightsMealEvent] = []

        for entry in sortedEntries.prefix(limit * 2) {  // Check extra in case some lack glucose
            let mealDate = entry.startDate
            let foodType = entry.foodType ?? "Unknown"
            let carbs = entry.quantity.doubleValue(for: .gram())

            // P4: Binary search for pre-meal glucose window
            let preMealStart = mealDate.addingTimeInterval(-1800)
            let preIdx = sortedDates.loopInsights_firstIndex(afterOrAt: preMealStart) { $0 }
            var lastPreMealValue: Double?
            for i in preIdx..<sortedDates.count {
                if sortedDates[i] > mealDate { break }
                lastPreMealValue = sortedValues[i]
            }
            guard let preMealGlucose = lastPreMealValue else { continue }

            // P4: Binary search for post-meal glucose (0-4h)
            let postEnd = mealDate.addingTimeInterval(4 * 3600)
            let postIdx = sortedDates.loopInsights_firstIndex(afterOrAt: mealDate) { $0 }
            var postValues: [Double] = []
            var postDates: [Date] = []
            for i in postIdx..<sortedDates.count {
                if sortedDates[i] > postEnd { break }
                if sortedDates[i] > mealDate {
                    postValues.append(sortedValues[i])
                    postDates.append(sortedDates[i])
                }
            }
            guard postValues.count >= 4 else { continue }

            let peakGlucose = postValues.max() ?? preMealGlucose

            // 2-hour glucose
            let twoHourStart = mealDate.addingTimeInterval(1.5 * 3600)
            let twoHourEnd = mealDate.addingTimeInterval(2.5 * 3600)
            var twoHourValues: [Double] = []
            for i in 0..<postDates.count {
                if postDates[i] >= twoHourStart && postDates[i] <= twoHourEnd {
                    twoHourValues.append(postValues[i])
                }
            }
            let twoHourGlucose = twoHourValues.isEmpty ? preMealGlucose :
                twoHourValues.reduce(0, +) / Double(twoHourValues.count)

            // Build timeline
            var timeline: [(minutesAfter: Int, glucose: Double)] = []
            timeline.append((0, preMealGlucose))
            for i in 0..<postDates.count {
                let minutes = Int(postDates[i].timeIntervalSince(mealDate) / 60)
                timeline.append((minutes, postValues[i]))
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

    // MARK: - Nutritional Glucose Correlation

    /// Correlate FoodFinder meal records (with full nutritional detail) against
    /// glucose data to discover how macronutrient composition affects BG response.
    /// Groups meals by nutritional profile (high-fat vs low-fat, etc.) and compares
    /// average glucose spikes between groups.
    static func analyzeNutritionalCorrelations(
        meals: [FoodFinder_AnalysisRecord],
        glucoseSamples: [StoredGlucoseSample]
    ) -> String {
        // Only analyze meals with full nutritional data
        let mealsWithNutrition = meals.filter { meal in
            guard let result = meal.analysisResult else { return false }
            return result.totalFat != nil && result.totalProtein != nil && meal.carbsGrams > 0
        }
        guard mealsWithNutrition.count >= 4 else { return "" }

        // Pre-sort glucose for binary search
        let sortedGlucose = glucoseSamples.sorted { $0.startDate < $1.startDate }
        let sortedDates = sortedGlucose.map { $0.startDate }
        let sortedValues = sortedGlucose.map { $0.quantity.doubleValue(for: .milligramsPerDeciliter) }

        guard !sortedDates.isEmpty else { return "" }

        // Calculate glucose spike for each meal
        struct MealSpike {
            let meal: FoodFinder_AnalysisRecord
            let peakRise: Double       // mg/dL above pre-meal
            let timeToPeak: Double     // minutes
            let fatPerCarb: Double     // fat grams per carb gram
            let proteinPerCarb: Double // protein grams per carb gram
            let fiberPerCarb: Double   // fiber grams per carb gram
        }

        var spikes: [MealSpike] = []

        for meal in mealsWithNutrition {
            guard let result = meal.analysisResult,
                  let fat = result.totalFat,
                  let protein = result.totalProtein else { continue }
            let fiber = result.totalFiber ?? 0

            let mealDate = meal.date

            // Pre-meal glucose (30 min before)
            let preMealStart = mealDate.addingTimeInterval(-1800)
            let preIdx = sortedDates.loopInsights_firstIndex(afterOrAt: preMealStart) { $0 }
            var preMealValues: [Double] = []
            for i in preIdx..<sortedDates.count {
                if sortedDates[i] > mealDate { break }
                preMealValues.append(sortedValues[i])
            }
            guard !preMealValues.isEmpty else { continue }
            let preMealAvg = preMealValues.reduce(0, +) / Double(preMealValues.count)

            // Post-meal glucose (0-4h)
            let postEnd = mealDate.addingTimeInterval(4 * 3600)
            let postIdx = sortedDates.loopInsights_firstIndex(afterOrAt: mealDate) { $0 }
            var postValues: [Double] = []
            var postDates: [Date] = []
            for i in postIdx..<sortedDates.count {
                if sortedDates[i] > postEnd { break }
                if sortedDates[i] > mealDate {
                    postValues.append(sortedValues[i])
                    postDates.append(sortedDates[i])
                }
            }
            guard postValues.count >= 4 else { continue }

            let peak = postValues.max() ?? preMealAvg
            let peakRise = peak - preMealAvg
            var timeToPeak: Double = 60
            if let peakIdx = postValues.firstIndex(of: peak) {
                timeToPeak = postDates[peakIdx].timeIntervalSince(mealDate) / 60
            }

            spikes.append(MealSpike(
                meal: meal,
                peakRise: peakRise,
                timeToPeak: timeToPeak,
                fatPerCarb: fat / meal.carbsGrams,
                proteinPerCarb: protein / meal.carbsGrams,
                fiberPerCarb: fiber / meal.carbsGrams
            ))
        }

        guard spikes.count >= 4 else { return "" }

        var lines: [String] = ["NUTRITIONAL GLUCOSE CORRELATIONS (\(spikes.count) meals analyzed):"]

        let avgSpike: ([MealSpike]) -> Double = { group in
            group.isEmpty ? 0 : group.map { $0.peakRise }.reduce(0, +) / Double(group.count)
        }
        let avgTime: ([MealSpike]) -> Double = { group in
            group.isEmpty ? 0 : group.map { $0.timeToPeak }.reduce(0, +) / Double(group.count)
        }

        // Fat analysis: high-fat (>0.5g fat per g carb) vs low-fat (<0.2g)
        let highFat = spikes.filter { $0.fatPerCarb > 0.5 }
        let lowFat = spikes.filter { $0.fatPerCarb < 0.2 }
        if highFat.count >= 2 && lowFat.count >= 2 {
            let hfSpike = avgSpike(highFat)
            let lfSpike = avgSpike(lowFat)
            let hfTime = avgTime(highFat)
            let lfTime = avgTime(lowFat)
            lines.append("  Fat Impact:")
            lines.append("    High-fat meals (\(highFat.count)): avg spike \(String(format: "%.0f", hfSpike)) mg/dL, peak at \(String(format: "%.0f", hfTime)) min")
            lines.append("    Low-fat meals (\(lowFat.count)): avg spike \(String(format: "%.0f", lfSpike)) mg/dL, peak at \(String(format: "%.0f", lfTime)) min")
            if hfTime > lfTime + 15 {
                lines.append("    → High-fat meals delay glucose peak by ~\(String(format: "%.0f", hfTime - lfTime)) min")
            }
        }

        // Protein analysis: high-protein (>0.5g protein per g carb) vs low-protein
        let highProtein = spikes.filter { $0.proteinPerCarb > 0.5 }
        let lowProtein = spikes.filter { $0.proteinPerCarb < 0.2 }
        if highProtein.count >= 2 && lowProtein.count >= 2 {
            let hpSpike = avgSpike(highProtein)
            let lpSpike = avgSpike(lowProtein)
            lines.append("  Protein Impact:")
            lines.append("    High-protein meals (\(highProtein.count)): avg spike \(String(format: "%.0f", hpSpike)) mg/dL")
            lines.append("    Low-protein meals (\(lowProtein.count)): avg spike \(String(format: "%.0f", lpSpike)) mg/dL")
        }

        // Fiber analysis: high-fiber (>0.15g fiber per g carb) vs low-fiber
        let highFiber = spikes.filter { $0.fiberPerCarb > 0.15 }
        let lowFiber = spikes.filter { $0.fiberPerCarb < 0.05 }
        if highFiber.count >= 2 && lowFiber.count >= 2 {
            let hfibSpike = avgSpike(highFiber)
            let lfibSpike = avgSpike(lowFiber)
            lines.append("  Fiber Impact:")
            lines.append("    High-fiber meals (\(highFiber.count)): avg spike \(String(format: "%.0f", hfibSpike)) mg/dL")
            lines.append("    Low-fiber meals (\(lowFiber.count)): avg spike \(String(format: "%.0f", lfibSpike)) mg/dL")
            if lfibSpike > hfibSpike + 10 {
                lines.append("    → Fiber reduces glucose spike by ~\(String(format: "%.0f", lfibSpike - hfibSpike)) mg/dL on average")
            }
        }

        // Top 3 highest-spike meals
        let sorted = spikes.sorted { $0.peakRise > $1.peakRise }
        lines.append("  Biggest Spikes:")
        for spike in sorted.prefix(3) {
            let fat = spike.meal.analysisResult?.totalFat ?? 0
            let protein = spike.meal.analysisResult?.totalProtein ?? 0
            lines.append("    \(spike.meal.name): +\(String(format: "%.0f", spike.peakRise)) mg/dL (\(String(format: "%.0f", spike.meal.carbsGrams))g carbs, \(String(format: "%.0f", fat))g fat, \(String(format: "%.0f", protein))g protein)")
        }

        return lines.joined(separator: "\n")
    }
}
