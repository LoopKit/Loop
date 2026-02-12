//
//  LoopInsights_DashboardViewModel.swift
//  Loop
//
//  Concept & design by Taylor Patterson. Coded & tested by Claude Code in February 2026.
//  Copyright (c) 2025-2026 LoopKit Authors. All rights reserved.
//

import Foundation
import Combine
import LoopKit

/// Main view model for the LoopInsights Dashboard. Orchestrates data aggregation,
/// AI analysis, and suggestion state management.
///
/// Owned by DashboardView. Calls Coordinator services for data access and AI analysis.
final class LoopInsights_DashboardViewModel: ObservableObject {

    // MARK: - Published State

    /// Current analysis state
    @Published var isAnalyzing = false
    @Published var analysisError: LoopInsightsError?
    @Published var lastAnalysisDate: Date?

    /// Current therapy snapshot
    @Published var currentSnapshot: LoopInsightsTherapySnapshot?

    /// AI analysis results
    @Published var analysisResponse: LoopInsightsAnalysisResponse?
    @Published var overallAssessment: String?

    /// Suggestion records (pending)
    @Published var pendingSuggestions: [LoopInsightsSuggestionRecord] = []

    /// Selected setting type for analysis focus
    @Published var focusSettingType: LoopInsightsSettingType = .carbRatio

    /// Analysis period
    @Published var analysisPeriod: LoopInsightsAnalysisPeriod

    /// Apply mode confirmation state
    @Published var showingApplyConfirmation = false
    @Published var recordToApply: LoopInsightsSuggestionRecord?

    /// Aggregated stats (for display)
    @Published var aggregatedStats: LoopInsightsAggregatedStats?

    /// Setting types that have been analyzed — used to show green "OK" status
    /// for settings that were reviewed and found to need no changes
    @Published var analyzedSettingTypes: Set<LoopInsightsSettingType> = []

    /// Detected glucose/insulin patterns from aggregated data
    @Published var detectedPatterns: [LoopInsightsDetectedPattern] = []

    // MARK: - Dependencies

    private let coordinator: LoopInsights_Coordinator
    private var cancellables = Set<AnyCancellable>()

    /// Expose suggestion store for views that need direct access
    var suggestionStore: LoopInsights_SuggestionStore {
        coordinator.suggestionStore
    }

    // MARK: - Initialization

    init(coordinator: LoopInsights_Coordinator) {
        self.coordinator = coordinator
        self.analysisPeriod = LoopInsights_FeatureFlags.analysisPeriod

        // Observe suggestion store changes
        coordinator.suggestionStore.$records
            .map { records in records.filter { $0.status == .pending }.sorted { $0.createdAt > $1.createdAt } }
            .receive(on: DispatchQueue.main)
            .assign(to: &$pendingSuggestions)

        // Load initial snapshot
        loadCurrentSettings()
    }

    // MARK: - Actions

    /// Load current therapy settings snapshot
    func loadCurrentSettings() {
        do {
            currentSnapshot = try coordinator.captureCurrentSnapshot()
        } catch {
            print("[LoopInsights] Failed to capture therapy snapshot: \(error)")
        }
    }

