//
//  LoopInsights_MealDebriefService.swift
//  Loop
//
//  LoopInsights — Prediction capture on meal log, debrief generation via AI,
//  and JSON storage for snapshots + debriefs.
//
//  Idea by Taylor Patterson. Coded by Claude Code.
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Foundation
import HealthKit
import os.log

/// Captures Loop's predicted glucose at meal time, then later generates
/// AI-powered debriefs comparing predicted vs actual glucose response.
final class LoopInsights_MealDebriefService {

    static let shared = LoopInsights_MealDebriefService()

    private let log = Logger(subsystem: "com.loopkit.Loop.LoopInsights", category: "MealDebrief")

    // MARK: - Prediction Capture

    /// Called when `.foodFinderMealLogged` fires. Reads the current predicted glucose
    /// from StatusExtensionContext and persists it alongside the meal record ID.
    func capturePredictionSnapshot(mealRecordID: String) {
        guard LoopInsights_FeatureFlags.mealDebriefEnabled else { return }

        guard let statusCtx = UserDefaults.appGroup?.statusExtensionContext,
              let predicted = statusCtx.predictedGlucose else {
            log.info("No predicted glucose available for snapshot (mealID: \(mealRecordID))")
            return
        }

        let samples = predicted.samples
        guard let first = samples.first else {
            log.info("Empty predicted glucose samples for snapshot (mealID: \(mealRecordID))")
            return
        }

        let snapshot = LoopInsights_PredictionSnapshot(
            id: mealRecordID,
            capturedAt: Date(),
            mealRecordID: mealRecordID,
            predictedValues: predicted.values,
            intervalSeconds: predicted.interval,
            startDate: predicted.startDate,
            preMealGlucose: first.value
        )

        LoopInsights_PredictionSnapshotStore.append(snapshot)
        log.info("Captured prediction snapshot for meal \(mealRecordID): \(predicted.values.count) points, pre-meal \(String(format: "%.0f", first.value)) mg/dL")
    }

    // MARK: - Debrief Generation

    /// Check if a debrief is ready (meal is ≥2h old and has a prediction snapshot).
    func isDebriefReady(for mealRecord: FoodFinder_AnalysisRecord) -> LoopInsights_DebriefReadiness {
        guard LoopInsights_FeatureFlags.mealDebriefEnabled else { return .featureDisabled }

        // Already cached?
        if LoopInsights_MealDebriefCache.debrief(forMealID: mealRecord.id) != nil {
            return .ready
        }

        // Has prediction snapshot?
        guard LoopInsights_PredictionSnapshotStore.snapshot(forMealID: mealRecord.id) != nil else {
            return .noSnapshot
        }

        // Is it old enough?
        let hoursElapsed = Date().timeIntervalSince(mealRecord.date) / 3600
        if hoursElapsed < 2 {
            let minutesRemaining = Int((2 - hoursElapsed) * 60)
            return .tooRecent(minutesRemaining: minutesRemaining)
        }

        return .readyToGenerate
    }

    /// Generate a debrief for a meal. Returns cached version if available.
    func generateDebrief(
        for mealRecord: FoodFinder_AnalysisRecord,
        actualTimeline: [(minutesAfter: Int, glucose: Double)],
        foodPattern: LoopInsightsFoodResponsePattern?
    ) async throws -> LoopInsights_MealDebrief {
        // Return cached
        if let cached = LoopInsights_MealDebriefCache.debrief(forMealID: mealRecord.id) {
            return cached
        }

        guard let snapshot = LoopInsights_PredictionSnapshotStore.snapshot(forMealID: mealRecord.id) else {
            throw LoopInsightsError.insufficientData("No prediction snapshot for meal \(mealRecord.id)")
        }

        let prompt = buildDebriefPrompt(
            mealRecord: mealRecord,
            snapshot: snapshot,
            actualTimeline: actualTimeline,
            foodPattern: foodPattern
        )

        let response = try await LoopInsights_AIServiceAdapter.shared.sendPrompt(
            "You are a diabetes meal analysis assistant. Analyze predicted vs actual glucose response. Be concise and practical.",
            userPrompt: prompt
        )

        let debrief = parseDebriefResponse(
            response: response,
            mealRecord: mealRecord,
            snapshot: snapshot,
            actualTimeline: actualTimeline
        )

        LoopInsights_MealDebriefCache.append(debrief)
        log.info("Generated debrief for meal \(mealRecord.id): \(debrief.learnings.count) learnings")

        // DataLayer: meal debrief generated
        NotificationCenter.default.post(
            name: Notification.Name("com.loopkit.Loop.loopInsightsMealDebrief"),
            object: nil,
            userInfo: [
                "predictedPeakMgDl": debrief.predictedPeakGlucose as Any,
                "actualPeakMgDl": debrief.actualPeakGlucose as Any,
                "effectiveCarbsEstimate": debrief.effectiveCarbsEstimate as Any,
                "timeToPeakMinutes": debrief.peakTimingDeltaMinutes as Any,
                "learningCount": debrief.learnings.count
            ]
        )

        return debrief
    }

