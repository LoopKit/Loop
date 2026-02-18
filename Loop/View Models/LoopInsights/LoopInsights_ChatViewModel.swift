//
//  LoopInsights_ChatViewModel.swift
//  Loop
//
//  Concept & design by Taylor Patterson. Coded & tested by Claude Code in February 2026.
//  Copyright (c) 2025-2026 LoopKit Authors. All rights reserved.
//

import Foundation
import Combine

/// View model for the LoopInsights chat interface.
/// Manages the conversation session, builds chat prompts, sends messages
/// through AIServiceAdapter, and provides quick-ask suggestion chips.
final class LoopInsights_ChatViewModel: ObservableObject {

    // MARK: - Published State

    @Published var messages: [LoopInsightsChatMessage] = []
    @Published var isLoading = false
    @Published var inputText = ""
    @Published var errorMessage: String?
    @Published var isSpeaking = false

    // MARK: - Dependencies

    private let session: LoopInsightsChatSession
    private let coordinator: LoopInsights_Coordinator
    private let serviceAdapter: LoopInsights_AIServiceAdapter
    let voiceService = LoopInsights_VoiceService()
    private var pendingVoiceMessage = false
    private var autoSendTimer: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()

    /// Pre-built quick-ask suggestions shown when the conversation is empty
    let quickAskSuggestions: [String] = [
        NSLocalizedString("Why am I high overnight?", comment: "LoopInsights quick ask: overnight highs"),
        NSLocalizedString("How's my basal rate?", comment: "LoopInsights quick ask: basal rate review"),
        NSLocalizedString("Analyze my last 3 days", comment: "LoopInsights quick ask: recent analysis"),
        NSLocalizedString("What should I change first?", comment: "LoopInsights quick ask: priority"),
        NSLocalizedString("Am I bolusing enough for meals?", comment: "LoopInsights quick ask: meal bolus"),
        NSLocalizedString("Why do I go low after exercise?", comment: "LoopInsights quick ask: exercise lows"),
    ]

    // MARK: - Initialization

    init(coordinator: LoopInsights_Coordinator, serviceAdapter: LoopInsights_AIServiceAdapter = .shared) {
        self.coordinator = coordinator
        self.serviceAdapter = serviceAdapter
        self.session = LoopInsightsChatSession()

        session.$messages
            .receive(on: DispatchQueue.main)
            .assign(to: &$messages)

        voiceService.$isSpeaking
            .receive(on: DispatchQueue.main)
            .assign(to: &$isSpeaking)
    }

    // MARK: - Actions

    /// Send the current input text as a message
    func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isLoading else { return }

        let isVoice = pendingVoiceMessage
        pendingVoiceMessage = false
        autoSendTimer?.cancel()
        autoSendTimer = nil

        inputText = ""
        errorMessage = nil
        voiceService.stopSpeaking()

        let userMessage = LoopInsightsChatMessage(role: .user, content: text, voiceInitiated: isVoice)
        session.appendMessage(userMessage)

        isLoading = true

        Task { @MainActor in
            do {
                var snapshot: LoopInsightsTherapySnapshot?
                do { snapshot = try coordinator.captureCurrentSnapshot() }
                catch { LoopInsights_FeatureFlags.log.error("Chat: failed to capture snapshot: \(error)") }

                var stats: LoopInsightsAggregatedStats?
                do { stats = try await coordinator.dataAggregator.aggregateData(period: LoopInsights_FeatureFlags.analysisPeriod) }
                catch { LoopInsights_FeatureFlags.log.error("Chat: failed to aggregate data: \(error)") }
                let context = Self.buildTherapyContext(snapshot: snapshot, stats: stats)

                let history = session.conversationHistory().dropLast().map { ($0.role, $0.content) }

                let systemPrompt = buildChatSystemPrompt(therapyContext: context)
                let userPrompt = buildUserPrompt(message: text, conversationHistory: Array(history))

                let response = try await serviceAdapter.sendPrompt(systemPrompt, userPrompt: userPrompt)

                let aiMessage = LoopInsightsChatMessage(role: .assistant, content: response, voiceInitiated: isVoice)
                session.appendMessage(aiMessage)

                isLoading = false

                if isVoice {
                    voiceService.speak(response)
                }

            } catch {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    /// Send a quick-ask suggestion
    func sendQuickAsk(_ question: String) {
        inputText = question
        sendMessage()
    }

    /// Called from the view's `.onChange(of: inputText)` to detect dictation vs typing
    func handleTextChange(oldValue: String, newValue: String) {
        let changeSize = newValue.count - oldValue.count
        let isAppend = newValue.hasPrefix(oldValue) || oldValue.isEmpty

        if isAppend && changeSize >= 4 {
            pendingVoiceMessage = true
        } else if changeSize == 1 || changeSize == -1 {
            pendingVoiceMessage = false
        }

        autoSendTimer?.cancel()
        if pendingVoiceMessage && !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let timer = DispatchWorkItem { [weak self] in
                self?.sendMessage()
            }
            autoSendTimer = timer
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: timer)
        }
    }

