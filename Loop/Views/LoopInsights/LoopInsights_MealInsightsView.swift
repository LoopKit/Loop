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
/// "Recent Meals" tab shows meals with glucose response cards and expandable AI debriefs.
/// "Pre-Meal Advice" tab lets user pick a food type and see historical pattern + AI advice.
struct LoopInsights_MealInsightsView: View {

    let coordinator: LoopInsights_Coordinator

    @StateObject private var viewModel: LoopInsights_MealInsightsViewModel
    @State private var selectedTab = 0
    @Environment(\.dismiss) private var dismiss

    init(coordinator: LoopInsights_Coordinator) {
        self.coordinator = coordinator
        _viewModel = StateObject(wrappedValue: LoopInsights_MealInsightsViewModel(coordinator: coordinator))
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                Text(NSLocalizedString("Recent Meals", comment: "LoopInsights meal tab: recent")).tag(0)
                Text(NSLocalizedString("Pre-Meal Advice", comment: "LoopInsights meal tab: advice")).tag(1)
            }
            .pickerStyle(.segmented)
            .padding()

            if viewModel.isLoading {
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
            await viewModel.loadMealData()
        }
    }

    // MARK: - Recent Meals Tab

    private var recentMealsTab: some View {
        Group {
            if viewModel.mealEvents.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "fork.knife")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text(NSLocalizedString("No recent meals found. Log meals with FoodFinder or carb entries to see them here.", comment: "LoopInsights no meals"))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        // Color key
                        HStack(spacing: 16) {
                            HStack(spacing: 4) {
                                Circle().fill(Color.green).frame(width: 8, height: 8)
                                Text(NSLocalizedString("Rise is \u{2264} 50 mg/dL", comment: "LoopInsights meal legend green"))
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

                        ForEach(viewModel.mealEvents) { event in
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
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
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
                }

                if let thumbID = event.thumbnailID,
                   let uiImage = FavoriteFoodImageStore.loadThumbnail(id: thumbID) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 48, height: 48)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color(.systemGray4), lineWidth: 0.5)
                        )
                }
            }

            // Nutritional breakdown (when available from FoodFinder analysis)
            if event.hasNutritionalData {
                HStack(spacing: 12) {
                    if let protein = event.totalProtein {
                        nutrientLabel("P", value: protein, unit: "g")
                    }
                    if let fat = event.totalFat {
                        nutrientLabel("F", value: fat, unit: "g")
                    }
                    if let fiber = event.totalFiber {
                        nutrientLabel("Fb", value: fiber, unit: "g")
                    }
                    if let cal = event.totalCalories {
                        nutrientLabel("Cal", value: cal, unit: "")
                    }
                    Spacer()
                }
            }

            // Insulin dosing row
            if event.hasDoseData, let units = event.bolusUnits {
                HStack(spacing: 6) {
                    Image(systemName: "syringe")
                        .font(.caption)
                        .foregroundColor(.blue)

                    if let manual = event.manualBolus, let auto = event.automaticBolus, manual > 0, auto > 0 {
                        Text(String(format: "%.1fU manual + %.1fU auto", manual, auto))
                            .font(.caption)
                            .foregroundColor(.blue)
                    } else {
                        Text(String(format: "%.1fU bolused", units))
                            .font(.caption)
                            .foregroundColor(.blue)
                    }

                    if let cr = event.effectiveCarbRatio {
                        Text("·")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(String(format: "CR %.0f:1", cr))
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
            }

            if event.hasGlucoseData,
               let preMeal = event.preMealGlucose,
               let peak = event.peakGlucose,
               let twoHour = event.twoHourGlucose {
                // Glucose response summary
                HStack(spacing: 16) {
                    glucoseStatPill(
                        label: NSLocalizedString("Pre", comment: "LoopInsights meal pre-meal label"),
                        value: String(format: "%.0f", preMeal),
                        color: glucoseColor(preMeal)
                    )
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    glucoseStatPill(
                        label: NSLocalizedString("Peak", comment: "LoopInsights meal peak label"),
                        value: String(format: "%.0f", peak),
                        color: glucoseColor(peak)
                    )
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    glucoseStatPill(
                        label: "2h",
                        value: String(format: "%.0f", twoHour),
                        color: glucoseColor(twoHour)
                    )
                }

                // Rise indicator
                let rise = peak - preMeal
                HStack(spacing: 4) {
                    Image(systemName: rise > 50 ? "arrow.up.circle.fill" : "arrow.up.circle")
                        .foregroundColor(rise > 50 ? .orange : .green)
                        .font(.caption)
                    Text(String(format: NSLocalizedString("Rise: %+.0f mg/dL", comment: "LoopInsights meal glucose rise"), rise))
                        .font(.caption)
                        .foregroundColor(rise > 50 ? .orange : .green)

                    if event.hasDoseData, let units = event.bolusUnits, units > 0 {
                        Text("·")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(String(format: "%.1f mg/dL per unit", rise / units))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                // No glucose data yet
                HStack(spacing: 6) {
                    let hoursAgo = Date().timeIntervalSince(event.date) / 3600
                    if hoursAgo < 4 {
                        Image(systemName: "clock")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(NSLocalizedString("Glucose response data collecting...", comment: "LoopInsights meal waiting for glucose"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Image(systemName: "waveform.path.ecg")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(NSLocalizedString("No glucose data matched", comment: "LoopInsights meal no glucose data"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            // AI Meal Debrief section (expandable)
            if LoopInsights_FeatureFlags.mealDebriefEnabled && event.hasGlucoseData {
                let readiness = viewModel.debriefReadiness(for: event)
                if case .featureDisabled = readiness {
                    // Don't show anything
                } else {
                    Divider()
                    LoopInsights_MealDebriefCard(
                        event: event,
                        readiness: readiness,
                        debrief: viewModel.debriefResults[event.id.uuidString],
                        isLoading: viewModel.debriefLoadingIDs.contains(event.id.uuidString),
                        errorMessage: viewModel.debriefErrors[event.id.uuidString],
                        isExpanded: viewModel.expandedDebriefID == event.id.uuidString,
                        onToggle: { viewModel.toggleDebrief(for: event) }
                    )
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    private func nutrientLabel(_ label: String, value: Double, unit: String) -> some View {
        HStack(spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(String(format: "%.0f%@", value, unit))
                .font(.caption2.weight(.medium))
                .foregroundColor(.primary)
        }
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
                if viewModel.foodPatterns.isEmpty {
                    Text(NSLocalizedString("No food-type patterns available. Log meals with food types to see patterns.", comment: "LoopInsights no food patterns"))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding()
                } else {
                    Text(NSLocalizedString("Select a food type to see your historical glucose response and get AI advice:", comment: "LoopInsights food pattern instructions"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)

                    ForEach(viewModel.foodPatterns) { pattern in
                        foodPatternCard(pattern)
                    }

                    if let advice = viewModel.aiAdvice {
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
            viewModel.requestAdvice(for: pattern)
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
                    if viewModel.selectedPattern?.id == pattern.id {
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

                if viewModel.isLoadingAdvice && viewModel.selectedPattern?.id == pattern.id {
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
                    .fill(viewModel.selectedPattern?.id == pattern.id
                        ? Color.accentColor.opacity(0.08)
                        : Color(.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(viewModel.selectedPattern?.id == pattern.id ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
    }

    // MARK: - Formatters

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()
}