    // MARK: - Prompt Building

    private func buildDebriefPrompt(
        mealRecord: FoodFinder_AnalysisRecord,
        snapshot: LoopInsights_PredictionSnapshot,
        actualTimeline: [(minutesAfter: Int, glucose: Double)],
        foodPattern: LoopInsightsFoodResponsePattern?
    ) -> String {
        var lines: [String] = []

        // Meal info
        lines.append("Meal: \(mealRecord.name), \(String(format: "%.0f", mealRecord.carbsGrams))g carbs entered")
        if let aiCarbs = mealRecord.originalAICarbs {
            var aiLine = " (AI suggested \(String(format: "%.0f", aiCarbs))g"
            if let conf = mealRecord.aiConfidencePercent {
                aiLine += ", \(conf)% confidence"
            }
            aiLine += ")"
            lines.append(aiLine)
        }

        // Nutrition from analysis result
        if let result = mealRecord.analysisResult {
            var macros: [String] = []
            if let fat = result.totalFat, fat > 0 { macros.append("\(String(format: "%.0f", fat))g fat") }
            if let protein = result.totalProtein, protein > 0 { macros.append("\(String(format: "%.0f", protein))g protein") }
            if let fiber = result.totalFiber, fiber > 0 { macros.append("\(String(format: "%.0f", fiber))g fiber") }
            if let cal = result.totalCalories, cal > 0 { macros.append("\(String(format: "%.0f", cal)) cal") }
            if !macros.isEmpty {
                lines.append("Nutrition: \(macros.joined(separator: ", "))")
            }
            if let absorb = result.absorptionTimeHours {
                lines.append("Absorption time: \(String(format: "%.1f", absorb))h")
            }
        }

        lines.append("Pre-meal glucose: \(String(format: "%.0f", snapshot.preMealGlucose)) mg/dL")
        lines.append("")

        // Predicted glucose
        lines.append("Predicted glucose (from Loop at meal time):")
        let predSamples = snapshot.predictedValues
        let interval = snapshot.intervalSeconds
        for (i, value) in predSamples.enumerated() {
            let minutes = Int(Double(i) * interval / 60)
            if minutes <= 240 && (minutes % 30 == 0 || i == 0) {
                lines.append("  \(minutes)min: \(String(format: "%.0f", value))")
            }
        }

        lines.append("")

        // Actual glucose
        lines.append("Actual glucose:")
        for point in actualTimeline {
            if point.minutesAfter <= 240 && (point.minutesAfter % 30 == 0 || point.minutesAfter == 0) {
                lines.append("  \(point.minutesAfter)min: \(String(format: "%.0f", point.glucose))")
            }
        }

        // Historical pattern
        if let pattern = foodPattern {
            lines.append("")
            lines.append("Historical pattern for \(pattern.foodType) (\(pattern.mealCount) meals): avg peak +\(String(format: "%.0f", pattern.peakGlucoseRise)) mg/dL in \(String(format: "%.0f", pattern.timeToPeakMinutes)) min")
        }

        // Correction pattern context (if relevant to this food type)
        let behaviorPatterns = LoopInsights_BehaviorInsightsAnalyzer.analyzePatterns()
        let relevantPatterns = behaviorPatterns.filter { pattern in
            (pattern.groupingType == .foodType && mealRecord.foodType.localizedCaseInsensitiveContains(pattern.groupingValue)) ||
            (pattern.groupingType == .location && mealRecord.locationName?.localizedCaseInsensitiveContains(pattern.groupingValue) == true)
        }
        if !relevantPatterns.isEmpty {
            lines.append("")
            lines.append("Known correction patterns for this meal context:")
            for pattern in relevantPatterns.prefix(3) {
                lines.append("  • \(pattern.summaryDescription)")
            }
        }

        lines.append("")
        lines.append("Analyze: What happened vs what was predicted? What did the carbs effectively behave like? What should be learned for next time? Keep it under 5 sentences.")
        lines.append("")
        lines.append("IMPORTANT: End your response with a line starting with 'LEARNINGS:' followed by 2-3 short bullet points (one per line, each starting with '- '). These will be shown as takeaways.")

        return lines.joined(separator: "\n")
    }

