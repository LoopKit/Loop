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
    @State private var showingDebugLog = false
    @State private var showingChat = false
    @State private var showingTrendsInsights = false
    @State private var showingGoals = false
    @State private var showingMealInsights = false
    @State private var showingCaffeineLog = false
    @State private var showingAlcoholLog = false
    @State private var selectedRecord: LoopInsightsSuggestionRecord?
    @State private var developerTapCount = 0
    @State private var showingSupportedModels = false

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

    private var showingPreFillEditorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.showingPreFillEditor },
            set: { viewModel.showingPreFillEditor = $0 }
        )
    }

    var body: some View {
        List {
            headerSection
            currentSettingsSection
            analysisSection
            if viewModel.aggregatedStats != nil {
                glucoseStatsCards
            }
            if !viewModel.detectedPatterns.isEmpty {
                detectedPatternsSection
            }
            if viewModel.overallAssessment != nil {
                assessmentSection
            }
            if viewModel.settingsScoreBreakdown != nil {
                settingsScoreSection
            }
            if viewModel.settingsAlreadyOptimal && !viewModel.pendingSuggestions.isEmpty {
                optimalWarningBanner
            }
            if !viewModel.autoAppliedSuggestions.isEmpty {
                autoAppliedSection
            }
            if !viewModel.pendingSuggestions.isEmpty {
                pendingSuggestionsSection
            }
            if viewModel.pendingSuggestions.isEmpty && viewModel.analysisResponse != nil && !viewModel.isAnalyzing {
                noChangesSection
            }
            navigationSection
        }
        .modifier(ListSectionSpacingModifier())
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
                LoopInsights_SuggestionHistoryView(
                    store: viewModel.suggestionStore,
                    onRevert: { record in viewModel.revertSuggestion(record) }
                )
            }
        }
        .sheet(isPresented: $showingDebugLog) {
            if let log = viewModel.lastDebugLog {
                NavigationView {
                    LoopInsights_DebugLogView(log: log)
                }
            }
        }
        .alert(
            applyAlertTitle,
            isPresented: showingApplyConfirmationBinding
        ) {
            if let record = viewModel.recordToApply, record.suggestion.hasAbsoluteViolation {
                Button(NSLocalizedString("OK", comment: "OK button"), role: .cancel) {
                    viewModel.cancelApply()
                }
            } else {
                Button(NSLocalizedString("Apply", comment: "LoopInsights apply button"), role: .destructive) {
                    viewModel.confirmApply()
                }
                Button(NSLocalizedString("Cancel", comment: "Cancel button"), role: .cancel) {
                    viewModel.cancelApply()
                }
            }
        } message: {
            Text(applyAlertMessage)
        }
        .sheet(isPresented: showingPreFillEditorBinding) {
            if let record = viewModel.recordToApply {
                NavigationView {
                    LoopInsights_PreFillEditorView(
                        record: record,
                        onApply: { editedBlocks in
                            viewModel.applyEditedSuggestion(editedBlocks: editedBlocks)
                        },
                        onCancel: {
                            viewModel.cancelApply()
                        }
                    )
                }
            }
        }
        .sheet(isPresented: $showingChat) {
            NavigationView {
                LoopInsights_ChatView(
                    viewModel: LoopInsights_ChatViewModel(coordinator: viewModel.coordinator)
                )
            }
        }
        .sheet(isPresented: $showingTrendsInsights) {
            NavigationView {
                LoopInsights_TrendsInsightsView(coordinator: viewModel.coordinator)
            }
        }
        .sheet(isPresented: $showingGoals) {
            NavigationView {
                LoopInsights_GoalsView(coordinator: viewModel.coordinator)
            }
        }
        .sheet(isPresented: $showingMealInsights) {
            NavigationView {
                LoopInsights_MealInsightsView(coordinator: viewModel.coordinator)
            }
        }
        .sheet(isPresented: $showingCaffeineLog) {
            NavigationView {
                LoopInsights_CaffeineLogView(tracker: viewModel.coordinator.caffeineTracker)
            }
        }
        .sheet(isPresented: $showingAlcoholLog) {
            NavigationView {
                LoopInsights_AlcoholLogView(tracker: viewModel.coordinator.alcoholTracker)
            }
        }
        .sheet(isPresented: $showingSupportedModels) {
            supportedModelsView
        }
        .overlay(alignment: .top) {
            if let monitor = viewModel.backgroundMonitor,
               monitor.showBanner,
               let suggestion = monitor.latestBackgroundSuggestion {
                notificationBanner(
                    suggestion: suggestion,
                    onView: {
                        monitor.dismissBanner()
                        viewModel.loadCurrentSettings()
                    },
                    onAsk: {
                        monitor.dismissBanner()
                        showingChat = true
                    },
                    onDismiss: {
                        monitor.dismissBanner()
                    }
                )
            }
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

                Text(NSLocalizedString("Analyzes your glucose, insulin, and carb data to suggest Basal Rate, Carb Ratio, and ISF adjustments. Select a setting and lookback period, then tap Analyze. All changes require approval", comment: "LoopInsights subtitle"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                if let lastDate = viewModel.lastAnalysisDate {
                    Text(String(format: NSLocalizedString("Last analysis: %@", comment: "LoopInsights last analysis date"), Self.dateFormatter.string(from: lastDate)))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Current Settings

    private var currentSettingsSection: some View {
        Section(header: Text(NSLocalizedString("Therapy Settings", comment: "LoopInsights current settings header")) ) {
            if let snapshot = viewModel.currentSnapshot {
                settingRow(
                    type: .basalRate,
                    items: snapshot.basalRateItems,
                    unit: "U/hr"
                )
                .padding(.top, 4)
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
                    Text("\(String(format: "%.2f", items[0].value)) \(unit)")
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
            // Period picker — Clarity-style capsule buttons
            HStack(spacing: 6) {
                ForEach(LoopInsightsAnalysisPeriod.allCases) { period in
                    let isSelected = viewModel.analysisPeriod == period
                    let clarityBlue = Color(red: 74/255, green: 115/255, blue: 213/255) // #4A73D5
                    Button {
                        viewModel.updateAnalysisPeriod(period)
                    } label: {
                        Text("\(period.rawValue)")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(isSelected ? clarityBlue : Color.clear)
                            .foregroundColor(isSelected ? .white : Color(.secondaryLabel))
                            .overlay(
                                Capsule()
                                    .stroke(
                                        isSelected ? clarityBlue : Color(.systemGray4),
                                        lineWidth: 1.5
                                    )
                            )
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)

            // Analyze buttons
            HStack(spacing: 10) {
                Button(action: { viewModel.runAnalysis() }) {
                    HStack {
                        Spacer()
                        if viewModel.isAnalyzing && !viewModel.isAnalyzingAll {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                                .tint(.white)
                                .scaleEffect(0.8)
                            Text(NSLocalizedString("Analyzing...", comment: "LoopInsights analyzing"))
                        } else {
                            Image(systemName: "sparkles")
                            Text(String(format: NSLocalizedString("Analyze %@", comment: "LoopInsights analyze button"), viewModel.focusSettingType.abbreviation))
                        }
                        Spacer()
                    }
                    .font(.subheadline.weight(.medium))
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

                Text(NSLocalizedString("or", comment: "LoopInsights or separator"))
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button(action: { viewModel.runAnalysisAll() }) {
                    HStack {
                        Spacer()
                        if viewModel.isAnalyzingAll {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                                .tint(.white)
                                .scaleEffect(0.8)
                            Text(NSLocalizedString("Analyzing...", comment: "LoopInsights analyzing all"))
                        } else {
                            Image(systemName: "sparkles")
                            Text(NSLocalizedString("Analyze All", comment: "LoopInsights analyze all button"))
                        }
                        Spacer()
                    }
                    .font(.subheadline.weight(.medium))
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
            }
            .listRowSeparator(.hidden, edges: .top)
            .padding(.bottom, 8)

            // AGP Chart — shown with analysis summary when enabled
            if LoopInsights_FeatureFlags.agpChartEnabled && !viewModel.agpComputedData.isEmpty {
                LoopInsights_AGPChartView(agpData: viewModel.agpComputedData, isAGPMode: viewModel.isAGPMode)
            }

            if !LoopInsights_SecureStorage.hasAPIKey {
                Text(NSLocalizedString("Configure your AI API key in LoopInsights Settings to begin analysis.", comment: "LoopInsights no API key message"))
                    .font(.caption)
                    .foregroundColor(.orange)
            }

            if let error = viewModel.analysisError {
                if case .emptyThinkingResponse = error {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(error.localizedDescription)
                            .font(.caption)
                            .foregroundColor(.red)
                        Button(action: { showingSupportedModels = true }) {
                            HStack(spacing: 4) {
                                Image(systemName: "info.circle")
                                Text(NSLocalizedString("View Supported Models", comment: "LoopInsights supported models button"))
                            }
                            .font(.caption)
                            .foregroundColor(.accentColor)
                        }
                    }
                } else {
                    Text(error.localizedDescription)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
        }
    }

    // MARK: - Supported Models

    private var supportedModelsView: some View {
        NavigationView {
            List {
                Section(header: Text("As of March 2026")) {
                    Text("The following models are confirmed to work with LoopInsights. \"Thinking\" models (e.g. Gemini 2.5) are not supported because they consume output tokens for internal reasoning and may return empty responses.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section(header: Text("OpenAI")) {
                    modelRow("gpt-4o", detail: "Recommended — best quality")
                    modelRow("gpt-4o-mini", detail: "Faster, lower cost")
                    modelRow("gpt-4.1", detail: "Latest flagship")
                    modelRow("gpt-4.1-mini", detail: "Latest, lower cost")
                    modelRow("gpt-4.1-nano", detail: "Cheapest")
                }

                Section(header: Text("Anthropic")) {
                    modelRow("claude-sonnet-4-5", detail: "Recommended — excellent at structured output")
                    modelRow("claude-sonnet-4-6", detail: "Latest")
                    modelRow("claude-haiku-3-5", detail: "Fast, lower cost")
                }

                Section(header: Text("Google Gemini")) {
                    modelRow("gemini-2.0-flash", detail: "Recommended — fast, reliable")
                    modelRow("gemini-2.0-flash-lite", detail: "Cheapest")
                    modelRow("gemini-1.5-flash", detail: "Older, stable")
                    modelRow("gemini-1.5-pro", detail: "Older, higher quality")
                }

                Section(header: Text("Not Supported")) {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark.circle")
                            .foregroundColor(.red)
                        Text("gemini-2.5-flash, gemini-2.5-pro, and any other \"thinking\" models")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Supported AI Models")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("Done", comment: "Done button")) {
                        showingSupportedModels = false
                    }
                }
            }
        }
    }

    private func modelRow(_ name: String, detail: String) -> some View {
        HStack {
            Text(name)
                .font(.subheadline)
                .fontWeight(.medium)
                .fontDesign(.monospaced)
            Spacer()
            Text(detail)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Auto-Applied Notification

    private var autoAppliedSection: some View {
        Section(header: Text(NSLocalizedString("AUTO-APPLIED CHANGES", comment: "LoopInsights auto-applied section header"))) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(.green)
                    Text(NSLocalizedString("The following changes were automatically applied to your therapy settings:", comment: "LoopInsights auto-applied description"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                ForEach(viewModel.autoAppliedSuggestions) { suggestion in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(suggestion.settingType.displayName)
                            .font(.subheadline.weight(.semibold))
                        ForEach(suggestion.timeBlocks) { block in
                            HStack {
                                Text(block.timeRangeFormatted)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(String(format: "%.2f → %.2f", block.currentValue, block.proposedValue))
                                    .font(.caption.weight(.medium))
                                    .foregroundColor(.green)
                                Text(String(format: "(%+.0f%%)", block.changePercent))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
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
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
            }
            HStack(spacing: 16) {
                Text(NSLocalizedString("Confidence Level:", comment: "LoopInsights confidence legend label"))
                legendDot(color: .green, label: NSLocalizedString("High", comment: "LoopInsights legend: high"))
                legendDot(color: .orange, label: NSLocalizedString("Medium", comment: "LoopInsights legend: medium"))
                legendDot(color: .yellow, label: NSLocalizedString("Low", comment: "LoopInsights legend: low"))
            }
            .font(.caption2)
            .foregroundColor(.secondary)
            .listRowSeparator(.hidden, edges: .top)
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
                    if record.suggestion.hasGuardrailWarning {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.caption)
                    }
                    confidenceBadge(record.suggestion.confidence)
                }

                // Show time blocks summary
                ForEach(record.suggestion.timeBlocks) { block in
                    HStack {
                        Text(block.timeRangeFormatted)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(String(format: "%.2f", block.currentValue)) → \(String(format: "%.2f", block.proposedValue))")
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
                        Text(NSLocalizedString("Apply", comment: "LoopInsights apply"))
                            .font(.caption.weight(.medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.green)
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)

                    Button(action: { viewModel.dismissSuggestion(record) }) {
                        Text(NSLocalizedString("Dismiss", comment: "LoopInsights dismiss"))
                            .font(.caption.weight(.medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.red)
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)

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
        HStack(spacing: 4) {
            Circle()
                .fill(confidenceColor(confidence))
                .frame(width: 8, height: 8)
            Text(confidence.displayName)
                .font(.caption.weight(.bold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(confidenceColor(confidence).opacity(0.15))
        .foregroundColor(confidenceColor(confidence))
        .cornerRadius(6)
    }

    private func confidenceColor(_ confidence: LoopInsightsConfidence) -> Color {
        switch confidence {
        case .low: return .yellow
        case .medium: return .orange
        case .high: return .green
        }
    }

    // MARK: - Guardrail Alert Helpers

    private var applyAlertTitle: String {
        guard let record = viewModel.recordToApply else {
            return NSLocalizedString("Apply Suggestion", comment: "LoopInsights apply confirmation title")
        }
        if record.suggestion.hasAbsoluteViolation {
            return NSLocalizedString("Cannot Apply", comment: "LoopInsights apply blocked title")
        }
        if record.suggestion.hasGuardrailWarning {
            return NSLocalizedString("Safety Warning", comment: "LoopInsights apply safety warning title")
        }
        return NSLocalizedString("Apply Suggestion", comment: "LoopInsights apply confirmation title")
    }

    private var applyAlertMessage: String {
        let disclaimer = NSLocalizedString(
            "This will modify your therapy settings. You are responsible for reviewing and verifying all changes. AI suggestions are advisory and may not be appropriate for your situation. Consult your healthcare provider for significant therapy adjustments.",
            comment: "LoopInsights apply disclaimer"
        )
        guard let record = viewModel.recordToApply else { return disclaimer }

        if record.suggestion.hasAbsoluteViolation {
            let warnings = record.suggestion.guardrailWarnings.joined(separator: "\n")
            return warnings + "\n\n" + NSLocalizedString(
                "One or more proposed values are outside safe clinical bounds. This suggestion cannot be applied.",
                comment: "LoopInsights apply absolute block message"
            )
        }

        var message = ""

        if record.suggestion.hasGuardrailWarning {
            let warnings = record.suggestion.guardrailWarnings.joined(separator: "\n")
            message += warnings + "\n\n"
        }

        if record.suggestion.settingType == .basalRate {
            message += NSLocalizedString(
                "⚠️ Basal Rate changes carry higher risk than other settings. Basal insulin delivers continuously — including overnight while you sleep. Changes that are too aggressive can cause severe low blood sugar (hypoglycemia), especially at night. Monitor your glucose closely for 3–5 days after applying this change.",
                comment: "LoopInsights basal rate safety warning"
            ) + "\n\n"
        }

        message += disclaimer
        return message
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

    // MARK: - No Changes

    private var noChangesSection: some View {
        Section {
            VStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 36))
                    .foregroundColor(.green)
                Text(NSLocalizedString("No Recommended Changes", comment: "LoopInsights no changes title"))
                    .font(.headline)
                Text(NSLocalizedString("Your current therapy settings look good based on the available data. Check back after more data has been generated for a fresh analysis.", comment: "LoopInsights no changes description"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Glucose Stats Cards (Clarity-style)

    private var glucoseStatsCards: some View {
        Group {
            if let stats = viewModel.aggregatedStats {
                Section {
                    glucoseCard(stats: stats)
                }
                Section {
                    timeInRangeCard(glucoseStats: stats.glucoseStats)
                }
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
        }
    }

    // MARK: - Glucose Card

    private func glucoseCard(stats: LoopInsightsAggregatedStats) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(NSLocalizedString("Glucose", comment: "LoopInsights glucose card title"))
                .font(.title3.weight(.semibold))
                .foregroundColor(.primary)
            Divider()

            // Average Glucose
            VStack(alignment: .leading, spacing: 2) {
                Text(NSLocalizedString("Average Glucose", comment: "LoopInsights avg glucose label"))
                    .font(.callout)
                    .foregroundColor(.primary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(String(format: "%.0f", stats.glucoseStats.averageGlucose))
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    Text(NSLocalizedString("mg/dL", comment: "LoopInsights unit mg/dL"))
                        .font(.callout)
                        .foregroundColor(Color(.secondaryLabel))
                }
            }

            // Std Dev & GMI side-by-side
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(NSLocalizedString("Standard Deviation", comment: "LoopInsights std dev label"))
                        .font(.callout)
                        .foregroundColor(.primary)
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(String(format: "%.0f", stats.glucoseStats.standardDeviation))
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                        Text(NSLocalizedString("mg/dL", comment: "LoopInsights unit mg/dL"))
                            .font(.caption)
                            .foregroundColor(Color(.secondaryLabel))
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(NSLocalizedString("GMI", comment: "LoopInsights GMI label"))
                        .font(.callout)
                        .foregroundColor(.primary)
                    if stats.glucoseStats.sampleCount >= 12 {
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text(String(format: "%.1f", stats.glucoseStats.gmi))
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundColor(.primary)
                            Text("%")
                                .font(.caption)
                                .foregroundColor(Color(.secondaryLabel))
                        }
                    } else {
                        Text(NSLocalizedString("Not enough\ndata available", comment: "LoopInsights GMI insufficient data"))
                            .font(.callout.weight(.semibold))
                            .foregroundColor(.primary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Time in Range Card

    // Clarity TIR colors
    private static let clarityVeryHigh = Color(red: 193/255, green: 79/255, blue: 12/255)   // #C14F0C — Very High
    private static let clarityHigh = Color(red: 240/255, green: 202/255, blue: 76/255)      // #F0CA4C — High
    private static let clarityGreen = Color(red: 116/255, green: 165/255, blue: 46/255)     // #74A52E — In Range
    private static let clarityTight = Color(red: 46/255, green: 139/255, blue: 130/255)     // #2E8B82 — Tight Range (teal)
    private static let clarityLow = Color(red: 211/255, green: 98/255, blue: 101/255)       // #D36265 — Low
    private static let clarityVeryLow = Color(red: 127/255, green: 3/255, blue: 2/255)      // #7F0302 — Very Low

    private func timeInRangeCard(glucoseStats g: LoopInsightsAggregatedStats.GlucoseStats) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(NSLocalizedString("Time in Range", comment: "LoopInsights TIR card title"))
                .font(.title3.weight(.semibold))
                .foregroundColor(.primary)
            Divider()

            HStack(alignment: .center, spacing: 14) {
                // Stacked color bar — standard 5-zone Dexcom/Clarity layout
                tirStackedBar(glucoseStats: g)
                    .frame(width: 65)

                // Percentage labels — standard 5-zone layout
                VStack(alignment: .leading, spacing: 5) {
                    tirLabelRow(percent: g.timeVeryHigh, label: NSLocalizedString("Very High", comment: "LoopInsights TIR very high"), isBold: false)
                    tirLabelRow(percent: g.timeHigh, label: NSLocalizedString("High", comment: "LoopInsights TIR high"), isBold: false)
                    tirLabelRow(percent: g.timeInRange, label: NSLocalizedString("In Range", comment: "LoopInsights TIR in range"), isBold: true)
                    tirLabelRow(percent: g.timeInTightRange, label: NSLocalizedString("Tight", comment: "LoopInsights TITR tight label"), isBold: true, color: Self.clarityTight)
                    tirLabelRow(percent: g.timeLow, label: NSLocalizedString("Low", comment: "LoopInsights TIR low"), isBold: false)
                    tirLabelRow(percent: g.timeVeryLow, label: NSLocalizedString("Very Low", comment: "LoopInsights TIR very low"), isBold: false)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 0) {
                    Text(NSLocalizedString("Target Range: ", comment: "LoopInsights TIR target label"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)
                    Text(NSLocalizedString("70–180 mg/dL", comment: "LoopInsights TIR target value"))
                        .font(.subheadline)
                        .foregroundColor(.primary)
                }
                HStack(spacing: 0) {
                    Text(NSLocalizedString("Tight Range: ", comment: "LoopInsights TITR target label"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(Self.clarityTight)
                    Text(String(format: NSLocalizedString("70–%d mg/dL", comment: "LoopInsights TITR target value"), g.tightRangeUpperBound))
                        .font(.subheadline)
                        .foregroundColor(Self.clarityTight)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func tirStackedBar(glucoseStats g: LoopInsightsAggregatedStats.GlucoseStats) -> some View {
        GeometryReader { geo in
            let totalHeight = geo.size.height
            let zones: [(Double, Color)] = [
                (g.timeVeryHigh, Self.clarityVeryHigh),
                (g.timeHigh, Self.clarityHigh),
                (g.timeInRange, Self.clarityGreen),
                (g.timeLow, Self.clarityLow),
                (g.timeVeryLow, Self.clarityVeryLow)
            ]
            VStack(spacing: 1) {
                ForEach(Array(zones.enumerated()), id: \.offset) { _, zone in
                    let height = max(zone.0 > 0 ? 2 : 0, totalHeight * zone.0 / 100)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(zone.1)
                        .frame(height: height)
                }
            }
        }
        .frame(height: 130)
    }

    private func tirLabelRow(percent: Double, label: String, isBold: Bool, color: Color? = nil) -> some View {
        let foreground = color ?? (isBold ? Color.primary : Color(.secondaryLabel))
        return HStack(spacing: 4) {
            Text(String(format: "%.0f%%", percent))
                .font(.subheadline)
                .fontWeight(isBold ? .bold : .regular)
                .foregroundColor(foreground)
                .fixedSize(horizontal: true, vertical: false)
            Text(label)
                .font(.subheadline)
                .fontWeight(isBold ? .bold : .regular)
                .foregroundColor(foreground)
        }
    }

    // MARK: - Settings Score

    private var settingsScoreSection: some View {
        Section(header: Text(NSLocalizedString("SETTINGS SCORE", comment: "LoopInsights settings score header"))) {
            if let breakdown = viewModel.settingsScoreBreakdown {
                HStack(alignment: .center) {
                    // Grade circle
                    ZStack {
                        Circle()
                            .stroke(breakdown.gradeColor.opacity(0.3), lineWidth: 6)
                            .frame(width: 60, height: 60)
                        Circle()
                            .trim(from: 0, to: Double(breakdown.total) / 100)
                            .stroke(breakdown.gradeColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                            .frame(width: 60, height: 60)
                            .rotationEffect(.degrees(-90))
                        VStack(spacing: 0) {
                            Text(breakdown.grade)
                                .font(.title2.weight(.bold))
                                .foregroundColor(breakdown.gradeColor)
                            Text("\(breakdown.total)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.trailing, 12)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(breakdown.summary)
                            .font(.subheadline.weight(.medium))
                        VStack(alignment: .leading, spacing: 2) {
                            scoreBar(label: "TIR", score: breakdown.tirScore, max: 40, color: breakdown.tirScore >= 32 ? .green : .orange)
                            scoreBar(label: "Safety", score: breakdown.belowRangeScore, max: 25, color: breakdown.belowRangeScore >= 20 ? .green : .red)
                            scoreBar(label: "Stability", score: breakdown.cvScore, max: 20, color: breakdown.cvScore >= 15 ? .green : .orange)
                            scoreBar(label: "GMI", score: breakdown.gmiScore, max: 15, color: breakdown.gmiScore >= 12 ? .green : .orange)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func scoreBar(label: String, score: Int, max: Int, color: Color) -> some View {
        HStack {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .fixedSize()
                .frame(width: 52, alignment: .leading)
                .padding(.trailing, 6)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 4)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color)
                        .frame(width: geo.size.width * CGFloat(score) / CGFloat(max), height: 4)
                }
            }
            .frame(height: 4)
            Text("\(score)/\(max)")
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .fixedSize()
                .frame(width: 36, alignment: .trailing)
                .padding(.leading, 6)
        }
    }

    // MARK: - Optimal Warning

    private var optimalWarningBanner: some View {
        Section {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.shield.fill")
                    .foregroundColor(.green)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(NSLocalizedString("Your settings are already performing well", comment: "LoopInsights optimal warning title"))
                        .font(.subheadline.weight(.medium))
                    Text(NSLocalizedString("TIR >85% with low hypoglycemia risk. The suggestions below are minor refinements — apply with caution.", comment: "LoopInsights optimal warning detail"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Navigation

    private var navigationSection: some View {
        Section {
            Button(action: { showingChat = true }) {
                HStack {
                    Text("🌀")
                    Text(NSLocalizedString("Ask Loopy!", comment: "LoopInsights Loopy chat button"))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if LoopInsights_FeatureFlags.alcoholTrackingEnabled {
                Button(action: { showingAlcoholLog = true }) {
                    HStack {
                        Image(systemName: "wineglass.fill")
                            .foregroundColor(.orange)
                        Text(NSLocalizedString("Alcohol Tracker", comment: "LoopInsights alcohol button"))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            if LoopInsights_FeatureFlags.caffeineTrackingEnabled {
                Button(action: { showingCaffeineLog = true }) {
                    HStack {
                        Image(systemName: "cup.and.saucer.fill")
                            .foregroundColor(.green)
                        Text(NSLocalizedString("Caffeine Tracker", comment: "LoopInsights caffeine button"))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            if LoopInsights_FeatureFlags.cgmBackfillDetectionEnabled {
                cgmSignalQualityCard
            }

            Button(action: { showingGoals = true }) {
                HStack {
                    Image(systemName: "target")
                        .foregroundColor(.accentColor)
                    Text(NSLocalizedString("Goals & Patterns", comment: "LoopInsights goals button"))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if LoopInsights_FeatureFlags.foodResponseEnabled {
                Button(action: { showingMealInsights = true }) {
                    HStack {
                        Image(systemName: "fork.knife")
                            .foregroundColor(.accentColor)
                        Text(NSLocalizedString("Meal Insights", comment: "LoopInsights meal insights button"))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

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

            Button(action: { showingTrendsInsights = true }) {
                HStack {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .foregroundColor(.accentColor)
                    Text(NSLocalizedString("Trends & Insights", comment: "LoopInsights trends button"))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Debug log (developer mode only)
            if LoopInsights_FeatureFlags.developerModeEnabled, viewModel.lastDebugLog != nil {
                Button(action: { showingDebugLog = true }) {
                    HStack {
                        Image(systemName: "doc.text.magnifyingglass")
                        Text(NSLocalizedString("View Last Analysis Log", comment: "LoopInsights debug log button"))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .foregroundColor(.orange)
                }
            }
        }
    }

    // MARK: - CGM Signal Quality Card

    @ViewBuilder
    private var cgmSignalQualityCard: some View {
        let period = viewModel.analysisPeriod.rawValue
        let summary = LoopInsights_BackfillDetector.shared.buildSummary(days: period)
        if summary.totalEvents > 0 {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .foregroundColor(.orange)
                    Text(NSLocalizedString("CGM Signal Quality", comment: "LoopInsights CGM signal quality card title"))
                        .font(.subheadline.weight(.semibold))
                }

                Text(String(
                    format: NSLocalizedString("%d signal gap(s) in the last %d days", comment: "LoopInsights CGM gap count"),
                    summary.totalEvents, period
                ))
                .font(.caption)
                .foregroundColor(.primary)

                if let longestEvent = summary.longestGapEvent {
                    HStack(spacing: 4) {
                        Text(NSLocalizedString("Longest:", comment: "LoopInsights CGM longest gap label"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(String(
                            format: NSLocalizedString("%d min (%@)", comment: "LoopInsights CGM longest gap value"),
                            summary.longestGapMinutes,
                            Self.shortDateFormatter.string(from: longestEvent.detectedAt)
                        ))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                }

                HStack(spacing: 4) {
                    Text(String(format: "%.1f%%", summary.realTimeCoveragePercent))
                        .font(.caption.weight(.semibold))
                        .foregroundColor(summary.realTimeCoveragePercent >= 95 ? .green : .orange)
                    Text(NSLocalizedString("real-time coverage", comment: "LoopInsights CGM coverage label"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Text(NSLocalizedString("During gaps, readings may be estimated by your sensor.", comment: "LoopInsights CGM gap disclaimer"))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE h:mm a"
        return formatter
    }()

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

    // MARK: - Notification Banner

    @ViewBuilder
    private func notificationBanner(
        suggestion: LoopInsightsSuggestion,
        onView: @escaping () -> Void,
        onAsk: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "brain.head.profile")
                    .font(.title3)
                    .foregroundColor(.white)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(NSLocalizedString("LoopInsights", comment: "LoopInsights banner title"))
                            .font(.subheadline.weight(.bold))
                            .foregroundColor(.white)
                        Spacer()
                        HStack(spacing: 4) {
                            Circle()
                                .fill(confidenceColor(suggestion.confidence))
                                .frame(width: 6, height: 6)
                            Text(suggestion.confidence.displayName)
                                .font(.caption2.weight(.bold))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.2))
                        .cornerRadius(8)
                        .foregroundColor(.white)
                    }

                    Text(suggestion.summaryDescription)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(2)

                    HStack(spacing: 12) {
                        Button(action: onView) {
                            Text(NSLocalizedString("View", comment: "LoopInsights banner view button"))
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.accentColor)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 6)
                                .background(Color.white)
                                .cornerRadius(14)
                        }
                        .buttonStyle(.plain)

                        Button(action: onAsk) {
                            Text(NSLocalizedString("Ask", comment: "LoopInsights banner ask button"))
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 6)
                                .background(Color.white.opacity(0.25))
                                .cornerRadius(14)
                        }
                        .buttonStyle(.plain)

                        Button(action: onDismiss) {
                            Text(NSLocalizedString("Dismiss", comment: "LoopInsights banner dismiss button"))
                                .font(.caption.weight(.medium))
                                .foregroundColor(.white.opacity(0.8))
                        }
                        .buttonStyle(.plain)

                        Spacer()
                    }
                    .padding(.top, 2)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.accentColor.opacity(0.95))
                    .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
            )
            .padding(.horizontal)

            Spacer()
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: - Formatters

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}

// MARK: - iOS 17+ List Section Spacing

private struct ListSectionSpacingModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content.listSectionSpacing(10)
        } else {
            content
        }
    }
}

// MARK: - Pre-Fill Editor View

/// Editor that shows proposed therapy changes with editable values.
/// The user can adjust proposed values before applying.
struct LoopInsights_PreFillEditorView: View {
    let record: LoopInsightsSuggestionRecord
    let onApply: ([LoopInsightsTimeBlock]) -> Void
    let onCancel: () -> Void

    @State private var editedValues: [UUID: Double] = [:]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section(header: Text(record.suggestion.settingType.displayName)) {
                Text(NSLocalizedString("Review and adjust the proposed values below before applying.", comment: "LoopInsights pre-fill editor instructions"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section(header: Text(NSLocalizedString("PROPOSED CHANGES", comment: "LoopInsights pre-fill editor changes header"))) {
                ForEach(record.suggestion.timeBlocks) { block in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(block.timeRangeFormatted)
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(NSLocalizedString("Current", comment: "LoopInsights pre-fill current label"))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text(String(format: "%.2f", block.currentValue))
                                    .font(.body.weight(.medium))
                            }

                            Image(systemName: "arrow.right")
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 8)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(NSLocalizedString("Proposed", comment: "LoopInsights pre-fill proposed label"))
                                    .font(.caption2)
                                    .foregroundColor(.green)
                                TextField(
                                    "",
                                    value: Binding(
                                        get: { editedValues[block.id] ?? block.proposedValue },
                                        set: { editedValues[block.id] = $0 }
                                    ),
                                    format: .number
                                )
                                .font(.body.weight(.semibold))
                                .foregroundColor(.green)
                                .textFieldStyle(.roundedBorder)
                                .keyboardType(.decimalPad)
                                .frame(width: 80)
                            }

                            Spacer()

                            let editedVal = editedValues[block.id] ?? block.proposedValue
                            let pct = block.currentValue != 0
                                ? ((editedVal - block.currentValue) / block.currentValue) * 100
                                : 0
                            Text(String(format: "(%+.0f%%)", pct))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Section(header: Text(NSLocalizedString("AI REASONING", comment: "LoopInsights pre-fill reasoning header"))) {
                Text(record.suggestion.reasoning)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section {
                Button(action: {
                    let editedBlocks = record.suggestion.timeBlocks.map { block in
                        LoopInsightsTimeBlock(
                            startTime: block.startTime,
                            endTime: block.endTime,
                            currentValue: block.currentValue,
                            proposedValue: editedValues[block.id] ?? block.proposedValue
                        )
                    }
                    onApply(editedBlocks)
                    dismiss()
                }) {
                    HStack {
                        Spacer()
                        Text(NSLocalizedString("Apply Changes", comment: "LoopInsights pre-fill apply button"))
                            .fontWeight(.semibold)
                        Spacer()
                    }
                    .foregroundColor(.white)
                    .padding(.vertical, 10)
                    .background(Color.green)
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)

                Button(action: {
                    onCancel()
                    dismiss()
                }) {
                    HStack {
                        Spacer()
                        Text(NSLocalizedString("Cancel", comment: "LoopInsights pre-fill cancel button"))
                            .fontWeight(.semibold)
                        Spacer()
                    }
                    .foregroundColor(.white)
                    .padding(.vertical, 10)
                    .background(Color.red)
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle(NSLocalizedString("Review Changes", comment: "LoopInsights pre-fill editor title"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Debug Log View

/// Developer-only view that shows the full AI prompt/response exchange.
/// Useful for diagnosing unexpected AI behavior.
struct LoopInsights_DebugLogView: View {
    let log: LoopInsightsDebugLog
    @State private var copied = false
    @Environment(\.dismiss) private var dismiss

    private var fullLogText: String {
        """
        === LoopInsights Analysis Debug Log ===
        Setting Type: \(log.settingType.displayName)
        Timestamp: \(Self.dateFormatter.string(from: log.timestamp))

        === SYSTEM PROMPT ===
        \(log.systemPrompt)

        === USER PROMPT ===
        \(log.userPrompt)

        === RAW AI RESPONSE ===
        \(log.rawResponse)
        """
    }

    var body: some View {
        List {
            Section {
                Button(action: {
                    UIPasteboard.general.string = fullLogText
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
                }) {
                    HStack {
                        Spacer()
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        Text(copied ? "Copied" : "Copy Full Log")
                            .fontWeight(.semibold)
                        Spacer()
                    }
                    .foregroundColor(.white)
                    .padding(.vertical, 10)
                    .background(copied ? Color.green : Color.orange)
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
            }

            Section(header: Text("Analysis Info")) {
                HStack {
                    Text("Setting Type")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(log.settingType.displayName)
                }
                HStack {
                    Text("Timestamp")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(Self.dateFormatter.string(from: log.timestamp))
                        .font(.caption)
                }
            }

            Section(header: Text("System Prompt")) {
                Text(log.systemPrompt)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
            }

            Section(header: Text("User Prompt")) {
                Text(log.userPrompt)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
            }

            Section(header: Text("Raw AI Response")) {
                Text(log.rawResponse)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
            }
        }
        .navigationTitle("Analysis Debug Log")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(NSLocalizedString("Done", comment: "Done button")) {
                    dismiss()
                }
            }
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()
}