    /// Stop any active TTS playback
    func stopSpeaking() {
        voiceService.stopSpeaking()
    }

    /// Clear the conversation and start fresh
    func clearConversation() {
        voiceService.stopSpeaking()
        session.clear()
        errorMessage = nil
    }

    // MARK: - Chat Prompt Building

    private func buildChatSystemPrompt(therapyContext: String) -> String {
        let personality = LoopInsights_FeatureFlags.aiPersonality

        return """
        You are an expert diabetes and automated insulin delivery (AID) advisor embedded \
        in the Loop app. The user is wearing an insulin pump managed by Loop's closed-loop \
        algorithm. You have access to their REAL therapy settings, glucose data, insulin \
        delivery data, carb logs, and biometrics — all provided below. This is not hypothetical. \
        These are this specific person's actual numbers from their actual pump and CGM.

        \(personality.promptInstruction)

        YOUR #1 RULE — ALWAYS ANSWER FROM THEIR DATA:
        The entire value of this conversation is that you can see this person's real numbers. \
        Every answer you give MUST reference their specific data. Do NOT give generic diabetes \
        advice that could apply to anyone. The user can Google generic advice — they came here \
        because you can see their TIR, their hourly glucose patterns, their basal/bolus split, \
        their correction counts, their actual settings schedules. USE THEM.

        When the user asks "why am I high overnight?", don't explain what causes overnight highs \
        in general — look at THEIR hourly averages from 12AM-6AM, THEIR basal rate during those \
        hours, THEIR overnight trend, and tell them what's happening in THEIR data specifically.

        When they ask "should I change my carb ratio?", don't explain what a carb ratio does — \
        look at THEIR post-meal glucose patterns, THEIR current CR schedule, THEIR carb stats, \
        and give them a specific assessment with specific numbers.

        GUIDELINES:
        - Ground every answer in their actual data. Cite specific numbers: "Your average glucose \
          between 12AM-6AM is 162 mg/dL with your basal at 0.8 U/hr" — not "overnight highs can \
          be caused by insufficient basal."
        - When their data tells a clear story, say so directly. When the data is ambiguous or \
          insufficient, say that too — but explain exactly what's missing and why it matters.
        - If asked about settings changes, reference their current value, explain what the data \
          suggests, and propose a specific adjustment with expected impact.
        - Frame suggestions as suggestions, not commands. Significant therapy changes should be \
          discussed with their healthcare provider.
        - Keep responses concise but thorough. Use bullet points for multi-part answers.
        - Never fabricate data or statistics — only reference what's provided in the context below.
        - If the data context says "No therapy data currently available", tell the user you don't \
          have their data loaded yet and suggest they run an analysis first.

        CURRENT DATA CONTEXT:
        \(therapyContext)
        """
    }

    private func buildUserPrompt(
        message: String,
        conversationHistory: [(role: String, content: String)]
    ) -> String {
        if conversationHistory.isEmpty {
            return message
        }

        var prompt = "CONVERSATION HISTORY:\n"
        let recentHistory = conversationHistory.suffix(10)
        for entry in recentHistory {
            let roleLabel = entry.role == "user" ? "User" : "Assistant"
            prompt += "\(roleLabel): \(entry.content)\n\n"
        }
        prompt += "User: \(message)"
        return prompt
    }

    // MARK: - Therapy Context