    // MARK: - Response Parsing

    private func parseDebriefResponse(
        response: String,
        mealRecord: FoodFinder_AnalysisRecord,
        snapshot: LoopInsights_PredictionSnapshot,
        actualTimeline: [(minutesAfter: Int, glucose: Double)]
    ) -> LoopInsights_MealDebrief {
        // Split response into interpretation and learnings
        let parts = response.components(separatedBy: "LEARNINGS:")
        let interpretation = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)

        var learnings: [String] = []
        if parts.count > 1 {
            learnings = parts[1]
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.hasPrefix("- ") || $0.hasPrefix("* ") }
                .map { String($0.dropFirst(2)) }
        }

        // Calculate effective carbs estimate from response (look for pattern like "Xg of carbs" or "X grams")
        let effectiveCarbs = extractEffectiveCarbs(from: response)

        // Predicted peak from snapshot
        let predictedPeak = snapshot.predictedValues.max()

        // Actual peak from timeline
        let actualPeak = actualTimeline.max(by: { $0.glucose < $1.glucose })?.glucose

        // Peak timing delta
        var peakTimingDelta: Double?
        if let predPeakIdx = snapshot.predictedValues.firstIndex(where: { $0 == predictedPeak }),
           let actPeakPoint = actualTimeline.max(by: { $0.glucose < $1.glucose }) {
            let predictedPeakMinutes = Double(predPeakIdx) * snapshot.intervalSeconds / 60
            peakTimingDelta = Double(actPeakPoint.minutesAfter) - predictedPeakMinutes
        }

        return LoopInsights_MealDebrief(
            id: mealRecord.id,
            mealRecordID: mealRecord.id,
            generatedAt: Date(),
            effectiveCarbsEstimate: effectiveCarbs,
            aiInterpretation: interpretation,
            learnings: learnings.isEmpty ? ["Review your carb count for this meal type"] : learnings,
            predictedPeakGlucose: predictedPeak,
            actualPeakGlucose: actualPeak,
            peakTimingDeltaMinutes: peakTimingDelta
        )
    }

    /// Try to extract an "effective carbs" number from AI response text
    private func extractEffectiveCarbs(from text: String) -> Double? {
        // Match patterns like "behaved like 70g" or "effectively 70 grams" or "~70g of carbs"
        let patterns = [
            "behaved like[\\s~]*(\\d+\\.?\\d*)\\s*g",
            "effectively[\\s~]*(\\d+\\.?\\d*)\\s*g",
            "equivalent to[\\s~]*(\\d+\\.?\\d*)\\s*g",
            "acted as[\\s~]*(\\d+\\.?\\d*)\\s*g"
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               match.numberOfRanges > 1,
               let range = Range(match.range(at: 1), in: text),
               let value = Double(text[range]) {
                return value
            }
        }
        return nil
    }
}

// MARK: - Debrief Readiness

enum LoopInsights_DebriefReadiness: Equatable {
    case featureDisabled
    case noSnapshot                       // No prediction was captured at meal time
    case tooRecent(minutesRemaining: Int) // Meal is <2h old
    case readyToGenerate                  // Has snapshot, ≥2h old, not yet generated
    case ready                            // Already generated and cached
}
