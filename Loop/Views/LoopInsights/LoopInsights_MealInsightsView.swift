//
//  LoopInsights_MealInsightsView.swift
//  Loop
//
//  Concept & design by Taylor Patterson. Coded & tested by Claude Code in February 2026.
//  Copyright (c) 2025-2026 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopKit
import HealthKit

/// Combined Meal Debrief + Pre-Meal Advisor view.
/// "Recent Meals" tab shows meals with glucose response cards.
/// "Pre-Meal Advice" tab lets user pick a food type and see historical pattern + AI advice.
struct LoopInsights_MealInsightsView: View {

    let coordinator: LoopInsights_Coordinator

    @State private var selectedTab = 0
    @State private var mealEvents: [LoopInsightsMealEvent] = []
    @State private var foodPatterns: [LoopInsightsFoodResponsePattern] = []
    @State private var isLoading = true
    @State private var selectedPattern: LoopInsightsFoodResponsePattern?
    @State private var aiAdvice: String?
    @State private var isLoadingAdvice = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                Text(NSLocalizedString("Recent Meals", comment: "LoopInsights meal tab: recent")).tag(0)
                Text(NSLocalizedString("Pre-Meal Advice", comment: "LoopInsights meal tab: advice")).tag(1)
            }
            .pickerStyle(.segmented)
            .padding()

            if isLoading {
                Spacer()
                ProgressView()
                Text(NSLocalizedString("Analyzing meal data...", comment: "LoopInsights meals loading"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            } else if selectedTab == 0 {
                recentMealsTab
            } else {
                preMealAdviceTab
            }
        }
        .navigationTitle(NSLocalizedString("Meal Insights", comment: "LoopInsights meal insights title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(NSLocalizedString("Done", comment: "Done button")) {
                    dismiss()
                }
            }
        }
        .task {
            await loadMealData()
        }
    }

    // MARK: - Recent Meals Tab

    private var recentMealsTab: some View {
        Group {
            if mealEvents.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "fork.knife")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text(NSLocalizedString("No recent meals with glucose data found", comment: "LoopInsights no meals"))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        // Color key
                        HStack(spacing: 16) {
                            HStack(spacing: 4) {
                                Circle().fill(Color.green).frame(width: 8, height: 8)
                                Text(NSLocalizedString("Rise is ≤ 50 mg/dL", comment: "LoopInsights meal legend green"))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            HStack(spacing: 4) {
                                Circle().fill(Color.orange).frame(width: 8, height: 8)
                                Text(NSLocalizedString("Rise is > 50 mg/dL", comment: "LoopInsights meal legend orange"))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }

                        ForEach(mealEvents) { event in
                            mealCard(event)
                        }
                    }
                    .padding()
                }
            }
        }
    }

    private func mealCard(_ event: LoopInsightsMealEvent) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(event.foodType)
                .font(.subheadline.weight(.semibold))
            HStack {
                Text(Self.dateFormatter.string(from: event.date))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                Text(String(format: "%.0fg carbs", event.carbs))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Glucose response summary
            HStack(spacing: 16) {
                glucoseStatPill(
                    label: NSLocalizedString("Pre", comment: "LoopInsights meal pre-meal label"),
                    value: String(format: "%.0f", event.preMealGlucose),
                    color: glucoseColor(event.preMealGlucose)
                )
                Image(systemName: "arrow.right")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                glucoseStatPill(
                    label: NSLocalizedString("Peak", comment: "LoopInsights meal peak label"),
                    value: String(format: "%.0f", event.peakGlucose),
                    color: glucoseColor(event.peakGlucose)
                )
                Image(systemName: "arrow.right")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                glucoseStatPill(
                    label: "2h",
                    value: String(format: "%.0f", event.twoHourGlucose),
                    color: glucoseColor(event.twoHourGlucose)
                )
            }

            // Rise indicator
            let rise = event.peakGlucose - event.preMealGlucose
            HStack(spacing: 4) {
                Image(systemName: rise > 50 ? "arrow.up.circle.fill" : "arrow.up.circle")
                    .foregroundColor(rise > 50 ? .orange : .green)
                    .font(.caption)
                Text(String(format: NSLocalizedString("Rise: %+.0f mg/dL", comment: "LoopInsights meal glucose rise"), rise))
                    .font(.caption)
                    .foregroundColor(rise > 50 ? .orange : .green)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    private func glucoseStatPill(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.caption.weight(.bold))
                .foregroundColor(color)
        }
        .frame(minWidth: 44)
    }

    private func glucoseColor(_ value: Double) -> Color {
        if value < 70 { return .red }
        if value <= 180 { return .green }
        return .orange
    }

    // MARK: - Pre-Meal Advice Tab

    private var preMealAdviceTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if foodPatterns.isEmpty {
                    Text(NSLocalizedString("No food-type patterns available. Log meals with food types to see patterns.", comment: "LoopInsights no food patterns"))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding()
                } else {
                    Text(NSLocalizedString("Select a food type to see your historical glucose response and get AI advice:", comment: "LoopInsights food pattern instructions"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)

                    ForEach(foodPatterns) { pattern in
                        foodPatternCard(pattern)
                    }

                    if let advice = aiAdvice {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 6) {
                                Image(systemName: "sparkles")
                                    .foregroundColor(.accentColor)
                                Text(NSLocalizedString("AI Advice", comment: "LoopInsights AI advice header"))
                                    .font(.subheadline.weight(.semibold))
                            }
                            Text(advice)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color(.secondarySystemGroupedBackground))
                        .cornerRadius(12)
                        .padding(.horizontal)
                    }
                }
            }
            .padding(.vertical)
        }
    }

    private func foodPatternCard(_ pattern: LoopInsightsFoodResponsePattern) -> some View {
        Button(action: {
            selectedPattern = pattern
            requestAdvice(for: pattern)
        }) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(pattern.foodType)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)
                    Spacer()
                    Text(String(format: "%d meals", pattern.mealCount))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if selectedPattern?.id == pattern.id {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.accentColor)
                    }
                }

                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(NSLocalizedString("Peak Rise", comment: "LoopInsights peak rise label"))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(String(format: "+%.0f mg/dL", pattern.peakGlucoseRise))
                            .font(.caption.weight(.bold))
                            .foregroundColor(pattern.peakGlucoseRise > 60 ? .orange : .green)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(NSLocalizedString("Time to Peak", comment: "LoopInsights time to peak label"))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(String(format: "%.0f min", pattern.timeToPeakMinutes))
                            .font(.caption.weight(.bold))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(NSLocalizedString("Avg Carbs", comment: "LoopInsights avg carbs label"))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(String(format: "%.0fg", pattern.averageCarbsPerMeal))
                            .font(.caption.weight(.bold))
                    }
                }

                if isLoadingAdvice && selectedPattern?.id == pattern.id {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text(NSLocalizedString("Getting advice...", comment: "LoopInsights getting advice"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(selectedPattern?.id == pattern.id
                        ? Color.accentColor.opacity(0.08)
                        : Color(.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(selectedPattern?.id == pattern.id ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
    }

    // MARK: - Data Loading

    private func loadMealData() async {
        let period = LoopInsights_FeatureFlags.analysisPeriod
        let endDate = Date()
        let startDate = endDate.addingTimeInterval(-period.timeInterval)

        do {
            let carbEntries = try await coordinator.fetchCarbEntries(start: startDate, end: endDate)
            let glucoseSamples = try await coordinator.fetchGlucoseSamples(start: startDate, end: endDate)

            let events = LoopInsights_FoodResponseAnalyzer.buildRecentMealEvents(
                carbEntries: carbEntries,
                glucoseSamples: glucoseSamples
            )
            let patterns = LoopInsights_FoodResponseAnalyzer.analyzeFoodResponses(
                carbEntries: carbEntries,
                glucoseSamples: glucoseSamples
            )

            await MainActor.run {
                self.mealEvents = events
                self.foodPatterns = patterns
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.isLoading = false
            }
        }
    }

    private func requestAdvice(for pattern: LoopInsightsFoodResponsePattern) {
        isLoadingAdvice = true
        aiAdvice = nil

        let prompt = """
        Based on my glucose response pattern for \(pattern.foodType):
        - Average carbs: \(String(format: "%.0f", pattern.averageCarbsPerMeal))g per meal
        - Peak glucose rise: \(String(format: "%.0f", pattern.peakGlucoseRise)) mg/dL
        - Time to peak: \(String(format: "%.0f", pattern.timeToPeakMinutes)) minutes
        - 2h post-meal average: \(String(format: "%.0f", pattern.twoHourPostMealAvg)) mg/dL
        - 4h post-meal average: \(String(format: "%.0f", pattern.fourHourPostMealAvg)) mg/dL

        Give me brief, practical advice for managing this food. Include: timing of pre-bolus, \
        any carb ratio considerations, and alternative strategies. Keep it under 4 sentences.
        """

        Task {
            do {
                let response = try await LoopInsights_AIServiceAdapter.shared.sendPrompt(
                    "You are a diabetes meal advisor. Be concise and practical.",
                    userPrompt: prompt
                )
                await MainActor.run {
                    self.aiAdvice = response
                    self.isLoadingAdvice = false
                }
            } catch {
                await MainActor.run {
                    self.aiAdvice = "Unable to get advice: \(error.localizedDescription)"
                    self.isLoadingAdvice = false
                }
            }
        }
    }

    // MARK: - Formatters

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()
}
