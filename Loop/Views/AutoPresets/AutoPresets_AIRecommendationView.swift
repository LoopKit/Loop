//
//  AutoPresets_AIRecommendationView.swift
//  Loop
//
//  AutoPresets — AI-powered preset recommendation view with analysis and native preset editor.
//
//  Idea by Taylor Patterson. Coded by Claude Code.
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import HealthKit
import LoopKit
import LoopKitUI
import SwiftUI

private let autoPresetsGreen = Color(red: 76/255, green: 175/255, blue: 80/255)

// MARK: - View Model

@MainActor
final class AutoPresets_AIRecommendationViewModel: ObservableObject {

    enum State {
        case idle
        case loading
        case loaded(AutoPresetsAIResponse)
        case error(String)
        case noAPIKey
    }

    @Published var state: State = .idle
    @Published var savedPresetNames: Set<String> = []
    @Published var selectedPeriod: LoopInsightsAnalysisPeriod = .fourteenDays

    private let advisor: AutoPresets_AIAdvisor

    init(coordinator: LoopInsights_Coordinator) {
        self.advisor = AutoPresets_AIAdvisor(coordinator: coordinator)
    }

    func analyze() {
        state = .loading

        let period = selectedPeriod
        Task {
            do {
                let response = try await advisor.generateRecommendations(period: period)
                state = .loaded(response)
            } catch let error as LoopInsightsError where error.isNoAPIKey {
                state = .noAPIKey
            } catch {
                state = .error(error.localizedDescription)
            }
        }
    }

    /// Build a TemporaryScheduleOverridePreset from a recommendation (for pre-filling the editor)
    func buildPreset(from recommendation: AutoPresetsRecommendation) -> TemporaryScheduleOverridePreset {
        AutoPresets_AIAdvisor.createPreset(from: recommendation)
    }

    /// Called after the user saves from the native preset editor
    func markSaved(_ recommendation: AutoPresetsRecommendation) {
        savedPresetNames.insert(recommendation.name)
    }
}

private extension LoopInsightsError {
    var isNoAPIKey: Bool {
        if case .noAPIKeyConfigured = self { return true }
        return false
    }

    var isInsufficientData: Bool {
        if case .insufficientData = self { return true }
        return false
    }
}

// MARK: - Main View

struct AutoPresets_AIRecommendationView: View {
    @StateObject private var viewModel: AutoPresets_AIRecommendationViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedRecommendation: AutoPresetsRecommendation?

    init(coordinator: LoopInsights_Coordinator) {
        _viewModel = StateObject(wrappedValue: AutoPresets_AIRecommendationViewModel(coordinator: coordinator))
    }

    var body: some View {
        NavigationView {
            Group {
                switch viewModel.state {
                case .idle:
                    idleView
                case .loading:
                    loadingView
                case .loaded(let response):
                    loadedView(response)
                case .error(let message):
                    errorView(message)
                case .noAPIKey:
                    noAPIKeyView
                }
            }
            .navigationTitle("AI Preset Advisor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $selectedRecommendation) { rec in
                PresetEditorWrapper(
                    preset: viewModel.buildPreset(from: rec),
                    onSave: { savedPreset in
                        AutoPresets_Coordinator.shared.createPreset(savedPreset)
                        viewModel.markSaved(rec)
                    }
                )
            }
        }
    }

    // MARK: - Idle