    /// Run AI analysis for the focused setting type
    func runAnalysis() {
        guard !isAnalyzing else { return }

        isAnalyzing = true
        analysisError = nil

        Task { @MainActor in
            do {
                // Aggregate data
                let stats = try await coordinator.dataAggregator.aggregateData(period: analysisPeriod)
                self.aggregatedStats = stats

                // Detect patterns from aggregated stats
                self.detectedPatterns = Self.detectPatterns(from: stats)

                // Capture current settings
                let snapshot = try coordinator.captureCurrentSnapshot()
                self.currentSnapshot = snapshot

                // Run AI analysis
                let response = try await coordinator.aiAnalysis.analyze(
                    settingType: focusSettingType,
                    currentSettings: snapshot,
                    stats: stats
                )

                self.analysisResponse = response
                self.overallAssessment = response.overallAssessment
                self.lastAnalysisDate = Date()

                // Track that this setting type has been analyzed
                self.analyzedSettingTypes.insert(focusSettingType)

                // Dismiss any existing pending suggestions for this setting type
                for record in pendingSuggestions where record.suggestion.settingType == focusSettingType {
                    coordinator.suggestionStore.markDismissed(recordID: record.id)
                }

                // Add new suggestions as pending records
                let _ = coordinator.suggestionStore.addSuggestions(response.suggestions)

                // If next focus is recommended, update
                if let nextFocus = response.nextRecommendedFocus {
                    self.focusSettingType = nextFocus
                }

                // Auto-apply if developer mode + auto-apply enabled
                if LoopInsights_FeatureFlags.developerModeEnabled &&
                   LoopInsights_FeatureFlags.applyMode == .autoApply {
                    for suggestion in response.suggestions where suggestion.confidence >= .high {
                        await autoApplySuggestion(suggestion)
                    }
                }

                self.isAnalyzing = false

            } catch let error as LoopInsightsError {
                self.analysisError = error
                self.isAnalyzing = false
            } catch {
                self.analysisError = .aiProviderError(error.localizedDescription)
                self.isAnalyzing = false
            }
        }
    }

    /// Apply a suggestion based on the current apply mode
    func applySuggestion(_ record: LoopInsightsSuggestionRecord) {
        let mode = LoopInsights_FeatureFlags.applyMode

        switch mode {
        case .manual:
            // Just mark as applied — user navigates to Therapy Settings manually
            let snapshotBefore = try? coordinator.captureCurrentSnapshot()
            coordinator.suggestionStore.markApplied(
                recordID: record.id,
                mode: .manual,
                snapshotBefore: snapshotBefore,
                snapshotAfter: nil
            )

        case .oneTap:
            // Show confirmation dialog first
            recordToApply = record
            showingApplyConfirmation = true

        case .preFill:
            // Navigate to editor with pre-filled values
            // For Phase 1, fall back to one-tap behavior with confirmation
            recordToApply = record
            showingApplyConfirmation = true

        case .autoApply:
            // This path is only available in developer mode
            Task { @MainActor in
                await autoApplySuggestion(record.suggestion)
            }
        }
    }

    /// Confirm one-tap apply after user accepts disclaimer
    func confirmApply() {
        guard let record = recordToApply else { return }

        let snapshotBefore = try? coordinator.captureCurrentSnapshot()

        // TODO: Phase 1 — implement actual settings write via SettingsManager
        // For now, mark as applied and log
        coordinator.suggestionStore.markApplied(
            recordID: record.id,
            mode: LoopInsights_FeatureFlags.applyMode,
            snapshotBefore: snapshotBefore,
            snapshotAfter: nil
        )

        recordToApply = nil
        showingApplyConfirmation = false
        loadCurrentSettings()
    }

    /// Cancel apply confirmation
    func cancelApply() {
        recordToApply = nil
        showingApplyConfirmation = false
    }

    /// Dismiss a suggestion
    func dismissSuggestion(_ record: LoopInsightsSuggestionRecord) {
        coordinator.suggestionStore.markDismissed(recordID: record.id)
    }

    /// Dismiss all pending suggestions
    func dismissAllPending() {
        coordinator.suggestionStore.dismissAllPending()
    }

    /// Returns the analysis status for a setting type (used for color indicators)
    func settingStatus(_ type: LoopInsightsSettingType) -> LoopInsightsSettingStatus {
        let hasPending = pendingSuggestions.contains { $0.suggestion.settingType == type }
        if hasPending {
            return .hasSuggestions
        } else if analyzedSettingTypes.contains(type) {
            return .analyzedOK
        }
        return .notAnalyzed
    }

    /// Update analysis period and persist to settings
    func updateAnalysisPeriod(_ period: LoopInsightsAnalysisPeriod) {
        analysisPeriod = period
        LoopInsights_FeatureFlags.analysisPeriod = period
    }

    // MARK: - Private

