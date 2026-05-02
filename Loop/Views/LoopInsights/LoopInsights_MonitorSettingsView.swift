//
//  LoopInsights_MonitorSettingsView.swift
//  Loop
//
//  Concept & design by Taylor Patterson. Coded & tested by Claude Code in February 2026.
//  Copyright (c) 2025-2026 LoopKit Authors. All rights reserved.
//

import SwiftUI
import Combine

// MARK: - View Model

/// Reads/writes all monitor preferences from LoopInsights_FeatureFlags.
private final class MonitorSettingsViewModel: ObservableObject {

    @Published var isEnabled: Bool {
        didSet { LoopInsights_FeatureFlags.backgroundMonitorEnabled = isEnabled }
    }

    @Published var frequency: LoopInsightsMonitorFrequency {
        didSet { LoopInsights_FeatureFlags.monitorFrequency = frequency }
    }

    @Published var minConfidence: LoopInsightsConfidence {
        didSet { LoopInsights_FeatureFlags.monitorMinConfidence = minConfidence }
    }

    @Published var quietHoursEnabled: Bool {
        didSet { LoopInsights_FeatureFlags.quietHoursEnabled = quietHoursEnabled }
    }

    @Published var quietHoursStart: Int {
        didSet { LoopInsights_FeatureFlags.quietHoursStart = quietHoursStart }
    }

    @Published var quietHoursEnd: Int {
        didSet { LoopInsights_FeatureFlags.quietHoursEnd = quietHoursEnd }
    }

    @Published var notificationStyle: LoopInsightsNotificationStyle {
        didSet { LoopInsights_FeatureFlags.notificationStyle = notificationStyle }
    }

    init() {
        self.isEnabled = LoopInsights_FeatureFlags.backgroundMonitorEnabled
        self.frequency = LoopInsights_FeatureFlags.monitorFrequency
        self.minConfidence = LoopInsights_FeatureFlags.monitorMinConfidence
        self.quietHoursEnabled = LoopInsights_FeatureFlags.quietHoursEnabled
        self.quietHoursStart = LoopInsights_FeatureFlags.quietHoursStart
        self.quietHoursEnd = LoopInsights_FeatureFlags.quietHoursEnd
        self.notificationStyle = LoopInsights_FeatureFlags.notificationStyle
    }

    /// Human-readable display of when the last background check ran
    var lastCheckedDisplay: String {
        let timestamp = UserDefaults.standard.double(forKey: "LoopInsights_lastBackgroundAnalysis")
        guard timestamp > 0 else {
            return NSLocalizedString("Never", comment: "LoopInsights monitor: never checked")
        }
        let date = Date(timeIntervalSince1970: timestamp)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    /// Human-readable display of when the next check is expected
    var nextCheckDisplay: String? {
        let timestamp = UserDefaults.standard.double(forKey: "LoopInsights_lastBackgroundAnalysis")
        guard timestamp > 0 else { return nil }
        let lastDate = Date(timeIntervalSince1970: timestamp)
        let nextDate = lastDate.addingTimeInterval(frequency.timeInterval)
        if nextDate <= Date() {
            return NSLocalizedString("Next Loop cycle", comment: "LoopInsights monitor: next check imminent")
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: nextDate, relativeTo: Date())
    }

    func formatHour(_ hour: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h a"
        var calendar = Calendar.current
        calendar.timeZone = TimeZone.current
        let date = calendar.startOfDay(for: Date()).addingTimeInterval(TimeInterval(hour * 3600))
        return formatter.string(from: date)
    }
}

// MARK: - View

/// Settings UI for configuring LoopInsights background monitoring preferences.
/// Allows users to control frequency, confidence thresholds, quiet hours,
/// and notification style.
struct LoopInsights_MonitorSettingsView: View {

    @StateObject private var viewModel = MonitorSettingsViewModel()

    /// Callback to restart the background monitor when settings change
    var onSettingsChanged: (() -> Void)?

    var body: some View {
        Form {
            masterToggleSection
            if viewModel.isEnabled {
                lastCheckedSection
                frequencySection
                confidenceSection
                quietHoursSection
                notificationStyleSection
                infoSection
            }
        }
        .navigationTitle(NSLocalizedString("Background Monitoring", comment: "LoopInsights monitor settings title"))
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            onSettingsChanged?()
        }
    }

    // MARK: - Master Toggle

