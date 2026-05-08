//
//  AutoPresets_AIAdvisor.swift
//  Loop
//
//  AutoPresets — AI service that analyzes patterns and recommends new override presets.
//
//  Idea by Taylor Patterson. Coded by Claude Code.
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit
import HealthKit

/// Analyzes glucose/insulin/meal patterns via AI and recommends new override presets.
/// Uses LoopInsights infrastructure (data aggregator, AI adapter) with a preset-focused prompt.
final class AutoPresets_AIAdvisor {

    private let coordinator: LoopInsights_Coordinator

    init(coordinator: LoopInsights_Coordinator) {
        self.coordinator = coordinator
    }

    // MARK: - Public API

    /// Analyze data for the given period and generate preset recommendations.
    /// If the requested period has insufficient data, automatically falls back to
    /// longer periods until data is found.
    func generateRecommendations(period: LoopInsightsAnalysisPeriod) async throws -> AutoPresetsAIResponse {
        // 1. Aggregate data (fall back to longer periods if needed)
        let stats = try await aggregateWithFallback(period: period)

        // 2. Capture therapy snapshot
        let snapshot = try coordinator.captureCurrentSnapshot()

        // 3. Get existing presets
        let existingPresets = AutoPresets_Coordinator.shared.availablePresets()

        // 4. Build supplemental context
        let supplemental = await coordinator.buildSupplementalContext(
            stats: stats,
            glucoseSamples: coordinator.dataAggregator.lastFetchedGlucoseSamples,
            carbEntries: coordinator.dataAggregator.lastFetchedCarbEntries
        )

        // 5. Build prompts
        let systemPrompt = buildSystemPrompt()
        let userPrompt = buildUserPrompt(
            stats: stats,
            snapshot: snapshot,
            existingPresets: existingPresets,
            supplementalContext: supplemental
        )

        // 6. Call AI
        let rawResponse = try await LoopInsights_AIServiceAdapter.shared.sendPrompt(
            systemPrompt,
            userPrompt: userPrompt
        )

        // 7. Parse and validate
        let response = try parseResponse(rawResponse)
        return response
    }

    // MARK: - System Prompt

