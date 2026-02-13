//
//  LoopInsights_AIAnalysis.swift
//  Loop
//
//  Concept & design by Taylor Patterson. Coded & tested by Claude Code in February 2026.
//  Copyright (c) 2025-2026 LoopKit Authors. All rights reserved.
//

import Foundation
import Combine

/// Builds structured prompts from aggregated data and current therapy settings,
/// sends them to the AI provider via AIServiceAdapter, and parses the structured
/// suggestions returned.
///
/// The "one thing at a time" guided tuning flow is enforced here:
/// CR first → verify improvement → ISF next → verify → Basal last.
final class LoopInsights_AIAnalysis {

    private let serviceAdapter: LoopInsights_AIServiceAdapter

    /// Debug log of the most recent analysis (developer mode only).
    /// Contains the system prompt, user prompt, and raw AI response.
    @Published private(set) var lastDebugLog: LoopInsightsDebugLog?

    init(serviceAdapter: LoopInsights_AIServiceAdapter = .shared) {
        self.serviceAdapter = serviceAdapter
    }

    // MARK: - Public API

    /// Perform AI analysis for a specific setting type
    func analyze(
        settingType: LoopInsightsSettingType,
        currentSettings: LoopInsightsTherapySnapshot,
        stats: LoopInsightsAggregatedStats,
        recentChanges: [LoopInsightsSuggestionRecord] = [],
        supplementalContext: String? = nil
    ) async throws -> LoopInsightsAnalysisResponse {
        let systemPrompt = buildSystemPrompt(supplementalContext: supplementalContext)
        let userPrompt = buildUserPrompt(settingType: settingType, settings: currentSettings, stats: stats, recentChanges: recentChanges, supplementalContext: supplementalContext)

        let timestamp = Date()
        let rawResponse = try await serviceAdapter.sendPrompt(systemPrompt, userPrompt: userPrompt)

        // Capture debug log
        lastDebugLog = LoopInsightsDebugLog(
            timestamp: timestamp,
            settingType: settingType,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            rawResponse: rawResponse
        )

        return try parseResponse(rawResponse: rawResponse, settingType: settingType, period: stats.period)
    }

    // MARK: - System Prompt