    private var masterToggleSection: some View {
        Section {
            Toggle(
                NSLocalizedString("Enable Background Monitoring", comment: "LoopInsights monitor toggle"),
                isOn: $viewModel.isEnabled
            )

            Text(NSLocalizedString("When enabled, LoopInsights periodically analyzes your data and notifies you when it detects a therapy setting that could be improved.", comment: "LoopInsights monitor description"))
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Frequency

    private var frequencySection: some View {
        Section(header: Text(NSLocalizedString("ANALYSIS FREQUENCY", comment: "LoopInsights monitor frequency header"))) {
            Picker(
                NSLocalizedString("Check every", comment: "LoopInsights monitor frequency picker"),
                selection: $viewModel.frequency
            ) {
                ForEach(LoopInsightsMonitorFrequency.allCases) { freq in
                    Text(freq.displayName).tag(freq)
                }
            }

            Text(NSLocalizedString("How often LoopInsights runs a full AI analysis on your data. More frequent checks use more API calls.", comment: "LoopInsights monitor frequency description"))
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Minimum Confidence

    private var confidenceSection: some View {
        Section(header: Text(NSLocalizedString("NOTIFICATION THRESHOLD", comment: "LoopInsights monitor confidence header"))) {
            Picker(
                NSLocalizedString("Notify for", comment: "LoopInsights monitor confidence picker"),
                selection: $viewModel.minConfidence
            ) {
                Text(NSLocalizedString("All", comment: "LoopInsights confidence filter: all")).tag(LoopInsightsConfidence.low)
                Text(NSLocalizedString("Medium & Above", comment: "LoopInsights confidence filter: medium+")).tag(LoopInsightsConfidence.medium)
                Text(NSLocalizedString("High Only", comment: "LoopInsights confidence filter: high only")).tag(LoopInsightsConfidence.high)
            }
            .pickerStyle(.segmented)

            Text(confidenceDescription)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var confidenceDescription: String {
        switch viewModel.minConfidence {
        case .low:
            return NSLocalizedString("Notify for all suggestions, including low-confidence ones. This may result in more notifications.", comment: "LoopInsights monitor confidence: all desc")
        case .medium:
            return NSLocalizedString("Notify for medium and high confidence suggestions. Good balance of signal vs. noise.", comment: "LoopInsights monitor confidence: medium+ desc")
        case .high:
            return NSLocalizedString("Only notify for high confidence suggestions. Fewer notifications, but only the most impactful changes.", comment: "LoopInsights monitor confidence: high only desc")
        }
    }

    // MARK: - Quiet Hours

    private var quietHoursSection: some View {
        Section(header: Text(NSLocalizedString("QUIET HOURS", comment: "LoopInsights monitor quiet hours header"))) {
            Toggle(
                NSLocalizedString("Enable Quiet Hours", comment: "LoopInsights monitor quiet hours toggle"),
                isOn: $viewModel.quietHoursEnabled
            )

            if viewModel.quietHoursEnabled {
                HStack {
                    Text(NSLocalizedString("From", comment: "LoopInsights monitor quiet hours from"))
                    Spacer()
                    Picker("", selection: $viewModel.quietHoursStart) {
                        ForEach(0..<24, id: \.self) { hour in
                            Text(viewModel.formatHour(hour)).tag(hour)
                        }
                    }
                    .pickerStyle(.menu)
                }

                HStack {
                    Text(NSLocalizedString("To", comment: "LoopInsights monitor quiet hours to"))
                    Spacer()
                    Picker("", selection: $viewModel.quietHoursEnd) {
                        ForEach(0..<24, id: \.self) { hour in
                            Text(viewModel.formatHour(hour)).tag(hour)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Text(NSLocalizedString("Notifications are suppressed during quiet hours. Analysis still runs — results are available when you next open LoopInsights.", comment: "LoopInsights monitor quiet hours description"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Notification Style

    private var notificationStyleSection: some View {
        Section(header: Text(NSLocalizedString("NOTIFICATION STYLE", comment: "LoopInsights monitor notification style header"))) {
            Picker(
                NSLocalizedString("Delivery", comment: "LoopInsights monitor notification picker"),
                selection: $viewModel.notificationStyle
            ) {
                ForEach(LoopInsightsNotificationStyle.allCases) { style in
                    Text(style.displayName).tag(style)
                }
            }

            Text(viewModel.notificationStyle.description)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Last Checked

    private var lastCheckedSection: some View {
        Section(header: Text(NSLocalizedString("STATUS", comment: "LoopInsights monitor status header"))) {
            HStack {
                Text(NSLocalizedString("Last checked", comment: "LoopInsights monitor last checked label"))
                Spacer()
                Text(viewModel.lastCheckedDisplay)
                    .foregroundColor(.secondary)
            }

            if let next = viewModel.nextCheckDisplay {
                HStack {
                    Text(NSLocalizedString("Next check", comment: "LoopInsights monitor next check label"))
                    Spacer()
                    Text(next)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Info

    private var infoSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.accentColor)
                    Text(NSLocalizedString("How it works", comment: "LoopInsights monitor info header"))
                        .font(.subheadline.weight(.medium))
                }

                Text(NSLocalizedString("Background monitoring piggybacks on Loop's existing ~5 minute cycle. When enough time has passed (based on your frequency setting), it runs a full AI analysis of all three therapy settings. If it finds suggestions that meet your confidence threshold, you'll be notified.", comment: "LoopInsights monitor info description"))
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(NSLocalizedString("Each analysis uses your configured AI provider and consumes API credits. With daily frequency, expect ~3 API calls per day (one per setting type).", comment: "LoopInsights monitor API usage note"))
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
    }
}
