//
//  AutoPresets_SettingsView.swift
//  Loop
//
//  AutoPresets — Settings UI for configuring activity-based preset automation.
//
//  Idea by Taylor Patterson. Coded by Claude Code.
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import LoopKit
import SwiftUI
import UIKit

// MARK: - Main Settings View

struct AutoPresets_SettingsView: View {
    @ObservedObject private var coordinator = AutoPresets_Coordinator.shared
    @State private var showingErrorAlert = false
    @State private var errorMessage = ""
    @State private var showingDebugLogs = false
    @State private var debugLogsCopied = false
    @State private var debugLogsCleared = false
    @State private var showingAIAdvisor = false
    @Environment(\.openURL) private var openURL

    // AI config state
    @State private var aiBaseURL: String = ""
    @State private var aiModel: String = ""
    @State private var aiAPIKeyText: String = ""
    @State private var showAIAPIKey = false
    @State private var aiTestResult: AIConfigTestResult?
    @State private var aiIsTesting = false

    /// Optional provider for LoopInsights data stores (nil when LoopInsights is not available)
    var dataStoresProvider: (() -> Any?)? = nil

    var body: some View {
        List {
            enableSection

            if coordinator.isEnabled {
                activityTypeSections
                detectionSettingsSection
                if dataStoresProvider != nil {
                    aiAdvisorSection
                }
                activityLogSection
                debugLogsSection
            }
        }
        .navigationTitle("AutoPresets")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Configuration Error", isPresented: $showingErrorAlert) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
        .sheet(isPresented: $showingDebugLogs) {
            AutoPresets_DebugLogsView(isPresented: $showingDebugLogs)
        }
        .sheet(isPresented: $showingAIAdvisor) {
            if let coordinator = buildLoopInsightsCoordinator() {
                AutoPresets_AIRecommendationView(coordinator: coordinator)
            }
        }
        .onAppear {
            let config = LoopInsights_FeatureFlags.aiConfiguration
            aiBaseURL = config.baseURL
            aiModel = config.model
            aiAPIKeyText = LoopInsights_SecureStorage.loadAPIKey() ?? ""
        }
    }

    // MARK: - Enable Section