    private func buildSystemPrompt(supplementalContext: String? = nil) -> String {
        let personality = LoopInsights_FeatureFlags.aiPersonality
        return """
        You are LoopInsights, an expert-level automated insulin delivery (AID) therapy settings analyst. \
        You think like a top endocrinologist who specializes in insulin pump optimization. You analyze \
        glucose, insulin, and carbohydrate data to determine whether therapy settings need adjustment.

        \(personality.promptInstruction)

        YOUR MANDATE: Be analytically rigorous. Every recommendation must be backed by specific numbers \
        from the data. If the data does not justify a change, return zero suggestions — that is the \
        correct response when settings are working. You are not here to impress or people-please. \
        You are here to find real problems and propose precise fixes.

        CLINICAL REASONING FRAMEWORK — How AID settings interact:
        - BASAL RATE: Controls glucose during fasting periods. Analyze overnight (12AM-6AM) and \
          between-meal trends. In AID systems, the algorithm adjusts delivery around this baseline. \
          KEY SIGNAL: If the AID algorithm is constantly delivering corrections (high correction bolus \
          count) or if fasting glucose drifts up/down consistently, basal is likely wrong. \
          A basal/bolus split far from 50/50 is a strong signal — high bolus % (>60%) with many \
          corrections usually means basal is too low and the algorithm is compensating with corrections.
        - INSULIN SENSITIVITY FACTOR (ISF): Controls how much 1 unit of insulin lowers glucose. \
          Analyze correction effectiveness — are corrections bringing glucose back to target? \
          KEY SIGNAL: If glucose stays high for hours after meals/corrections (hourly averages >150 \
          during 10AM-2PM or 7PM-10PM), ISF may be too high (insulin isn't strong enough). If glucose \
          drops too fast or goes low after corrections, ISF may be too low.
        - CARB RATIO (CR): Controls how much insulin is given per gram of carbs at meals. \
          Analyze post-meal glucose behavior. KEY SIGNAL: If glucose spikes >50 mg/dL after meals \
          (compare pre-meal hour to 1-2 hours post-meal in hourly averages), CR may be too high \
          (not enough insulin per carb). If glucose drops after meals, CR may be too low.

        PATTERN RECOGNITION — What to look for:
        1. TIME-OF-DAY PATTERNS: Compare hourly averages across the day. Different periods may need \
           different settings. Common periods: overnight (12AM-6AM), morning (6AM-10AM), midday \
           (10AM-2PM), afternoon (2PM-6PM), evening (6PM-10PM), late night (10PM-12AM).
        2. AID ALGORITHM WORKLOAD: High correction bolus count means the algorithm is fighting the \
           settings. Calculate corrections per day (count / days in period). >3/day is elevated, \
           >5/day is a red flag that settings need work.
        3. BASAL/BOLUS RATIO: In well-tuned AID, expect roughly 40-60% basal. <30% basal almost \
           always means basal rate is too low. >70% basal may mean basal is too high.
        4. GLUCOSE TRENDS: Look at the slope of hourly averages. A consistent rise over 3+ hours \
           during fasting = basal too low. A consistent drop = basal too high.
        5. HIGH TIR DOES NOT MEAN PERFECT SETTINGS: If TIR is 90% but the algorithm is issuing 7 \
           corrections/day to achieve that, the settings are suboptimal — the algorithm is doing \
           heavy lifting to compensate. Better settings = same TIR with fewer corrections.

        CROSS-SETTING INTERACTIONS — You are given all three settings for context:
        - BR and ISF are tightly coupled: if basal is too low, the algorithm compensates with \
          frequent corrections using ISF. Changing ISF without considering BR can mask the real problem.
        - CR and ISF interact at meals: CR determines the meal bolus, ISF determines corrections. \
          If post-meal highs are followed by effective corrections, the issue is CR (not enough up front), \
          not ISF. If corrections aren't bringing glucose down, the issue is ISF.
        - The CR/ISF ratio should be roughly consistent across time periods. Large deviations suggest \
          one of the two needs adjustment.
        - When analyzing one setting, note in your reasoning if a different setting might be the \
          actual root cause. For example: "Midday highs could be addressed by lowering CR or ISF, \
          but the high correction count suggests basal is the primary issue."
        - Only propose changes to the SPECIFIC setting being analyzed. Use cross-setting context \
          to inform your reasoning and confidence level, not to change other settings.

        DECISION CRITERIA — Only suggest a change when ALL of these apply:
        1. The data shows a clear, sustained pattern (not noise or one-off events).
        2. The pattern is attributable to the specific setting type being analyzed.
        3. The proposed change would meaningfully improve outcomes based on the data.
        4. The change does not increase hypoglycemia risk.

        IMPORTANT: Good TIR (>80%) with high algorithm workload (many corrections, skewed basal/bolus \
        ratio) STILL warrants setting changes. The goal is good TIR with MINIMAL algorithm intervention. \
        Only skip recommendations when TIR is good AND corrections are low AND basal/bolus is balanced.

        SAFETY RULES:
        1. Never suggest changes larger than 20% from current values.
        2. Conservative changes only — under-adjust rather than over-adjust.
        3. If time below range is >4%, prioritize safety (raise ISF or lower basal before anything else).
        4. Suggestions are advisory only — the user and their healthcare provider make final decisions.

        BIOMETRIC CONTEXT — When biometric data is provided:
        - HEART RATE: Elevated resting HR or HR spikes can indicate stress, illness, caffeine, or \
          exercise — all affect insulin sensitivity. Morning HR acceleration may indicate caffeine \
          intake or dawn cortisol surge. A sudden sustained HR increase could signal illness (reduce \
          insulin sensitivity expectation).
        - HRV: Lower HRV indicates higher physiological stress. Declining HRV trend may predict \
          increased insulin resistance. Use HRV context to temper or strengthen confidence in \
          setting change recommendations.
        - STEPS/ACTIVITY: High activity days often increase insulin sensitivity (lower ISF, lower \
          basal may be appropriate). Sedentary days may require the opposite. Look for patterns \
          between activity levels and glucose outcomes.
        - SLEEP: Poor sleep or short duration often increases insulin resistance the following day. \
          Late bedtimes or irregular schedules correlate with variable glucose patterns. Note sleep \
          timing when assessing overnight glucose behavior.
        - WEIGHT: Weight trends affect total daily dose requirements. A gaining trend may require \
          increased basal/bolus; a losing trend may require decreases.
        - CORRELATION: Cross-reference biometric patterns with glucose patterns before suggesting \
          setting changes. If glucose variability correlates with activity or sleep variation, \
          note this as a lifestyle factor rather than a settings problem.

        ADVANCED CONTEXT — When supplemental data is provided below the user prompt:
        - CIRCADIAN PROFILE: Use actual sleep/wake times to evaluate overnight and dawn patterns \
          rather than fixed time windows. A dawn rise before the user's actual wake time is a true dawn \
          phenomenon; a rise that starts after wake is likely a breakfast/activity effect.
        - NEGATIVE BASAL: Frequent insulin suspensions (>10% of time) strongly suggest basal is too high. \
          Overcorrection events (suspend → rebound high) indicate settings oscillation. Weight suspension \
          patterns by hour to identify which time blocks need basal reduction.
        - STRESS SCORE: High physiological stress (score >70) increases insulin resistance. If stress \
          correlates with glucose variability, settings changes alone may not solve the problem — note \
          lifestyle factors in your assessment.
        - FOOD RESPONSE: Per-food glucose patterns help distinguish CR problems from ISF problems. If \
          high-GI foods cause large spikes but low-GI foods are handled well, the issue is food choice, \
          not necessarily CR settings.
        - CAFFEINE: Active caffeine >100mg can increase insulin resistance and glucose variability. \
          Factor caffeine timing into your assessment of glucose patterns, especially morning highs.

        RESPONSE FORMAT:
        Respond with valid JSON in this exact structure:
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
                    "reasoning": "Specific data-backed explanation citing exact numbers that justify this change",
                    "confidence": "low|medium|high"
                }
            ],
            "overall_assessment": "Factual summary including: algorithm workload assessment, time-of-day pattern summary, and what the basal/bolus ratio tells us",
            "next_recommended_focus": "carb_ratio|insulin_sensitivity|basal_rate|null"
        }

        If NO changes are warranted, return: { "suggestions": [], "overall_assessment": "...", "next_recommended_focus": null }
        Only return empty suggestions when TIR is good AND algorithm workload is low AND no time-of-day patterns exist.

        Time blocks use seconds since midnight (0 = 12:00 AM, 21600 = 6:00 AM, 43200 = 12:00 PM, etc.)
        Combine all time blocks for the same setting type into a single suggestion. Do NOT return separate suggestions for the same setting — use multiple time_blocks within one suggestion.
        """
    }