    /// Build a therapy context string from a snapshot and stats.
    static func buildTherapyContext(
        snapshot: LoopInsightsTherapySnapshot?,
        stats: LoopInsightsAggregatedStats?
    ) -> String {
        var context = ""

        if let snapshot = snapshot {
            context += "CURRENT THERAPY SETTINGS:\n"

            context += "Basal Rates:\n"
            for item in snapshot.basalRateItems {
                context += "  \(formatTime(item.startTime)): \(String(format: "%.2f", item.value)) U/hr\n"
            }

            context += "Carb Ratios:\n"
            for item in snapshot.carbRatioItems {
                context += "  \(formatTime(item.startTime)): \(String(format: "%.1f", item.value)) g/U\n"
            }

            context += "Insulin Sensitivity Factors:\n"
            for item in snapshot.insulinSensitivityItems {
                context += "  \(formatTime(item.startTime)): \(String(format: "%.0f", item.value)) mg/dL per U\n"
            }
        }

        if let stats = stats {
            context += "\nRECENT GLUCOSE STATISTICS (\(stats.period.displayName)):\n"
            context += "  Average Glucose: \(String(format: "%.0f", stats.glucoseStats.averageGlucose)) mg/dL\n"
            context += "  Time in Range (70-180): \(String(format: "%.1f", stats.glucoseStats.timeInRange))%\n"
            context += "  Time Below Range (<70): \(String(format: "%.1f", stats.glucoseStats.timeBelowRange))%\n"
            context += "  Time Above Range (>180): \(String(format: "%.1f", stats.glucoseStats.timeAboveRange))%\n"
            context += "  GMI (est. A1C): \(String(format: "%.1f", stats.glucoseStats.gmi))%\n"
            context += "  Coefficient of Variation: \(String(format: "%.1f", stats.glucoseStats.coefficientOfVariation))%\n"
            context += "  Standard Deviation: \(String(format: "%.1f", stats.glucoseStats.standardDeviation)) mg/dL\n"

            context += "\nINSULIN STATISTICS:\n"
            context += "  Total Daily Dose: \(String(format: "%.1f", stats.insulinStats.totalDailyDose)) U/day\n"
            context += "  Basal %: \(String(format: "%.0f", stats.insulinStats.basalPercentage))%\n"
            context += "  Bolus %: \(String(format: "%.0f", stats.insulinStats.bolusPercentage))%\n"
            context += "  Correction Boluses: \(stats.insulinStats.correctionBolusCount)\n"

            context += "\nCARB STATISTICS:\n"
            context += "  Average Daily Carbs: \(String(format: "%.0f", stats.carbStats.averageDailyCarbs)) g/day\n"
            context += "  Average Carbs Per Meal: \(String(format: "%.0f", stats.carbStats.averageCarbsPerMeal)) g\n"
            context += "  Total Meals Logged: \(stats.carbStats.mealCount)\n"

            if !stats.glucoseStats.hourlyAverages.isEmpty {
                context += "\nHOURLY GLUCOSE AVERAGES:\n"
                for hour in 0..<24 {
                    if let avg = stats.glucoseStats.hourlyAverages[hour] {
                        context += "  \(String(format: "%02d", hour)):00 — \(String(format: "%.0f", avg)) mg/dL\n"
                    }
                }
            }

            if let bio = stats.biometricStats {
                context += "\nBIOMETRIC DATA:\n"

                if let hr = bio.heartRate {
                    context += "  Resting HR: \(String(format: "%.0f", hr.averageRestingHR)) bpm\n"
                    context += "  Active HR: \(String(format: "%.0f", hr.averageActiveHR)) bpm\n"
                }

                if let hrv = bio.hrv {
                    context += "  HRV (SDNN): \(String(format: "%.1f", hrv.averageSDNN)) ms (trend: \(hrv.trend >= 0 ? "+" : "")\(String(format: "%.1f", hrv.trend)))\n"
                }

                if let steps = bio.steps {
                    context += "  Avg Daily Steps: \(String(format: "%.0f", steps.averageDailySteps))\n"
                }

                if let sleep = bio.sleep {
                    context += "  Avg Sleep: \(String(format: "%.1f", sleep.averageDurationHours)) hrs/night\n"
                    context += "  Avg Bedtime: \(Self.formatTimeFromSeconds(sleep.averageBedtime))\n"
                    context += "  Avg Wake: \(Self.formatTimeFromSeconds(sleep.averageWakeTime))\n"
                }

                if let energy = bio.activeEnergy {
                    context += "  Avg Active Calories: \(String(format: "%.0f", energy.averageDailyCalories)) kcal/day\n"
                }

                if let weight = bio.weight {
                    context += "  Weight: \(String(format: "%.1f", weight.latestWeight)) kg (trend: \(weight.weightTrend >= 0 ? "+" : "")\(String(format: "%.1f", weight.weightTrend)) kg)\n"
                }
            }
        }

        if context.isEmpty {
            context = "No therapy data currently available."
        }

        return context
    }

    private static func formatTime(_ seconds: TimeInterval) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        var calendar = Calendar.current
        calendar.timeZone = TimeZone.current
        let date = calendar.startOfDay(for: Date()).addingTimeInterval(seconds)
        return formatter.string(from: date)
    }

    private static func formatTimeFromSeconds(_ seconds: Double) -> String {
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let period = hours >= 12 ? "PM" : "AM"
        let displayHour = hours == 0 ? 12 : (hours > 12 ? hours - 12 : hours)
        return String(format: "%d:%02d %@", displayHour, minutes, period)
    }
}
