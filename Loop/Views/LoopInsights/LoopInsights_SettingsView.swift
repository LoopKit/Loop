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
import WebKit

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

    // Biometrics
    @State private var biometricsEnabled = LoopInsights_FeatureFlags.biometricsEnabled
    @StateObject private var healthKitManager = LoopInsights_HealthKitManager()
    @State private var isRequestingBiometricAuth = false

    // Tight Range
    @State private var tightRangeUpperBound = LoopInsights_FeatureFlags.tightRangeUpperBound

    // Phase 5 flags
    @State private var circadianEnabled = LoopInsights_FeatureFlags.circadianEnabled
    @State private var foodResponseEnabled = LoopInsights_FeatureFlags.foodResponseEnabled
    @State private var mealDebriefEnabled = LoopInsights_FeatureFlags.mealDebriefEnabled
    @State private var preMealAdvisorEnabled = LoopInsights_FeatureFlags.preMealAdvisorEnabled
    @State private var caffeineTrackingEnabled = LoopInsights_FeatureFlags.caffeineTrackingEnabled
    @State private var alcoholTrackingEnabled = LoopInsights_FeatureFlags.alcoholTrackingEnabled
    @State private var nightscoutImportEnabled = LoopInsights_FeatureFlags.nightscoutImportEnabled
    @State private var agpChartEnabled = LoopInsights_FeatureFlags.agpChartEnabled
    @State private var cgmBackfillDetectionEnabled = LoopInsights_FeatureFlags.cgmBackfillDetectionEnabled

    // Nightscout
    @State private var nightscoutConfig = LoopInsightsNightscoutConfig.load()
    @State private var isTestingNightscout = false
    @State private var nightscoutTestResult: TestResult?

    // MyFitnessPal
    @State private var mfpImportEnabled = LoopInsights_FeatureFlags.mfpImportEnabled
    @State private var mfpConnected = LoopInsights_SecureStorage.hasMFPAuth
    @State private var showMFPLogin = false
    @State private var isMFPSyncing = false
    @State private var mfpSyncResult: MFPSyncResult?
    @State private var mfpError: String?

    private enum MFPSyncResult {
        case success(LoopInsights_MFPSyncSummary)
        case failure(String)
    }

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
                biometricsSection
                phase5FeaturesSection
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
            biometricsEnabled = LoopInsights_FeatureFlags.biometricsEnabled
            circadianEnabled = LoopInsights_FeatureFlags.circadianEnabled
            foodResponseEnabled = LoopInsights_FeatureFlags.foodResponseEnabled
            mealDebriefEnabled = LoopInsights_FeatureFlags.mealDebriefEnabled
            preMealAdvisorEnabled = LoopInsights_FeatureFlags.preMealAdvisorEnabled
            caffeineTrackingEnabled = LoopInsights_FeatureFlags.caffeineTrackingEnabled
            alcoholTrackingEnabled = LoopInsights_FeatureFlags.alcoholTrackingEnabled
            nightscoutImportEnabled = LoopInsights_FeatureFlags.nightscoutImportEnabled
            mfpImportEnabled = LoopInsights_FeatureFlags.mfpImportEnabled
            mfpConnected = LoopInsights_SecureStorage.hasMFPAuth
            agpChartEnabled = LoopInsights_FeatureFlags.agpChartEnabled
            cgmBackfillDetectionEnabled = LoopInsights_FeatureFlags.cgmBackfillDetectionEnabled
            tightRangeUpperBound = LoopInsights_FeatureFlags.tightRangeUpperBound
            nightscoutConfig = LoopInsightsNightscoutConfig.load()
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
        .sheet(isPresented: $showMFPLogin) {
            NavigationView {
                LoopInsights_MFPLoginWebView(
                    onAuthSuccess: { auth in
                        do {
                            try LoopInsights_SecureStorage.saveMFPAuth(auth)
                            mfpConnected = true
                            mfpError = nil
                        } catch {
                            mfpError = "Failed to save credentials: \(error.localizedDescription)"
                        }
                        showMFPLogin = false
                    },
                    onError: { errorMessage in
                        mfpError = errorMessage
                        showMFPLogin = false
                    }
                )
                .navigationTitle("MyFitnessPal Login")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") { showMFPLogin = false }
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
                        .foregroundColor(Color(red: 26/255, green: 138/255, blue: 158/255))
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
                        HStack {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .foregroundColor(Color(red: 26/255, green: 138/255, blue: 158/255))
                            Text(NSLocalizedString("View LoopInsights Dashboard", comment: "LoopInsights open dashboard button"))
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(Color(.tertiaryLabel))
                        }
                    }
                    .buttonStyle(.plain)
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
                        .foregroundColor(Color(red: 26/255, green: 138/255, blue: 158/255))
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
                        .foregroundColor(Color(red: 26/255, green: 138/255, blue: 158/255))
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

                Text(NSLocalizedString("Rolling lookback period for automated AI-based suggestions and Ask Loopy Chatbot - how far back do you want LoopInsights to look when analyzing your glucose, insulin, and carb data?", comment: "LoopInsights Loopy analysis period description"))
                    .font(.caption)
                    .foregroundColor(.secondary)

                Divider()

                // Tight Range Upper Bound
                Stepper(value: $tightRangeUpperBound, in: 120...160, step: 5) {
                    HStack {
                        Text(NSLocalizedString("Tight Range Upper Bound", comment: "LoopInsights tight range stepper label"))
                            .font(.subheadline)
                        Spacer()
                        Text("\(tightRangeUpperBound) mg/dL")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.accentColor)
                    }
                }
                .onChange(of: tightRangeUpperBound) { newValue in
                    LoopInsights_FeatureFlags.tightRangeUpperBound = newValue
                }

                Text(NSLocalizedString("Upper limit for Time in Tight Range (TITR). Standard is 140 mg/dL per international consensus.", comment: "LoopInsights tight range description"))
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

    // MARK: - Biometrics

    private var biometricsSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "heart.text.square")
                        .foregroundColor(Color(red: 26/255, green: 138/255, blue: 158/255))
                    Text(NSLocalizedString("BIOMETRICS", comment: "LoopInsights biometrics header"))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                }

                Toggle(NSLocalizedString("Include Biometric Data", comment: "LoopInsights biometrics toggle"), isOn: $biometricsEnabled)
                    .onChange(of: biometricsEnabled) { newValue in
                        LoopInsights_FeatureFlags.biometricsEnabled = newValue
                        if newValue && !healthKitManager.authorizationRequested {
                            requestBiometricAuthorization()
                        }
                    }

                Text(NSLocalizedString("When enabled, LoopInsights includes heart rate, HRV, steps, sleep, active energy, and weight data in AI analysis. This helps the AI correlate lifestyle factors with glucose patterns.", comment: "LoopInsights biometrics description"))
                    .font(.caption)
                    .foregroundColor(.secondary)

                if biometricsEnabled {
                    if !LoopInsights_HealthKitManager.isHealthDataAvailable {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.red)
                            Text(NSLocalizedString("HealthKit is not available on this device.", comment: "LoopInsights HealthKit not available"))
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    } else {
                        // Authorization button (show when not yet requested)
                        if !healthKitManager.authorizationRequested {
                            Button(action: requestBiometricAuthorization) {
                                HStack(spacing: 6) {
                                    if isRequestingBiometricAuth {
                                        ProgressView()
                                            .progressViewStyle(.circular)
                                            .scaleEffect(0.8)
                                    } else {
                                        Image(systemName: "heart.circle")
                                    }
                                    Text(NSLocalizedString("Authorize HealthKit Access", comment: "LoopInsights authorize HealthKit button"))
                                }
                                .font(.body.weight(.medium))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color.pink)
                                .cornerRadius(10)
                            }
                            .disabled(isRequestingBiometricAuth)
                            .buttonStyle(.plain)
                        } else {
                            // Authorization sheet was shown — we can't see read permission status
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text(NSLocalizedString("HealthKit permissions configured", comment: "LoopInsights HealthKit permissions configured"))
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                        }

                        // Biometric types list (two columns)
                        HStack(alignment: .top, spacing: 16) {
                            VStack(alignment: .leading, spacing: 6) {
                                biometricTypeLabel("Heart Rate", icon: "heart.fill")
                                biometricTypeLabel("HRV", icon: "waveform.path.ecg")
                                biometricTypeLabel("Steps", icon: "figure.walk")
                            }
                            VStack(alignment: .leading, spacing: 6) {
                                biometricTypeLabel("Sleep", icon: "bed.double.fill")
                                biometricTypeLabel("Energy", icon: "flame.fill")
                                biometricTypeLabel("Weight", icon: "scalemass.fill")
                            }
                        }

                        Text(NSLocalizedString("Biometric data is read-only and never leaves your device except as part of AI analysis prompts. Manage permissions in Settings > Health > Loop.", comment: "LoopInsights biometrics privacy note"))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    private func biometricTypeLabel(_ name: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundColor(.pink)
                .font(.caption)
                .frame(width: 16)
            Text(name)
                .font(.caption)
                .foregroundColor(.primary)
        }
    }

    private func requestBiometricAuthorization() {
        isRequestingBiometricAuth = true
        Task {
            do {
                try await healthKitManager.requestAuthorization()
            } catch {
                LoopInsights_FeatureFlags.log.error("HealthKit authorization error: \(error)")
            }
            await MainActor.run {
                isRequestingBiometricAuth = false
            }
        }
    }

    // MARK: - AI Personality

    private var personalitySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "theatermasks")
                        .foregroundColor(Color(red: 26/255, green: 138/255, blue: 158/255))
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
                        .foregroundColor(Color(red: 26/255, green: 138/255, blue: 158/255))
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
                        .foregroundColor(Color(red: 26/255, green: 138/255, blue: 158/255))
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


    // MARK: - Phase 5 Features

    private var phase5FeaturesSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkle")
                        .foregroundColor(Color(red: 26/255, green: 138/255, blue: 158/255))
                    Text(NSLocalizedString("ADVANCED FEATURES", comment: "LoopInsights Phase 5 features header"))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                }

                Toggle(NSLocalizedString("AGP Chart", comment: "LoopInsights AGP toggle"), isOn: $agpChartEnabled)
                    .onChange(of: agpChartEnabled) { newValue in
                        LoopInsights_FeatureFlags.agpChartEnabled = newValue
                    }
                Text(NSLocalizedString("Show Ambulatory Glucose Profile chart on the dashboard with percentile bands (P10/P25/P50/P75/P90) over 24 hours.", comment: "LoopInsights AGP description"))
                    .font(.caption)
                    .foregroundColor(.secondary)

                if foodResponseEnabled {
                    Divider()

                    Toggle(NSLocalizedString("AI Meal Debrief", comment: "LoopInsights meal debrief toggle"), isOn: $mealDebriefEnabled)
                        .onChange(of: mealDebriefEnabled) { newValue in
                            LoopInsights_FeatureFlags.mealDebriefEnabled = newValue
                        }
                    Text(NSLocalizedString("Captures Loop's predicted glucose at meal time, then generates AI analysis comparing predicted vs actual response. Tap any meal card after 2 hours to see the debrief.", comment: "LoopInsights meal debrief description"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Divider()

                Toggle(NSLocalizedString("Alcohol Tracking", comment: "LoopInsights alcohol toggle"), isOn: $alcoholTrackingEnabled)
                    .onChange(of: alcoholTrackingEnabled) { newValue in
                        LoopInsights_FeatureFlags.alcoholTrackingEnabled = newValue
                    }
                Text(NSLocalizedString("Log alcohol intake to help the AI account for delayed hypoglycemia risk. Tracks standard drinks with linear metabolism.", comment: "LoopInsights alcohol description"))
                    .font(.caption)
                    .foregroundColor(.secondary)

                Divider()

                Toggle(NSLocalizedString("Caffeine Tracking", comment: "LoopInsights caffeine toggle"), isOn: $caffeineTrackingEnabled)
                    .onChange(of: caffeineTrackingEnabled) { newValue in
                        LoopInsights_FeatureFlags.caffeineTrackingEnabled = newValue
                    }
                Text(NSLocalizedString("Log caffeine intake to help the AI correlate caffeine with glucose patterns. Uses a 5.7-hour half-life decay model.", comment: "LoopInsights caffeine description"))
                    .font(.caption)
                    .foregroundColor(.secondary)

                Divider()

                Toggle(NSLocalizedString("CGM Signal Quality", comment: "LoopInsights CGM backfill toggle"), isOn: $cgmBackfillDetectionEnabled)
                    .onChange(of: cgmBackfillDetectionEnabled) { newValue in
                        LoopInsights_FeatureFlags.cgmBackfillDetectionEnabled = newValue
                    }
                Text(NSLocalizedString("Shows a banner when your CGM reconnects after a signal gap. Also tracks signal quality over time on the dashboard. Informational only — does not affect dosing.", comment: "LoopInsights CGM backfill description"))
                    .font(.caption)
                    .foregroundColor(.secondary)

                Divider()

                Toggle(NSLocalizedString("Circadian Analysis", comment: "LoopInsights circadian toggle"), isOn: $circadianEnabled)
                    .onChange(of: circadianEnabled) { newValue in
                        LoopInsights_FeatureFlags.circadianEnabled = newValue
                    }
                Text(NSLocalizedString("Enables circadian glucose profiling, dawn phenomenon detection, negative basal awareness, and HRV-based stress scoring. Enriches AI analysis with sleep/wake patterns.", comment: "LoopInsights circadian description"))
                    .font(.caption)
                    .foregroundColor(.secondary)

                Divider()

                NavigationLink {
                    DataLayer_ConsentView()
                } label: {
                    HStack {
                        Image(systemName: "arrow.up.doc")
                            .foregroundColor(.accentColor)
                        Text(NSLocalizedString("Data Sharing", comment: "DataLayer consent view navigation"))
                    }
                }
                Text(NSLocalizedString("Control how your health data is shared with healthcare providers and optionally contributed to diabetes research.", comment: "DataLayer consent description"))
                    .font(.caption)
                    .foregroundColor(.secondary)

                Divider()

                Toggle(NSLocalizedString("Food Response Analysis", comment: "LoopInsights food response toggle"), isOn: $foodResponseEnabled)
                    .onChange(of: foodResponseEnabled) { newValue in
                        LoopInsights_FeatureFlags.foodResponseEnabled = newValue
                    }
                Text(NSLocalizedString("Analyzes glucose responses by food type. Enables Meal Insights view with meal debrief cards and pre-meal AI advisor.", comment: "LoopInsights food response description"))
                    .font(.caption)
                    .foregroundColor(.secondary)

                Divider()

                Toggle(NSLocalizedString("MyFitnessPal Import", comment: "LoopInsights MFP toggle"), isOn: $mfpImportEnabled)
                    .onChange(of: mfpImportEnabled) { newValue in
                        LoopInsights_FeatureFlags.mfpImportEnabled = newValue
                    }
                Text(NSLocalizedString("Import meals from your MyFitnessPal diary. Imported meals appear in Meal Insights and Ask LoopInsights.", comment: "LoopInsights MFP description"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                if mfpImportEnabled {
                    if mfpConnected {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                            Text("Connected to MyFitnessPal")
                                .font(.caption).foregroundColor(.green)
                        }
                        HStack(spacing: 12) {
                            Button(action: syncMFPNow) {
                                HStack(spacing: 4) {
                                    if isMFPSyncing {
                                        ProgressView().progressViewStyle(.circular).scaleEffect(0.7)
                                    } else {
                                        Image(systemName: "arrow.triangle.2.circlepath")
                                    }
                                    Text(isMFPSyncing ? "Syncing..." : "Sync Now")
                                }
                                .font(.caption.weight(.medium))
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.green)
                                .cornerRadius(8)
                            }
                            .disabled(isMFPSyncing)
                            .opacity(isMFPSyncing ? 0.5 : 1.0)
                            .buttonStyle(.plain)

                            Button(action: disconnectMFP) {
                                HStack(spacing: 4) {
                                    Image(systemName: "xmark.circle")
                                    Text("Disconnect")
                                }
                                .font(.caption.weight(.medium))
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.red)
                                .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        }
                    } else {
                        Button(action: { showMFPLogin = true }) {
                            HStack(spacing: 6) {
                                Image(systemName: "link")
                                Text("Connect to MyFitnessPal")
                            }
                            .font(.body.weight(.medium))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.blue)
                            .cornerRadius(10)
                        }
                        .buttonStyle(.plain)
                        Text("Signs in via MyFitnessPal's website. Your credentials are never stored by Loop.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    if let result = mfpSyncResult {
                        switch result {
                        case .success(let summary):
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                                Text(summary.displayString)
                                    .font(.caption).foregroundColor(.green)
                            }
                        case .failure(let message):
                            HStack(alignment: .top, spacing: 4) {
                                Image(systemName: "xmark.circle.fill").foregroundColor(.red)
                                Text(message).font(.caption).foregroundColor(.red)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    if let error = mfpError {
                        HStack(alignment: .top, spacing: 4) {
                            Image(systemName: "xmark.circle.fill").foregroundColor(.red)
                            Text(error).font(.caption).foregroundColor(.red)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if let lastSync = LoopInsights_FeatureFlags.mfpLastSyncDate {
                        let formatter = RelativeDateTimeFormatter()
                        Text("Last synced \(formatter.localizedString(for: lastSync, relativeTo: Date()))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                Divider()

                Toggle(NSLocalizedString("Nightscout Import", comment: "LoopInsights nightscout toggle"), isOn: $nightscoutImportEnabled)
                    .onChange(of: nightscoutImportEnabled) { newValue in
                        LoopInsights_FeatureFlags.nightscoutImportEnabled = newValue
                    }
                Text(NSLocalizedString("Import glucose and treatment data from a Nightscout server as a supplemental data source.", comment: "LoopInsights nightscout description"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                if nightscoutImportEnabled {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Site URL").font(.caption).foregroundColor(.secondary)
                        TextField("https://your-site.herokuapp.com", text: $nightscoutConfig.siteURL)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .keyboardType(.URL)
                            .onChange(of: nightscoutConfig.siteURL) { _ in
                                nightscoutConfig.isConnected = false
                                nightscoutTestResult = nil
                                nightscoutConfig.save()
                            }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("API Secret").font(.caption).foregroundColor(.secondary)
                        SecureField("Your API secret", text: $nightscoutConfig.apiSecret)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .onChange(of: nightscoutConfig.apiSecret) { _ in
                                nightscoutConfig.isConnected = false
                                nightscoutTestResult = nil
                                nightscoutConfig.save()
                            }
                    }
                    Button(action: testNightscoutConnection) {
                        HStack(spacing: 6) {
                            if isTestingNightscout {
                                ProgressView().progressViewStyle(.circular).scaleEffect(0.8).tint(.black)
                                Text("Testing...")
                            } else {
                                Image(systemName: "checkmark.shield")
                                Text("Test Connection")
                            }
                        }
                        .font(.body.weight(.medium))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.white)
                        .cornerRadius(10)
                    }
                    .disabled(isTestingNightscout || nightscoutConfig.siteURL.isEmpty)
                    .opacity((isTestingNightscout || nightscoutConfig.siteURL.isEmpty) ? 0.5 : 1.0)
                    .buttonStyle(.plain)
                    if let result = nightscoutTestResult {
                        switch result {
                        case .success:
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                                Text("Connected to Nightscout").font(.caption).foregroundColor(.green)
                            }
                        case .failure(let message):
                            HStack(alignment: .top, spacing: 4) {
                                Image(systemName: "xmark.circle.fill").foregroundColor(.red)
                                Text(message).font(.caption).foregroundColor(.red)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        case .warning(let message):
                            HStack(alignment: .top, spacing: 4) {
                                Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                                Text(message).font(.caption).foregroundColor(.orange)
                            }
                        }
                    }
                    Text("Nightscout data is used as supplemental context for AI analysis. Your existing Loop data stores remain the primary source.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                if foodResponseEnabled {
                    Divider()

                    Toggle(NSLocalizedString("Pre-Meal Advisor", comment: "LoopInsights pre-meal advisor toggle"), isOn: $preMealAdvisorEnabled)
                        .onChange(of: preMealAdvisorEnabled) { newValue in
                            LoopInsights_FeatureFlags.preMealAdvisorEnabled = newValue
                        }
                    Text(NSLocalizedString("Shows historical glucose patterns and AI-powered advice when you identify a food you've eaten before in FoodFinder.", comment: "LoopInsights pre-meal advisor description"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private func testNightscoutConnection() {
        isTestingNightscout = true
        nightscoutTestResult = nil

        Task {
            do {
                let importer = LoopInsights_NightscoutImporter(config: nightscoutConfig)
                let success = try await importer.testConnection()
                await MainActor.run {
                    nightscoutConfig.isConnected = success
                    nightscoutConfig.save()
                    nightscoutTestResult = success ? .success : .failure("Unknown error")
                    isTestingNightscout = false
                }
            } catch {
                await MainActor.run {
                    nightscoutConfig.isConnected = false
                    nightscoutConfig.save()
                    nightscoutTestResult = .failure(error.localizedDescription)
                    isTestingNightscout = false
                }
            }
        }
    }

    private func syncMFPNow() {
        isMFPSyncing = true
        mfpSyncResult = nil
        mfpError = nil
        Task {
            do {
                let lastSync = LoopInsights_FeatureFlags.mfpLastSyncDate
                let summary = try await LoopInsights_MFPImporter.syncDiary(since: lastSync)
                await MainActor.run {
                    isMFPSyncing = false
                    mfpSyncResult = .success(summary)
                }
            } catch {
                await MainActor.run {
                    isMFPSyncing = false
                    if let mfpErr = error as? LoopInsights_MFPImporter.MFPError {
                        switch mfpErr {
                        case .sessionExpired, .notConnected:
                            mfpConnected = false
                        default: break
                        }
                    }
                    mfpSyncResult = .failure(error.localizedDescription)
                }
            }
        }
    }

    private func disconnectMFP() {
        LoopInsights_MFPImporter.disconnect()
        mfpConnected = false
        mfpSyncResult = nil
        mfpError = nil
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
            do {
                try LoopInsights_SecureStorage.saveAPIKey(key)
            } catch {
                LoopInsights_FeatureFlags.log.error("Failed to save API key: \(error)")
            }
        }
        saveConfiguration()
    }

    private func testConnection() {
        guard !baseURL.isEmpty, !apiKeyText.isEmpty else { return }

        isTesting = true
        testResult = nil

        // Save key and config first
        do {
            try LoopInsights_SecureStorage.saveAPIKey(apiKeyText)
        } catch {
            LoopInsights_FeatureFlags.log.error("Failed to save API key for test: \(error)")
        }
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
class LoopInsights_DashboardContainer: ObservableObject {
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
struct LoopInsights_TestDashboardWrapper: View {
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

// MARK: - MFP Login WebView

/// Presents MyFitnessPal's login page in a WKWebView. After the user authenticates,
/// extracts a bearer token via JavaScript and returns it through the callback.
/// The user's credentials are handled entirely by MFP's website — Loop never sees them.
private struct LoopInsights_MFPLoginWebView: UIViewRepresentable {
    let onAuthSuccess: (LoopInsights_MFPAuthData) -> Void
    let onError: (String) -> Void

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "authResult")
        config.userContentController = contentController

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator

        if let url = URL(string: "https://www.myfitnesspal.com/account/login") {
            webView.load(URLRequest(url: url))
        }

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "authResult")
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onAuthSuccess: onAuthSuccess, onError: onError)
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let onAuthSuccess: (LoopInsights_MFPAuthData) -> Void
        let onError: (String) -> Void
        private var hasExchangedToken = false

        init(onAuthSuccess: @escaping (LoopInsights_MFPAuthData) -> Void,
             onError: @escaping (String) -> Void) {
            self.onAuthSuccess = onAuthSuccess
            self.onError = onError
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !hasExchangedToken else { return }
            guard let url = webView.url,
                  url.host?.contains("myfitnesspal.com") == true,
                  !url.path.contains("/account/login"),
                  !url.path.contains("/api/auth/") else { return }

            // User has navigated away from login — attempt token exchange
            hasExchangedToken = true
            webView.evaluateJavaScript("""
                fetch('/user/auth_token?refresh=true')
                    .then(function(r) { return r.text(); })
                    .then(function(t) { window.webkit.messageHandlers.authResult.postMessage(t); })
                    .catch(function(e) { window.webkit.messageHandlers.authResult.postMessage('ERROR:' + e.message); })
            """)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            if !hasExchangedToken {
                onError("Navigation failed: \(error.localizedDescription)")
            }
        }

        func userContentController(_ userContentController: WKUserContentController,
                                    didReceive message: WKScriptMessage) {
            guard message.name == "authResult",
                  let body = message.body as? String else { return }

            if body.hasPrefix("ERROR:") {
                onError("Token exchange failed: \(String(body.dropFirst(6)))")
            } else if let auth = LoopInsights_MFPImporter.parseAuthResponse(body) {
                onAuthSuccess(auth)
            } else {
                onError("Could not authenticate with MyFitnessPal. Please try again.")
            }
        }
    }
}