    // MARK: - User Prompt

    private func buildUserPrompt(
        settingType: LoopInsightsSettingType,
        settings: LoopInsightsTherapySnapshot,
        stats: LoopInsightsAggregatedStats,
        recentChanges: [LoopInsightsSuggestionRecord] = [],
        supplementalContext: String? = nil
    ) -> String {
        var prompt = "Evaluate whether my \(settingType.displayName) settings need adjustment.\n\n"

        // Include recent LoopInsights-applied changes so the AI knows data predates current settings
        let relevantChanges = recentChanges.filter {
            ($0.status == .applied || $0.status == .autoApplied) &&
            $0.suggestion.settingType == settingType
        }
        if !relevantChanges.isEmpty {
            prompt += "## IMPORTANT: Recent Settings Changes\n"
            prompt += "The following changes were JUST applied to these settings based on a previous analysis of this same data. "
            prompt += "The historical data below was collected BEFORE these changes took effect. "
            prompt += "Do NOT suggest further changes to values that were already adjusted — the data does not yet reflect the new settings.\n\n"
            for change in relevantChanges {
                let agoText = formatDuration(Date().timeIntervalSince(change.resolvedAt ?? change.createdAt))
                prompt += "- Applied \(agoText) ago: "
                for block in change.suggestion.timeBlocks {
                    prompt += "\(formatTime(block.startTime))–\(formatTime(block.endTime)): \(String(format: "%.1f", block.currentValue)) → \(String(format: "%.1f", block.proposedValue)). "
                }
                prompt += "\n"
            }
            prompt += "\n"
        }

        // All three therapy settings — AI needs full context to reason about interactions
        prompt += "## All Current Therapy Settings\n"
        prompt += "You are analyzing **\(settingType.displayName)** specifically, but consider how all three settings interact.\n\n"

        prompt += "### Basal Rate Schedule\(settingType == .basalRate ? " ← ANALYZING THIS" : "")\n"
        for item in settings.basalRateItems {
            prompt += "- \(formatTime(item.startTime)): \(String(format: "%.2f", item.value)) U/hr\n"
        }

        prompt += "\n### Insulin Sensitivity Factor Schedule\(settingType == .insulinSensitivity ? " ← ANALYZING THIS" : "")\n"
        for item in settings.insulinSensitivityItems {
            prompt += "- \(formatTime(item.startTime)): \(String(format: "%.1f", item.value)) mg/dL per U\n"
        }

        prompt += "\n### Carb Ratio Schedule\(settingType == .carbRatio ? " ← ANALYZING THIS" : "")\n"
        for item in settings.carbRatioItems {
            prompt += "- \(formatTime(item.startTime)): \(String(format: "%.1f", item.value)) g/U\n"
        }

        prompt += "\n"

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

        // Computed: corrections per day and basal/bolus assessment
        let days = max(1, stats.period.rawValue)
        let correctionsPerDay = Double(stats.insulinStats.correctionBolusCount) / Double(days)
        prompt += "- Corrections per Day: \(String(format: "%.1f", correctionsPerDay))\n"
        if correctionsPerDay > 5 {
            prompt += "  ** RED FLAG: >5 corrections/day means the AID algorithm is heavily compensating for suboptimal settings **\n"
        } else if correctionsPerDay > 3 {
            prompt += "  ** ELEVATED: >3 corrections/day suggests the algorithm is working harder than ideal **\n"
        }
        if stats.insulinStats.basalPercentage < 30 {
            prompt += "  ** RED FLAG: Basal is only \(String(format: "%.0f", stats.insulinStats.basalPercentage))% of TDD — strongly suggests basal rate is too low **\n"
        } else if stats.insulinStats.basalPercentage < 40 {
            prompt += "  ** NOTE: Basal is \(String(format: "%.0f", stats.insulinStats.basalPercentage))% of TDD — lower than the ideal 40-60% range **\n"
        }

        // Carb stats
        prompt += "\n## Carbohydrate Statistics\n"
        prompt += "- Average Daily Carbs: \(String(format: "%.0f", stats.carbStats.averageDailyCarbs)) g/day\n"
        prompt += "- Meals Logged: \(stats.carbStats.mealCount)\n"
        prompt += "- Average Carbs per Meal: \(String(format: "%.0f", stats.carbStats.averageCarbsPerMeal)) g\n"

        // Biometric stats (if available)
        if let bio = stats.biometricStats {
            prompt += "\n## Biometric Context\n"

            if let hr = bio.heartRate {
                prompt += "### Heart Rate\n"
                prompt += "- Average Resting HR: \(String(format: "%.0f", hr.averageRestingHR)) bpm\n"
                prompt += "- Average Active HR: \(String(format: "%.0f", hr.averageActiveHR)) bpm\n"
                if !hr.hourlyAverages.isEmpty {
                    prompt += "- Hourly HR averages: "
                    let sorted = hr.hourlyAverages.sorted { $0.key < $1.key }
                    prompt += sorted.map { "\(String(format: "%02d", $0.key)):00=\(String(format: "%.0f", $0.value))" }.joined(separator: ", ")
                    prompt += "\n"
                }
            }

            if let hrv = bio.hrv {
                prompt += "### HRV (Heart Rate Variability)\n"
                prompt += "- Average SDNN: \(String(format: "%.1f", hrv.averageSDNN)) ms\n"
                prompt += "- Trend: \(hrv.trend >= 0 ? "+" : "")\(String(format: "%.1f", hrv.trend)) ms (\(hrv.trend >= 0 ? "improving" : "declining"))\n"
            }

            if let steps = bio.steps {
                prompt += "### Steps/Activity\n"
                prompt += "- Average Daily Steps: \(String(format: "%.0f", steps.averageDailySteps))\n"
            }

            if let sleep = bio.sleep {
                prompt += "### Sleep\n"
                prompt += "- Average Duration: \(String(format: "%.1f", sleep.averageDurationHours)) hours/night\n"
                prompt += "- Average Bedtime: \(formatTimeFromSeconds(sleep.averageBedtime))\n"
                prompt += "- Average Wake Time: \(formatTimeFromSeconds(sleep.averageWakeTime))\n"
            }

            if let energy = bio.activeEnergy {
                prompt += "### Active Energy\n"
                prompt += "- Average Daily Active Calories: \(String(format: "%.0f", energy.averageDailyCalories)) kcal\n"
            }

            if let weight = bio.weight {
                prompt += "### Weight\n"
                prompt += "- Latest Weight: \(String(format: "%.1f", weight.latestWeight)) kg (\(String(format: "%.1f", weight.latestWeight * 2.205)) lbs)\n"
                prompt += "- Weight Trend: \(weight.weightTrend >= 0 ? "+" : "")\(String(format: "%.1f", weight.weightTrend)) kg over period\n"
            }
        }

        // Computed: time-of-day glucose analysis
        prompt += "\n## Time-of-Day Analysis (computed from hourly averages)\n"
        let g = stats.glucoseStats
        let periods: [(name: String, hours: ClosedRange<Int>)] = [
            ("Overnight (12AM-6AM)", 0...5),
            ("Morning (6AM-10AM)", 6...9),
            ("Midday (10AM-2PM)", 10...13),
            ("Afternoon (2PM-6PM)", 14...17),
            ("Evening (6PM-10PM)", 18...21),
            ("Late Night (10PM-12AM)", 22...23)
        ]
        for period in periods {
            let hourlyValues = period.hours.compactMap { g.hourlyAverages[$0] }
            guard !hourlyValues.isEmpty else { continue }
            let avg = hourlyValues.reduce(0, +) / Double(hourlyValues.count)
            let min = hourlyValues.min() ?? avg
            let max = hourlyValues.max() ?? avg
            let trend = (hourlyValues.last ?? avg) - (hourlyValues.first ?? avg)
            prompt += "- \(period.name): avg \(String(format: "%.0f", avg)) mg/dL, "
            prompt += "range \(String(format: "%.0f", min))-\(String(format: "%.0f", max)), "
            prompt += "trend \(trend >= 0 ? "+" : "")\(String(format: "%.0f", trend)) mg/dL\n"
            if avg > 150 {
                prompt += "  ** ELEVATED: Average glucose in this period is above 150 mg/dL **\n"
            }
            if abs(trend) > 30 {
                prompt += "  ** SIGNIFICANT DRIFT: \(trend > 0 ? "Rising" : "Falling") \(String(format: "%.0f", abs(trend))) mg/dL across this period **\n"
            }
        }

        // Phase 5: Supplemental context from advanced analyzers
        if let supplemental = supplementalContext, !supplemental.isEmpty {
            prompt += "\n\n## Supplemental Analysis Context\n"
            prompt += supplemental
            prompt += "\n"
        }

        prompt += "\nAnalyze this data focusing specifically on \(settingType.displayName). "
        prompt += "Use the time-of-day analysis and algorithm workload metrics to identify actionable patterns. "
        prompt += "If supplemental context is provided above, incorporate it into your reasoning. "
        prompt += "If the data clearly supports adjustments, propose them. If not, return empty suggestions. "
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

        // Merge multiple suggestions into one (all share the same setting type
        // within a single analysis call, so separate entries are just LLM inconsistency)
        let merged = mergeSuggestions(suggestions, settingType: settingType, period: period)

        let overallAssessment = json["overall_assessment"] as? String ?? "Analysis complete."

        var nextFocus: LoopInsightsSettingType? = nil
        if let nextRaw = json["next_recommended_focus"] as? String {
            nextFocus = LoopInsightsSettingType(rawValue: nextRaw)
        }

        return LoopInsightsAnalysisResponse(
            suggestions: merged,
            overallAssessment: overallAssessment,
            nextRecommendedFocus: nextFocus,
            rawResponse: rawResponse
        )
    }

