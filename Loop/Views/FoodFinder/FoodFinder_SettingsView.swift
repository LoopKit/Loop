//
//  AISettingsView.swift
//  Loop
//
//  Created by Taylor Patterson, Coded by Claude Code for AI Settings Configuration in June 2025
//  Copyright © 2025 LoopKit Authors. All rights reserved.
//

import SwiftUI

/// Settings view for configuring AI food analysis.
/// Completely AI-agnostic — the user enters their own endpoint, key, and model.
struct AISettingsView: View {
    @Environment(\.openURL) var openURL

    // Feature toggles
    @AppStorage("com.loopkit.Loop.foodSearchEnabled") private var foodSearchEnabled: Bool = false
    @AppStorage("com.loopkit.Loop.advancedDosingRecommendationsEnabled") private var advancedDosingRecommendationsEnabled: Bool = false
    @AppStorage("com.loopkit.Loop.analysisHistoryRetentionDays") private var retentionDays: Int = 7

    // AI configuration (non-secret settings)
    @AppStorage("com.loopkit.Loop.customAIBaseURL") private var baseURL: String = ""
    @AppStorage("com.loopkit.Loop.customAIModel") private var model: String = ""
    @AppStorage("com.loopkit.Loop.customAIEndpointPath") private var endpointPath: String = ""
    @AppStorage("com.loopkit.Loop.customAIAPIVersion") private var apiVersion: String = ""
    @AppStorage("com.loopkit.Loop.customAIOrganization") private var organizationID: String = ""

    // API keys (Keychain-backed)
    @State private var apiKey: String = ""
    @State private var usdaAPIKey: String = ""

    // UI state
    @State private var showAPIKey: Bool = false
    @State private var showUSDAKey: Bool = false
    @State private var isTesting: Bool = false
    @State private var testResult: TestResult?
    @State private var showAdvanced: Bool = false
    @State private var formatOverride: RequestFormat?

    private enum TestResult {
        case success
        case successWithVisionWarning(String)
        case warning(String)
        case failure(String)
    }

    var body: some View {
        Form {
            featureToggleSection
            if foodSearchEnabled {
                usdaSection
                aiConfigSection
                advancedSettingsSection
            }
        }
        .navigationTitle("FoodFinder Settings")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Load API keys from Keychain
            apiKey = FoodFinder_SecureStorage.loadAPIKey() ?? ""
            usdaAPIKey = FoodFinder_SecureStorage.loadUSDAKey() ?? ""

            // Clear stale endpoint path if it matches a different format's default
            // (e.g. Google endpoint left over when user switched to OpenAI)
            if !endpointPath.isEmpty {
                let detectedFormat = RequestFormat.detect(from: baseURL)
                let isKnownDefault = RequestFormat.allCases.contains { $0.defaultEndpoint == endpointPath }
                if isKnownDefault && endpointPath != detectedFormat.defaultEndpoint {
                    endpointPath = ""
                }
            }

            // Ensure an AIProviderConfiguration exists if we have a base URL
            if !baseURL.isEmpty {
                saveConfiguration()
            }
        }
    }
}

// MARK: - Sections

extension AISettingsView {

    // MARK: Feature Toggle

