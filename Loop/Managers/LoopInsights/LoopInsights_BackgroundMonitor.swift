//
//  LoopInsights_BackgroundMonitor.swift
//  Loop
//
//  Concept & design by Taylor Patterson. Coded & tested by Claude Code in February 2026.
//  Copyright (c) 2025-2026 LoopKit Authors. All rights reserved.
//

import Foundation
import UserNotifications
import Combine

/// Monitors Loop's completion cycle and periodically runs AI analysis
/// to proactively detect therapy setting adjustment opportunities.
///
/// Hooks into `Notification.Name.LoopCompleted` which fires ~every 5 minutes.
/// Actual analysis is throttled to the user's configured frequency (6h/12h/24h/weekly).
/// When new suggestions are found, delivers notifications based on user preferences.
final class LoopInsights_BackgroundMonitor: ObservableObject {

    // MARK: - Published State

    /// The most recent background suggestion (for in-app banner display)
    @Published private(set) var latestBackgroundSuggestion: LoopInsightsSuggestion?

    /// Whether a new suggestion banner should be shown
    @Published var showBanner = false

    // MARK: - Properties

    private var loopCompletedObserver: NSObjectProtocol?
    private let coordinator: LoopInsights_Coordinator
    private var isRunningAnalysis = false

    /// UserDefaults key for last analysis timestamp
    private static let lastAnalysisKey = "LoopInsights_lastBackgroundAnalysis"

    /// Notification category identifier for LoopInsights
    static let notificationCategoryID = "LoopInsights_Suggestion"

    // MARK: - Initialization

    init(coordinator: LoopInsights_Coordinator) {
        self.coordinator = coordinator
    }

    deinit {
        stop()
    }

    // MARK: - Lifecycle

    /// Start observing Loop completion notifications.
    func start() {
        guard loopCompletedObserver == nil else { return }
        guard LoopInsights_FeatureFlags.backgroundMonitorEnabled else {
            print("[LoopInsights Monitor] Background monitoring is disabled")
            return
        }

        loopCompletedObserver = NotificationCenter.default.addObserver(
            forName: .LoopCompleted,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.handleLoopCompleted()
        }

        print("[LoopInsights Monitor] Started — frequency: \(LoopInsights_FeatureFlags.monitorFrequency.displayName)")
    }

    /// Stop observing and cancel any pending work.
    func stop() {
        if let observer = loopCompletedObserver {
            NotificationCenter.default.removeObserver(observer)
            loopCompletedObserver = nil
        }
        print("[LoopInsights Monitor] Stopped")
    }

    /// Restart the monitor (e.g. after settings change).
    func restart() {
        stop()
        start()
    }

    // MARK: - Loop Completion Handler

    private func handleLoopCompleted() {
        guard LoopInsights_FeatureFlags.backgroundMonitorEnabled else { return }
        guard !isRunningAnalysis else { return }
        guard shouldRunAnalysis() else { return }

        isRunningAnalysis = true

        Task {
            await runBackgroundAnalysis()
            await MainActor.run {
                isRunningAnalysis = false
            }
        }
    }

    /// Check if enough time has elapsed since the last analysis
    private func shouldRunAnalysis() -> Bool {
        let frequency = LoopInsights_FeatureFlags.monitorFrequency
        let lastAnalysis = UserDefaults.standard.double(forKey: Self.lastAnalysisKey)

        guard lastAnalysis > 0 else {
            return true // Never run before
        }

        let lastDate = Date(timeIntervalSince1970: lastAnalysis)
        let elapsed = Date().timeIntervalSince(lastDate)
        return elapsed >= frequency.timeInterval
    }

    /// Check if the current time falls within quiet hours
    private func isInQuietHours() -> Bool {
        guard LoopInsights_FeatureFlags.quietHoursEnabled else { return false }

        let calendar = Calendar.current
        let currentHour = calendar.component(.hour, from: Date())
        let start = LoopInsights_FeatureFlags.quietHoursStart
        let end = LoopInsights_FeatureFlags.quietHoursEnd

        if start <= end {
            // e.g., quiet hours 22-07 wraps around midnight → this is the non-wrapping case like 09-17
            return currentHour >= start && currentHour < end
        } else {
            // Wraps around midnight: e.g., 22-07 means quiet from 22:00 to 06:59
            return currentHour >= start || currentHour < end
        }
    }