    private func autoApplySuggestion(_ suggestion: LoopInsightsSuggestion) async {
        let snapshotBefore = try? coordinator.captureCurrentSnapshot()

        // TODO: Implement actual settings write
        // For now, just log the auto-apply intent
        print("[LoopInsights] Auto-applying suggestion: \(suggestion.summaryDescription)")

        if let record = coordinator.suggestionStore.pendingRecords.first(where: { $0.suggestion.id == suggestion.id }) {
            coordinator.suggestionStore.markApplied(
                recordID: record.id,
                mode: .autoApply,
                snapshotBefore: snapshotBefore,
                snapshotAfter: nil
            )
        }
    }

    // MARK: - Pattern Detection

    /// Detect glucose/insulin patterns from aggregated statistics.
    /// Returns patterns sorted by severity (high first).
    static func detectPatterns(from stats: LoopInsightsAggregatedStats) -> [LoopInsightsDetectedPattern] {
        var patterns: [LoopInsightsDetectedPattern] = []
        let g = stats.glucoseStats
        let period = stats.period

        // Overnight lows: average glucose during hours 0-5 below 80 mg/dL
        let overnightHours = (0...5)
        let overnightAvgs = overnightHours.compactMap { g.hourlyAverages[$0] }
        if !overnightAvgs.isEmpty {
            let overnightAvg = overnightAvgs.reduce(0, +) / Double(overnightAvgs.count)
            if overnightAvg < 70 {
                patterns.append(LoopInsightsDetectedPattern(
                    type: .overnightLows,
                    detail: String(format: NSLocalizedString("Average overnight glucose %.0f mg/dL in %@", comment: "LoopInsights pattern detail: overnight lows"), overnightAvg, period.displayName),
                    severity: .high
                ))
            } else if overnightAvg < 80 {
                patterns.append(LoopInsightsDetectedPattern(
                    type: .overnightLows,
                    detail: String(format: NSLocalizedString("Average overnight glucose %.0f mg/dL in %@", comment: "LoopInsights pattern detail: overnight lows moderate"), overnightAvg, period.displayName),
                    severity: .medium
                ))
            }
        }

        // Frequent lows: time below range > 4% (ADA target < 4%)
        if g.timeBelowRange > 8 {
            patterns.append(LoopInsightsDetectedPattern(
                type: .frequentLows,
                detail: String(format: NSLocalizedString("%.1f%% time below range in %@", comment: "LoopInsights pattern detail: frequent lows"), g.timeBelowRange, period.displayName),
                severity: .high
            ))
        } else if g.timeBelowRange > 4 {
            patterns.append(LoopInsightsDetectedPattern(
                type: .frequentLows,
                detail: String(format: NSLocalizedString("%.1f%% time below range in %@", comment: "LoopInsights pattern detail: frequent lows moderate"), g.timeBelowRange, period.displayName),
                severity: .medium
            ))
        }

        // Overnight highs: average glucose during hours 0-5 above 180 mg/dL
        if !overnightAvgs.isEmpty {
            let overnightAvg = overnightAvgs.reduce(0, +) / Double(overnightAvgs.count)
            if overnightAvg > 200 {
                patterns.append(LoopInsightsDetectedPattern(
                    type: .overnightHighs,
                    detail: String(format: NSLocalizedString("Average overnight glucose %.0f mg/dL in %@", comment: "LoopInsights pattern detail: overnight highs"), overnightAvg, period.displayName),
                    severity: .high
                ))
            } else if overnightAvg > 180 {
                patterns.append(LoopInsightsDetectedPattern(
                    type: .overnightHighs,
                    detail: String(format: NSLocalizedString("Average overnight glucose %.0f mg/dL in %@", comment: "LoopInsights pattern detail: overnight highs moderate"), overnightAvg, period.displayName),
                    severity: .medium
                ))
            }
        }

        // Dawn phenomenon: glucose rises > 30 mg/dL between hours 3-7
        let dawnStart = g.hourlyAverages[3] ?? g.hourlyAverages[4]
        let dawnPeak = g.hourlyAverages[7] ?? g.hourlyAverages[6]
        if let start = dawnStart, let peak = dawnPeak {
            let rise = peak - start
            if rise > 40 {
                patterns.append(LoopInsightsDetectedPattern(
                    type: .dawnPhenomenon,
                    detail: String(format: NSLocalizedString("Average rise of %.0f mg/dL between 3 AM–7 AM", comment: "LoopInsights pattern detail: dawn phenomenon"), rise),
                    severity: .high
                ))
            } else if rise > 20 {
                patterns.append(LoopInsightsDetectedPattern(
                    type: .dawnPhenomenon,
                    detail: String(format: NSLocalizedString("Average rise of %.0f mg/dL between 3 AM–7 AM", comment: "LoopInsights pattern detail: dawn phenomenon moderate"), rise),
                    severity: .medium
                ))
            }
        }

        // Post-meal spikes: high glucose during common meal hours relative to pre-meal
        // Compare hours 7-8 (breakfast) vs 6, hours 12-13 (lunch) vs 11, hours 18-19 (dinner) vs 17
        var spikeCount = 0
        let mealWindows: [(pre: Int, post: Int)] = [(6, 8), (11, 13), (17, 19)]
        for window in mealWindows {
            if let pre = g.hourlyAverages[window.pre], let post = g.hourlyAverages[window.post] {
                if post - pre > 50 { spikeCount += 1 }
            }
        }
        if spikeCount >= 2 {
            patterns.append(LoopInsightsDetectedPattern(
                type: .postMealSpikes,
                detail: String(format: NSLocalizedString("Post-meal glucose spikes detected at %d of 3 meal windows", comment: "LoopInsights pattern detail: post-meal spikes"), spikeCount),
                severity: spikeCount >= 3 ? .high : .medium
            ))
        }

        // High variability: CV > 36% (ADA target < 36%)
        if g.coefficientOfVariation > 45 {
            patterns.append(LoopInsightsDetectedPattern(
                type: .highVariability,
                detail: String(format: NSLocalizedString("Coefficient of variation %.1f%% (target <36%%)", comment: "LoopInsights pattern detail: high variability"), g.coefficientOfVariation),
                severity: .high
            ))
        } else if g.coefficientOfVariation > 36 {
            patterns.append(LoopInsightsDetectedPattern(
                type: .highVariability,
                detail: String(format: NSLocalizedString("Coefficient of variation %.1f%% (target <36%%)", comment: "LoopInsights pattern detail: high variability moderate"), g.coefficientOfVariation),
                severity: .medium
            ))
        }

        // Consistent highs: time above range > 25% (ADA target < 25%)
        if g.timeAboveRange > 40 {
            patterns.append(LoopInsightsDetectedPattern(
                type: .consistentHighs,
                detail: String(format: NSLocalizedString("%.1f%% time above range in %@", comment: "LoopInsights pattern detail: consistent highs"), g.timeAboveRange, period.displayName),
                severity: .high
            ))
        } else if g.timeAboveRange > 25 {
            patterns.append(LoopInsightsDetectedPattern(
                type: .consistentHighs,
                detail: String(format: NSLocalizedString("%.1f%% time above range in %@", comment: "LoopInsights pattern detail: consistent highs moderate"), g.timeAboveRange, period.displayName),
                severity: .medium
            ))
        }

        // Consistent lows: time below range with low average
        if g.averageGlucose < 100 && g.timeBelowRange > 2 {
            patterns.append(LoopInsightsDetectedPattern(
                type: .consistentLows,
                detail: String(format: NSLocalizedString("Average glucose %.0f mg/dL with %.1f%% below range", comment: "LoopInsights pattern detail: consistent lows"), g.averageGlucose, g.timeBelowRange),
                severity: g.averageGlucose < 90 ? .high : .medium
            ))
        }

        // Sort: high severity first
        return patterns.sorted { $0.severity > $1.severity }
    }
}