    private func buildSystemPrompt() -> String {
        let unitContext = AutoPresets_Coordinator.shared.unitContext
        let jsonFieldClarification = """

        JSON FIELD UNITS — IMPORTANT:
        Although prose in the `reasoning` and `overall_assessment` fields must use the user's unit,
        the JSON fields `target_range_low_mgdl` and `target_range_high_mgdl` MUST ALWAYS contain
        values in mg/dL — they are canonical storage fields. Convert from your prose unit to mg/dL
        before populating those fields. The app converts back to the user's unit for display.
        """
        return """
        \(unitContext.aiPromptUnitContext())
        \(jsonFieldClarification)

        You are a friendly, expert diabetes management advisor specializing in Loop's override \
        preset system. You are speaking DIRECTLY to the user — always use "you" and "your" \
        (never "this person", "the person", "the user", or "they"). Be warm, personal, and \
        conversational while remaining clinically precise.

        Your job is to analyze the user's glucose, insulin, meal, and activity patterns and ONLY \
        recommend new override presets when their data shows clear, recurring situations that \
        Loop's normal algorithm cannot adequately handle on its own.

        WHAT OVERRIDES DO — THIS IS CRITICAL:
        An override simultaneously scales THREE therapy settings for the entire duration:
        - Basal rates (scaled by insulinNeedsScaleFactor)
        - Insulin Sensitivity Factor / ISF (scaled inversely — higher insulin needs = lower ISF)
        - Carb Ratio / CR (scaled inversely — higher insulin needs = lower CR, meaning more insulin per carb)
        This is NOT just a basal rate change. Setting 150% insulin needs means 50% more basal, \
        50% more aggressive corrections, AND 50% more insulin per gram of carbs. This is a powerful \
        tool that should only be used for situations where ALL insulin needs genuinely change.

        An override can also set a temporary target range, replacing the normal correction range. \
        A higher target (e.g., 140-160) makes Loop less aggressive. A lower target makes it more aggressive.

        WHEN OVERRIDES ARE APPROPRIATE — STRICT CRITERIA:
        Only recommend a preset if ALL of these are true:
        1. The pattern occurs REPEATEDLY (at least 3+ occurrences in the data period)
        2. The pattern causes glucose outcomes that Loop's normal algorithm fails to manage
        3. The situation involves a genuine change in insulin sensitivity or physiology, not just \
           a food/meal that could be handled with normal carb counting and bolusing
        4. The preset would be activated BEFORE or AT THE START of the situation (not reactive)

        LEGITIMATE USE CASES (recommend ONLY for these categories):
        - EXERCISE: Sustained physical activity where insulin sensitivity increases significantly. \
          Reduce insulin needs (e.g., 60-85%) and/or raise targets (e.g., 140-160 mg/dL). \
          NEVER increase insulin for exercise. Data must show repeated exercise sessions with lows.
        - ILLNESS / SICK DAYS: Periods where insulin resistance increases markedly. \
          Increase insulin needs (e.g., 120-150%). Data must show repeated multi-day high patterns.
        - HORMONAL CHANGES: Menstrual cycle phases, steroid medications, or other hormonal shifts \
          that consistently alter insulin sensitivity. Data must show a recurring multi-day pattern.
        - DAWN PHENOMENON / TIME-OF-DAY: Consistent early-morning rises or overnight patterns \
          that Loop's normal scheduled basal rates don't adequately cover. Data must show this \
          pattern on the majority of days (not just occasionally).
        - SUSTAINED HIGH-FAT/HIGH-PROTEIN MEALS: Only if the data shows a REPEATED pattern of \
          specific meal types (e.g., regular pizza nights, daily high-fat breakfast) causing \
          prolonged glucose elevation that persists well beyond normal meal bolus duration (4+ hours). \
          You must encounter this meal pattern frequently enough to justify a preset.

        DO NOT RECOMMEND PRESETS FOR:
        - Occasional dietary events (a few beers, one pizza, an occasional treat)
        - Standard meals that can be handled with proper carb counting and bolusing
        - One-off situations or infrequent occurrences (fewer than 3 occurrences)
        - Caffeine or alcohol consumption (Loop handles these through normal adjustments)
        - Situations where the data doesn't clearly show Loop struggling to maintain targets
        - Patterns already well-covered by existing presets (check the data)

        SAFETY GUARDRAILS:
        - insulinNeedsScaleFactor: \(AutoPresetsAdvisorGuardrails.minInsulinScale) to \(AutoPresetsAdvisorGuardrails.maxInsulinScale)
        - Target range low: \(Int(AutoPresetsAdvisorGuardrails.minTargetLow))-\(Int(AutoPresetsAdvisorGuardrails.maxTargetLow)) mg/dL
        - Target range high: \(Int(AutoPresetsAdvisorGuardrails.minTargetHigh))-\(Int(AutoPresetsAdvisorGuardrails.maxTargetHigh)) mg/dL
        - Duration: \(AutoPresetsAdvisorGuardrails.minDurationMinutes)-\(AutoPresetsAdvisorGuardrails.maxDurationMinutes) minutes
        - Exercise presets: insulin scale must be ≤ 1.0 (raise target instead)
        - Maximum 3 recommendations. It is BETTER to return 0 recommendations than to suggest \
          a preset that isn't clearly supported by the data. Quality over quantity.

        TONE AND VOICE:
        - Always address the user as "you" — e.g., "Your data shows...", "I noticed you tend to..."
        - NEVER say "this person", "the person", "the user", or "they" when referring to the user
        - Be encouraging and supportive — e.g., "Your exercise routine is great for your control"
        - Be direct about what you found — e.g., "I found a clear pattern in your morning data"
        - Keep it concise but personal

        RESPONSE FORMAT:
        Respond with ONLY valid JSON (no markdown, no code fences, no explanation outside JSON):
        {
          "recommendations": [
            {
              "name": "Short descriptive name (2-4 words)",
              "symbol": "Single emoji that represents this preset",
              "reasoning": "2-3 sentences speaking directly to the user explaining the pattern \
                you found in their data, how many times it occurred, and why Loop can't handle it. \
                Use 'you/your' — e.g., 'I noticed your glucose consistently rises...'",
              "confidence": "high|medium|low",
              "insulin_needs_scale": 0.7,
              "target_range_low_mgdl": 140,
              "target_range_high_mgdl": 160,
              "duration_minutes": 120,
              "trigger_context": "exercise|timeOfDay|meal|dayOfWeek",
              "pattern_description": "One sentence describing when to activate — e.g., \
                'Activate before your morning workout to prevent lows'"
            }
          ],
          "overall_assessment": "1-2 sentences speaking directly to the user about their data \
            patterns and preset coverage — e.g., 'Your data shows solid time in range, but I \
            noticed a consistent pattern that could benefit from a preset.'"
        }

        FIELD RULES:
        - insulin_needs_scale: null if only adjusting target, or a value like 0.7 (less insulin) \
          or 1.3 (more insulin). Remember this affects basal AND bolus calculations.
        - target_range_low_mgdl / target_range_high_mgdl: Both must be set together or both null. \
          For exercise presets, ALWAYS include a raised target range (e.g., 140-160). \
          For most presets, include a target range — it's rare that only insulin scaling is needed.
        - At least one of insulin_needs_scale or target range must be non-null.
        - confidence: "high" only if 5+ clear occurrences, "medium" for 3-4, "low" should not \
          be recommended (return empty instead).

        If the data doesn't clearly support any new presets, return an empty recommendations array \
        with an overall_assessment speaking directly to the user — e.g., "Your current presets \
        are covering your patterns well. I didn't find any recurring situations that would benefit \
        from a new preset."
        """
    }