    // MARK: - Background Analysis

    private func runBackgroundAnalysis() async {
        print("[LoopInsights Monitor] Running background analysis...")

        do {
            let period = LoopInsights_FeatureFlags.analysisPeriod
            let stats = try await coordinator.dataAggregator.aggregateData(period: period)
            let snapshot = try coordinator.captureCurrentSnapshot()

            var newSuggestions: [LoopInsightsSuggestion] = []
            let minConfidence = LoopInsights_FeatureFlags.monitorMinConfidence

            // Analyze all three setting types
            for settingType in LoopInsightsSettingType.allCases {
                let response = try await coordinator.aiAnalysis.analyze(
                    settingType: settingType,
                    currentSettings: snapshot,
                    stats: stats
                )

                // Filter by minimum confidence
                let qualifying = response.suggestions.filter { $0.confidence >= minConfidence }
                newSuggestions.append(contentsOf: qualifying)
            }

            // Update last analysis timestamp
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastAnalysisKey)

            guard !newSuggestions.isEmpty else {
                print("[LoopInsights Monitor] No new suggestions found")
                return
            }

            // Check for genuinely new suggestions (not duplicates of existing pending ones)
            let existingPending = coordinator.suggestionStore.pendingRecords
            let genuinelyNew = newSuggestions.filter { suggestion in
                !existingPending.contains { existing in
                    existing.suggestion.settingType == suggestion.settingType &&
                    existing.suggestion.timeBlocks.count == suggestion.timeBlocks.count
                }
            }

            guard !genuinelyNew.isEmpty else {
                print("[LoopInsights Monitor] Suggestions match existing pending — no notification needed")
                return
            }

            // Store the new suggestions
            let _ = coordinator.suggestionStore.addSuggestions(genuinelyNew)

            // Deliver notification
            await deliverNotification(for: genuinelyNew)

        } catch {
            print("[LoopInsights Monitor] Analysis failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Notification Delivery

    private func deliverNotification(for suggestions: [LoopInsightsSuggestion]) async {
        let style = LoopInsights_FeatureFlags.notificationStyle

        // Check quiet hours — still store suggestions but suppress notifications
        if isInQuietHours() {
            print("[LoopInsights Monitor] Quiet hours active — suppressing notification")
            return
        }

        guard let primary = suggestions.first else { return }

        switch style {
        case .banner:
            await deliverInAppBanner(suggestion: primary)
        case .push:
            await deliverPushNotification(suggestions: suggestions)
        case .silent:
            // No notification — suggestions are available in the store
            print("[LoopInsights Monitor] Silent mode — \(suggestions.count) suggestion(s) stored")
        }
    }

    private func deliverInAppBanner(suggestion: LoopInsightsSuggestion) async {
        await MainActor.run {
            latestBackgroundSuggestion = suggestion
            showBanner = true
        }
    }

    private func deliverPushNotification(suggestions: [LoopInsightsSuggestion]) async {
        let notification = UNMutableNotificationContent()
        notification.title = NSLocalizedString("LoopInsights", comment: "LoopInsights notification title")

        if suggestions.count == 1, let suggestion = suggestions.first {
            notification.body = String(
                format: NSLocalizedString("New %@ suggestion: %@", comment: "LoopInsights notification body: single suggestion"),
                suggestion.settingType.displayName,
                suggestion.summaryDescription
            )
        } else {
            notification.body = String(
                format: NSLocalizedString("%d new therapy setting suggestions available", comment: "LoopInsights notification body: multiple suggestions"),
                suggestions.count
            )
        }

        notification.sound = .default
        notification.categoryIdentifier = Self.notificationCategoryID

        let request = UNNotificationRequest(
            identifier: "LoopInsights_Background_\(UUID().uuidString)",
            content: notification,
            trigger: nil
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
            print("[LoopInsights Monitor] Push notification sent for \(suggestions.count) suggestion(s)")
        } catch {
            print("[LoopInsights Monitor] Failed to send notification: \(error.localizedDescription)")
        }
    }

    /// Dismiss the in-app banner
    func dismissBanner() {
        showBanner = false
        latestBackgroundSuggestion = nil
    }
}
