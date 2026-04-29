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

    /// Data bundle for a past applied suggestion that needs outcome evaluation
    struct SuggestionWithOutcomeData {
        let record: LoopInsightsSuggestionRecord
        let postChangeGlucoseStats: [Int: Double]  // hour → average glucose after the change
        let daysSinceApplied: Int
    }

    /// Perform AI analysis for a specific setting type
    func analyze(
        settingType: LoopInsightsSettingType,
        currentSettings: LoopInsightsTherapySnapshot,
        stats: LoopInsightsAggregatedStats,
        recentChanges: [LoopInsightsSuggestionRecord] = [],
        supplementalContext: String? = nil,
        pastAppliedWithOutcomes: [SuggestionWithOutcomeData] = []
    ) async throws -> LoopInsightsAnalysisResponse {
        let systemPrompt = buildSystemPrompt(supplementalContext: supplementalContext)
        let userPrompt = buildUserPrompt(settingType: settingType, settings: currentSettings, stats: stats, recentChanges: recentChanges, supplementalContext: supplementalContext, pastAppliedWithOutcomes: pastAppliedWithOutcomes)

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

        return try parseResponse(rawResponse: rawResponse, settingType: settingType, period: stats.period, stats: stats)
    }

    // MARK: - System Prompt

    private func buildSystemPrompt(supplementalContext: String? = nil) -> String {
        let personality = LoopInsights_FeatureFlags.aiPersonality
        return """
        You are Loopy, an expert-level automated insulin delivery (AID) therapy settings analyst. \
        You think like a top board certified endocrinologist who specializes in insulin pump optimization. \
        You analyze glucose, insulin, and carbohydrate data to determine whether therapy settings need adjustment.

        \(personality.promptInstruction)

        YOUR MANDATE: Be analytically rigorous. You have this person's REAL data — their actual \
        glucose readings, insulin delivery, carb logs, and pump settings. Every recommendation must \
        cite specific numbers from THEIR data, not generic clinical wisdom. If the data does not \
        justify a change, return zero suggestions — that is the correct response when settings are \
        working. You are not here to impress or people-please. You are here to find real problems \
        in THIS person's data and propose precise fixes grounded in THEIR numbers.

        CRITICAL — DATA-DRIVEN ONLY: You are a clinical reasoning system, not a text generation system. \
        Do NOT produce recommendations that merely "sound clinically plausible" without being derived \
        from the actual data provided. If you cannot determine a setting from the available data, you \
        MUST return empty suggestions for that setting — never fill the gap with training-data priors \
        or textbook defaults. Specifically: \
        - If there are insufficient carb entries or meal boluses to evaluate Carb Ratio, return [] for suggestions. \
        - If there are insufficient correction events to evaluate ISF, return [] for suggestions. \
        - NEVER recommend a value just because it falls in a "typical" range. Typical ranges are irrelevant — \
          only THIS person's data matters. \
        - If you find yourself writing "kept close to current settings because no data supports a change" — \
          that means you should return ZERO suggestions, not echo the current value with medium/high confidence. \
        - Every proposed_value MUST be justified by a specific, citable pattern in the glucose/insulin data. \
          If you cannot point to the exact data pattern that drives your recommendation, do not make it.

        CLINICAL REASONING FRAMEWORK — How AID settings interact:
        - BASAL RATE: Controls glucose during fasting periods. Analyze overnight (12AM-6AM) and \
          between-meal trends. In AID systems, the algorithm adjusts delivery around this baseline. \
          ⚠️ HIGHEST RISK SETTING — basal delivers insulin 24/7, including overnight when the user \
          is asleep. A basal rate set too high can cause severe nocturnal hypoglycemia. Always err on \
          the side of under-adjustment. \
          KEY SIGNAL: If fasting glucose drifts up/down consistently, basal is likely wrong. \
          A basal/bolus split skewed heavily toward bolus (>60%) with poor glucose outcomes \
          may suggest basal is too low. Correction activity alone is not a problem — \
          the algorithm issuing corrections is normal AID behavior.
        - INSULIN SENSITIVITY FACTOR (ISF): Controls how much 1 unit of insulin lowers glucose. \
          Analyze correction effectiveness — are corrections bringing glucose back to target? \
          KEY SIGNAL: If glucose stays high for hours after meals/corrections (hourly averages >150 \
          during 10AM-2PM or 7PM-10PM), ISF may be too high (insulin isn't strong enough). If glucose \
          drops too fast or goes low after corrections, ISF may be too low.
        - CARB RATIO (CR): Controls how much insulin is given per gram of carbs strictly at meals. \
          Analyze post-meal glucose behavior. KEY SIGNAL: If glucose spikes >50 mg/dL after meals \
          (compare pre-meal hour to 1-2 hours post-meal in hourly averages), CR may be too high \
          (not enough insulin per carb). If glucose drops after meals, CR may be too low. \
        While the CR doesn't change the ISF, a wrong CR shifts work to other settings: \
        If CR is too weak at meals: The user won't get enough insulin for the meal. \
        The system will see the resulting rise and trigger auto-corrections (using the ISF) or increased basal \
        to fix the mistake. If CR is too aggressive: The user will drop low after eating. \
        The system will then suspend or reduce basal insulin to recover back to target.

        PATTERN RECOGNITION — What to look for:
        1. TIME-OF-DAY PATTERNS: Compare hourly averages across the day. Different periods may need \
           different settings. Common periods: overnight (12AM-6AM), morning (6AM-10AM), midday \
           (10AM-2PM), afternoon (2PM-6PM), evening (6PM-10PM), late night (10PM-12AM).
        2. AID ALGORITHM ACTIVITY: Correction bolus count is additional context, not a diagnosis on its own. \
           AID systems are DESIGNED to issue corrections — that is their core function. A high correction \
           count only matters if paired with poor glucose outcomes (high variability, low TIR, frequent \
           lows/highs). Corrections with good TIR and low variability mean the system is working well.
        3. BASAL/BOLUS RATIO: This varies widely between individuals and is influenced by diet, activity, \
           insulin type, and physiology. There is no single "correct" ratio. Use it as one contextual data \
           point alongside glucose outcomes, not as a standalone diagnostic. A 30/70 split with excellent \
           TIR and no lows is perfectly fine for that person.
        4. GLUCOSE TRENDS: Look at the slope of hourly averages. A consistent rise over 3+ hours \
           during fasting may suggest basal is too low. A consistent drop may suggest basal is too high.
        5. OUTCOMES MATTER MOST: The primary question is always: are glucose outcomes good? If TIR is \
           high, time below range is low, and variability is acceptable, the settings are working — even \
           if the algorithm is active. Only recommend changes when glucose OUTCOMES clearly need improvement.

        CROSS-SETTING INTERACTIONS — You are given all three settings for context:
        - The CR is the user's "front-end" tool for meals. Their ISF and BR are the "back-end" tools the system uses \
          to keep the user stable between meals.
        - BR and ISF are tightly coupled: if basal is too low, the system relies more on \
          corrections via ISF. Changing ISF without considering BR can mask the real problem.
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

        IMPORTANT: If glucose outcomes are good (TIR >80%, time below range <4%, CV <36%), respect that \
        the current settings are working for THIS person. AID systems are meant to actively manage delivery — \
        corrections and basal adjustments are features, not failures. Only recommend changes when glucose \
        outcomes clearly need improvement, not because the algorithm is active.

        SAFETY RULES:
        1. Never suggest CR or ISF changes larger than 20% from current values in a single step. \
           For BASAL RATE, never suggest changes larger than 10% — basal delivers insulin continuously \
           and small changes compound over hours, especially overnight.
        2. Conservative changes only — under-adjust rather than over-adjust.
        3. If time below range is >4%, prioritize safety (raise ISF or lower basal before anything else).
        4. Suggestions are advisory only — the user and their healthcare provider make final decisions.
        5. ABSOLUTE CLINICAL BOUNDS — proposed values MUST stay within these ranges. BR is 'background insulin' meant to act \
           as the liver's neutralizer for hepatic glucose. Clamp to bound if needed:
           - Carb Ratio: 2.0–150.0 g/U (recommended 4.0–28.0)
           - ISF: 10.0–500.0 mg/dL/U (recommended 16.0–400.0)
           - Basal Rate: 0.05–30.0 U/hr (recommended 0.05–10.0)
           Values outside the recommended range should only be proposed with LOW confidence and explicit justification.
        6. CUMULATIVE CHANGE AWARENESS: If recent settings changes are listed above, do NOT stack \
           additional changes on top. Settings changes need time (3-7 days minimum) to show effect in the data. \
           If the data predates a recent change, recommend waiting for new data before adjusting further.

        BASAL RATE SAFETY — CRITICAL:
        Basal rate changes carry the HIGHEST RISK of all three therapy settings. Unlike CR (which only \
        affects mealtimes) or ISF (which only affects corrections), basal insulin delivers CONTINUOUSLY — \
        including overnight while the user is asleep and cannot respond to a low. Excessive basal can cause \
        severe nocturnal hypoglycemia. Follow these rules strictly when analyzing basal rate:
        1. Maximum 10% change per time block. Even if the data shows a strong signal, limit basal changes \
           to 10% increments. It is always safer to make two small changes over two analysis cycles than one \
           large change that risks overnight lows.
        2. OVERNIGHT PERIODS (10PM–6AM) require EXTRA conservatism. If suggesting a basal INCREASE for any \
           time block that overlaps overnight hours, explicitly warn about nighttime low risk in your reasoning. \
           Prefer smaller increases (5–7%) for overnight blocks.
        3. If time below range is >2% (not just >4%), seriously consider whether basal is already too high \
           before suggesting ANY basal increase. Nighttime lows are dangerous and often go undetected.
        4. If the data shows frequent insulin suspensions or negative basal events, this is a STRONG signal \
           that basal is already too high — do NOT increase it regardless of other signals.
        5. Always include a safety note in your reasoning when suggesting basal changes, reminding the user \
           that basal changes affect overnight glucose and should be monitored closely for 3–5 days.

        BIOMETRIC CONTEXT — When biometric data is provided:
        - HEART RATE: Elevated resting HR or HR spikes can indicate stress, illness, caffeine, or \
          exercise — all affect insulin sensitivity. Morning HR acceleration may indicate caffeine \
          intake or dawn cortisol surge. A sudden sustained HR increase could signal illness (reduce \
          insulin sensitivity expectation).
        - Heart Rate Variability: Lower HRV indicates higher physiological stress. Declining HRV trend may \
          predict increased insulin resistance. Use HRV context to temper or strengthen confidence in \
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
        - ALCOHOL: Alcohol SUPPRESSES hepatic gluconeogenesis, causing DELAYED HYPOGLYCEMIA 4-24 hours \
          after consumption, peaking at 8-12 hours. This is the OPPOSITE of caffeine's effect. \
          The liver metabolizes ~1 standard drink per hour. During metabolism, glucose production drops ~45%. \
          CRITICAL OVERNIGHT RISK: Evening drinking causes peak hypo risk during sleep (2AM-10AM). \
          The AID algorithm can suspend basal but cannot remove IOB already delivered. \
          Dose-dependent: 1-2 drinks = mild suppression, 20% basal reduction recommended overnight. \
          3-4 drinks = moderate, higher targets + 20-30% basal reduction. \
          5+ drinks = severe, up to 24h duration, 30-50% basal reduction. \
          AVOID AGGRESSIVE CORRECTIONS after drinking — post-meal highs from carb-containing drinks \
          will self-correct as gluconeogenesis suppression kicks in. Over-correcting causes stacking. \
          When analyzing settings with active alcohol context: \
          Do NOT recommend basal INCREASES if drinking occurred in the last 24 hours. \
          High glucose immediately after drinking is transient — not a settings problem. \
          Low glucose 8-16 hours after drinking is alcohol-induced — not necessarily a settings problem. \
          If the analysis period contains significant alcohol intake, note this as a confounding factor \
          and REDUCE confidence in all settings change recommendations.
          On an empty stomach, drinking alcohol can also cause short term hypoglycemia. Alcohol is a toxin, \
          so the body 'spends' extra glucose energy to process the toxin out. With no onboard glucose the user may go low. \

        INSULIN TYPE & DIA — Duration of Insulin Action defines the IOB calculation window:
        - RAPID-ACTING (Novolog/Humalog/Apidra): Onset ~15 min, peak ~75 min, DIA ~6 hrs. \
          Pre-bolusing 15-20 min is effective. Corrections take 2-3 hrs to fully resolve.
        - ULTRA-RAPID (Fiasp/Lyumjev): Onset ~2-5 min, peak ~55 min, DIA ~6 hrs. \
          Large spikes despite on-time bolusing strongly suggests weak CR (not timing). \
          Corrections resolve in ~1.5-2 hrs — if glucose stays high after correction, ISF is likely too high.
        - INHALED (Afrezza): Onset ~2 min, peak ~29 min, DIA ~5 hrs.
        - DIA TOO SHORT → Loop underestimates IOB → insulin stacking → lows (look for rollercoaster pattern). \
          DIA TOO LONG → Loop overestimates IOB → withholds corrections → persistent highs. \
          Physiological DIA for rapid-acting is 5-7 hrs. If patterns suggest stacking or timidity, \
          flag DIA in your overall_assessment (not in time_blocks suggestions).
        - Use insulin type to distinguish TIMING vs DOSING issues. Novolog spikes that resolve by hour 3 = \
          pre-bolus timing issue. Fiasp spikes = likely CR issue since Fiasp should already be active.

        SUCCESS CRITERIA — Every suggestion MUST include success_criteria:
        For each suggestion, define specific, measurable criteria the user should watch for to know \
        if the change worked. Use actual numbers from THEIR data — not generic targets. Include:
        1. expected_outcomes: 2-4 concrete statements like "Overnight average glucose should drop from \
           145 mg/dL to below 130 mg/dL" or "Time below range should stay under 3%".
        2. evaluation_days: How many days to wait before judging (3-7 days, longer for basal changes).
        3. revert_warnings: 1-3 danger signals that mean the change should be reverted immediately, \
           e.g. "More than 2 lows below 60 mg/dL in a single night" or "Time below range exceeds 6%".
        4. metric_targets: Key metrics with target ranges, e.g. {"overnight_avg": "<130 mg/dL", \
           "time_below_range": "<4%"}.

        PAST SUGGESTION EVALUATION — When previously applied suggestions are listed in the user prompt:
        Before making ANY new recommendations, evaluate each past applied suggestion against its \
        success criteria using the post-change glucose data provided. For each past suggestion:
        1. If evaluation_days have NOT elapsed since it was applied, return verdict "insufficient_data" \
           and recommend the user wait before making further changes to that setting.
        2. If evaluation_days HAVE elapsed, compare actual outcomes to the success criteria. Count how \
           many criteria were met. Return a verdict: "success" (all met), "partial" (some met), \
           "no_improvement" (none met), or "worsened" (metrics got worse).
        3. Include reasoning explaining what the data shows about the change's effect.
        4. If a previous change worsened outcomes, recommend reverting before making new suggestions.
        Return evaluations in "past_suggestion_evaluations" keyed by the suggestion's record_id.

        RESPONSE FORMAT:
        Respond with valid JSON in this exact structure:
        {
            "past_suggestion_evaluations": {
                "record-uuid-here": {
                    "criteria_met": 2,
                    "criteria_total": 3,
                    "verdict": "partial",
                    "reasoning": "Overnight average dropped from 145 to 132 mg/dL (met), but time below range increased to 5% (not met)."
                }
            },
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
                    "confidence": "low|medium|high",
                    "success_criteria": {
                        "expected_outcomes": [
                            "Overnight average glucose should drop from 145 to below 130 mg/dL",
                            "Time below range should remain under 4%"
                        ],
                        "evaluation_days": 5,
                        "revert_warnings": [
                            "More than 2 readings below 60 mg/dL overnight"
                        ],
                        "metric_targets": {
                            "overnight_avg": "<130 mg/dL",
                            "time_below_range": "<4%"
                        }
                    }
                }
            ],
            "overall_assessment": "Factual summary including: time-of-day pattern summary, glucose outcome trends, and what the basal/bolus ratio tells us",
            "next_recommended_focus": "carb_ratio|insulin_sensitivity|basal_rate|null"
        }

        If NO changes are warranted, return: { "suggestions": [], "past_suggestion_evaluations": {}, "overall_assessment": "...", "next_recommended_focus": null }
        Only return empty suggestions when TIR is good AND glucose outcomes are stable AND no time-of-day patterns exist.
        If there are no past suggestions to evaluate, return "past_suggestion_evaluations": {}.

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
        supplementalContext: String? = nil,
        pastAppliedWithOutcomes: [SuggestionWithOutcomeData] = []
    ) -> String {
        var prompt = "Evaluate whether my \(settingType.displayName) settings need adjustment.\n\n"

        // Include past applied suggestions that need outcome evaluation
        let relevantOutcomes = pastAppliedWithOutcomes.filter {
            $0.record.suggestion.settingType == settingType
        }
        if !relevantOutcomes.isEmpty {
            prompt += "## Previously Applied Suggestions — EVALUATE THESE FIRST\n"
            prompt += "Before making new recommendations, evaluate each of these past changes against their success criteria.\n\n"
            for outcome in relevantOutcomes {
                let record = outcome.record
                prompt += "### Record ID: \(record.id.uuidString)\n"
                prompt += "- Applied \(outcome.daysSinceApplied) day\(outcome.daysSinceApplied == 1 ? "" : "s") ago\n"
                prompt += "- Change: "
                for block in record.suggestion.timeBlocks {
                    prompt += "\(formatTime(block.startTime))–\(formatTime(block.endTime)): \(String(format: "%.1f", block.currentValue)) → \(String(format: "%.1f", block.proposedValue)). "
                }
                prompt += "\n"

                if let criteria = record.suggestion.successCriteria {
                    prompt += "- Evaluation window: \(criteria.evaluationDays) days\n"
                    prompt += "- Success criteria:\n"
                    for (i, expected) in criteria.expectedOutcomes.enumerated() {
                        prompt += "  \(i + 1). \(expected)\n"
                    }
                    if !criteria.revertWarnings.isEmpty {
                        prompt += "- Revert warnings: \(criteria.revertWarnings.joined(separator: "; "))\n"
                    }
                }

                // Include post-change glucose stats for the hours affected by this change
                if !outcome.postChangeGlucoseStats.isEmpty {
                    prompt += "- Post-change hourly glucose averages:\n"
                    for hour in outcome.postChangeGlucoseStats.keys.sorted() {
                        if let avg = outcome.postChangeGlucoseStats[hour] {
                            prompt += "  \(String(format: "%02d", hour)):00: \(String(format: "%.0f", avg)) mg/dL\n"
                        }
                    }
                }
                prompt += "\n"
            }
        }

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

        // AID system identification — critical for avoiding training-prior anchoring (Street 2026)
        prompt += "## AID System & Device Context\n"
        prompt += "- **System**: Loop (oref-based automated insulin delivery)\n"
        prompt += "- **Algorithm**: Loop's dosing algorithm uses DIA, ISF, CR, and basal schedules to calculate IOB and make automated delivery adjustments.\n"
        if let diaHours = settings.insulinDiaHours {
            prompt += "- **Duration of Insulin Action (DIA): \(String(format: "%.1f", diaHours)) hours** ← This is the user's ACTUAL configured DIA. Do NOT recommend a different DIA. The oref algorithm in Loop uses longer DIA values (typically 6-10 hours) than textbook insulin action curves. This is intentional and correct for this AID system.\n"
        }
        if let insulinType = settings.insulinTypeName {
            prompt += "- **Insulin Type**: \(insulinType)\n"
        }
        prompt += "- Use these current settings as your reference point. Any recommendations must be small adjustments FROM these values based on data patterns, not replacements based on clinical norms.\n\n"

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
        prompt += "- Time in Tight Range (70-\(stats.glucoseStats.tightRangeUpperBound)): \(String(format: "%.1f", stats.glucoseStats.timeInTightRange))%\n"
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
        let tdi = stats.insulinStats.totalDailyDose
        prompt += "\n## Insulin Statistics\n"
        prompt += "- TDI: \(String(format: "%.1f", tdi)) U/day (range: \(String(format: "%.1f", stats.insulinStats.tddMin))–\(String(format: "%.1f", stats.insulinStats.tddMax)), CV: \(String(format: "%.0f", stats.insulinStats.tddVariabilityCV))%)\n"
        if let weekChange = stats.insulinStats.tddWeekOverWeekChange {
            prompt += "- TDI Week-over-Week: \(weekChange >= 0 ? "+" : "")\(String(format: "%.0f", weekChange))%\n"
        }
        prompt += "- Basal: \(String(format: "%.0f", stats.insulinStats.basalPercentage))% / Bolus: \(String(format: "%.0f", stats.insulinStats.bolusPercentage))%\n"
        prompt += "- Correction Boluses: \(stats.insulinStats.correctionBolusCount) in period\n"

        // Computed: corrections per day (context, not a diagnosis)
        let days = max(1, stats.period.rawValue)
        let correctionsPerDay = Double(stats.insulinStats.correctionBolusCount) / Double(days)
        prompt += "- Corrections per Day: \(String(format: "%.1f", correctionsPerDay))\n"

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
                if !steps.hourlyAverages.isEmpty {
                    // Group into time-of-day activity levels
                    let activityPeriods: [(name: String, hours: ClosedRange<Int>)] = [
                        ("Morning 6-10AM", 6...9), ("Midday 10AM-2PM", 10...13),
                        ("Afternoon 2-6PM", 14...17), ("Evening 6-10PM", 18...21)
                    ]
                    for period in activityPeriods {
                        let periodSteps = period.hours.compactMap { steps.hourlyAverages[$0] }
                        if !periodSteps.isEmpty {
                            let total = periodSteps.reduce(0, +)
                            prompt += "- \(period.name): \(String(format: "%.0f", total)) avg steps\n"
                        }
                    }
                    // Peak activity hour
                    if let peakHour = steps.hourlyAverages.max(by: { $0.value < $1.value }) {
                        prompt += "- Peak activity hour: \(String(format: "%02d", peakHour.key)):00 (\(String(format: "%.0f", peakHour.value)) steps)\n"
                    }

                    // Activity-glucose correlation: compare high-activity hours to glucose
                    let glucoseHourly = stats.glucoseStats.hourlyAverages
                    if !glucoseHourly.isEmpty {
                        var correlations: [String] = []
                        let avgGlucose = stats.glucoseStats.averageGlucose
                        for (hour, stepCount) in steps.hourlyAverages where stepCount > 200 {
                            let postActivityHour = (hour + 2) % 24
                            if let postGlucose = glucoseHourly[postActivityHour] {
                                let delta = postGlucose - avgGlucose
                                if abs(delta) > 10 {
                                    correlations.append("Activity at \(String(format: "%02d", hour)):00 → glucose \(delta > 0 ? "+" : "")\(String(format: "%.0f", delta)) mg/dL vs avg at \(String(format: "%02d", postActivityHour)):00")
                                }
                            }
                        }
                        if !correlations.isEmpty {
                            prompt += "- **Activity-Glucose Correlations (2h lag)**:\n"
                            for c in correlations.prefix(5) { prompt += "  - \(c)\n" }
                        }
                    }
                }
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
                if !energy.hourlyAverages.isEmpty {
                    let activityPeriods: [(name: String, hours: ClosedRange<Int>)] = [
                        ("Morning 6-10AM", 6...9), ("Midday 10AM-2PM", 10...13),
                        ("Afternoon 2-6PM", 14...17), ("Evening 6-10PM", 18...21)
                    ]
                    for period in activityPeriods {
                        let periodKcal = period.hours.compactMap { energy.hourlyAverages[$0] }
                        if !periodKcal.isEmpty {
                            let total = periodKcal.reduce(0, +)
                            prompt += "- \(period.name): \(String(format: "%.0f", total)) avg kcal\n"
                        }
                    }
                }
            }

            if let weight = bio.weight {
                prompt += "### Weight\n"
                prompt += "- Latest Weight: \(String(format: "%.1f", weight.latestWeight)) kg (\(String(format: "%.1f", weight.latestWeight * 2.205)) lbs)\n"
                prompt += "- Weight Trend: \(weight.weightTrend >= 0 ? "+" : "")\(String(format: "%.1f", weight.weightTrend)) kg over period\n"
            }

            if let menstrual = bio.menstrualCycle, menstrual.dataAvailable {
                prompt += "### Menstrual Cycle\n"
                prompt += "- Current Phase: \(menstrual.currentPhase.rawValue)\n"
                if let day = menstrual.currentCycleDay {
                    prompt += "- Cycle Day: \(day)\n"
                }
                if let avgLength = menstrual.averageCycleLength {
                    prompt += "- Average Cycle Length: \(String(format: "%.0f", avgLength)) days\n"
                }
                if menstrual.flowDaysInLookback > 0 {
                    prompt += "- Flow Days in Period: \(menstrual.flowDaysInLookback)\n"
                }
                prompt += "- Note: Luteal phase typically increases insulin resistance 15-30%. Consider hormonal impact before recommending permanent settings changes.\n"
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
        prompt += "Use the time-of-day analysis and glucose outcome metrics to identify actionable patterns. "
        prompt += "If supplemental context is provided above, incorporate it into your reasoning. "
        prompt += "If the data clearly supports adjustments, propose them. If not, return empty suggestions. "

        if settingType == .basalRate {
            prompt += "\n\n⚠️ BASAL RATE REMINDER: Basal rate is the highest-risk setting to change. "
            prompt += "It delivers insulin continuously, including overnight when the user is asleep. "
            prompt += "Limit all proposed changes to ≤10% per time block. For overnight blocks (10PM–6AM), "
            prompt += "prefer even smaller changes (5–7%). If suggesting any basal increase, you MUST include "
            prompt += "a warning about monitoring for nighttime lows in your reasoning. "
            prompt += "If time below range is >2%, strongly consider whether basal is already too high.\n"
        }

        prompt += "Respond with JSON only, no markdown formatting."

        return prompt
    }

    // MARK: - Response Parsing

    private func parseResponse(rawResponse: String, settingType: LoopInsightsSettingType, period: LoopInsightsAnalysisPeriod, stats: LoopInsightsAggregatedStats) throws -> LoopInsightsAnalysisResponse {
        // Extract JSON from the response (AI might wrap it in markdown code blocks)
        var jsonString = extractJSON(from: rawResponse)

        guard let data = jsonString.data(using: .utf8) else {
            throw LoopInsightsError.parseError("Unable to convert response to data")
        }

        // Try parsing as-is first; if that fails, attempt to repair truncated JSON
        var json: [String: Any]
        if let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            json = parsed
        } else {
            // Thinking models (e.g. Gemini 2.5) consume output tokens for thinking,
            // which can truncate the JSON response. Try to repair by closing unclosed brackets.
            jsonString = repairTruncatedJSON(jsonString)
            guard let repairedData = jsonString.data(using: .utf8),
                  let repaired = try? JSONSerialization.jsonObject(with: repairedData) as? [String: Any] else {
                throw LoopInsightsError.parseError("Response is not valid JSON: \(rawResponse.prefix(200))")
            }
            json = repaired
        }

        // Detect empty responses from thinking models (all output tokens used for thinking, no actual content)
        if json.keys.contains("candidates") || json.keys.contains("usageMetadata") {
            // We're looking at the API envelope, not the AI-generated content.
            // This happens when the model produces only thinking tokens and no response.
            throw LoopInsightsError.emptyThinkingResponse
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
                    proposedValue: settingType.roundedToIncrement(proposedValue)
                )
            }

            guard !timeBlocks.isEmpty else { continue }

            // Post-parse safety validation: reject blocks outside absolute bounds
            // and enforce max change percentage as a code-level backstop
            let validatedBlocks = timeBlocks.filter { block in
                let classification = LoopInsights_SafetyGuardrails.classify(
                    value: block.proposedValue, settingType: settingType
                )

                // Hard reject: values outside absolute bounds
                if classification == .belowAbsolute || classification == .aboveAbsolute {
                    LoopInsights_FeatureFlags.log.error(
                        "Guardrail REJECTED: \(settingType.displayName) proposed \(block.proposedValue) at \(block.startTimeFormatted) — outside absolute bounds"
                    )
                    return false
                }

                // Warn (but pass through): values outside recommended bounds
                if classification != .withinRecommended {
                    LoopInsights_FeatureFlags.log.warning(
                        "Guardrail WARNING: \(settingType.displayName) proposed \(block.proposedValue) at \(block.startTimeFormatted) — outside recommended range"
                    )
                }

                // Backstop: reject blocks exceeding max change (15% for basal, 25% for CR/ISF)
                let changePercent = abs(block.changePercent)
                let maxAllowed = settingType == .basalRate
                    ? LoopInsights_SafetyGuardrails.maxBasalChangePercent
                    : LoopInsights_SafetyGuardrails.maxChangePercent
                if changePercent > maxAllowed {
                    LoopInsights_FeatureFlags.log.error(
                        "Guardrail REJECTED: \(settingType.displayName) proposed \(String(format: "%.1f", block.proposedValue)) at \(block.startTimeFormatted) — \(String(format: "%.0f", changePercent))%% change exceeds \(String(format: "%.0f", maxAllowed))%% limit"
                    )
                    return false
                }

                return true
            }

            guard !validatedBlocks.isEmpty else { continue }

            // Parse success criteria if present
            var successCriteria: LoopInsightsSuccessCriteria? = nil
            if let criteriaJSON = suggestionJSON["success_criteria"] as? [String: Any] {
                let expectedOutcomes = criteriaJSON["expected_outcomes"] as? [String] ?? []
                let evaluationDays = criteriaJSON["evaluation_days"] as? Int ?? 5
                let revertWarnings = criteriaJSON["revert_warnings"] as? [String] ?? []
                let metricTargets = criteriaJSON["metric_targets"] as? [String: String] ?? [:]
                if !expectedOutcomes.isEmpty {
                    successCriteria = LoopInsightsSuccessCriteria(
                        expectedOutcomes: expectedOutcomes,
                        evaluationDays: evaluationDays,
                        revertWarnings: revertWarnings,
                        metricTargets: metricTargets
                    )
                }
            }

            let suggestion = LoopInsightsSuggestion(
                id: UUID(),
                settingType: settingType,
                timeBlocks: validatedBlocks,
                reasoning: reasoning,
                confidence: confidence,
                analysisPeriod: period,
                createdAt: Date(),
                successCriteria: successCriteria
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

        // Parse past suggestion evaluations
        var pastEvaluations: [String: LoopInsightsOutcomeEvaluation] = [:]
        if let evalsJSON = json["past_suggestion_evaluations"] as? [String: [String: Any]] {
            for (recordID, evalData) in evalsJSON {
                guard let verdictRaw = evalData["verdict"] as? String,
                      let verdict = LoopInsightsOutcomeEvaluation.Verdict(rawValue: verdictRaw) else {
                    continue
                }
                let criteriaMet = evalData["criteria_met"] as? Int ?? 0
                let criteriaTotal = evalData["criteria_total"] as? Int ?? 0
                let reasoning = evalData["reasoning"] as? String ?? ""
                pastEvaluations[recordID] = LoopInsightsOutcomeEvaluation(
                    evaluatedAt: Date(),
                    criteriaMetCount: criteriaMet,
                    criteriaTotalCount: criteriaTotal,
                    verdict: verdict,
                    reasoning: reasoning
                )
            }
        }

        // ─── Post-hoc validation (Street 2026, recommendations #2 and #3) ───
        var validationNotes: [String] = []
        var validatedSuggestions = merged

        // 1. Programmatic bounds checking — clamp values that exceed max change %
        //    but fall within absolute bounds (vs hard reject above, this catches edge cases
        //    where the AI slightly overshoots the percentage limit after rounding)
        validatedSuggestions = validatedSuggestions.map { suggestion in
            let clampedBlocks = suggestion.timeBlocks.map { block -> LoopInsightsTimeBlock in
                let maxPct = settingType == .basalRate
                    ? LoopInsights_SafetyGuardrails.maxBasalChangePercent
                    : LoopInsights_SafetyGuardrails.maxChangePercent
                let changePct = block.changePercent
                if abs(changePct) > maxPct && abs(changePct) <= maxPct * 1.5 {
                    // Clamp to max allowed change instead of rejecting
                    let direction: Double = block.proposedValue > block.currentValue ? 1.0 : -1.0
                    let clamped = block.currentValue * (1.0 + direction * maxPct / 100.0)
                    let rounded = settingType.roundedToIncrement(clamped)
                    validationNotes.append("Clamped \(settingType.displayName) at \(block.startTimeFormatted) from \(String(format: "%.1f", block.proposedValue)) to \(String(format: "%.1f", rounded)) (exceeded \(String(format: "%.0f", maxPct))% limit)")
                    return LoopInsightsTimeBlock(
                        startTime: block.startTime,
                        endTime: block.endTime,
                        currentValue: block.currentValue,
                        proposedValue: rounded
                    )
                }
                return block
            }
            return LoopInsightsSuggestion(
                id: suggestion.id,
                settingType: suggestion.settingType,
                timeBlocks: clampedBlocks,
                reasoning: suggestion.reasoning,
                confidence: suggestion.confidence,
                analysisPeriod: suggestion.analysisPeriod,
                createdAt: suggestion.createdAt,
                successCriteria: suggestion.successCriteria
            )
        }

        // 2. Citation verification — check glucose values cited in reasoning against
        //    actual hourly averages. Misattributed citations are the dominant error mode
        //    (30-70% per Street 2026) and are architecturally independent of anchoring.
        let hourlyAverages = stats.glucoseStats.hourlyAverages
        if !hourlyAverages.isEmpty {
            for suggestion in validatedSuggestions {
                let cited = extractCitedGlucoseValues(from: suggestion.reasoning)
                guard !cited.isEmpty else { continue }
                let actualValues = hourlyAverages.values.map { Int($0.rounded()) }
                let misattributed = cited.filter { citedValue in
                    // Allow ±2 mg/dL tolerance for rounding differences
                    !actualValues.contains(where: { abs($0 - citedValue) <= 2 })
                }
                if !misattributed.isEmpty {
                    let pct = Int((Double(misattributed.count) / Double(cited.count)) * 100)
                    validationNotes.append("Citation check: \(misattributed.count)/\(cited.count) glucose values (\(pct)%) cited in reasoning do not match hourly averages provided to the model")
                }
            }
        }

        // 3. Confidence adjustment by data availability — if insufficient data exists
        //    to validate a setting, cap confidence at "low" to flag anchor substitution risk.
        //    Per Street 2026: ICR is "mostly anchor" without meal data; ISF is "mixed" without corrections.
        let dataAvailabilityWarning: String? = {
            switch settingType {
            case .carbRatio:
                if stats.carbStats.mealCount < 5 {
                    return "Carb Ratio analysis has limited meal data (\(stats.carbStats.mealCount) meals in period). Confidence capped at Low — recommendations may reflect model training priors rather than your data (Street 2026: anchor substitution risk)."
                }
            case .insulinSensitivity:
                if stats.insulinStats.correctionBolusCount < 3 {
                    return "ISF analysis has limited correction data (\(stats.insulinStats.correctionBolusCount) corrections in period). Confidence capped at Low — insufficient correction events to validate sensitivity factor."
                }
            case .basalRate:
                break // Basal is the most data-driven setting (CGM patterns); no cap needed
            }
            return nil
        }()

        if let warning = dataAvailabilityWarning {
            validationNotes.append(warning)
            // Cap all suggestion confidence to .low
            validatedSuggestions = validatedSuggestions.map { suggestion in
                guard suggestion.confidence != .low else { return suggestion }
                return LoopInsightsSuggestion(
                    id: suggestion.id,
                    settingType: suggestion.settingType,
                    timeBlocks: suggestion.timeBlocks,
                    reasoning: suggestion.reasoning + "\n\n⚠️ " + warning,
                    confidence: .low,
                    analysisPeriod: suggestion.analysisPeriod,
                    createdAt: suggestion.createdAt,
                    successCriteria: suggestion.successCriteria
                )
            }
        }

        // 4. Contradiction detection — models produce confident recommendations while
        //    simultaneously admitting data is insufficient (Street 2026 §8.3c: "The model
        //    cannot distinguish 'I have evidence' from 'I should generate something plausible'").
        //    Detect this contradiction and suppress the suggestion entirely.
        validatedSuggestions = validatedSuggestions.filter { suggestion in
            let reasoning = suggestion.reasoning.lowercased()
            let insufficiencyPhrases = [
                "cannot be derived", "cannot be determined", "cannot be calculated",
                "cannot be meaningfully", "insufficient data", "no meal data",
                "no carb entries", "no bolus data", "unable to determine",
                "kept close to current settings", "echoing current", "no meals available",
                "cannot validate", "no correction events"
            ]
            let admitsInsufficiency = insufficiencyPhrases.contains { reasoning.contains($0) }

            if admitsInsufficiency && suggestion.confidence != .low {
                validationNotes.append("Contradiction detected: AI admitted insufficient data to derive \(settingType.displayName) but returned \(suggestion.confidence.displayName) confidence. Suggestion suppressed — model was filling gaps with training priors, not reasoning from data.")
                return false // Remove this suggestion
            }
            return true
        }

        return LoopInsightsAnalysisResponse(
            suggestions: validatedSuggestions,
            overallAssessment: overallAssessment,
            nextRecommendedFocus: nextFocus,
            rawResponse: rawResponse,
            pastEvaluations: pastEvaluations,
            validationNotes: validationNotes
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

        // Use the first suggestion's success criteria (all share same setting type)
        let mergedCriteria = suggestions.first(where: { $0.successCriteria != nil })?.successCriteria

        let merged = LoopInsightsSuggestion(
            id: UUID(),
            settingType: settingType,
            timeBlocks: allBlocks,
            reasoning: combinedReasoning,
            confidence: highestConfidence,
            analysisPeriod: period,
            createdAt: Date(),
            successCriteria: mergedCriteria
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

    /// Attempts to repair truncated JSON by closing unclosed braces, brackets, and strings.
    /// Thinking models (e.g. Gemini 2.5) consume output tokens for thinking, which can
    /// cause the JSON response to be cut off mid-structure.
    private func repairTruncatedJSON(_ json: String) -> String {
        var result = json

        // Strip trailing incomplete key-value pair after the last comma
        if let lastComma = result.lastIndex(of: ",") {
            let afterComma = result[result.index(after: lastComma)...].trimmingCharacters(in: .whitespacesAndNewlines)
            if !afterComma.hasSuffix("}") && !afterComma.hasSuffix("]") && !afterComma.isEmpty {
                result = String(result[...lastComma])
                result = String(result.dropLast()) // remove the trailing comma
            }
        }

        // Count open vs close braces/brackets
        var openBraces = 0
        var openBrackets = 0
        var inString = false
        var prevChar: Character = " "
        for ch in result {
            if ch == "\"" && prevChar != "\\" { inString.toggle() }
            if !inString {
                if ch == "{" { openBraces += 1 }
                else if ch == "}" { openBraces -= 1 }
                else if ch == "[" { openBrackets += 1 }
                else if ch == "]" { openBrackets -= 1 }
            }
            prevChar = ch
        }

        if inString { result += "\"" }
        for _ in 0..<max(0, openBrackets) { result += "]" }
        for _ in 0..<max(0, openBraces) { result += "}" }

        return result
    }

    /// Extract integer glucose values cited in AI reasoning text.
    /// Looks for patterns like "145 mg/dL", "glucose of 132", "average 128 mg/dL", etc.
    /// Used for citation verification per Street (2026) recommendation #3.
    private func extractCitedGlucoseValues(from text: String) -> [Int] {
        // Match numbers in plausible glucose range (40-400) followed by mg/dL or preceded by glucose-related words
        let patterns = [
            "([0-9]{2,3})\\s*mg/dL",           // "145 mg/dL"
            "glucose.*?([0-9]{2,3})",            // "glucose of 145"
            "average.*?([0-9]{2,3})",            // "average 145"
            "([0-9]{2,3})\\s*mg/dl"             // case-insensitive variant
        ]
        var values: [Int] = []
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for match in matches {
                if match.numberOfRanges > 1,
                   let range = Range(match.range(at: 1), in: text),
                   let value = Int(text[range]),
                   value >= 40 && value <= 400 {
                    values.append(value)
                }
            }
        }
        // Deduplicate while preserving order
        var seen = Set<Int>()
        return values.filter { seen.insert($0).inserted }
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
