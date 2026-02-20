//
//  LoopInsights_PreMealAdvisorService.swift
//  Loop
//
//  LoopInsights — Pattern lookup by foodType, pre-computed summary,
//  and async AI advice for the Pre-Meal Advisor card.
//
//  Idea by Taylor Patterson. Coded by Claude Code.
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit
import HealthKit
import os.log

/// Provides instant historical patterns and async AI advice for familiar food types.
/// Used by FoodFinder_EntryPoint to show a "Personal Insight" card.
final class LoopInsights_PreMealAdvisorService {

    static let shared = LoopInsights_PreMealAdvisorService()

    private let log = Logger(subsystem: "com.loopkit.Loop.LoopInsights", category: "PreMealAdvisor")

    // Cache of recent advice to avoid re-querying for the same food type within a session
    private var adviceCache: [String: LoopInsights_PreMealAdvice] = [:]

    // MARK: - Public API

    /// Check if we have enough data to show advice for this food type.
    /// Returns pre-computed advice immediately if ≥2 meals match.
    func checkForAdvice(foodType: String) -> LoopInsights_PreMealAdvice? {
        guard LoopInsights_FeatureFlags.preMealAdvisorEnabled,
              LoopInsights_FeatureFlags.foodResponseEnabled,
              !foodType.isEmpty else {
            return nil
        }

        let normalizedType = foodType.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedType.isEmpty else { return nil }

        // Check cache
        if let cached = adviceCache[normalizedType.lowercased()] {
            return cached
        }

        // Query MealArchive for matching meals (full history)
        let allMeals = MealArchive.loadAll()
        let matching = allMeals.filter {
            $0.foodType.lowercased().contains(normalizedType.lowercased()) ||
            normalizedType.lowercased().contains($0.foodType.lowercased())
        }

        guard matching.count >= 2 else { return nil }

        // Compute summary from MealArchive data
        let avgCarbs = matching.map(\.carbsGrams).reduce(0, +) / Double(matching.count)

        // Try to get glucose patterns from FoodResponseAnalyzer via existing patterns
        // We'll compute basic stats from archive data
        let advice = LoopInsights_PreMealAdvice(
            foodType: normalizedType,
            mealCount: matching.count,
            averageCarbs: avgCarbs,
            averagePeakRise: 0, // Will be enriched if glucose data available
            averageTimeToPeak: 0,
            summaryText: buildSummaryText(foodType: normalizedType, meals: matching, avgCarbs: avgCarbs)
        )

        adviceCache[normalizedType.lowercased()] = advice
        return advice
    }

    /// Enrich advice with glucose pattern data from FoodResponseAnalyzer.
    /// Call this after initial advice is returned to add peak/timing stats.
    func enrichWithGlucosePatterns(
        advice: LoopInsights_PreMealAdvice,
        patterns: [LoopInsightsFoodResponsePattern]
    ) -> LoopInsights_PreMealAdvice {
        guard let pattern = patterns.first(where: {
            $0.foodType.lowercased() == advice.foodType.lowercased()
        }) else {
            return advice
        }

        var enriched = LoopInsights_PreMealAdvice(
            foodType: advice.foodType,
            mealCount: advice.mealCount,
            averageCarbs: advice.averageCarbs,
            averagePeakRise: pattern.peakGlucoseRise,
            averageTimeToPeak: pattern.timeToPeakMinutes,
            summaryText: buildEnrichedSummary(
                foodType: advice.foodType,
                mealCount: advice.mealCount,
                avgCarbs: advice.averageCarbs,
                peakRise: pattern.peakGlucoseRise,
                timeToPeak: pattern.timeToPeakMinutes
            )
        )
        enriched.aiAdvice = advice.aiAdvice
        enriched.isLoadingAI = advice.isLoadingAI

        adviceCache[advice.foodType.lowercased()] = enriched
        return enriched
    }

