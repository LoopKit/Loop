//
//  LoopInsights_DashboardView.swift
//  Loop
//
//  Concept & design by Taylor Patterson. Coded & tested by Claude Code in February 2026.
//  Copyright (c) 2025-2026 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopKit

/// Primary entry-point view for LoopInsights. Displays current therapy settings
/// summary, AI suggestion cards, analysis trigger, and navigation to history.
///
/// NOTE: This view uses a plain `var` for the viewModel rather than @ObservedObject.
/// The parent view (wrapper/container) is responsible for observing the viewModel's
/// objectWillChange and triggering re-renders. This avoids a silent SwiftUI crash
/// that occurs when @ObservedObject subscribes to the ViewModel's publisher
/// during the sheet presentation rendering cycle.
struct LoopInsights_DashboardView: View {

    var viewModel: LoopInsights_DashboardViewModel
    /// Changed by the parent container on every ViewModel objectWillChange,
    /// forcing SwiftUI to re-evaluate this view's body.
    var renderTrigger: Int = 0

    @State private var showingHistory = false
    @State private var selectedRecord: LoopInsightsSuggestionRecord?
    @State private var developerTapCount = 0

    // Manual Bindings — required because viewModel is not @ObservedObject
    private var analysisPeriodBinding: Binding<LoopInsightsAnalysisPeriod> {
        Binding(
            get: { viewModel.analysisPeriod },
            set: { viewModel.updateAnalysisPeriod($0) }
        )
    }

    private var showingApplyConfirmationBinding: Binding<Bool> {
        Binding(
            get: { viewModel.showingApplyConfirmation },
            set: { viewModel.showingApplyConfirmation = $0 }
        )
    }

    var body: some View {
        List {
            headerSection
            currentSettingsSection
            analysisSection
            if !viewModel.detectedPatterns.isEmpty {
                detectedPatternsSection
            }
            if viewModel.overallAssessment != nil {
                assessmentSection
            }
            if !viewModel.pendingSuggestions.isEmpty {
                pendingSuggestionsSection
            }
            navigationSection
        }
        .navigationTitle(NSLocalizedString("LoopInsights", comment: "LoopInsights dashboard title"))
        .sheet(item: $selectedRecord) { record in
            NavigationView {
                LoopInsights_SuggestionDetailView(
                    record: record,
                    onApply: { viewModel.applySuggestion(record) },
                    onDismiss: { viewModel.dismissSuggestion(record) }
                )
            }
        }
        .sheet(isPresented: $showingHistory) {
            NavigationView {
                LoopInsights_SuggestionHistoryView(store: viewModel.suggestionStore)
            }
        }
        .alert(
            NSLocalizedString("Apply Suggestion", comment: "LoopInsights apply confirmation title"),
            isPresented: showingApplyConfirmationBinding
        ) {
            Button(NSLocalizedString("Apply", comment: "LoopInsights apply button"), role: .destructive) {
                viewModel.confirmApply()
            }
            Button(NSLocalizedString("Cancel", comment: "Cancel button"), role: .cancel) {
                viewModel.cancelApply()
            }
        } message: {
            Text(NSLocalizedString(
                "This will modify your therapy settings. You are responsible for reviewing and verifying all changes. AI suggestions are advisory and may not be appropriate for your situation. Consult your healthcare provider for significant therapy adjustments.",
                comment: "LoopInsights apply disclaimer"
            ))
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "brain.head.profile")
                        .font(.title2)
                        .foregroundColor(.accentColor)
                    Text(NSLocalizedString("LoopInsights", comment: "LoopInsights header"))
                        .font(.title2)
                        .fontWeight(.bold)
                }
                .onLongPressGesture(minimumDuration: 1) {
                    handleDeveloperTap()
                }

