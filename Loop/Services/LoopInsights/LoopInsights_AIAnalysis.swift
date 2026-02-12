//
//  LoopInsights_AIAnalysis.swift
//  Loop
//
//  Concept & design by Taylor Patterson. Coded & tested by Claude Code in February 2026.
//  Copyright (c) 2025-2026 LoopKit Authors. All rights reserved.
//

import Foundation

/// Builds structured prompts from aggregated data and current therapy settings,
/// sends them to the AI provider via AIServiceAdapter, and parses the structured
/// suggestions returned.
///
/// The "one thing at a time" guided tuning flow is enforced here:
/// CR first → verify improvement → ISF next → verify → Basal last.
final class LoopInsights_AIAnalysis {

    private let serviceAdapter: LoopInsights_AIServiceAdapter

    init(serviceAdapter: LoopInsights_AIServiceAdapter = .shared) {
        self.serviceAdapter = serviceAdapter
    }

    // MARK: - Public API

    /// Perform AI analysis for a specific setting type
    func analyze(
        settingType: LoopInsightsSettingType,
        currentSettings: LoopInsightsTherapySnapshot,
        stats: LoopInsightsAggregatedStats
    ) async throws -> LoopInsightsAnalysisResponse {
        let systemPrompt = buildSystemPrompt()
        let userPrompt = buildUserPrompt(settingType: settingType, settings: currentSettings, stats: stats)

        let rawResponse = try await serviceAdapter.sendPrompt(systemPrompt, userPrompt: userPrompt)

        return try parseResponse(rawResponse: rawResponse, settingType: settingType, period: stats.period)
    }

    // MARK: - System Prompt

    private func buildSystemPrompt() -> String {
        let personality = LoopInsights_FeatureFlags.aiPersonality
        return """
        You are LoopInsights, an AI therapy settings advisor for people using insulin pump therapy \
        with automated insulin delivery (AID) systems. Your role is to analyze glucose, insulin, and \
        carbohydrate data to suggest therapy setting adjustments that improve Time in Range (TIR).

        \(personality.promptInstruction)

        CRITICAL SAFETY RULES:
        1. Never suggest changes larger than 20% from current values in a single adjustment.
        2. Always suggest conservative changes — it's better to under-adjust than over-adjust.
        3. Focus on one setting type at a time (Carb Ratio OR Insulin Sensitivity OR Basal Rate).
        4. Consider time-of-day patterns — different hours may need different adjustments.
        5. Flag any concerning patterns (frequent lows, extreme highs) prominently.
        6. Your suggestions are advisory only — the user makes the final decision.

        TUNING ORDER (one at a time):
        1. Carb Ratio (CR) — adjust first, as incorrect CR causes the most post-meal variability
        2. Insulin Sensitivity Factor (ISF) — adjust second, affects correction doses
        3. Basal Rate (BR) — adjust last, as basal changes affect the entire 24-hour profile

        RESPONSE FORMAT:
        You MUST respond with valid JSON in this exact structure:
        {
            "suggestions": [
                {
                    "time_blocks": [
                        {
                            "start_seconds": 0,
                            "end_seconds": 21600,
                            "current_value": 10.0,
                            "proposed_value": 11.0
                        }
                    ],
                    "reasoning": "Explanation of why this change is recommended",
                    "confidence": "low|medium|high"
                }
            ],
            "overall_assessment": "Brief summary of the analysis findings",
            "next_recommended_focus": "carb_ratio|insulin_sensitivity|basal_rate|null"
        }

        Time blocks use seconds since midnight (0 = 12:00 AM, 21600 = 6:00 AM, 43200 = 12:00 PM, etc.)
        Only suggest changes for time blocks where adjustment is warranted. If a time block is fine, omit it.
        """
    }

    // MARK: - User Prompt