    private var featureToggleSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "fork.knife.circle.fill")
                        .foregroundColor(.purple)
                    Text("FOODFINDER")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                        .lineLimit(1)
                        .layoutPriority(1)
                }
                Toggle("Enable FoodFinder", isOn: $foodSearchEnabled)
                Text("Enable this to show FoodFinder in the carb entry screen. Requires Internet connection. When disabled, the feature is hidden but settings are preserved.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                if foodSearchEnabled {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "cross.fill")
                                .foregroundColor(.red)
                            Text("MEDICAL DISCLAIMER")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                                .textCase(.uppercase)
                                .lineLimit(1)
                        }
                        Text("AI nutritional estimates are approximations only. Verify information before dosing; this is not medical advice.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Divider()
                    HStack {
                        Text("Analysis History")
                        Picker("", selection: $retentionDays) {
                            Text("Last 24 hours").tag(1)
                            Text("Last 7 days").tag(7)
                            Text("Last 14 days").tag(14)
                        }
                        .pickerStyle(.menu)
                    }
                    Text("How long to keep AI-analyzed foods available for quick re-entry.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Divider()
                    Toggle("Advanced Dosing Insights", isOn: $advancedDosingRecommendationsEnabled)
                    Text("Enable advanced dosing advice including Fat/Protein Units (FPUs) calculations. Prolongs analysis.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: AI Configuration

    private var aiConfigSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .foregroundColor(.purple)
                    Text("AI CONFIGURATION")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                }
                Text("Enter your preferred AI API connection details for any AI service that supports vision-capable chat completions.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                // API key signup links
                VStack(alignment: .leading, spacing: 6) {
                    Text("OR, get an API key from one of these popular providers:").font(.caption).foregroundColor(.secondary)
                    HStack(spacing: 12) {
                        apiKeyLink("OpenAI  ", url: "https://platform.openai.com/api-keys", color: .green)
                        apiKeyLink("Anthropic  ", url: "https://console.anthropic.com/settings/keys", color: .orange)
                        apiKeyLink("Gemini  ", url: "https://aistudio.google.com/apikey", color: .blue)
                        apiKeyLink("Grok  ", url: "https://console.x.ai", color: .red)
                    }
                }

                // Base URL
                VStack(alignment: .leading, spacing: 4) {
                    Text("Base URL").font(.caption).foregroundColor(.secondary)
                    HStack(spacing: 8) {
                        TextField("", text: $baseURL)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .overlay(alignment: .leading) {
                                if baseURL.isEmpty {
                                    Text("e.g. https://api.example.com/v1")
                                        .foregroundColor(.secondary)
                                        .padding(.leading, 4)
                                        .allowsHitTesting(false)
                                }
                            }
                            .foregroundColor(.primary)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                            .onChange(of: baseURL) { _ in
                                // Reset endpoint path and format override so auto-detection
                                // drives the correct defaults for the new URL.
                                endpointPath = ""
                                formatOverride = nil
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
                    Text("API Key").font(.caption).foregroundColor(.secondary)
                    HStack(spacing: 8) {
                        Group {
                            if showAPIKey {
                                TextField("Enter your API key", text: $apiKey)
                            } else {
                                SecureField("Enter your API key", text: $apiKey)
                            }
                        }
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                        .onChange(of: apiKey) { newValue in
                            saveAPIKey(newValue)
                            testResult = nil
                        }
                        Button(action: { showAPIKey.toggle() }) {
                            Image(systemName: showAPIKey ? "eye.slash" : "eye")
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(.plain)
                        if !apiKey.isEmpty {
                            Button(action: { apiKey = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if !apiKey.isEmpty {
                        Text("Stored securely in Keychain")
                            .font(.caption2)
                            .foregroundColor(.green)
                    }
                }

                // Model
                VStack(alignment: .leading, spacing: 4) {
                    Text("Model").font(.caption).foregroundColor(.secondary)
                    HStack(spacing: 8) {
                        TextField("e.g. gpt-4o, claude-sonnet-4-20250514, gemini-2.0-flash", text: $model)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
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
                    .disabled(isTesting || apiKey.isEmpty || baseURL.isEmpty)
                    .opacity((isTesting || apiKey.isEmpty || baseURL.isEmpty) ? 0.5 : 1.0)
                    .buttonStyle(.plain)

                    if let result = testResult {
                        switch result {
                        case .success:
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("Connected")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                        case .successWithVisionWarning(let message):
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                    Text("Connected")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                }
                                HStack(alignment: .top, spacing: 4) {
                                    Image(systemName: "eye.trianglebadge.exclamationmark")
                                        .foregroundColor(.orange)
                                    Text(message)
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
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

    // MARK: USDA Database

    private var usdaSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "leaf").foregroundColor(.green)
                    Text("USDA DATABASE (TEXT SEARCH)")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                }

                HStack(spacing: 8) {
                    Group {
                        if showUSDAKey {
                            TextField("Enter your USDA API key (optional)", text: $usdaAPIKey)
                        } else {
                            SecureField("Enter your USDA API key (optional)", text: $usdaAPIKey)
                        }
                    }
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
                    .onChange(of: usdaAPIKey) { newValue in
                        saveUSDAKey(newValue)
                    }
                    Button(action: { showUSDAKey.toggle() }) {
                        Image(systemName: showUSDAKey ? "eye.slash" : "eye").foregroundColor(.green)
                    }
                    .buttonStyle(.plain)
                }
                Button(action: { if let url = URL(string: "https://fdc.nal.usda.gov/api-guide") { openURL(url) } }) {
                    HStack { Image(systemName: "info.circle"); Text("How to get a key") }
                        .foregroundColor(.green)
                }
                .buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 2) {
                    Text("How to obtain a USDA API key:")
                        .font(.caption)
                        .fontWeight(.semibold)
                    Text("1. Open the USDA FoodData Central API Guide. 2. Sign in or create an account. 3. Request a new API key. 4. Copy and paste it here. The key activates immediately.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Why add a key?")
                        .font(.caption)
                        .fontWeight(.semibold)
                    Text("Without your own key, searches use a public DEMO_KEY that is heavily rate-limited and often returns 429 errors. Adding your free personal key avoids this.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: Advanced Settings

    private var advancedSettingsSection: some View {
        Section {
            DisclosureGroup("Advanced Settings", isExpanded: $showAdvanced) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("This section is for self-hosted, Azure, or non-standard API endpoints. Most users can ignore these.")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    // Endpoint path
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Endpoint Path").font(.caption).foregroundColor(.secondary)
                        TextField("e.g. /chat/completions", text: $endpointPath)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                            .onChange(of: endpointPath) { _ in saveConfiguration() }
                        Text("Leave blank to use the default for your chosen format.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    // API Version
                    VStack(alignment: .leading, spacing: 4) {
                        Text("API Version").font(.caption).foregroundColor(.secondary)
                        TextField("e.g. 2024-06-01 (Azure only)", text: $apiVersion)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                            .onChange(of: apiVersion) { _ in saveConfiguration() }
                    }

                    // Organization ID
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Organization ID").font(.caption).foregroundColor(.secondary)
                        TextField("e.g. org-... (OpenAI, Azure)", text: $organizationID)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                            .onChange(of: organizationID) { _ in saveConfiguration() }
                    }

                    // Request Format override
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Request Format Override").font(.caption).foregroundColor(.secondary)
                        Picker("Format", selection: Binding(
                            get: { formatOverride ?? .openAICompatible },
                            set: { formatOverride = $0; saveConfiguration() }
                        )) {
                            ForEach(RequestFormat.allCases, id: \.self) { format in
                                Text(format.displayName).tag(format)
                            }
                        }
                        .pickerStyle(.segmented)
                        HStack(spacing: 4) {
                            Text("Auto-detected:")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(resolvedFormat.displayName)
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                            if formatOverride != nil {
                                Button("Reset") { formatOverride = nil; saveConfiguration() }
                                    .font(.caption2)
                            }
                        }
                        Text("Most providers use Chat Completions. Only change this if auto-detection is wrong.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    if !endpointPreview.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Full endpoint URL:")
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

}

// MARK: - Helpers

extension AISettingsView {

    private func apiKeyLink(_ name: String, url: String, color: Color) -> some View {
        Button(action: { if let u = URL(string: url) { openURL(u) } }) {
            Text(name)
                .font(.caption)
                .foregroundColor(color)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Actions

extension AISettingsView {

    /// The effective request format: user override if set, otherwise auto-detected from base URL.
    private var resolvedFormat: RequestFormat {
        formatOverride ?? RequestFormat.detect(from: baseURL)
    }

    private func saveAPIKey(_ key: String) {
        if key.isEmpty {
            try? FoodFinder_SecureStorage.deleteAPIKey()
        } else {
            try? FoodFinder_SecureStorage.saveAPIKey(key)
        }
        saveConfiguration()
    }

    private func saveUSDAKey(_ key: String) {
        if key.isEmpty {
            try? FoodFinder_SecureStorage.deleteUSDAKey()
        } else {
            try? FoodFinder_SecureStorage.saveUSDAKey(key)
        }
    }

    /// Saves the current settings as an AIProviderConfiguration and sets it as active.
    private func saveConfiguration() {
        let config = AIProviderConfiguration(
            name: "AI Provider",
            baseURL: baseURL,
            model: model,
            endpointPath: endpointPath.isEmpty ? nil : endpointPath,
            requestFormat: resolvedFormat,
            apiVersion: apiVersion.isEmpty ? nil : apiVersion,
            organizationID: organizationID.isEmpty ? nil : organizationID
        )

        // Always maintain a single configuration — replace or create
        var configs = UserDefaults.standard.aiProviderConfigurations

        if let index = configs.firstIndex(where: { _ in true }) {
            // Replace the first (only) config, keeping its ID for stability
            let existingID = configs[index].id
            var updated = config
            updated.id = existingID
            configs[index] = updated
            UserDefaults.standard.aiProviderConfigurations = configs
            UserDefaults.standard.activeAIProviderConfigurationId = existingID
        } else {
            configs.append(config)
            UserDefaults.standard.aiProviderConfigurations = configs
            UserDefaults.standard.activeAIProviderConfigurationId = config.id
        }
    }

    private func testConnection() {
        guard !baseURL.isEmpty, !apiKey.isEmpty else { return }

        isTesting = true
        testResult = nil

        let config = AIProviderConfiguration(
            name: "AI Provider",
            baseURL: baseURL,
            model: model,
            endpointPath: endpointPath.isEmpty ? nil : endpointPath,
            requestFormat: resolvedFormat,
            apiVersion: apiVersion.isEmpty ? nil : apiVersion,
            organizationID: organizationID.isEmpty ? nil : organizationID,
            apiKey: apiKey
        )

        Task {
            let result = await AIServiceManager.shared.testConnection(to: config)
            await MainActor.run {
                isTesting = false
                if result.success {
                    // 402/429 are "connected with caveats" — show as warning
                    if let code = result.statusCode, (code == 402 || code == 429) {
                        testResult = .warning(result.message)
                    } else if result.supportsVision == false {
                        testResult = .successWithVisionWarning("Connected — but this model may not support image analysis. FoodFinder requires a vision-capable model.")
                    } else {
                        testResult = .success
                    }
                } else {
                    testResult = .failure(result.message)
                }
            }
        }
    }

    private var endpointPreview: String {
        let base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else { return "" }
        let trimmed = base.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let path = endpointPath.isEmpty ? resolvedFormat.defaultEndpoint : endpointPath
        let resolvedPath = path.replacingOccurrences(of: "{MODEL}", with: model.isEmpty ? "<model>" : model)
        return "\(trimmed)\(resolvedPath)"
    }
}

// MARK: - Preview

#if DEBUG
struct AISettingsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            AISettingsView()
        }
    }
}
#endif
