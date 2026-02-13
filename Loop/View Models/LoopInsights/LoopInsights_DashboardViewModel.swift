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
import SwiftUI

/// Main view model for the LoopInsights Dashboard. Orchestrates data aggregation,
/// AI analysis, and suggestion state management.
///
/// Owned by DashboardView. Calls Coordinator services for data access and AI analysis.
final class LoopInsights_DashboardViewModel: ObservableObject {

    // MARK: - Published State

    /// Current analysis state
    @Published var isAnalyzing = false
    @Published var isAnalyzingAll = false
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
    @Published var focusSettingType: LoopInsightsSettingType = .basalRate

    /// Analysis period
    @Published var analysisPeriod: LoopInsightsAnalysisPeriod

    /// Apply mode confirmation state
    @Published var showingApplyConfirmation = false
    @Published var showingPreFillEditor = false
    @Published var recordToApply: LoopInsightsSuggestionRecord?

    /// Aggregated stats (for display)
    @Published var aggregatedStats: LoopInsightsAggregatedStats?

    /// Setting types that have been analyzed — used to show green "OK" status
    /// for settings that were reviewed and found to need no changes
    @Published var analyzedSettingTypes: Set<LoopInsightsSettingType> = []

    /// Detected glucose/insulin patterns from aggregated data
    @Published var detectedPatterns: [LoopInsightsDetectedPattern] = []

    /// Suggestions that were just auto-applied (for notification display)
    @Published var autoAppliedSuggestions: [LoopInsightsSuggestion] = []

    /// Settings score (0-100) based on objective metrics
    @Published var settingsScore: Int?
    @Published var settingsScoreBreakdown: SettingsScoreBreakdown?

    /// Whether current metrics indicate settings are already performing well
    @Published var settingsAlreadyOptimal: Bool = false

    // MARK: - Dependencies

    let coordinator: LoopInsights_Coordinator
    private var cancellables = Set<AnyCancellable>()

    /// Expose suggestion store for views that need direct access
    var suggestionStore: LoopInsights_SuggestionStore {
        coordinator.suggestionStore
    }

