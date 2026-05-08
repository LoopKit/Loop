//
//  LoopInsights_BehaviorInsightsView.swift
//  Loop
//
//  LoopInsights — Shows detected correction patterns from FoodFinder meal data.
//  Users can review how the AI systematically over/under-estimates for specific
//  food types, locations, times of day, or confidence levels.
//
//  Idea by Taylor Patterson. Coded by Claude Code.
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import SwiftUI

struct LoopInsights_BehaviorInsightsView: View {

    @State private var patterns: [LoopInsightsCorrectionPattern] = []
    @State private var isLoading = true
    @State private var selectedGrouping: LoopInsightsCorrectionPattern.GroupingType?

    /// BolusPro behavior patterns rendered in their own section below
    /// the FoodFinder correction patterns.
    @State private var bolusProPatterns: [BolusProBehaviorPattern] = []

    private let tealColor = Color(red: 26/255, green: 138/255, blue: 158/255)

    var body: some View {
        List {
            headerSection

            if isLoading {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                            .padding()
                        Spacer()
                    }
                }
            } else if patterns.isEmpty && bolusProPatterns.isEmpty {
                emptyStateSection
            } else {
                if !patterns.isEmpty {
                    summarySection
                    filterSection
                    patternsSection
                }
                if !bolusProPatterns.isEmpty {
                    bolusProPatternsSection
                }
            }
        }
        .navigationTitle(NSLocalizedString("Behavior Insights", comment: "LoopInsights behavior insights title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { dismiss() }) {
                    Text(NSLocalizedString("Done", comment: "Done button"))
                }
            }
        }
        .onAppear { loadPatterns() }
    }

    @Environment(\.dismiss) private var dismiss

    // MARK: - Header

    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "brain.head.profile")
                        .font(.title2)
                        .foregroundColor(tealColor)
                    Text(NSLocalizedString("Learning from Your Corrections", comment: "Behavior insights header"))
                        .font(.headline)
                }

                Text(NSLocalizedString("When you consistently adjust AI carb estimates for the same foods, we detect the pattern and surface it here. These insights help you understand where the AI needs calibration.", comment: "Behavior insights explanation"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Empty State

    private var emptyStateSection: some View {
        Section {
            VStack(spacing: 12) {
                Image(systemName: "checkmark.circle")
                    .font(.largeTitle)
                    .foregroundColor(.green)

                Text(NSLocalizedString("No Correction Patterns Detected", comment: "Behavior insights empty state title"))
                    .font(.headline)

                Text(NSLocalizedString("The AI estimates are tracking well with your entries. Keep logging meals with FoodFinder — patterns will appear here when we detect consistent adjustments.", comment: "Behavior insights empty state message"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                Text(NSLocalizedString("Patterns require at least 3 meals with corrections in the same food type, location, or time of day.", comment: "Behavior insights threshold note"))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Summary

    private var summarySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(String(format: NSLocalizedString("%d pattern(s) detected", comment: "Behavior insights pattern count"), filteredPatterns.count))
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    if let lastCheck = LoopInsights_BehaviorInsightsStore.lastCheckDate {
                        Text(lastCheck, style: .relative)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                let underCount = filteredPatterns.filter(\.isUnderestimation).count
                let overCount = filteredPatterns.filter(\.isOverestimation).count

                if underCount > 0 || overCount > 0 {
                    HStack(spacing: 12) {
                        if underCount > 0 {
                            Label(String(format: "%d under-estimates", underCount), systemImage: "arrow.up.circle.fill")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                        if overCount > 0 {
                            Label(String(format: "%d over-estimates", overCount), systemImage: "arrow.down.circle.fill")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Filter

    private var filterSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    filterChip(label: "All", isSelected: selectedGrouping == nil) {
                        selectedGrouping = nil
                    }
                    ForEach(availableGroupings, id: \.self) { grouping in
                        filterChip(
                            label: grouping.displayName,
                            isSelected: selectedGrouping == grouping
                        ) {
                            selectedGrouping = grouping
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
        }
    }

    private func filterChip(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? tealColor.opacity(0.2) : Color(.systemGray6))
                .foregroundColor(isSelected ? tealColor : .primary)
                .cornerRadius(16)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Patterns List

    private var patternsSection: some View {
        Section(header: Text(NSLocalizedString("Detected Patterns", comment: "Behavior insights patterns section header"))) {
            ForEach(filteredPatterns) { pattern in
                patternRow(pattern)
            }
        }
    }

    private func patternRow(_ pattern: LoopInsightsCorrectionPattern) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header row
            HStack(spacing: 8) {
                Image(systemName: pattern.groupingType.systemImage)
                    .foregroundColor(tealColor)
                    .font(.subheadline)

                VStack(alignment: .leading, spacing: 2) {
                    Text(pattern.groupingValue)
                        .font(.subheadline.weight(.medium))
                    Text(pattern.groupingType.displayName)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Direction badge
                directionBadge(pattern)
            }

            // Correction detail
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(NSLocalizedString("Avg Correction", comment: "Behavior insights average correction label"))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(String(format: "%@%.0fg", pattern.isUnderestimation ? "+" : "", pattern.averageCorrectionGrams))
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(pattern.isUnderestimation ? .orange : .blue)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(NSLocalizedString("Relative", comment: "Behavior insights relative correction label"))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(String(format: "%@%.0f%%", pattern.isUnderestimation ? "+" : "", pattern.averageCorrectionPercent))
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(pattern.isUnderestimation ? .orange : .blue)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(NSLocalizedString("Meals", comment: "Behavior insights meal count label"))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("\(pattern.mealCount)")
                        .font(.subheadline.weight(.medium))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(NSLocalizedString("Consistency", comment: "Behavior insights consistency label"))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(String(format: "%.0f%%", pattern.consistency * 100))
                        .font(.subheadline.weight(.medium))
                }
            }

            // Recommendation
            HStack(spacing: 6) {
                Image(systemName: "lightbulb.fill")
                    .font(.caption)
                    .foregroundColor(.yellow)
                Text(pattern.recommendedAction)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 2)
        }
        .padding(.vertical, 4)
    }

    private func directionBadge(_ pattern: LoopInsightsCorrectionPattern) -> some View {
        HStack(spacing: 4) {
            Image(systemName: pattern.isUnderestimation ? "arrow.up" : "arrow.down")
                .font(.caption2)
            Text(pattern.isUnderestimation ?
                 NSLocalizedString("Under", comment: "Behavior insights under-estimate badge") :
                 NSLocalizedString("Over", comment: "Behavior insights over-estimate badge"))
                .font(.caption2)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(pattern.isUnderestimation ? Color.orange.opacity(0.15) : Color.blue.opacity(0.15))
        .foregroundColor(pattern.isUnderestimation ? .orange : .blue)
        .cornerRadius(8)
    }

    // MARK: - Computed

    private var filteredPatterns: [LoopInsightsCorrectionPattern] {
        if let grouping = selectedGrouping {
            return patterns.filter { $0.groupingType == grouping }
        }
        return patterns
    }

    private var availableGroupings: [LoopInsightsCorrectionPattern.GroupingType] {
        let types = Set(patterns.map(\.groupingType))
        // Consistent ordering
        return [.foodType, .location, .timeOfDay, .confidenceLevel].filter { types.contains($0) }
    }

    // MARK: - Loading

    private func loadPatterns() {
        DispatchQueue.global(qos: .userInitiated).async {
            let detected = LoopInsights_BehaviorInsightsAnalyzer.analyzePatterns()
            LoopInsights_BehaviorInsightsStore.storePatterns(detected)
            let bolusPro = BolusPro_BehaviorAnalyzer.shared.analyzePatterns()
            DispatchQueue.main.async {
                self.patterns = detected
                self.bolusProPatterns = bolusPro
                self.isLoading = false
            }
        }
    }
}

// MARK: - BolusPro Patterns Section

extension LoopInsights_BehaviorInsightsView {
    private var bolusProPatternsSection: some View {
        Section(header: Text(NSLocalizedString("BolusPro Patterns", comment: "Behavior insights BolusPro section header"))) {
            ForEach(bolusProPatterns) { pattern in
                bolusProPatternRow(pattern)
            }
        }
    }

    private func bolusProPatternRow(_ pattern: BolusProBehaviorPattern) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: pattern.systemImage)
                .font(.title3)
                .foregroundColor((Color(red: 230/255, green: 188/255, blue: 60/255)))
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(pattern.summary)
                    .font(.subheadline.weight(.semibold))
                Text(pattern.detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}
