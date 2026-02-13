//
//  LoopInsights_SettingsView.swift
//  Loop
//
//  Concept & design by Taylor Patterson. Coded & tested by Claude Code in February 2026.
//  Copyright (c) 2025-2026 LoopKit Authors. All rights reserved.
//

import SwiftUI
import Combine
import LoopKit

/// LoopInsights settings and configuration view.
/// Accessible from Loop's main SettingsView via NavigationLink.
struct LoopInsights_SettingsView: View {

    @Environment(\.openURL) var openURL

    /// Real data store references passed from Loop's SettingsView (type-erased).
    /// When nil, falls back to test data (simulator / preview).
    var dataStoresProvider: (() -> Any?)?

    @State private var isEnabled = LoopInsights_FeatureFlags.isEnabled
    @State private var selectedPeriod = LoopInsights_FeatureFlags.analysisPeriod
    @State private var selectedApplyMode = LoopInsights_FeatureFlags.applyMode
    @State private var selectedPersonality = LoopInsights_FeatureFlags.aiPersonality

    // AI Configuration
    @State private var baseURL: String
    @State private var model: String
    @State private var apiKeyText = ""
    @State private var showAPIKey = false
    @State private var detectedFormat: LoopInsightsRequestFormat

    // Advanced settings
    @State private var showAdvanced = false
    @State private var endpointPath: String
    @State private var apiVersion: String
    @State private var organizationID: String
    @State private var formatOverride: LoopInsightsRequestFormat?

    // Test connection
    @State private var isTesting = false
    @State private var testResult: TestResult?

    // Data
    @State private var showingClearHistory = false

    // Developer mode unlock
    @State private var developerTapCount = 0
    @State private var showDeveloperUnlocked = false

    // Test data (developer mode)
    @State private var useTestData = LoopInsights_FeatureFlags.useTestData
    @State private var testDataProvider: LoopInsights_TestDataProvider?
    @State private var showTestDashboard = false

    private enum TestResult {
        case success
        case warning(String)
        case failure(String)

        var isSuccess: Bool {
            if case .success = self { return true }
            return false
        }
    }

    init(dataStoresProvider: (() -> Any?)? = nil) {
        self.dataStoresProvider = dataStoresProvider
        let config = LoopInsights_FeatureFlags.aiConfiguration
        _baseURL = State(initialValue: config.baseURL)
        _model = State(initialValue: config.model)
        _detectedFormat = State(initialValue: LoopInsightsRequestFormat.detect(from: config.baseURL))
        _endpointPath = State(initialValue: config.endpointPath)
        _apiVersion = State(initialValue: config.apiVersion ?? "")
        _organizationID = State(initialValue: config.organizationID ?? "")

        // Check if user has overridden format (differs from auto-detected)
        let detected = LoopInsightsRequestFormat.detect(from: config.baseURL)
        if config.requestFormat != detected {
            _formatOverride = State(initialValue: config.requestFormat)
        } else {
            _formatOverride = State(initialValue: nil)
        }
    }