    private func buildUserPrompt(
        settingType: LoopInsightsSettingType,
        settings: LoopInsightsTherapySnapshot,
        stats: LoopInsightsAggregatedStats
    ) -> String {
        var prompt = "Analyze my \(settingType.displayName) settings and suggest adjustments.\n\n"

        // Current settings
        prompt += "## Current \(settingType.displayName) Schedule\n"
        let items: [LoopInsightsTherapySnapshot.LoopInsightsScheduleItem]
        let unit: String

        switch settingType {
        case .carbRatio:
            items = settings.carbRatioItems
            unit = "g/U"
        case .insulinSensitivity:
            items = settings.insulinSensitivityItems
            unit = "mg/dL per U"
        case .basalRate:
            items = settings.basalRateItems
            unit = "U/hr"
        }

        for item in items {
            let timeStr = formatTime(item.startTime)
            prompt += "- \(timeStr): \(String(format: "%.1f", item.value)) \(unit)\n"
        }

        // Glucose stats
        prompt += "\n## Glucose Statistics (\(stats.period.displayName))\n"
        prompt += "- Average Glucose: \(String(format: "%.0f", stats.glucoseStats.averageGlucose)) mg/dL\n"
        prompt += "- Standard Deviation: \(String(format: "%.0f", stats.glucoseStats.standardDeviation)) mg/dL\n"
        prompt += "- Coefficient of Variation: \(String(format: "%.1f", stats.glucoseStats.coefficientOfVariation))%\n"
        prompt += "- Time in Range (70-180): \(String(format: "%.1f", stats.glucoseStats.timeInRange))%\n"
        prompt += "- Time Below Range (<70): \(String(format: "%.1f", stats.glucoseStats.timeBelowRange))%\n"
        prompt += "- Time Above Range (>180): \(String(format: "%.1f", stats.glucoseStats.timeAboveRange))%\n"
        prompt += "- GMI (est. A1C): \(String(format: "%.1f", stats.glucoseStats.gmi))%\n"
        prompt += "- Sample Count: \(stats.glucoseStats.sampleCount)\n"

        // Hourly glucose pattern
        prompt += "\n### Hourly Average Glucose\n"
        for hour in 0..<24 {
            if let avg = stats.glucoseStats.hourlyAverages[hour] {
                prompt += "- \(String(format: "%02d", hour)):00: \(String(format: "%.0f", avg)) mg/dL\n"
            }
        }

        // Insulin stats
        prompt += "\n## Insulin Statistics\n"
        prompt += "- Total Daily Dose: \(String(format: "%.1f", stats.insulinStats.totalDailyDose)) U/day\n"
        prompt += "- Basal: \(String(format: "%.0f", stats.insulinStats.basalPercentage))% / Bolus: \(String(format: "%.0f", stats.insulinStats.bolusPercentage))%\n"
        prompt += "- Correction Boluses: \(stats.insulinStats.correctionBolusCount) in period\n"

        // Carb stats
        prompt += "\n## Carbohydrate Statistics\n"
        prompt += "- Average Daily Carbs: \(String(format: "%.0f", stats.carbStats.averageDailyCarbs)) g/day\n"
        prompt += "- Meals Logged: \(stats.carbStats.mealCount)\n"
        prompt += "- Average Carbs per Meal: \(String(format: "%.0f", stats.carbStats.averageCarbsPerMeal)) g\n"

        prompt += "\nPlease analyze this data and suggest adjustments to my \(settingType.displayName) settings. "
        prompt += "Respond with JSON only, no markdown formatting."

        return prompt
    }

    // MARK: - Response Parsing

    private func parseResponse(rawResponse: String, settingType: LoopInsightsSettingType, period: LoopInsightsAnalysisPeriod) throws -> LoopInsightsAnalysisResponse {
        // Extract JSON from the response (AI might wrap it in markdown code blocks)
        let jsonString = extractJSON(from: rawResponse)

        guard let data = jsonString.data(using: .utf8) else {
            throw LoopInsightsError.parseError("Unable to convert response to data")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LoopInsightsError.parseError("Response is not valid JSON: \(rawResponse.prefix(200))")
        }

        // Parse suggestions
        guard let suggestionsArray = json["suggestions"] as? [[String: Any]] else {
            throw LoopInsightsError.parseError("Missing 'suggestions' array in response")
        }

        var suggestions: [LoopInsightsSuggestion] = []

        for suggestionJSON in suggestionsArray {
            guard let timeBlocksArray = suggestionJSON["time_blocks"] as? [[String: Any]],
                  let reasoning = suggestionJSON["reasoning"] as? String,
                  let confidenceRaw = suggestionJSON["confidence"] as? String,
                  let confidence = LoopInsightsConfidence(rawValue: confidenceRaw) else {
                continue
            }

            let timeBlocks = timeBlocksArray.compactMap { block -> LoopInsightsTimeBlock? in
                guard let startSeconds = block["start_seconds"] as? Double,
                      let endSeconds = block["end_seconds"] as? Double,
                      let currentValue = block["current_value"] as? Double,
                      let proposedValue = block["proposed_value"] as? Double else {
                    return nil
                }
                return LoopInsightsTimeBlock(
                    startTime: startSeconds,
                    endTime: endSeconds,
                    currentValue: currentValue,
                    proposedValue: proposedValue
                )
            }

            guard !timeBlocks.isEmpty else { continue }

            let suggestion = LoopInsightsSuggestion(
                id: UUID(),
                settingType: settingType,
                timeBlocks: timeBlocks,
                reasoning: reasoning,
                confidence: confidence,
                analysisPeriod: period,
                createdAt: Date()
            )
            suggestions.append(suggestion)
        }

        let overallAssessment = json["overall_assessment"] as? String ?? "Analysis complete."

        var nextFocus: LoopInsightsSettingType? = nil
        if let nextRaw = json["next_recommended_focus"] as? String {
            nextFocus = LoopInsightsSettingType(rawValue: nextRaw)
        }

        return LoopInsightsAnalysisResponse(
            suggestions: suggestions,
            overallAssessment: overallAssessment,
            nextRecommendedFocus: nextFocus,
            rawResponse: rawResponse
        )
    }

    // MARK: - Helpers

    private func extractJSON(from text: String) -> String {
        // Try to find JSON block in markdown code fences
        if let jsonRange = text.range(of: "```json\n"),
           let endRange = text.range(of: "\n```", range: jsonRange.upperBound..<text.endIndex) {
            return String(text[jsonRange.upperBound..<endRange.lowerBound])
        }

        // Try to find JSON block in plain code fences
        if let jsonRange = text.range(of: "```\n"),
           let endRange = text.range(of: "\n```", range: jsonRange.upperBound..<text.endIndex) {
            return String(text[jsonRange.upperBound..<endRange.lowerBound])
        }

        // Try to find raw JSON object
        if let start = text.firstIndex(of: "{"),
           let end = text.lastIndex(of: "}") {
            return String(text[start...end])
        }

        return text
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let period = hours >= 12 ? "PM" : "AM"
        let displayHour = hours == 0 ? 12 : (hours > 12 ? hours - 12 : hours)
        return String(format: "%d:%02d %@", displayHour, minutes, period)
    }
}