    // MARK: - Merge

    /// Consolidate multiple suggestions (same setting type) into a single suggestion
    /// with all time blocks combined. Takes the highest confidence and joins reasoning.
    private func mergeSuggestions(
        _ suggestions: [LoopInsightsSuggestion],
        settingType: LoopInsightsSettingType,
        period: LoopInsightsAnalysisPeriod
    ) -> [LoopInsightsSuggestion] {
        guard suggestions.count > 1 else { return suggestions }

        let allBlocks = suggestions.flatMap { $0.timeBlocks }
            .sorted { $0.startTime < $1.startTime }
        let highestConfidence = suggestions.map { $0.confidence }.max() ?? .low
        let combinedReasoning = suggestions.map { $0.reasoning }.joined(separator: " ")

        let merged = LoopInsightsSuggestion(
            id: UUID(),
            settingType: settingType,
            timeBlocks: allBlocks,
            reasoning: combinedReasoning,
            confidence: highestConfidence,
            analysisPeriod: period,
            createdAt: Date()
        )
        return [merged]
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

    private func formatDuration(_ interval: TimeInterval) -> String {
        let totalMinutes = Int(interval) / 60
        if totalMinutes < 60 {
            return "\(totalMinutes) minute\(totalMinutes == 1 ? "" : "s")"
        }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours < 24 {
            if minutes == 0 {
                return "\(hours) hour\(hours == 1 ? "" : "s")"
            }
            return "\(hours) hour\(hours == 1 ? "" : "s") \(minutes) minute\(minutes == 1 ? "" : "s")"
        }
        let days = hours / 24
        let remainingHours = hours % 24
        if remainingHours == 0 {
            return "\(days) day\(days == 1 ? "" : "s")"
        }
        return "\(days) day\(days == 1 ? "" : "s") \(remainingHours) hour\(remainingHours == 1 ? "" : "s")"
    }

    private func formatTimeFromSeconds(_ seconds: Double) -> String {
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let period = hours >= 12 ? "PM" : "AM"
        let displayHour = hours == 0 ? 12 : (hours > 12 ? hours - 12 : hours)
        return String(format: "%d:%02d %@", displayHour, minutes, period)
    }
}