    var body: some View {
        Form {
            featureToggleSection
            if isEnabled {
                aiConfigSection
                advancedAISection
                analysisOptionsSection
                personalitySection
                backgroundMonitoringSection
                dataSection
                if LoopInsights_FeatureFlags.developerModeEnabled {
                    developerSection
                }
            }
        }
        .navigationTitle(NSLocalizedString("LoopInsights Settings", comment: "LoopInsights settings title"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Re-sync @State from persisted values on every appearance
            isEnabled = LoopInsights_FeatureFlags.isEnabled
            selectedPeriod = LoopInsights_FeatureFlags.analysisPeriod
            selectedApplyMode = LoopInsights_FeatureFlags.applyMode
            selectedPersonality = LoopInsights_FeatureFlags.aiPersonality
            useTestData = LoopInsights_FeatureFlags.useTestData
            apiKeyText = LoopInsights_SecureStorage.loadAPIKey() ?? ""

            // Clear stale endpoint path if it matches a different format's default
            if !endpointPath.isEmpty {
                let detected = LoopInsightsRequestFormat.detect(from: baseURL)
                let isKnownDefault = LoopInsightsRequestFormat.allCases.contains { $0.defaultEndpoint == endpointPath }
                if isKnownDefault && endpointPath != detected.defaultEndpoint {
                    endpointPath = ""
                }
            }
        }
        .alert(
            NSLocalizedString("Clear History", comment: "LoopInsights clear history alert title"),
            isPresented: $showingClearHistory
        ) {
            Button(NSLocalizedString("Clear All", comment: "LoopInsights clear all button"), role: .destructive) {
                LoopInsights_SuggestionStore.shared.clearAllHistory()
            }
            Button(NSLocalizedString("Cancel", comment: "Cancel button"), role: .cancel) {}
        } message: {
            Text(NSLocalizedString("This will permanently delete all suggestion history. This cannot be undone.", comment: "LoopInsights clear history warning"))
        }
        .alert(
            NSLocalizedString("Developer Mode", comment: "LoopInsights developer mode alert title"),
            isPresented: $showDeveloperUnlocked
        ) {
            Button(NSLocalizedString("OK", comment: "OK button")) {}
        } message: {
            Text(NSLocalizedString("Developer mode has been enabled. You now have access to test data fixtures and auto-apply mode.", comment: "LoopInsights developer mode unlocked message"))
        }
        .sheet(isPresented: $showTestDashboard) {
            NavigationView {
                LoopInsights_TestDashboardWrapper(dataStoresProvider: dataStoresProvider)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button(NSLocalizedString("Done", comment: "Done button")) {
                                showTestDashboard = false
                            }
                        }
                    }
            }
        }
    }

    // MARK: - Feature Toggle

    private var featureToggleSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "brain.head.profile")
                        .foregroundColor(.accentColor)
                    Text("LOOPINSIGHTS")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                        .lineLimit(1)
                        .layoutPriority(1)
                }
                .onLongPressGesture(minimumDuration: 1) {
                    developerTapCount += 1
                    if developerTapCount >= LoopInsights_FeatureFlags.developerUnlockThreshold {
                        LoopInsights_FeatureFlags.developerModeEnabled = true
                        developerTapCount = 0
                        showDeveloperUnlocked = true
                    }
                }

                Toggle(NSLocalizedString("Enable LoopInsights", comment: "LoopInsights enable toggle"), isOn: $isEnabled)
                    .onChange(of: isEnabled) { newValue in
                        LoopInsights_FeatureFlags.isEnabled = newValue
                    }

                Text(NSLocalizedString("Enable AI-powered therapy settings analysis and suggestions. When disabled, the feature is hidden but settings are preserved.", comment: "LoopInsights feature toggle description"))
                    .font(.caption)
                    .foregroundColor(.secondary)

                if isEnabled {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "cross.fill")
                                .foregroundColor(.red)
                            Text(NSLocalizedString("MEDICAL DISCLAIMER", comment: "LoopInsights medical disclaimer header"))
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                                .textCase(.uppercase)
                                .lineLimit(1)
                        }
                        Text(NSLocalizedString("AI therapy suggestions are advisory only. You are responsible for reviewing all changes. Consult your healthcare provider for significant therapy adjustments.", comment: "LoopInsights medical disclaimer"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Button(action: { showTestDashboard = true }) {
                        HStack(spacing: 10) {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .font(.title3)
                            Text(NSLocalizedString("Open Dashboard", comment: "LoopInsights open dashboard button"))
                                .fontWeight(.semibold)
                            Spacer()
                            Image(systemName: "arrow.right")
                                .font(.subheadline.weight(.semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .background(Color.green)
                        .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
            }
        }
    }

    // MARK: - AI Configuration

    private var aiConfigSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .foregroundColor(.accentColor)
                    Text(NSLocalizedString("AI CONFIGURATION", comment: "LoopInsights AI config header"))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                }

                Text(NSLocalizedString("Enter your preferred AI API connection details. Any provider that supports chat completions will work.", comment: "LoopInsights AI config description"))
                    .font(.caption)
                    .foregroundColor(.secondary)

                // API key signup links
                VStack(alignment: .leading, spacing: 6) {
                    Text(NSLocalizedString("Get an API key from a provider:", comment: "LoopInsights API key links header"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    HStack(spacing: 12) {
                        apiKeyLink("OpenAI", url: "https://platform.openai.com/api-keys", color: .green)
                        apiKeyLink("Anthropic", url: "https://console.anthropic.com/settings/keys", color: .orange)
                        apiKeyLink("Gemini", url: "https://aistudio.google.com/apikey", color: .blue)
                        apiKeyLink("Grok", url: "https://console.x.ai", color: .red)
                    }
                }

                // Base URL
                VStack(alignment: .leading, spacing: 4) {
                    Text(NSLocalizedString("Base URL", comment: "LoopInsights base URL label"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    HStack(spacing: 8) {
                        TextField("", text: $baseURL)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .overlay(alignment: .leading) {
                                if baseURL.isEmpty {
                                    Text("e.g. https://api.openai.com/v1")
                                        .foregroundColor(.secondary)
                                        .padding(.leading, 4)
                                        .allowsHitTesting(false)
                                }
                            }
                            .foregroundColor(.primary)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .keyboardType(.URL)
                            .onChange(of: baseURL) { _ in
                                detectedFormat = LoopInsightsRequestFormat.detect(from: baseURL)
                                formatOverride = nil
                                endpointPath = ""
                                testResult = nil
                                saveConfiguration()
                            }
                        if !baseURL.isEmpty {
                            Button(action: { baseURL = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // API Key
                VStack(alignment: .leading, spacing: 4) {
                    Text(NSLocalizedString("API Key", comment: "LoopInsights API key label"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    HStack(spacing: 8) {
                        Group {
                            if showAPIKey {
                                TextField(NSLocalizedString("Enter your API key", comment: "LoopInsights API key placeholder"), text: $apiKeyText)
                            } else {
                                SecureField(NSLocalizedString("Enter your API key", comment: "LoopInsights API key placeholder"), text: $apiKeyText)
                            }
                        }
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .onChange(of: apiKeyText) { newValue in
                            saveAPIKey(newValue)
                            testResult = nil
                        }
                        Button(action: { showAPIKey.toggle() }) {
                            Image(systemName: showAPIKey ? "eye.slash" : "eye")
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(.plain)
                        if !apiKeyText.isEmpty {
                            Button(action: { apiKeyText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if !apiKeyText.isEmpty {
                        Text(NSLocalizedString("Stored securely in Keychain", comment: "LoopInsights keychain confirmation"))
                            .font(.caption2)
                            .foregroundColor(.green)
                    }
                }

                // Model
                VStack(alignment: .leading, spacing: 4) {
                    Text(NSLocalizedString("Model", comment: "LoopInsights model label"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    HStack(spacing: 8) {
                        TextField("e.g. gpt-4o, claude-sonnet-4-5-20250514, gemini-2.0-flash", text: $model)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .onChange(of: model) { _ in
                                testResult = nil
                                saveConfiguration()
                            }
                        if !model.isEmpty {
                            Button(action: { model = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // Test Connection
                VStack(spacing: 8) {
                    Button(action: testConnection) {
                        HStack(spacing: 6) {
                            if isTesting {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .scaleEffect(0.8)
                                    .tint(.black)
                                Text(NSLocalizedString("Testing...", comment: "LoopInsights testing connection"))
                            } else {
                                Image(systemName: "checkmark.shield")
                                Text(NSLocalizedString("Test Connection", comment: "LoopInsights test connection button"))
                            }
                        }
                        .font(.body.weight(.medium))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.white)
                        .cornerRadius(10)
                    }
                    .disabled(isTesting || apiKeyText.isEmpty || baseURL.isEmpty)
                    .opacity((isTesting || apiKeyText.isEmpty || baseURL.isEmpty) ? 0.5 : 1.0)
                    .buttonStyle(.plain)

                    if let result = testResult {
                        switch result {
                        case .success:
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text(NSLocalizedString("Connected", comment: "LoopInsights connection success"))
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                        case .warning(let message):
                            HStack(alignment: .top, spacing: 4) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text(message)
                                    .font(.caption)
                                    .foregroundColor(.orange)
                                    .fixedSize(horizontal: false, vertical: true)
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
            }
        }
    }

    // MARK: - Advanced AI Config

    private var advancedAISection: some View {
        Section {
            DisclosureGroup(NSLocalizedString("Advanced API Settings", comment: "LoopInsights advanced settings toggle"), isExpanded: $showAdvanced) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(NSLocalizedString("This section is for self-hosted, Azure, or non-standard API endpoints. Most users can ignore these.", comment: "LoopInsights advanced settings description"))
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    // Endpoint Path
                    VStack(alignment: .leading, spacing: 4) {
                        Text(NSLocalizedString("Endpoint Path", comment: "LoopInsights endpoint path label"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("e.g. /chat/completions", text: $endpointPath)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .onChange(of: endpointPath) { _ in
                                saveConfiguration()
                            }
                        Text(NSLocalizedString("Leave blank to use the default for your chosen format.", comment: "LoopInsights endpoint path hint"))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    // API Version
                    VStack(alignment: .leading, spacing: 4) {
                        Text(NSLocalizedString("API Version", comment: "LoopInsights API version label"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("e.g. 2024-06-01 (Azure only)", text: $apiVersion)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .onChange(of: apiVersion) { _ in
                                saveConfiguration()
                            }
                    }

                    // Organization ID
                    VStack(alignment: .leading, spacing: 4) {
                        Text(NSLocalizedString("Organization ID", comment: "LoopInsights org ID label"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("e.g. org-... (OpenAI, Azure)", text: $organizationID)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .onChange(of: organizationID) { _ in
                                saveConfiguration()
                            }
                    }

                    // Request Format Override
                    VStack(alignment: .leading, spacing: 4) {
                        Text(NSLocalizedString("Request Format Override", comment: "LoopInsights format override label"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Picker("Format", selection: Binding(
                            get: { formatOverride ?? .openAICompatible },
                            set: { formatOverride = $0; saveConfiguration() }
                        )) {
                            ForEach(LoopInsightsRequestFormat.allCases, id: \.rawValue) { format in
                                Text(format.displayName).tag(format)
                            }
                        }
                        .pickerStyle(.segmented)
                        HStack(spacing: 4) {
                            Text(NSLocalizedString("Auto-detected:", comment: "LoopInsights auto-detected format label"))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(detectedFormat.displayName)
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                            if formatOverride != nil {
                                Button(NSLocalizedString("Reset", comment: "LoopInsights reset format button")) {
                                    formatOverride = nil
                                    saveConfiguration()
                                }
                                .font(.caption2)
                            }
                        }
                        Text(NSLocalizedString("Most providers use OpenAI Compatible. Only change this if auto-detection is wrong.", comment: "LoopInsights format override hint"))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    // Endpoint preview
                    if !endpointPreview.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(NSLocalizedString("Full endpoint URL:", comment: "LoopInsights endpoint preview label"))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(endpointPreview)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Analysis Options (Apply Mode + Period)

    private var analysisOptionsSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundColor(.accentColor)
                    Text(NSLocalizedString("ANALYSIS OPTIONS", comment: "LoopInsights analysis options header"))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                }

                // Lookback period slider
                VStack(spacing: 8) {
                    HStack {
                        Text(NSLocalizedString("Lookback Period", comment: "LoopInsights period picker"))
                            .font(.subheadline)
                        Spacer()
                        Text(selectedPeriod.displayName)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.accentColor)
                    }

                    let cases = LoopInsightsAnalysisPeriod.allCases
                    let currentIndex = Double(cases.firstIndex(of: selectedPeriod) ?? 0)
                    Slider(
                        value: Binding(
                            get: { currentIndex },
                            set: { newValue in
                                let index = Int(newValue.rounded())
                                if index >= 0 && index < cases.count {
                                    selectedPeriod = cases[index]
                                }
                            }
                        ),
                        in: 0...Double(cases.count - 1),
                        step: 1
                    )
                    HStack {
                        Text(cases.first?.displayName ?? "")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(cases.last?.displayName ?? "")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .onChange(of: selectedPeriod) { newValue in
                    LoopInsights_FeatureFlags.analysisPeriod = newValue
                }

                Text(NSLocalizedString("Rolling lookback period for automated AI-based suggestions - how far back do you want LoopInsights to look when analyzing your glucose, insulin, and carb data?", comment: "LoopInsights analysis period description"))
                    .font(.caption)
                    .foregroundColor(.secondary)

                Divider()

                // Apply mode picker
                let availableModes = LoopInsights_FeatureFlags.developerModeEnabled
                    ? LoopInsightsApplyMode.allCases
                    : LoopInsightsApplyMode.publicModes

                HStack {
                    Text(NSLocalizedString("When applying suggestions", comment: "LoopInsights apply mode picker"))
                    Spacer()
                    Menu {
                        ForEach(availableModes) { mode in
                            Button(action: {
                                selectedApplyMode = mode
                                LoopInsights_FeatureFlags.applyMode = mode
                            }) {
                                if mode == selectedApplyMode {
                                    Label(mode == .autoApply ? "\(mode.displayName) \u{26A0}\u{FE0F}" : mode.displayName, systemImage: "checkmark")
                                } else {
                                    Text(mode == .autoApply ? "\(mode.displayName) \u{26A0}\u{FE0F}" : mode.displayName)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(selectedApplyMode.displayName)
                                .foregroundColor(selectedApplyMode == .autoApply ? .orange : .accentColor)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2)
                                .foregroundColor(selectedApplyMode == .autoApply ? .orange : .accentColor)
                        }
                    }
                }

                Text(selectedApplyMode.description)
                    .font(.caption)
                    .foregroundColor(selectedApplyMode == .autoApply ? .orange : .secondary)
            }
        }
    }

    // MARK: - AI Personality

    private var personalitySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "theatermasks")
                        .foregroundColor(.accentColor)
                    Text(NSLocalizedString("AI PERSONALITY", comment: "LoopInsights AI personality header"))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                }

                Picker(NSLocalizedString("Response Style", comment: "LoopInsights personality picker label"), selection: $selectedPersonality) {
                    ForEach(LoopInsightsAIPersonality.allCases) { personality in
                        Text(personality.displayName).tag(personality)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: selectedPersonality) { newValue in
                    LoopInsights_FeatureFlags.aiPersonality = newValue
                }

                Text(selectedPersonality.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Background Monitoring

    private var backgroundMonitoringSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "bell.badge")
                        .foregroundColor(.accentColor)
                    Text(NSLocalizedString("BACKGROUND MONITORING", comment: "LoopInsights background monitoring header"))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                }

                NavigationLink {
                    LoopInsights_MonitorSettingsView()
                } label: {
                    HStack {
                        Text(NSLocalizedString("Background Monitoring", comment: "LoopInsights background monitoring row"))
                        Spacer()
                        Text(LoopInsights_FeatureFlags.backgroundMonitorEnabled
                            ? LoopInsights_FeatureFlags.monitorFrequency.displayName
                            : NSLocalizedString("Off", comment: "LoopInsights monitoring off"))
                            .foregroundColor(.secondary)
                    }
                }

                Text(NSLocalizedString("LoopInsights can continuously monitor your data and proactively notify you when it detects a setting change opportunity.", comment: "LoopInsights background monitoring description"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Data

    private var dataSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundColor(.accentColor)
                    Text(NSLocalizedString("SUGGESTION HISTORY", comment: "LoopInsights history header"))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                }

                HStack {
                    Text(NSLocalizedString("Stored Suggestions", comment: "LoopInsights stored suggestions label"))
                    Spacer()
                    Text("\(LoopInsights_SuggestionStore.shared.allRecords.count)")
                        .foregroundColor(.secondary)
                    Button(role: .destructive, action: { showingClearHistory = true }) {
                        Image(systemName: "trash")
                            .font(.caption)
                    }
                }
            }
        }
    }

    // MARK: - Developer Section (Hidden)

    private var developerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "hammer.fill")
                        .foregroundColor(.orange)
                    Text(NSLocalizedString("DEVELOPER", comment: "LoopInsights developer section header"))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.orange)
                        .textCase(.uppercase)
                }

                HStack {
                    Text(NSLocalizedString("Developer Mode", comment: "LoopInsights developer mode label"))
                    Spacer()
                    Text(NSLocalizedString("Active", comment: "LoopInsights developer mode active"))
                        .foregroundColor(.orange)
                        .fontWeight(.medium)
                }

                if selectedApplyMode == .autoApply {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text(NSLocalizedString("Auto-Apply is enabled. High-confidence suggestions will be applied automatically.", comment: "LoopInsights auto-apply warning"))
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }

                // Test Data Toggle
                Toggle(NSLocalizedString("Use Test Data Fixtures", comment: "LoopInsights test data toggle"), isOn: $useTestData)
                    .onChange(of: useTestData) { newValue in
                        LoopInsights_FeatureFlags.useTestData = newValue
                        if newValue {
                            testDataProvider = LoopInsights_TestDataProvider()
                        } else {
                            testDataProvider = nil
                        }
                    }

                Text(NSLocalizedString("Load JSON fixtures from Documents/LoopInsights/ instead of real Loop data. Use pull_tidepool_data.py to generate fixtures from your Tidepool account.", comment: "LoopInsights test data description"))
                    .font(.caption)
                    .foregroundColor(.secondary)

                // Test data status
                if useTestData {
                    testDataStatusView
                }

                Button(action: {
                    LoopInsights_FeatureFlags.developerModeEnabled = false
                    LoopInsights_FeatureFlags.applyMode = .manual
                    selectedApplyMode = .manual
                    useTestData = false
                    LoopInsights_FeatureFlags.useTestData = false
                    testDataProvider = nil
                }) {
                    HStack {
                        Image(systemName: "lock.fill")
                        Text(NSLocalizedString("Disable Developer Mode", comment: "LoopInsights disable developer button"))
                    }
                    .foregroundColor(.orange)
                }
            }
        }
    }

    // MARK: - Test Data Status

    private var testDataStatusView: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let provider = testDataProvider {
                if provider.hasTestData {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                        Text(NSLocalizedString("Fixtures loaded", comment: "LoopInsights fixtures loaded"))
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                    Text(provider.dataSummary)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    if let range = provider.dateRange {
                        let formatter = DateFormatter()
                        let _ = formatter.dateStyle = .short
                        Text("\(formatter.string(from: range.start)) — \(formatter.string(from: range.end))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.caption)
                        Text(NSLocalizedString("No fixtures found", comment: "LoopInsights no fixtures"))
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    Text(NSLocalizedString("Place fixture files in Documents/LoopInsights/ or rebuild with bundled test data.", comment: "LoopInsights no fixtures hint"))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("Documents path: \(LoopInsights_TestDataProvider.documentsDirectory.path)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                }
            } else {
                ProgressView()
                    .scaleEffect(0.8)
            }
        }
        .onAppear {
            if useTestData && testDataProvider == nil {
                testDataProvider = LoopInsights_TestDataProvider()
            }
        }
    }


    // MARK: - Helpers

    private var effectiveFormat: LoopInsightsRequestFormat {
        return formatOverride ?? detectedFormat
    }

    private var endpointPreview: String {
        let base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else { return "" }
        let trimmed = base.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let path = endpointPath.isEmpty ? effectiveFormat.defaultEndpoint : endpointPath
        let resolvedPath = path.replacingOccurrences(of: "{MODEL}", with: model.isEmpty ? "<model>" : model)
        return "\(trimmed)\(resolvedPath)"
    }

    private func apiKeyLink(_ name: String, url: String, color: Color) -> some View {
        Button(action: { if let u = URL(string: url) { openURL(u) } }) {
            Text(name)
                .font(.caption)
                .foregroundColor(color)
        }
        .buttonStyle(.plain)
    }

    private func saveConfiguration() {
        let format = effectiveFormat
        var config = LoopInsights_FeatureFlags.aiConfiguration
        config.baseURL = baseURL
        config.model = model
        config.endpointPath = endpointPath.isEmpty ? format.defaultEndpoint : endpointPath
        config.requestFormat = format
        config.apiKeyHeader = format.defaultAPIKeyHeader
        config.apiKeyPrefix = format.defaultAPIKeyPrefix
        config.apiVersion = apiVersion.isEmpty ? nil : apiVersion
        config.organizationID = organizationID.isEmpty ? nil : organizationID
        LoopInsights_FeatureFlags.aiConfiguration = config
    }

    private func saveAPIKey(_ key: String) {
        if key.isEmpty {
            LoopInsights_SecureStorage.deleteAPIKey()
        } else {
            try? LoopInsights_SecureStorage.saveAPIKey(key)
        }
        saveConfiguration()
    }

    private func testConnection() {
        guard !baseURL.isEmpty, !apiKeyText.isEmpty else { return }

        isTesting = true
        testResult = nil

        // Save key and config first
        try? LoopInsights_SecureStorage.saveAPIKey(apiKeyText)
        saveConfiguration()

        Task {
            do {
                let success = try await LoopInsights_AIServiceAdapter.shared.testConnection()
                await MainActor.run {
                    testResult = success ? .success : .failure(NSLocalizedString("Unknown error", comment: "LoopInsights unknown error"))
                    isTesting = false
                }
            } catch let error as LoopInsightsError {
                await MainActor.run {
                    // 402/429 are "connected with caveats" — show as warning
                    let message = error.localizedDescription
                    if message.contains("402") || message.contains("429") {
                        testResult = .warning(message)
                    } else {
                        testResult = .failure(message)
                    }
                    isTesting = false
                }
            } catch {
                await MainActor.run {
                    testResult = .failure(error.localizedDescription)
                    isTesting = false
                }
            }
        }
    }
}

// MARK: - Dashboard Wrapper

/// Lightweight container that owns the ViewModel and defers heavy creation to
/// onAppear. Also forwards the ViewModel's objectWillChange to its own publisher
/// so the wrapper view re-renders when any ViewModel @Published property changes.
/// This allows DashboardView to use a plain `var` instead of @ObservedObject,
/// avoiding a silent SwiftUI crash during sheet presentation rendering.
private class LoopInsights_DashboardContainer: ObservableObject {
    @Published var viewModel: LoopInsights_DashboardViewModel?
    /// Increments on every ViewModel objectWillChange, forcing SwiftUI to
    /// re-evaluate DashboardView's body (since the reference itself doesn't change).
    @Published var renderTrigger: Int = 0
    private var vmCancellable: AnyCancellable?

    func initializeIfNeeded(dataStoresProvider: (() -> Any?)? = nil) {
        guard viewModel == nil else { return }

        let coordinator: LoopInsights_Coordinator

        // Developer mode: test data takes priority
        if let testCoordinator = LoopInsights_Coordinator.withTestDataIfAvailable() {
            coordinator = testCoordinator
        }
        // Real data stores from Loop (cast from type-erased tuple)
        else if let any = dataStoresProvider?(),
                let stores = any as? (GlucoseStoreProtocol, DoseStoreProtocol, CarbStoreProtocol, LatestStoredSettingsProvider, LoopInsightsSettingsWriter) {
            coordinator = LoopInsights_Coordinator(
                glucoseStore: stores.0,
                doseStore: stores.1,
                carbStore: stores.2,
                settingsProvider: stores.3,
                settingsWriter: stores.4
            )
        }
        // Fallback: test data provider (simulator with no real stores)
        else {
            let provider = LoopInsights_TestDataProvider()
            coordinator = LoopInsights_Coordinator(testDataProvider: provider)
        }

        // Start background monitoring if enabled
        coordinator.startBackgroundMonitoring()

        let vm = LoopInsights_DashboardViewModel(coordinator: coordinator)

        // Forward ViewModel's objectWillChange → increment renderTrigger
        // so SwiftUI sees a value change and re-evaluates DashboardView
        vmCancellable = vm.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.renderTrigger += 1
            }
        }

        // Defer @Published assignment to next run loop to avoid
        // objectWillChange during SwiftUI's view update cycle
        DispatchQueue.main.async { [weak self] in
            self?.viewModel = vm
        }
    }
}

/// Wrapper view that owns the Container via @StateObject and presents
/// the DashboardView once the ViewModel is ready.
private struct LoopInsights_TestDashboardWrapper: View {
    @StateObject private var container = LoopInsights_DashboardContainer()
    var dataStoresProvider: (() -> Any?)?

    var body: some View {
        Group {
            if let vm = container.viewModel {
                LoopInsights_DashboardView(
                    viewModel: vm,
                    renderTrigger: container.renderTrigger
                )
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                    Text(NSLocalizedString("Loading data...", comment: "LoopInsights loading data"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .onAppear {
            container.initializeIfNeeded(dataStoresProvider: dataStoresProvider)
        }
    }
}