                Text(NSLocalizedString("LoopInsights analyzes your glucose, insulin, and carb data to suggest adjustments to your Basal Rates, Carb Ratios, and Insulin Sensitivity factors. Tap one of the settings, choose a lookback period, and tap Analyze to get AI-generated suggestions. All changes require your review and approval.", comment: "LoopInsights subtitle"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                if let lastDate = viewModel.lastAnalysisDate {
                    Text(String(format: NSLocalizedString("Last analysis: %@", comment: "LoopInsights last analysis date"), Self.dateFormatter.string(from: lastDate)))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Current Settings

    private var currentSettingsSection: some View {
        Section(header: Text(NSLocalizedString("Pick from your Current Therapy Settings", comment: "LoopInsights current settings header"))) {
            if let snapshot = viewModel.currentSnapshot {
                settingRow(
                    type: .carbRatio,
                    items: snapshot.carbRatioItems,
                    unit: "g/U"
                )
                settingRow(
                    type: .insulinSensitivity,
                    items: snapshot.insulinSensitivityItems,
                    unit: "mg/dL/U"
                )
                settingRow(
                    type: .basalRate,
                    items: snapshot.basalRateItems,
                    unit: "U/hr"
                )
                HStack(spacing: 16) {
                    legendDot(color: .gray, label: NSLocalizedString("Not analyzed", comment: "LoopInsights legend: not analyzed"))
                    legendDot(color: .green, label: NSLocalizedString("No changes", comment: "LoopInsights legend: OK"))
                    legendDot(color: .purple, label: NSLocalizedString("Review", comment: "LoopInsights legend: review"))
                }
                .font(.caption2)
                .foregroundColor(.secondary)
            } else {
                Text(NSLocalizedString("Loading therapy settings...", comment: "LoopInsights loading settings"))
                    .foregroundColor(.secondary)
            }
        }
    }

    private func settingRow(type: LoopInsightsSettingType, items: [LoopInsightsTherapySnapshot.LoopInsightsScheduleItem], unit: String) -> some View {
        let status = viewModel.settingStatus(type)
        return HStack {
            // Status indicator dot
            Circle()
                .fill(settingStatusColor(status))
                .frame(width: 8, height: 8)
            Image(systemName: type.systemImage)
                .foregroundColor(.accentColor)
                .frame(width: 24)
            VStack(alignment: .leading) {
                Text(type.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                if items.count == 1 {
                    Text("\(String(format: "%.1f", items[0].value)) \(unit)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text(String(format: NSLocalizedString("%d time blocks", comment: "LoopInsights time block count"), items.count))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            if viewModel.focusSettingType == type {
                Image(systemName: "target")
                    .foregroundColor(.accentColor)
                    .font(.caption)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.focusSettingType = type
        }
    }

    // MARK: - Analysis

    private var analysisSection: some View {
        Section {
            // Period picker
            Picker(NSLocalizedString("Analysis Period", comment: "LoopInsights period picker label"), selection: analysisPeriodBinding) {
                ForEach(LoopInsightsAnalysisPeriod.allCases) { period in
                    Text(period.displayName).tag(period)
                }
            }

            // Analyze button
            Button(action: { viewModel.runAnalysis() }) {
                HStack {
                    Spacer()
                    if viewModel.isAnalyzing {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .tint(.white)
                            .padding(.trailing, 8)
                        Text(NSLocalizedString("Analyzing...", comment: "LoopInsights analyzing"))
                    } else {
                        Image(systemName: "sparkles")
                        Text(String(format: NSLocalizedString("Analyze %@", comment: "LoopInsights analyze button"), viewModel.focusSettingType.abbreviation))
                    }
                    Spacer()
                }
                .font(.body.weight(.medium))
                .foregroundColor(.white)
                .padding(.vertical, 10)
                .background(
                    (viewModel.isAnalyzing || !LoopInsights_SecureStorage.hasAPIKey)
                        ? Color(red: 0.2, green: 0.6, blue: 0.2)
                        : Color.green
                )
                .cornerRadius(10)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isAnalyzing || !LoopInsights_SecureStorage.hasAPIKey)

            if !LoopInsights_SecureStorage.hasAPIKey {
                Text(NSLocalizedString("Configure your AI API key in LoopInsights Settings to begin analysis.", comment: "LoopInsights no API key message"))
                    .font(.caption)
                    .foregroundColor(.orange)
            }

            if let error = viewModel.analysisError {
                Text(error.localizedDescription)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
    }

    // MARK: - Pending Suggestions

    private var pendingSuggestionsSection: some View {
        Section(header: HStack {
            Text(NSLocalizedString("Suggestions for Fine Tuning", comment: "LoopInsights suggestions header"))
            Spacer()
            Button(NSLocalizedString("Dismiss All", comment: "LoopInsights dismiss all button")) {
                viewModel.dismissAllPending()
            }
            .font(.caption)
        }) {
            ForEach(viewModel.pendingSuggestions) { record in
                suggestionCard(record)
            }
            HStack(spacing: 16) {
                Text(NSLocalizedString("Confidence Level:", comment: "LoopInsights confidence legend label"))
                legendDot(color: .blue, label: NSLocalizedString("High", comment: "LoopInsights legend: high"))
                legendDot(color: .orange, label: NSLocalizedString("Medium", comment: "LoopInsights legend: medium"))
                legendDot(color: .yellow, label: NSLocalizedString("Low", comment: "LoopInsights legend: low"))
            }
            .font(.caption2)
            .foregroundColor(.secondary)
        }
    }

    private func suggestionCard(_ record: LoopInsightsSuggestionRecord) -> some View {
        Button(action: { selectedRecord = record }) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: record.suggestion.settingType.systemImage)
                        .foregroundColor(.accentColor)
                    Text(record.suggestion.summaryDescription)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    Spacer()
                    confidenceBadge(record.suggestion.confidence)
                }

                // Show time blocks summary
                ForEach(record.suggestion.timeBlocks) { block in
                    HStack {
                        Text(block.timeRangeFormatted)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(String(format: "%.1f", block.currentValue)) → \(String(format: "%.1f", block.proposedValue))")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(block.proposedValue > block.currentValue ? .orange : .blue)
                        Text("(\(String(format: "%+.0f", block.changePercent))%)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                // Quick action buttons
                HStack {
                    Button(action: { viewModel.applySuggestion(record) }) {
                        Label(NSLocalizedString("Apply", comment: "LoopInsights apply"), systemImage: "checkmark.circle")
                            .font(.caption)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Button(action: { viewModel.dismissSuggestion(record) }) {
                        Label(NSLocalizedString("Dismiss", comment: "LoopInsights dismiss"), systemImage: "xmark.circle")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Spacer()

                    Button(action: { selectedRecord = record }) {
                        Text(NSLocalizedString("Reasoning", comment: "LoopInsight's detailed reasoning"))
                            .font(.caption)
                    }
                    .controlSize(.small)
                }
                .padding(.top, 2)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private func confidenceBadge(_ confidence: LoopInsightsConfidence) -> some View {
        Text(confidence.displayName)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(confidenceColor(confidence).opacity(0.2))
            .foregroundColor(confidenceColor(confidence))
            .cornerRadius(4)
    }

    private func confidenceColor(_ confidence: LoopInsightsConfidence) -> Color {
        switch confidence {
        case .low: return .yellow
        case .medium: return .orange
        case .high: return .blue
        }
    }

    private func settingStatusColor(_ status: LoopInsightsSettingStatus) -> Color {
        switch status {
        case .notAnalyzed: return .gray
        case .analyzedOK: return .green
        case .hasSuggestions: return .purple
        }
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
        }
    }

    // MARK: - Detected Patterns

    private var detectedPatternsSection: some View {
        Section(header: HStack {
            Image(systemName: "waveform.path.ecg")
            Text(NSLocalizedString("Detected Patterns", comment: "LoopInsights detected patterns header"))
        }) {
            ForEach(viewModel.detectedPatterns) { pattern in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: pattern.type.systemImage)
                        .foregroundColor(.accentColor)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(pattern.type.displayName)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text(pattern.detail)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    confidenceBadge(pattern.severity)
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - Assessment

    private var assessmentSection: some View {
        Section(header: Text(NSLocalizedString("AI Assessment", comment: "LoopInsights assessment header"))) {
            if let assessment = viewModel.overallAssessment {
                Text(assessment)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            if let stats = viewModel.aggregatedStats {
                statsRow(label: NSLocalizedString("Time in Range", comment: "LoopInsights TIR label"),
                         value: String(format: "%.1f%%", stats.glucoseStats.timeInRange))
                statsRow(label: NSLocalizedString("Average Glucose", comment: "LoopInsights avg glucose label"),
                         value: String(format: "%.0f mg/dL", stats.glucoseStats.averageGlucose))
                statsRow(label: NSLocalizedString("GMI (est. A1C)", comment: "LoopInsights GMI label"),
                         value: String(format: "%.1f%%", stats.glucoseStats.gmi))
                statsRow(label: NSLocalizedString("Total Daily Dose", comment: "LoopInsights TDD label"),
                         value: String(format: "%.1f U/day", stats.insulinStats.totalDailyDose))
                statsRow(label: NSLocalizedString("CV", comment: "LoopInsights CV label"),
                         value: String(format: "%.1f%%", stats.glucoseStats.coefficientOfVariation))
            }
        }
    }

    private func statsRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
        }
    }

    // MARK: - Navigation

    private var navigationSection: some View {
        Section {
            Button(action: { showingHistory = true }) {
                HStack {
                    Image(systemName: "clock.arrow.circlepath")
                    Text(NSLocalizedString("Suggestion History", comment: "LoopInsights history button"))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Developer Mode

    private func handleDeveloperTap() {
        developerTapCount += 1
        if developerTapCount >= LoopInsights_FeatureFlags.developerUnlockThreshold {
            LoopInsights_FeatureFlags.developerModeEnabled.toggle()
            developerTapCount = 0
            // Haptic feedback
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(LoopInsights_FeatureFlags.developerModeEnabled ? .success : .warning)
        }
    }

    // MARK: - Formatters

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}