    // MARK: - User Prompt

    private func buildUserPrompt(
        stats: LoopInsightsAggregatedStats,
        snapshot: LoopInsightsTherapySnapshot,
        existingPresets: [TemporaryScheduleOverridePreset],
        supplementalContext: String?
    ) -> String {
        var prompt = ""

        // Therapy context (reuse ChatViewModel's builder)
        prompt += LoopInsights_ChatViewModel.buildTherapyContext(snapshot: snapshot, stats: stats)

        // Existing presets
        prompt += "\nEXISTING OVERRIDE PRESETS:\n"
        if existingPresets.isEmpty {
            prompt += "  (none configured)\n"
        } else {
            for preset in existingPresets {
                prompt += "  \(preset.symbol) \(preset.name)"
                if let scale = preset.settings.insulinNeedsScaleFactor {
                    prompt += " — insulin needs \(String(format: "%.0f", scale * 100))%"
                }
                if let range = preset.settings.targetRange {
                    let low = range.lowerBound.doubleValue(for: .milligramsPerDeciliter)
                    let high = range.upperBound.doubleValue(for: .milligramsPerDeciliter)
                    prompt += ", target \(String(format: "%.0f", low))-\(String(format: "%.0f", high)) mg/dL"
                }
                switch preset.duration {
                case .finite(let interval):
                    let minutes = Int(interval / 60)
                    prompt += ", \(minutes) min"
                case .indefinite:
                    prompt += ", indefinite"
                }
                prompt += "\n"
            }
        }

        // Hourly meal frequency for pattern detection
        if !stats.carbStats.hourlyMealFrequency.isEmpty {
            prompt += "\nMEAL TIMING PATTERNS (hourly frequency):\n"
            for hour in 0..<24 {
                if let freq = stats.carbStats.hourlyMealFrequency[hour], freq > 0 {
                    prompt += "  \(String(format: "%02d", hour)):00 — \(String(format: "%.1f", freq)) meals/day\n"
                }
            }
        }

        // Supplemental context (caffeine, alcohol, food patterns, circadian)
        if let supplemental = supplementalContext {
            prompt += "\n\(supplemental)"
        }

        prompt += "\nAnalyze my data for RECURRING patterns (3+ clear occurrences) where Loop's "
        prompt += "normal algorithm struggles. Only recommend override presets for genuine changes in "
        prompt += "insulin sensitivity (exercise, illness, hormonal, consistent time-of-day). "
        prompt += "Do NOT recommend presets for occasional dietary events or situations that normal "
        prompt += "carb counting and bolusing can handle. For each recommendation, include both "
        prompt += "insulin_needs_scale AND target_range when appropriate. "
        prompt += "Remember to speak directly to me using 'you' and 'your'."

        return prompt
    }