    /// Request AI-generated personalized advice (async). Updates the advice in-place.
    func requestAIAdvice(for advice: LoopInsights_PreMealAdvice) async -> LoopInsights_PreMealAdvice {
        var updated = advice
        updated.isLoadingAI = true

        // Check for recent debriefs for this food type to include in prompt
        let recentDebriefs = LoopInsights_MealDebriefCache.loadAll()
            .filter { debrief in
                let record = MealArchive.loadAll().first { $0.id == debrief.mealRecordID }
                return record?.foodType.lowercased() == advice.foodType.lowercased()
            }
            .sorted { $0.generatedAt > $1.generatedAt }
            .prefix(3)

        let prompt = buildAIPrompt(advice: advice, recentDebriefs: Array(recentDebriefs))

        do {
            let response = try await LoopInsights_AIServiceAdapter.shared.sendPrompt(
                "You are a diabetes pre-meal advisor. Give brief, actionable advice based on the user's personal history. Keep it under 3 sentences.",
                userPrompt: prompt
            )
            updated.aiAdvice = response
            updated.isLoadingAI = false
        } catch {
            log.error("AI advice failed for \(advice.foodType): \(error)")
            updated.isLoadingAI = false
        }

        adviceCache[advice.foodType.lowercased()] = updated
        return updated
    }

    /// Clear the advice cache (e.g., on view disappear)
    func clearCache() {
        adviceCache.removeAll()
    }

    // MARK: - Private

    private func buildSummaryText(foodType: String, meals: [FoodFinder_AnalysisRecord], avgCarbs: Double) -> String {
        let timeFormatter = DateFormatter()
        timeFormatter.dateStyle = .short
        timeFormatter.timeStyle = .none

        var text = String(format: NSLocalizedString("You've had %@ %d times. Avg carbs: %.0fg.", comment: "Pre-meal advisor summary"), foodType, meals.count, avgCarbs)

        // Add absorption time info if available
        let absorptionTimes = meals.compactMap { $0.analysisResult?.absorptionTimeHours }
        if !absorptionTimes.isEmpty {
            let avgAbsorption = absorptionTimes.reduce(0, +) / Double(absorptionTimes.count)
            text += String(format: NSLocalizedString(" Avg absorption: %.1fh.", comment: "Pre-meal advisor absorption"), avgAbsorption)
        }

        // Add last time info
        if let lastMeal = meals.sorted(by: { $0.date > $1.date }).first {
            text += String(format: NSLocalizedString(" Last: %@.", comment: "Pre-meal advisor last meal"), timeFormatter.string(from: lastMeal.date))
        }

        return text
    }

    private func buildEnrichedSummary(foodType: String, mealCount: Int, avgCarbs: Double, peakRise: Double, timeToPeak: Double) -> String {
        return String(format: NSLocalizedString("You've had %@ %d times. Avg peak: +%.0f mg/dL in %.0f min. Avg carbs: %.0fg.", comment: "Pre-meal advisor enriched summary"), foodType, mealCount, peakRise, timeToPeak, avgCarbs)
    }

    private func buildAIPrompt(advice: LoopInsights_PreMealAdvice, recentDebriefs: [LoopInsights_MealDebrief]) -> String {
        var lines: [String] = []
        lines.append("I'm about to eat \(advice.foodType).")
        lines.append("My personal history with this food (\(advice.mealCount) meals):")
        lines.append("- Average carbs: \(String(format: "%.0f", advice.averageCarbs))g")
        if advice.averagePeakRise > 0 {
            lines.append("- Average peak glucose rise: +\(String(format: "%.0f", advice.averagePeakRise)) mg/dL")
            lines.append("- Average time to peak: \(String(format: "%.0f", advice.averageTimeToPeak)) min")
        }

        if !recentDebriefs.isEmpty {
            lines.append("")
            lines.append("Recent meal debriefs for this food:")
            for debrief in recentDebriefs {
                if let effective = debrief.effectiveCarbsEstimate {
                    lines.append("- Effective carbs: ~\(String(format: "%.0f", effective))g")
                }
                for learning in debrief.learnings {
                    lines.append("- \(learning)")
                }
            }
        }

        lines.append("")
        lines.append("What should I consider for bolusing this time? Be specific about timing and approach.")

        return lines.joined(separator: "\n")
    }
}