    private var idleView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "wand.and.stars")
                .font(.system(size: 56))
                .foregroundColor(autoPresetsGreen)

            Text("AI Preset Advisor")
                .font(.title2)
                .fontWeight(.bold)

            Text("Analyze your glucose, insulin, and meal patterns to discover override presets that could help you manage recurring situations.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            periodPicker

            Button {
                viewModel.analyze()
            } label: {
                HStack {
                    Image(systemName: "sparkles")
                    Text("Analyze My Data")
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(autoPresetsGreen)
                .cornerRadius(12)
            }
            .padding(.horizontal, 32)

            Text("Requires an AI API key in AutoPresets settings.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()
        }
    }

    // MARK: - Period Picker

    private var periodPicker: some View {
        VStack(spacing: 6) {
            Text("Lookback Period")
                .font(.caption)
                .foregroundColor(.secondary)
            HStack(spacing: 8) {
                ForEach(LoopInsightsAnalysisPeriod.allCases) { period in
                    let isSelected = viewModel.selectedPeriod == period
                    Button {
                        viewModel.selectedPeriod = period
                    } label: {
                        Text(period.displayName)
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity)
                            .background(isSelected ? autoPresetsGreen : Color.clear)
                            .foregroundColor(isSelected ? .white : Color(.secondaryLabel))
                            .overlay(
                                Capsule()
                                    .stroke(
                                        isSelected ? autoPresetsGreen : Color(.systemGray4),
                                        lineWidth: 1.5
                                    )
                            )
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 4)
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .scaleEffect(1.5)
            Text("Analyzing your patterns...")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("This may take 15-30 seconds")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
        }
    }

    // MARK: - Loaded

    private func loadedView(_ response: AutoPresetsAIResponse) -> some View {
        List {
            if !response.overallAssessment.isEmpty {
                Section("Assessment") {
                    Text(response.overallAssessment)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            if response.recommendations.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle")
                            .font(.title)
                            .foregroundColor(.green)
                        Text("No New Presets Needed")
                            .font(.headline)
                        Text("Your current presets cover the patterns found in your data.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                }
            } else {
                Section("Recommended Presets") {
                    ForEach(response.recommendations) { rec in
                        recommendationCard(rec)
                    }
                }
            }

            Section {
                periodPicker
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

                Button {
                    viewModel.analyze()
                } label: {
                    HStack {
                        Spacer()
                        Image(systemName: "arrow.clockwise")
                        Text("Re-Analyze")
                        Spacer()
                    }
                }
            }
        }
    }

    // MARK: - Recommendation Card

    private func recommendationCard(_ rec: AutoPresetsRecommendation) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header: emoji + name + confidence
            HStack {
                Text(rec.symbol)
                    .font(.title2)
                Text(rec.name)
                    .font(.headline)
                Spacer()
                confidenceBadge(rec.confidence)
            }

            // Trigger context
            HStack(spacing: 4) {
                Image(systemName: rec.triggerContext.iconName)
                    .font(.caption)
                Text(rec.triggerContext.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .foregroundColor(autoPresetsGreen)

            // Pattern description
            Text(rec.patternDescription)
                .font(.subheadline)
                .foregroundColor(.secondary)

            // Settings preview
            settingsPreview(rec)

            // Reasoning (expandable)
            DisclosureGroup("Why this preset?") {
                Text(rec.reasoning)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }
            .font(.subheadline)

            // Review & Save button
            if viewModel.savedPresetNames.contains(rec.name) {
                HStack {
                    Spacer()
                    Label("Saved", systemImage: "checkmark.circle.fill")
                        .font(.subheadline)
                        .foregroundColor(.green)
                    Spacer()
                }
                .padding(.top, 4)
            } else {
                Button {
                    selectedRecommendation = rec
                } label: {
                    HStack {
                        Spacer()
                        Image(systemName: "plus.circle.fill")
                        Text("Review & Save Preset")
                            .fontWeight(.semibold)
                        Spacer()
                    }
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .padding(.vertical, 10)
                    .background(autoPresetsGreen)
                    .cornerRadius(8)
                }
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Settings Preview

    private func settingsPreview(_ rec: AutoPresetsRecommendation) -> some View {
        HStack(spacing: 16) {
            if let scale = rec.insulinNeedsScale {
                VStack(spacing: 2) {
                    Text("Insulin")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("\(String(format: "%.0f", scale * 100))%")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(scale > 1.0 ? .orange : (scale < 1.0 ? .blue : .primary))
                }
                .frame(minWidth: 60)
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .background(Color(.systemGray6))
                .cornerRadius(8)
            }

            if let low = rec.targetRangeLowMgdl, let high = rec.targetRangeHighMgdl {
                VStack(spacing: 2) {
                    Text("Target")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("\(Int(low))-\(Int(high))")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                .frame(minWidth: 60)
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .background(Color(.systemGray6))
                .cornerRadius(8)
            }

            VStack(spacing: 2) {
                Text("Duration")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(formatDuration(rec.durationMinutes))
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            .frame(minWidth: 60)
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(Color(.systemGray6))
            .cornerRadius(8)

            Spacer()
        }
    }

    // MARK: - Confidence Badge

    private func confidenceBadge(_ confidence: AutoPresetsRecommendationConfidence) -> some View {
        Text(confidence.displayName)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundColor(confidence.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(confidence.color.opacity(0.15))
            .cornerRadius(6)
    }

    // MARK: - Error View

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            Text("Analysis Failed")
                .font(.title3)
                .fontWeight(.bold)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                viewModel.analyze()
            } label: {
                Text("Try Again")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 12)
                    .background(autoPresetsGreen)
                    .cornerRadius(10)
            }
            Spacer()
        }
    }

    // MARK: - No API Key View

    private var noAPIKeyView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "key")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("API Key Required")
                .font(.title3)
                .fontWeight(.bold)
            Text("Configure an AI API key in AutoPresets settings to use the AI Preset Advisor.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
    }

    // MARK: - Helpers

    private func formatDuration(_ minutes: Int) -> String {
        if minutes < 60 {
            return "\(minutes)m"
        } else if minutes % 60 == 0 {
            return "\(minutes / 60)h"
        } else {
            return "\(minutes / 60)h \(minutes % 60)m"
        }
    }
}

// MARK: - Native Preset Editor Wrapper

/// Wraps Loop's AddEditOverrideTableViewController in SwiftUI.
/// Pre-fills the editor with AI-suggested values and calls onSave when the user taps Save.
private struct PresetEditorWrapper: UIViewControllerRepresentable {
    let preset: TemporaryScheduleOverridePreset
    let onSave: (TemporaryScheduleOverridePreset) -> Void

    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(onSave: onSave, dismiss: dismiss)
    }

    func makeUIViewController(context: Context) -> UINavigationController {
        let editVC = AddEditOverrideTableViewController(glucoseUnit: .milligramsPerDeciliter)
        editVC.delegate = context.coordinator
        editVC.customDismissalMode = .dismissModal

        // Force the view hierarchy to load before setting inputMode so that
        // configure(with:) has a fully-initialized table view to work with.
        editVC.loadViewIfNeeded()
        editVC.inputMode = .editPreset(preset)

        let nav = UINavigationController(rootViewController: editVC)
        return nav
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}

    final class Coordinator: NSObject, AddEditOverrideTableViewControllerDelegate {
        let onSave: (TemporaryScheduleOverridePreset) -> Void
        let dismiss: DismissAction

        init(onSave: @escaping (TemporaryScheduleOverridePreset) -> Void, dismiss: DismissAction) {
            self.onSave = onSave
            self.dismiss = dismiss
        }

        func addEditOverrideTableViewController(
            _ vc: AddEditOverrideTableViewController,
            didSavePreset preset: TemporaryScheduleOverridePreset
        ) {
            onSave(preset)
            dismiss()
        }
    }
}