    private var enableSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "figure.walk")
                        .foregroundColor(Color(red: 76/255, green: 175/255, blue: 80/255))
                    Text("AUTOPRESETS")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                        .lineLimit(1)
                        .layoutPriority(1)
                }
                Toggle(isOn: Binding(
                    get: { coordinator.isEnabled },
                    set: { enabled in
                        if enabled {
                            guard !coordinator.availablePresets().isEmpty else {
                                showErrorAlert("Please create at least one preset before enabling AutoPresets.")
                                return
                            }
                        }
                        coordinator.isEnabled = enabled
                    }
                )) {
                    VStack(alignment: .leading) {
                        Text("Enable AutoPresets")
                            .font(.headline)
                        Text("Automatically activates a preset when motion is detected.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - AI Advisor Section

    private var aiAdvisorSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { coordinator.settings.aiRecommendationsEnabled },
                set: { value in
                    coordinator.updateSettings { $0.aiRecommendationsEnabled = value }
                }
            )) {
                VStack(alignment: .leading) {
                    Text("Enable AI Preset Recommendations")
                        .font(.headline)
                    Text("Analyze your patterns and suggest new presets using AI.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if coordinator.settings.aiRecommendationsEnabled {
                aiConfigSection

                Button {
                    showingAIAdvisor = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "wand.and.stars")
                            .font(.title3)
                            .foregroundColor(Color(red: 76/255, green: 175/255, blue: 80/255))
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("AI Preset Advisor")
                                .font(.headline)
                                .foregroundColor(.primary)
                            Text("Analyze patterns and discover new presets")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(aiAPIKeyText.isEmpty || aiBaseURL.isEmpty)
                .opacity((aiAPIKeyText.isEmpty || aiBaseURL.isEmpty) ? 0.5 : 1.0)
            }
        }
    }

    // MARK: - AI Config Section

    @ViewBuilder
    private var aiConfigSection: some View {
        // Provider links
        VStack(alignment: .leading, spacing: 6) {
            Text("Get an API key from a provider:")
                .font(.caption)
                .foregroundColor(.secondary)
            HStack(spacing: 12) {
                aiProviderLink("OpenAI", url: "https://platform.openai.com/api-keys", color: .green)
                aiProviderLink("Anthropic", url: "https://console.anthropic.com/settings/keys", color: .orange)
                aiProviderLink("Gemini", url: "https://aistudio.google.com/apikey", color: .blue)
                aiProviderLink("Grok", url: "https://console.x.ai", color: .red)
            }
        }

        // Base URL
        VStack(alignment: .leading, spacing: 4) {
            Text("Base URL")
                .font(.caption)
                .foregroundColor(.secondary)
            HStack(spacing: 8) {
                TextField("e.g. https://api.openai.com/v1", text: $aiBaseURL)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .keyboardType(.URL)
                    .onChange(of: aiBaseURL) { _ in
                        aiTestResult = nil
                        saveAIConfiguration()
                    }
                if !aiBaseURL.isEmpty {
                    Button(action: { aiBaseURL = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }

        // API Key
        VStack(alignment: .leading, spacing: 4) {
            Text("API Key")
                .font(.caption)
                .foregroundColor(.secondary)
            HStack(spacing: 8) {
                Group {
                    if showAIAPIKey {
                        TextField("Enter your API key", text: $aiAPIKeyText)
                    } else {
                        SecureField("Enter your API key", text: $aiAPIKeyText)
                    }
                }
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .onChange(of: aiAPIKeyText) { newValue in
                    saveAIAPIKey(newValue)
                    aiTestResult = nil
                }
                Button(action: { showAIAPIKey.toggle() }) {
                    Image(systemName: showAIAPIKey ? "eye.slash" : "eye")
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
                if !aiAPIKeyText.isEmpty {
                    Button(action: { aiAPIKeyText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            if !aiAPIKeyText.isEmpty {
                Text("Stored securely in Keychain")
                    .font(.caption2)
                    .foregroundColor(.green)
            }
        }

        // Model
        VStack(alignment: .leading, spacing: 4) {
            Text("Model")
                .font(.caption)
                .foregroundColor(.secondary)
            HStack(spacing: 8) {
                TextField("e.g. gpt-4o, claude-sonnet-4-5-20250514", text: $aiModel)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .onChange(of: aiModel) { _ in
                        aiTestResult = nil
                        saveAIConfiguration()
                    }
                if !aiModel.isEmpty {
                    Button(action: { aiModel = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }

        // Test Connection
        VStack(spacing: 8) {
            Button(action: testAIConnection) {
                HStack(spacing: 6) {
                    if aiIsTesting {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(0.8)
                        Text("Testing...")
                    } else {
                        Image(systemName: "checkmark.shield")
                        Text("Test Connection")
                    }
                }
                .font(.body.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color(.systemGray5))
                .cornerRadius(10)
            }
            .disabled(aiIsTesting || aiAPIKeyText.isEmpty || aiBaseURL.isEmpty)
            .opacity((aiIsTesting || aiAPIKeyText.isEmpty || aiBaseURL.isEmpty) ? 0.5 : 1.0)
            .buttonStyle(.plain)

            if let result = aiTestResult {
                switch result {
                case .success:
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Connected")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                case .failure(let message):
                    HStack(alignment: .top, spacing: 4) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                        Text(message)
                            .font(.caption)
                            .foregroundColor(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }

        Text("This configuration is shared with LoopInsights. Changes here apply to both features.")
            .font(.caption2)
            .foregroundColor(.secondary)
    }

    // MARK: - Activity Type Sections

    private var activityTypeSections: some View {
        ForEach(AutoPresetsActivityType.allCases, id: \.self) { activityType in
            Section {
                activityTypeRow(for: activityType)

                if coordinator.settings.supportedActivityTypes.contains(activityType) {
                    presetSelectionView(for: activityType)
                }
            }
        }
    }

    private func activityTypeRow(for activityType: AutoPresetsActivityType) -> some View {
        HStack {
            Image(systemName: activityType.systemImageName)
                .foregroundColor(coordinator.settings.supportedActivityTypes.contains(activityType) ? Color(red: 76/255, green: 175/255, blue: 80/255) : .secondary)
                .frame(width: 24)

            VStack(alignment: .leading) {
                Text(activityType.displayName)
                    .font(.headline)
                Text("Detect \(activityType.displayName.lowercased()) activity")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Toggle("", isOn: activityToggleBinding(for: activityType))
        }
        .contentShape(Rectangle())
        .onTapGesture {
            toggleActivityType(activityType)
        }
    }

    private func presetSelectionView(for activityType: AutoPresetsActivityType) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Select your preset for \(activityType.displayName)")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                .padding(.top, 8)

            ForEach(coordinator.availablePresets(), id: \.id) { preset in
                Button {
                    coordinator.setPreset(preset, for: activityType)
                } label: {
                    HStack {
                        Text("\(preset.symbol) \(preset.name)")
                            .foregroundColor(.primary)
                        Spacer()
                        if coordinator.settings.presetId(for: activityType) == preset.id {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(Color(red: 76/255, green: 175/255, blue: 80/255))
                        } else {
                            Image(systemName: "circle")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }

    // MARK: - Detection Settings Section

    private var detectionSettingsSection: some View {
        Section("Detection Settings") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Continuous Activity Time")
                        .font(.headline)
                    Spacer()
                    Text(formatContinuousActivityTime(coordinator.settings.continuousActivityTime))
                        .foregroundColor(.secondary)
                }

                Text("After enough steps are detected, how long sustained activity must continue before the preset activates. Acts as a confirmation that you are truly active and not just briefly moving.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Slider(
                    value: Binding(
                        get: { continuousActivityTimeSliderValue(from: coordinator.settings.continuousActivityTime) },
                        set: { sliderValue in
                            coordinator.updateSettings { $0.continuousActivityTime = continuousActivityTimeFromSlider(sliderValue) }
                        }
                    ),
                    in: 0 ... 12,
                    step: 1
                )
            }
            .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Stop Delay")
                        .font(.headline)
                    Spacer()
                    Text(formatContinuousActivityTime(coordinator.settings.stopInterval))
                        .foregroundColor(.secondary)
                }

                Text("How long to wait after motion stops before deactivating preset.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Slider(
                    value: Binding(
                        get: { continuousActivityTimeSliderValue(from: coordinator.settings.stopInterval) },
                        set: { sliderValue in
                            coordinator.updateSettings { $0.stopInterval = continuousActivityTimeFromSlider(sliderValue) }
                        }
                    ),
                    in: 0 ... 12,
                    step: 1
                )
            }
            .padding(.vertical, 4)

            // High Confidence toggle hidden — CoreMotion's classifier is too
            // slow/unreliable to gate confirmation. Step-based checks (rate +
            // recency) are sufficient. Backend code remains for future use.
            // Toggle(isOn: Binding(
            //     get: { coordinator.settings.requireHighConfidence },
            //     set: { value in
            //         coordinator.updateSettings { $0.requireHighConfidence = value }
            //     }
            // )) {
            //     VStack(alignment: .leading) {
            //         Text("Require High Confidence")
            //             .font(.headline)
            //         Text("Only activate preset when motion is detected with high confidence. More strict but may miss some activity.")
            //             .font(.caption)
            //             .foregroundColor(.secondary)
            //     }
            // }
        }
    }

    // MARK: - Activity Log Section

    @ViewBuilder
    private var activityLogSection: some View {
        if !coordinator.settings.recentActivityLog.isEmpty {
            Section("Recent Activity (last 20 events)") {
                ForEach(coordinator.settings.recentActivityLog) { logEntry in
                    activityLogRow(for: logEntry)
                }

                Button(role: .destructive) {
                    coordinator.clearActivityLog()
                } label: {
                    HStack {
                        Spacer()
                        Text("Clear Logs")
                        Spacer()
                    }
                }
            }
        }
    }

    // MARK: - Debug Logs Section

    private var debugLogsSection: some View {
        Section("Debug Logs") {
            Toggle(isOn: Binding(
                get: { coordinator.settings.debugLoggingEnabled },
                set: { value in
                    coordinator.updateSettings { $0.debugLoggingEnabled = value }
                }
            )) {
                VStack(alignment: .leading) {
                    Text("Enable Debug Logging")
                        .font(.headline)
                    Text("Records detailed activity detection events for troubleshooting.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if coordinator.settings.debugLoggingEnabled {
                Button {
                    let logs = AutoPresets_Logger.shared.getLogContents()
                    UIPasteboard.general.string = logs
                    debugLogsCopied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        debugLogsCopied = false
                    }
                } label: {
                    HStack {
                        Image(systemName: "doc.on.doc")
                        Text(debugLogsCopied ? "Copied!" : "Copy Debug Logs to Clipboard")
                        Spacer()
                    }
                }

                Button {
                    showingDebugLogs = true
                } label: {
                    HStack {
                        Image(systemName: "doc.text")
                        Text("View Debug Logs")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                    }
                }

                Button(role: debugLogsCleared ? .cancel : .destructive) {
                    AutoPresets_Logger.shared.clearLogs()
                    debugLogsCleared = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        debugLogsCleared = false
                    }
                } label: {
                    HStack {
                        Spacer()
                        Text(debugLogsCleared ? "Cleared!" : "Clear Debug Logs")
                        Spacer()
                    }
                }
            }
        }
    }

    // MARK: - Helper Methods

    private func activityToggleBinding(for activityType: AutoPresetsActivityType) -> Binding<Bool> {
        Binding(
            get: { coordinator.settings.supportedActivityTypes.contains(activityType) },
            set: { enabled in
                if enabled {
                    guard !coordinator.availablePresets().isEmpty else {
                        showErrorAlert("No presets available to assign to activity types. Please create presets first.")
                        return
                    }
                }
                coordinator.updateSettings { settings in
                    if enabled {
                        settings.supportedActivityTypes.insert(activityType)
                    } else {
                        settings.supportedActivityTypes.remove(activityType)
                    }
                }
            }
        )
    }

    private func toggleActivityType(_ activityType: AutoPresetsActivityType) {
        let currentlyEnabled = coordinator.settings.supportedActivityTypes.contains(activityType)

        if !currentlyEnabled {
            guard !coordinator.availablePresets().isEmpty else {
                showErrorAlert("No presets available to assign to activity types. Please create presets first.")
                return
            }
        }

        coordinator.updateSettings { settings in
            if currentlyEnabled {
                settings.supportedActivityTypes.remove(activityType)
            } else {
                settings.supportedActivityTypes.insert(activityType)
            }
        }
    }

    private func activityLogRow(for logEntry: AutoPresetsLogEntry) -> some View {
        HStack {
            Image(systemName: logEntry.event.iconName)
                .foregroundColor(colorForEvent(logEntry.event))
                .frame(width: 24)

            VStack(alignment: .leading) {
                HStack {
                    Text(logEntry.event.displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    if let activityType = logEntry.activityType {
                        Text("(\(activityType.displayName))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                if let presetName = logEntry.presetName {
                    Text(presetName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if logEntry.event == .presetDeactivated,
                   let activationEntry = findMatchingActivationEntry(for: logEntry)
                {
                    let duration = logEntry.date.timeIntervalSince(activationEntry.date)
                    Text("Duration: \(formatDuration(duration))")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }

            Spacer()

            VStack(alignment: .trailing) {
                Text(Self.relativeDateFormatter.string(for: logEntry.date) ?? "")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(Self.timeFormatter.string(from: logEntry.date))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func colorForEvent(_ event: AutoPresetsLogEvent) -> Color {
        switch event {
        case .presetActivated: return .blue
        case .presetDeactivated: return .blue
        case .featureEnabled: return .green
        case .featureDisabled: return .orange
        case .presetCreatedByAI: return Color(red: 76/255, green: 175/255, blue: 80/255)
        }
    }

    private func findMatchingActivationEntry(for deactivationEntry: AutoPresetsLogEntry) -> AutoPresetsLogEntry? {
        guard deactivationEntry.event == .presetDeactivated else { return nil }

        return coordinator.settings.recentActivityLog.first { entry in
            entry.event == .presetActivated &&
                entry.activityType == deactivationEntry.activityType &&
                entry.presetName == deactivationEntry.presetName &&
                entry.date < deactivationEntry.date
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        return formatter.string(from: duration) ?? "\(Int(duration))s"
    }

    private func showErrorAlert(_ message: String) {
        errorMessage = message
        showingErrorAlert = true
    }

    // MARK: - Continuous Activity Time Slider

    private static let continuousActivityTimeValues: [TimeInterval] = [10, 20, 30, 60, 120, 180, 240, 300, 360, 420, 480, 540, 600]

    private func continuousActivityTimeSliderValue(from interval: TimeInterval) -> Double {
        if let index = Self.continuousActivityTimeValues.firstIndex(where: { $0 >= interval }) {
            return Double(index)
        }
        return 12
    }

    private func continuousActivityTimeFromSlider(_ sliderValue: Double) -> TimeInterval {
        let index = Int(sliderValue.rounded())
        guard index >= 0 && index < Self.continuousActivityTimeValues.count else {
            return 30
        }
        return Self.continuousActivityTimeValues[index]
    }

    private func formatContinuousActivityTime(_ interval: TimeInterval) -> String {
        if interval < 60 {
            return "\(Int(interval)) sec"
        } else {
            let minutes = Int(interval / 60)
            return "\(minutes) min"
        }
    }

    // MARK: - Formatters

    private static var relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        return formatter
    }()

    private static var timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()

    // MARK: - LoopInsights Coordinator Builder

    /// Build a LoopInsights_Coordinator from the type-erased data stores tuple.
    /// Same pattern as LoopInsights_SettingsView uses internally.
    private func buildLoopInsightsCoordinator() -> LoopInsights_Coordinator? {
        // Try test data first (developer mode)
        if let testCoordinator = LoopInsights_Coordinator.withTestDataIfAvailable() {
            return testCoordinator
        }
        // Real data stores from Loop (cast from type-erased tuple)
        guard let any = dataStoresProvider?(),
              let stores = any as? (GlucoseStoreProtocol, DoseStoreProtocol, CarbStoreProtocol, LatestStoredSettingsProvider, LoopInsightsSettingsWriter)
        else {
            return nil
        }
        return LoopInsights_Coordinator(
            glucoseStore: stores.0,
            doseStore: stores.1,
            carbStore: stores.2,
            settingsProvider: stores.3,
            settingsWriter: stores.4
        )
    }

    // MARK: - AI Config Helpers

    private func aiProviderLink(_ name: String, url: String, color: Color) -> some View {
        Button(action: { if let u = URL(string: url) { openURL(u) } }) {
            Text(name)
                .font(.caption)
                .foregroundColor(color)
        }
        .buttonStyle(.plain)
    }

    private func saveAIConfiguration() {
        let format = LoopInsightsRequestFormat.detect(from: aiBaseURL)
        var config = LoopInsights_FeatureFlags.aiConfiguration
        config.baseURL = aiBaseURL
        config.model = aiModel
        config.endpointPath = format.defaultEndpoint
        config.requestFormat = format
        config.apiKeyHeader = format.defaultAPIKeyHeader
        config.apiKeyPrefix = format.defaultAPIKeyPrefix
        LoopInsights_FeatureFlags.aiConfiguration = config
    }

    private func saveAIAPIKey(_ key: String) {
        if key.isEmpty {
            LoopInsights_SecureStorage.deleteAPIKey()
        } else {
            do {
                try LoopInsights_SecureStorage.saveAPIKey(key)
            } catch {
                LoopInsights_FeatureFlags.log.error("Failed to save API key: \(error)")
            }
        }
        saveAIConfiguration()
    }

    private func testAIConnection() {
        guard !aiBaseURL.isEmpty, !aiAPIKeyText.isEmpty else { return }

        aiIsTesting = true
        aiTestResult = nil

        do {
            try LoopInsights_SecureStorage.saveAPIKey(aiAPIKeyText)
        } catch {
            LoopInsights_FeatureFlags.log.error("Failed to save API key for test: \(error)")
        }
        saveAIConfiguration()

        Task {
            do {
                let success = try await LoopInsights_AIServiceAdapter.shared.testConnection()
                await MainActor.run {
                    aiTestResult = success ? .success : .failure("Unknown error")
                    aiIsTesting = false
                }
            } catch {
                await MainActor.run {
                    aiTestResult = .failure(error.localizedDescription)
                    aiIsTesting = false
                }
            }
        }
    }

}

// MARK: - AI Config Test Result

private enum AIConfigTestResult {
    case success
    case failure(String)
}

// MARK: - Debug Logs View

struct AutoPresets_DebugLogsView: View {
    @Binding var isPresented: Bool
    @State private var logContents: String = ""

    var body: some View {
        NavigationView {
            ScrollView {
                Text(logContents)
                    .font(.system(.caption, design: .monospaced))
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("Debug Logs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        isPresented = false
                    }
                }
            }
        }
        .onAppear {
            logContents = AutoPresets_Logger.shared.getLogContents()
        }
    }
}

// MARK: - Icon View

struct AutoPresets_IconView: View {
    @ObservedObject private var coordinator = AutoPresets_Coordinator.shared
    @State private var isAnimating = false

    var body: some View {
        Image(systemName: "figure.walk")
            .resizable()
            .scaledToFit()
            .frame(width: 36, height: 36)
            .foregroundColor(coordinator.isEnabled ? Color(red: 76/255, green: 175/255, blue: 80/255) : .secondary)
            .scaleEffect(coordinator.isEnabled && isAnimating ? 1.3 : 1.0)
            .animation(
                coordinator.isEnabled ? .easeInOut(duration: 0.4).repeatForever(autoreverses: true) : .default,
                value: isAnimating
            )
            .onAppear {
                if coordinator.isEnabled {
                    isAnimating = true
                }
            }
            .onChange(of: coordinator.isEnabled) { newValue in
                isAnimating = newValue
            }
    }
}

// MARK: - Preview

#if DEBUG
struct AutoPresets_SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            AutoPresets_SettingsView()
        }
    }
}
#endif