    // MARK: - Response Parsing

    private func parseResponse(_ raw: String) throws -> AutoPresetsAIResponse {
        // Strip markdown fences if present
        let cleaned = raw
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = cleaned.data(using: .utf8) else {
            throw AutoPresetsAdvisorError.invalidResponse("Response is not valid UTF-8")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AutoPresetsAdvisorError.invalidResponse("Response is not valid JSON")
        }

        let overallAssessment = json["overall_assessment"] as? String ?? ""

        guard let rawRecs = json["recommendations"] as? [[String: Any]] else {
            return AutoPresetsAIResponse(recommendations: [], overallAssessment: overallAssessment)
        }

        var recommendations: [AutoPresetsRecommendation] = []

        for rawRec in rawRecs {
            guard let name = rawRec["name"] as? String,
                  let symbol = rawRec["symbol"] as? String,
                  let reasoning = rawRec["reasoning"] as? String,
                  let confidenceStr = rawRec["confidence"] as? String,
                  let triggerStr = rawRec["trigger_context"] as? String,
                  let patternDesc = rawRec["pattern_description"] as? String,
                  let durationMinutes = rawRec["duration_minutes"] as? Int
            else {
                continue
            }

            let confidence = AutoPresetsRecommendationConfidence(rawValue: confidenceStr) ?? .low
            let trigger = AutoPresetsTriggerContext(rawValue: triggerStr) ?? .meal

            let insulinScale = rawRec["insulin_needs_scale"] as? Double
            let targetLow = rawRec["target_range_low_mgdl"] as? Double
            let targetHigh = rawRec["target_range_high_mgdl"] as? Double

            let rec = AutoPresetsRecommendation(
                name: name,
                symbol: symbol,
                reasoning: reasoning,
                confidence: confidence,
                insulinNeedsScale: insulinScale,
                targetRangeLowMgdl: targetLow,
                targetRangeHighMgdl: targetHigh,
                durationMinutes: durationMinutes,
                triggerContext: trigger,
                patternDescription: patternDesc
            )

            // Validate against guardrails
            if let validated = validateRecommendation(rec) {
                recommendations.append(validated)
            }
        }

        return AutoPresetsAIResponse(
            recommendations: recommendations,
            overallAssessment: overallAssessment
        )
    }

    // MARK: - Validation