    /// Expose background monitor for banner overlay in DashboardView.
    /// Returns nil if monitoring is disabled.
    var backgroundMonitor: LoopInsights_BackgroundMonitor? {
        guard LoopInsights_FeatureFlags.backgroundMonitorEnabled else { return nil }
        return coordinator.backgroundMonitor
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
        autoAppliedSuggestions = []

        Task { @MainActor in
            do {
                // Aggregate data
                let stats = try await coordinator.dataAggregator.aggregateData(period: analysisPeriod)
                self.aggregatedStats = stats

                // Capture current settings
                let snapshot = try coordinator.captureCurrentSnapshot()
                self.currentSnapshot = snapshot

                // Run AI analysis (include recent changes so AI knows data predates current settings)
                let recentChanges = self.recentlyAppliedRecords()
                let response = try await coordinator.aiAnalysis.analyze(
                    settingType: focusSettingType,
                    currentSettings: snapshot,
                    stats: stats,
                    recentChanges: recentChanges
                )

                // Show patterns, score, and AI results together after analysis completes
                self.detectedPatterns = Self.detectPatterns(from: stats)
                self.updateSettingsScore()
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

                // Note: nextRecommendedFocus from AI is intentionally ignored
                // for single-analysis — keep focus on what the user selected.

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

    /// Run AI analysis for all three setting types sequentially
    func runAnalysisAll() {
        guard !isAnalyzing else { return }

        isAnalyzing = true
        isAnalyzingAll = true
        analysisError = nil
        autoAppliedSuggestions = []

        Task { @MainActor in
            do {
                // Aggregate data once for all analyses
                let stats = try await coordinator.dataAggregator.aggregateData(period: analysisPeriod)
                self.aggregatedStats = stats

                let snapshot = try coordinator.captureCurrentSnapshot()
                self.currentSnapshot = snapshot

                // Analyze each setting type in tuning order: CR → ISF → BR
                let recentChanges = self.recentlyAppliedRecords()
                for settingType in LoopInsightsSettingType.allCases {
                    let response = try await coordinator.aiAnalysis.analyze(
                        settingType: settingType,
                        currentSettings: snapshot,
                        stats: stats,
                        recentChanges: recentChanges
                    )

                    self.overallAssessment = response.overallAssessment
                    self.analyzedSettingTypes.insert(settingType)

                    // Dismiss existing pending suggestions for this type
                    for record in pendingSuggestions where record.suggestion.settingType == settingType {
                        coordinator.suggestionStore.markDismissed(recordID: record.id)
                    }

                    let _ = coordinator.suggestionStore.addSuggestions(response.suggestions)

                    // Auto-apply if developer mode + auto-apply enabled
                    if LoopInsights_FeatureFlags.developerModeEnabled &&
                       LoopInsights_FeatureFlags.applyMode == .autoApply {
                        for suggestion in response.suggestions where suggestion.confidence >= .high {
                            await autoApplySuggestion(suggestion)
                        }
                    }
                }

                // Show patterns and score after all analyses complete
                self.detectedPatterns = Self.detectPatterns(from: stats)
                self.updateSettingsScore()

                self.lastAnalysisDate = Date()
                self.isAnalyzing = false
                self.isAnalyzingAll = false

            } catch let error as LoopInsightsError {
                self.analysisError = error
                self.isAnalyzing = false
                self.isAnalyzingAll = false
            } catch {
                self.analysisError = .aiProviderError(error.localizedDescription)
                self.isAnalyzing = false
                self.isAnalyzingAll = false
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
            // Open editor pre-filled with proposed values for user review
            recordToApply = record
            showingPreFillEditor = true

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

        // Write the therapy settings changes to Loop
        coordinator.applyTherapyChanges(suggestion: record.suggestion)

        let snapshotAfter = try? coordinator.captureCurrentSnapshot()

        coordinator.suggestionStore.markApplied(
            recordID: record.id,
            mode: LoopInsights_FeatureFlags.applyMode,
            snapshotBefore: snapshotBefore,
            snapshotAfter: snapshotAfter
        )

        recordToApply = nil
        showingApplyConfirmation = false
        loadCurrentSettings()
    }

    /// Cancel apply confirmation
    func cancelApply() {
        recordToApply = nil
        showingApplyConfirmation = false
        showingPreFillEditor = false
    }

    /// Apply with user-edited values from the pre-fill editor
    func applyEditedSuggestion(editedBlocks: [LoopInsightsTimeBlock]) {
        guard let record = recordToApply else { return }

        let snapshotBefore = try? coordinator.captureCurrentSnapshot()

        // Build a modified suggestion with the user's edited values
        let editedSuggestion = LoopInsightsSuggestion(
            id: record.suggestion.id,
            settingType: record.suggestion.settingType,
            timeBlocks: editedBlocks,
            reasoning: record.suggestion.reasoning,
            confidence: record.suggestion.confidence,
            analysisPeriod: record.suggestion.analysisPeriod,
            createdAt: record.suggestion.createdAt
        )

        coordinator.applyTherapyChanges(suggestion: editedSuggestion)

        let snapshotAfter = try? coordinator.captureCurrentSnapshot()

        coordinator.suggestionStore.markApplied(
            recordID: record.id,
            mode: .preFill,
            snapshotBefore: snapshotBefore,
            snapshotAfter: snapshotAfter
        )

        recordToApply = nil
        showingPreFillEditor = false
        loadCurrentSettings()
    }

    /// Dismiss a suggestion
    func dismissSuggestion(_ record: LoopInsightsSuggestionRecord) {
        coordinator.suggestionStore.markDismissed(recordID: record.id)
    }

    /// Dismiss all pending suggestions
    func dismissAllPending() {
        coordinator.suggestionStore.dismissAllPending()
    }

    /// Revert a previously applied suggestion by restoring the pre-apply snapshot.
    /// Returns true if the revert succeeded.
    @discardableResult
    func revertSuggestion(_ record: LoopInsightsSuggestionRecord) -> Bool {
        guard record.status.isRevertable else { return false }
        guard let snapshotBefore = record.settingsSnapshotBefore else {
            print("[LoopInsights] Cannot revert: no pre-apply snapshot stored")
            return false
        }

        let success = coordinator.revertToSnapshot(snapshotBefore)
        if success {
            coordinator.suggestionStore.markReverted(recordID: record.id)
            loadCurrentSettings()
        }
        return success
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

    /// The most recent AI debug log (system prompt, user prompt, raw response).
    /// Available in developer mode for troubleshooting.
    var lastDebugLog: LoopInsightsDebugLog? {
        coordinator.aiAnalysis.lastDebugLog
    }

    /// Get records that were applied/auto-applied within the last 24 hours
    /// AND whose changes are still reflected in the current settings.
    /// If the user manually reverted settings, those records are excluded.
    private func recentlyAppliedRecords() -> [LoopInsightsSuggestionRecord] {
        let cutoff = Date().addingTimeInterval(-24 * 3600)
        guard let currentSnapshot = currentSnapshot else { return [] }

        return coordinator.suggestionStore.allRecords.filter { record in
            guard (record.status == .applied || record.status == .autoApplied),
                  (record.resolvedAt ?? record.createdAt) > cutoff else {
                return false
            }

            // Verify the proposed changes are still in effect by comparing
            // against current settings. If the user manually reverted, the
            // current values won't match the proposed values.
            let currentItems: [LoopInsightsTherapySnapshot.LoopInsightsScheduleItem]
            switch record.suggestion.settingType {
            case .carbRatio: currentItems = currentSnapshot.carbRatioItems
            case .insulinSensitivity: currentItems = currentSnapshot.insulinSensitivityItems
            case .basalRate: currentItems = currentSnapshot.basalRateItems
            }

            // Check if at least one proposed value still matches current settings
            for block in record.suggestion.timeBlocks {
                let currentValue = Self.effectiveValue(at: block.startTime, in: currentItems)
                if abs(currentValue - block.proposedValue) < 0.01 {
                    return true // This change is still active
                }
            }
            return false // None of the proposed values match — change was reverted
        }
    }

    /// Find the effective value at a given time in a schedule snapshot.
    private static func effectiveValue(
        at time: TimeInterval,
        in items: [LoopInsightsTherapySnapshot.LoopInsightsScheduleItem]
    ) -> Double {
        let sorted = items.sorted { $0.startTime < $1.startTime }
        var result = sorted.first?.value ?? 0
        for item in sorted {
            if item.startTime <= time {
                result = item.value
            } else {
                break
            }
        }
        return result
    }

    // MARK: - Private

    private func autoApplySuggestion(_ suggestion: LoopInsightsSuggestion) async {
        let snapshotBefore = try? coordinator.captureCurrentSnapshot()

        coordinator.applyTherapyChanges(suggestion: suggestion)

        let snapshotAfter = try? coordinator.captureCurrentSnapshot()

        if let record = coordinator.suggestionStore.pendingRecords.first(where: { $0.suggestion.id == suggestion.id }) {
            coordinator.suggestionStore.markApplied(
                recordID: record.id,
                mode: .autoApply,
                snapshotBefore: snapshotBefore,
                snapshotAfter: snapshotAfter
            )
        }

        autoAppliedSuggestions.append(suggestion)
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

    // MARK: - Settings Score

    struct SettingsScoreBreakdown {
        let tirScore: Int        // 0-40 points
        let belowRangeScore: Int // 0-25 points
        let cvScore: Int         // 0-20 points
        let gmiScore: Int        // 0-15 points
        let total: Int           // 0-100

        var grade: String {
            switch total {
            case 90...100: return "A"
            case 80..<90: return "B"
            case 70..<80: return "C"
            case 60..<70: return "D"
            default: return "F"
            }
        }

        var gradeColor: Color {
            switch total {
            case 90...100: return .green
            case 80..<90: return .blue
            case 70..<80: return .yellow
            case 60..<70: return .orange
            default: return .red
            }
        }

        var summary: String {
            switch total {
            case 90...100: return NSLocalizedString("Excellent — your settings are well-optimized", comment: "LoopInsights score: excellent")
            case 80..<90: return NSLocalizedString("Good — minor improvements possible", comment: "LoopInsights score: good")
            case 70..<80: return NSLocalizedString("Fair — some adjustments recommended", comment: "LoopInsights score: fair")
            case 60..<70: return NSLocalizedString("Needs attention — settings adjustments likely needed", comment: "LoopInsights score: needs attention")
            default: return NSLocalizedString("Review recommended — significant adjustments may help", comment: "LoopInsights score: review")
            }
        }
    }

    /// Calculate an objective settings score from glucose metrics.
    /// Based on international consensus targets (ADA/AACE).
    static func calculateSettingsScore(from stats: LoopInsightsAggregatedStats.GlucoseStats) -> SettingsScoreBreakdown {
        // TIR score: 40 points max. Target >70% (ADA consensus)
        // 90%+ = 40, 80% = 32, 70% = 24, <50% = 0
        let tirScore: Int
        if stats.timeInRange >= 90 { tirScore = 40 }
        else if stats.timeInRange >= 70 { tirScore = Int(((stats.timeInRange - 50) / 40) * 40) }
        else if stats.timeInRange >= 50 { tirScore = Int(((stats.timeInRange - 50) / 20) * 16) }
        else { tirScore = 0 }

        // Below range score: 25 points max. Target <4% (ADA consensus)
        // <1% = 25, <4% = 20, <8% = 10, >8% = 0
        let belowRangeScore: Int
        if stats.timeBelowRange < 1 { belowRangeScore = 25 }
        else if stats.timeBelowRange < 4 { belowRangeScore = 20 }
        else if stats.timeBelowRange < 8 { belowRangeScore = Int(25 - (stats.timeBelowRange * 2.5)) }
        else { belowRangeScore = 0 }

        // CV score: 20 points max. Target <36% (ADA consensus)
        // <30% = 20, <36% = 15, <45% = 8, >45% = 0
        let cvScore: Int
        if stats.coefficientOfVariation < 30 { cvScore = 20 }
        else if stats.coefficientOfVariation < 36 { cvScore = 15 }
        else if stats.coefficientOfVariation < 45 { cvScore = 8 }
        else { cvScore = 0 }

        // GMI score: 15 points max. Target <7.0% (ADA)
        // <6.5% = 15, <7.0% = 12, <7.5% = 8, <8.0% = 4, >8% = 0
        let gmiScore: Int
        if stats.gmi < 6.5 { gmiScore = 15 }
        else if stats.gmi < 7.0 { gmiScore = 12 }
        else if stats.gmi < 7.5 { gmiScore = 8 }
        else if stats.gmi < 8.0 { gmiScore = 4 }
        else { gmiScore = 0 }

        let total = max(0, min(100, tirScore + belowRangeScore + cvScore + gmiScore))
        return SettingsScoreBreakdown(tirScore: tirScore, belowRangeScore: belowRangeScore, cvScore: cvScore, gmiScore: gmiScore, total: total)
    }

    /// Update the settings score from current aggregated stats.
    func updateSettingsScore() {
        guard let stats = aggregatedStats else { return }
        let breakdown = Self.calculateSettingsScore(from: stats.glucoseStats)
        settingsScore = breakdown.total
        settingsScoreBreakdown = breakdown

        // Flag if settings are already performing well
        settingsAlreadyOptimal = stats.glucoseStats.timeInRange > 85 && stats.glucoseStats.timeBelowRange < 4
    }
}