    /// Clamp values to safety guardrails. Returns nil if recommendation is fundamentally invalid.
    private func validateRecommendation(_ rec: AutoPresetsRecommendation) -> AutoPresetsRecommendation? {
        var insulinScale = rec.insulinNeedsScale
        var targetLow = rec.targetRangeLowMgdl
        var targetHigh = rec.targetRangeHighMgdl
        let duration = max(
            AutoPresetsAdvisorGuardrails.minDurationMinutes,
            min(rec.durationMinutes, AutoPresetsAdvisorGuardrails.maxDurationMinutes)
        )

        // Clamp insulin scale
        if let scale = insulinScale {
            insulinScale = max(AutoPresetsAdvisorGuardrails.minInsulinScale,
                               min(scale, AutoPresetsAdvisorGuardrails.maxInsulinScale))
        }

        // Safety: exercise patterns must not increase insulin
        if rec.triggerContext == .exercise, let scale = insulinScale, scale > 1.0 {
            insulinScale = 1.0
        }

        // Clamp target range
        if let low = targetLow {
            targetLow = max(AutoPresetsAdvisorGuardrails.minTargetLow,
                            min(low, AutoPresetsAdvisorGuardrails.maxTargetLow))
        }
        if let high = targetHigh {
            targetHigh = max(AutoPresetsAdvisorGuardrails.minTargetHigh,
                             min(high, AutoPresetsAdvisorGuardrails.maxTargetHigh))
        }

        // Ensure low ≤ high
        if let low = targetLow, let high = targetHigh, low > high {
            targetLow = high
        }

        // Must have at least one adjustment
        if insulinScale == nil && targetLow == nil && targetHigh == nil {
            return nil
        }

        // Filter out low-confidence recommendations — not enough data to justify a preset
        if rec.confidence == .low {
            return nil
        }

        return AutoPresetsRecommendation(
            name: rec.name,
            symbol: rec.symbol,
            reasoning: rec.reasoning,
            confidence: rec.confidence,
            insulinNeedsScale: insulinScale,
            targetRangeLowMgdl: targetLow,
            targetRangeHighMgdl: targetHigh,
            durationMinutes: duration,
            triggerContext: rec.triggerContext,
            patternDescription: rec.patternDescription
        )
    }

    // MARK: - Data Aggregation with Fallback

    /// Try to aggregate data for the requested period. If that fails due to
    /// insufficient data, progressively try longer periods.
    private func aggregateWithFallback(period: LoopInsightsAnalysisPeriod) async throws -> LoopInsightsAggregatedStats {
        let allPeriods: [LoopInsightsAnalysisPeriod] = [.threeDays, .sevenDays, .fourteenDays, .thirtyDays, .ninetyDays]

        // Start from the requested period and try progressively longer ones
        let startIndex = allPeriods.firstIndex(of: period) ?? 0
        var lastError: Error?

        for i in startIndex..<allPeriods.count {
            do {
                return try await coordinator.dataAggregator.aggregateData(period: allPeriods[i])
            } catch let error as LoopInsightsError {
                if case .insufficientData = error {
                    lastError = error
                    continue
                }
                throw error
            }
        }

        throw lastError ?? AutoPresetsAdvisorError.noData
    }

    // MARK: - Preset Creation

    /// Convert a recommendation into a LoopKit TemporaryScheduleOverridePreset
    static func createPreset(from recommendation: AutoPresetsRecommendation) -> TemporaryScheduleOverridePreset {
        var targetRange: ClosedRange<HKQuantity>?
        if let low = recommendation.targetRangeLowMgdl, let high = recommendation.targetRangeHighMgdl {
            let lowQ = HKQuantity(unit: .milligramsPerDeciliter, doubleValue: low)
            let highQ = HKQuantity(unit: .milligramsPerDeciliter, doubleValue: high)
            targetRange = lowQ...highQ
        }

        let settings = TemporaryScheduleOverrideSettings(
            targetRange: targetRange,
            insulinNeedsScaleFactor: recommendation.insulinNeedsScale
        )

        let durationSeconds = TimeInterval(recommendation.durationMinutes * 60)

        return TemporaryScheduleOverridePreset(
            symbol: recommendation.symbol,
            name: recommendation.name,
            settings: settings,
            duration: .finite(durationSeconds)
        )
    }
}

// MARK: - Errors

enum AutoPresetsAdvisorError: LocalizedError {
    case invalidResponse(String)
    case noData

    var errorDescription: String? {
        switch self {
        case .invalidResponse(let detail): return "Invalid AI response: \(detail)"
        case .noData: return "Not enough data to analyze"
        }
    }
}
