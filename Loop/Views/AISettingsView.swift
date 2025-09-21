//
//  AISettingsView.swift
//  Loop
//
//  Created by Taylor Patterson, Coded by Claude Code for AI Settings Configuration in June 2025
//  Copyright © 2025 LoopKit Authors. All rights reserved.
//

import SwiftUI

/// Simple secure field that uses proper SwiftUI components
struct StableSecureField: View {
    let placeholder: String
    @Binding var text: String
    let isSecure: Bool
    
    var body: some View {
        let field: some View = Group {
            if isSecure {
                SecureField(placeholder, text: $text)
            } else {
                TextField(placeholder, text: $text)
            }
        }
        .textFieldStyle(RoundedBorderTextFieldStyle())
        .autocapitalization(.none)
        .autocorrectionDisabled()
        .overlay(alignment: .trailing) {
            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 8)
            }
        }
        // Return the composed field view
        field
    }
}

// Small reusable modifier to add a clear (x) button to standard TextField inputs
private struct ClearButton: ViewModifier {
    @Binding var text: String
    func body(content: Content) -> some View {
        content.overlay(alignment: .trailing) {
            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 8)
            }
        }
    }
}

/// Settings view for configuring AI food analysis
struct AISettingsView: View {
    @ObservedObject private var aiService = ConfigurableAIService.shared
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.openURL) var openURL
    @State private var claudeKey: String = ""
    @State private var claudeQuery: String = ""
    @State private var openAIKey: String = ""
    @State private var openAIQuery: String = ""
    @State private var googleGeminiKey: String = ""
    @State private var googleGeminiQuery: String = ""
    // USDA (database) API key – optional but recommended to avoid DEMO_KEY rate limits
    @State private var usdaAPIKey: String = ""
    // Bring Your Own (OpenAI-compatible)
    @State private var customAPIBaseURL: String = ""
    @State private var customAPIKey: String = ""
    @State private var customModel: String = ""
    @State private var customAPIVersion: String = ""
    @State private var customOrganizationID: String = ""
    @State private var customAPIEndpointPath: String = ""
    @State private var isTestingBYO: Bool = false
    @State private var byoTestMessage: String = ""
    @State private var showBYOTestAlert: Bool = false
    @State private var byoLastTestOK: Bool = false

    // Detect unsaved changes for BYO fields vs persisted values
    private var hasUnsavedBYOChanges: Bool {
        let base = customAPIBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = customAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = customModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let version = customAPIVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        let org = customOrganizationID.trimmingCharacters(in: .whitespacesAndNewlines)
        return base != UserDefaults.standard.customAIBaseURL ||
               key != UserDefaults.standard.customAIAPIKey ||
               model != UserDefaults.standard.customAIModel ||
               version != UserDefaults.standard.customAIAPIVersion ||
               org != UserDefaults.standard.customAIOrganization ||
               customAPIEndpointPath.trimmingCharacters(in: .whitespacesAndNewlines) != UserDefaults.standard.customAIEndpointPath
    }
    @State private var showingAPIKeyAlert = false
    
    // API Key visibility toggles - start with keys hidden (secure)
    @State private var showClaudeKey: Bool = false
    @State private var showOpenAIKey: Bool = false
    @State private var showGoogleGeminiKey: Bool = false
    @State private var showUSDAKey: Bool = false
    @State private var showCustomKey: Bool = false

    // Feature flag for Food Search
    @State private var foodSearchEnabled: Bool = UserDefaults.standard.foodSearchEnabled

    // Feature flag for Advanced Dosing Insights
    @State private var advancedDosingRecommendationsEnabled: Bool = UserDefaults.standard.advancedDosingRecommendationsEnabled

    // GPT-5 feature flag
    @State private var useGPT5ForOpenAI: Bool = UserDefaults.standard.useGPT5ForOpenAI
    @State private var isCheckingGPT5Availability: Bool = false
    @State private var showGPT5AvailabilityAlert: Bool = false
    @State private var gpt5AvailabilityMessage: String = ""

    // Selected provider tab: 0 OpenAI, 1 Claude, 2 Gemini, 3 BYO
    @State private var selectedTab: Int = 0

    init() {
        _claudeKey = State(initialValue: ConfigurableAIService.shared.getAPIKey(for: .claude) ?? "")
        _claudeQuery = State(initialValue: ConfigurableAIService.shared.getQuery(for: .claude) ?? "")
        _openAIKey = State(initialValue: ConfigurableAIService.shared.getAPIKey(for: .openAI) ?? "")
        _openAIQuery = State(initialValue: ConfigurableAIService.shared.getQuery(for: .openAI) ?? "")
        _googleGeminiKey = State(initialValue: ConfigurableAIService.shared.getAPIKey(for: .googleGemini) ?? "")
        _googleGeminiQuery = State(initialValue: ConfigurableAIService.shared.getQuery(for: .googleGemini) ?? "")
        // USDA key
        _usdaAPIKey = State(initialValue: UserDefaults.standard.usdaAPIKey)
        // BYO
        _customAPIBaseURL = State(initialValue: UserDefaults.standard.customAIBaseURL)
        _customAPIKey = State(initialValue: UserDefaults.standard.customAIAPIKey)
        _customModel = State(initialValue: UserDefaults.standard.customAIModel)
        _customAPIVersion = State(initialValue: UserDefaults.standard.customAIAPIVersion)
        _customOrganizationID = State(initialValue: UserDefaults.standard.customAIOrganization)
        _customAPIEndpointPath = State(initialValue: UserDefaults.standard.customAIEndpointPath)
        // Init selected tab from current provider
        let pImage = UserDefaults.standard.aiImageProvider.lowercased()
        if pImage.contains("bring") { _selectedTab = State(initialValue: 3) }
        else if pImage.contains("claude") { _selectedTab = State(initialValue: 1) }
        else if pImage.contains("gemini") || pImage.contains("google") { _selectedTab = State(initialValue: 2) }
        else { _selectedTab = State(initialValue: 0) }
    }
    
    var body: some View {
        NavigationView {
            Form {
                featureToggleSection
                if foodSearchEnabled {
                    providerMappingSection
                    usdaKeySection
                    providerSelectionSection
                    analysisModeSection
                    advancedOptionsSection
                }
            }
            .navigationTitle("FoodFinder Settings")
            .navigationBarTitleDisplayMode(.inline)
        .navigationBarItems(
            leading: Button("Cancel") {
                    // Restore original values (discard changes)
                    claudeKey = ConfigurableAIService.shared.getAPIKey(for: .claude) ?? ""
                    claudeQuery = ConfigurableAIService.shared.getQuery(for: .claude) ?? ""
                    openAIKey = ConfigurableAIService.shared.getAPIKey(for: .openAI) ?? ""
                    openAIQuery = ConfigurableAIService.shared.getQuery(for: .openAI) ?? ""
                    googleGeminiKey = ConfigurableAIService.shared.getAPIKey(for: .googleGemini) ?? ""
                    googleGeminiQuery = ConfigurableAIService.shared.getQuery(for: .googleGemini) ?? ""
                    usdaAPIKey = UserDefaults.standard.usdaAPIKey
                    foodSearchEnabled = UserDefaults.standard.foodSearchEnabled  // Restore original feature flag state
                    advancedDosingRecommendationsEnabled = UserDefaults.standard.advancedDosingRecommendationsEnabled  // Restore original advanced dosing flag state
                    
                    presentationMode.wrappedValue.dismiss()
                }
                .foregroundColor(.secondary),
                trailing: Button("Save") {
                    saveSettings()
                }
                .font(.headline)
                .foregroundColor(.accentColor)
            )
            .alert(isPresented: $showingAPIKeyAlert) {
                Alert(
                    title: Text("API Key Required"),
                    message: Text("This AI provider requires an API key. Please enter your API key in the settings below."),
                    dismissButton: .default(Text("OK"))
                )
            }
            .alert(isPresented: $showBYOTestAlert) {
                Alert(
                    title: Text("BYO Connection Test"),
                    message: Text(byoTestMessage),
                    dismissButton: .default(Text("OK"))
                )
            }
            .alert("GPT-5 Not Available", isPresented: $showGPT5AvailabilityAlert, actions: {
                Button("OK", role: .cancel) {
                    gpt5AvailabilityMessage = ""
                }
            }, message: {
                Text(gpt5AvailabilityMessage)
            })
        }
    }
}

// Helper views and methods
extension AISettingsView {
    private var endpointPathError: String? {
        let p = customAPIEndpointPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if p.isEmpty { return nil }
        if p.contains("://") { return "Enter only the path, not a full URL (e.g., /v1/chat/completions)." }
        if p.contains(" ") { return "Path cannot contain spaces." }
        return nil
    }

    private func normalizedPath(_ path: String) -> String {
        let p = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if p.isEmpty { return "/v1/chat/completions" }
        return p.hasPrefix("/") ? p : "/" + p
    }

    private var endpointPreview: String {
        let base = customAPIBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else { return "" }
        let trimmedBase = base.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let isAzure = base.lowercased().contains(".openai.azure.com") || !customAPIVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if isAzure {
            let dep = customModel.trimmingCharacters(in: .whitespacesAndNewlines)
            let ver = customAPIVersion.trimmingCharacters(in: .whitespacesAndNewlines)
            let depDisp = dep.isEmpty ? "<deployment>" : dep
            let verDisp = ver.isEmpty ? "<api-version>" : ver
            return "\(trimmedBase)/openai/deployments/\(depDisp)/chat/completions?api-version=\(verDisp)"
        } else {
            let path = normalizedPath(customAPIEndpointPath)
            return "\(trimmedBase)\(path)"
        }
    }

    // MARK: Section builders (to help type-checker)
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
                }
            }
        }
    }

    private var providerMappingSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundColor(.blue)
                    Text("FOODFINDER PROVIDER")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                        .lineLimit(1)
                        .layoutPriority(1)
                }
                Text("Configure the service used for each type of search. AI Image Analysis controls what happens when you take photos of food.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                ForEach(SearchType.allCases, id: \.self) { searchType in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(searchType.rawValue).font(.headline)
                            Spacer()
                        }
                        Text(searchType.description).font(.caption).foregroundColor(.secondary)
                        Picker(selection: getBindingForSearchType(searchType)) {
                            ForEach(aiService.getAvailableProvidersForSearchType(searchType), id: \.self) { provider in
                                Text(provider.rawValue).tag(provider)
                            }
                        } label: { EmptyView() }
                        .pickerStyle(MenuPickerStyle())
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var providerSelectionSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles").foregroundColor(.purple)
                    Text("API KEY CONFIGURATION")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                }

                Picker("Provider", selection: $selectedTab) {
                    Text("OpenAI Chat GPT").tag(0)
                    Text("Anthropic Claude").tag(1)
                    Text("Google Gemini").tag(2)
                    Text("BYO").tag(3)
                }
                .pickerStyle(.segmented)
                .onChange(of: selectedTab) { newVal in
                    switch newVal {
                    case 0:
                        UserDefaults.standard.aiImageProvider = "OpenAI (ChatGPT API)"
                    case 1:
                        UserDefaults.standard.aiImageProvider = "Anthropic (Claude API)"
                    case 2:
                        UserDefaults.standard.aiImageProvider = "Google (Gemini API)"
                    case 3:
                        UserDefaults.standard.aiImageProvider = "Bring your own (Custom)"
                    default:
                        break
                    }
                }
                Text("Choose which AI service you want to use for food analysis")
                    .font(.footnote)
                    .foregroundColor(.secondary)

                Group {
                    if selectedTab == 0 { openAIKeyRow }
                    else if selectedTab == 1 { claudeKeyRow }
                    else if selectedTab == 2 { geminiKeyRow }
                    else { bringYourOwnRow }
                }
            }
        }
    }

    // USDA database key section (optional but recommended)
    private var usdaKeySection: some View {
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
                    StableSecureField(placeholder: "Enter your USDA API key (optional)", text: $usdaAPIKey, isSecure: !showUSDAKey)
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

    private var openAIKeyRow: some View {
        Group {
            HStack(spacing: 8) {
                Image(systemName: "brain.head.profile").foregroundColor(.blue)
                Text("ChatGPT Configuration").font(.headline).foregroundColor(.blue)
            }
            HStack {
                StableSecureField(placeholder: "Enter your OpenAI API key", text: $openAIKey, isSecure: !showOpenAIKey)
                Button(action: { showOpenAIKey.toggle() }) {
                    Image(systemName: showOpenAIKey ? "eye.slash" : "eye").foregroundColor(.blue)
                }
                .buttonStyle(.plain)
            }
            Button(action: { if let url = URL(string: "https://platform.openai.com/api-keys") { openURL(url) } }) {
                HStack { Image(systemName: "info.circle"); Text("How to get API keys") }
                    .foregroundColor(.blue)
            }
            .buttonStyle(.plain)
            // GPT-5 option (OpenAI only)
            Toggle("Use GPT-5 Models", isOn: $useGPT5ForOpenAI)
                .disabled(!foodSearchEnabled || isCheckingGPT5Availability)
                .onChange(of: useGPT5ForOpenAI) { newValue in
                    aiService.objectWillChange.send()
                    guard newValue else { return }
                    isCheckingGPT5Availability = true
                    Task {
                        let trimmedKey = openAIKey.trimmingCharacters(in: .whitespacesAndNewlines)
                        let keyToCheck = trimmedKey.isEmpty ? (ConfigurableAIService.shared.getAPIKey(for: .openAI) ?? "") : trimmedKey
                        guard !keyToCheck.isEmpty else {
                            await MainActor.run {
                                useGPT5ForOpenAI = false
                                aiService.objectWillChange.send()
                                UserDefaults.standard.useGPT5ForOpenAI = false
                                isCheckingGPT5Availability = false
                                gpt5AvailabilityMessage = "Enter your OpenAI API key before enabling GPT-5 models."
                                showGPT5AvailabilityAlert = true
                            }
                            return
                        }
                        do {
                            try await OpenAIFoodAnalysisService.shared.ensureGPT5Availability(apiKey: keyToCheck, organizationID: nil)
                        } catch {
                            await MainActor.run {
                                useGPT5ForOpenAI = false
                                aiService.objectWillChange.send()
                                UserDefaults.standard.useGPT5ForOpenAI = false
                                gpt5AvailabilityMessage = error.localizedDescription
                                showGPT5AvailabilityAlert = true
                            }
                        }
                        await MainActor.run {
                            isCheckingGPT5Availability = false
                        }
                    }
                }
            if isCheckingGPT5Availability {
                HStack(spacing: 8) {
                    ProgressView()
                        .progressViewStyle(.circular)
                    Text("Verifying GPT-5 access…")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            Text("OpenAI: highly accurate vision models (GPT-4o/GPT-5). ~$0.01/image. GPT-5 are large models - they will be slower.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var claudeKeyRow: some View {
        Group {
            HStack(spacing: 8) {
                Image(systemName: "bolt.heart").foregroundColor(.orange)
                Text("Claude Configuration").font(.headline).foregroundColor(.orange)
            }
            HStack {
                StableSecureField(placeholder: "Enter your Claude API key", text: $claudeKey, isSecure: !showClaudeKey)
                Button(action: { showClaudeKey.toggle() }) {
                    Image(systemName: showClaudeKey ? "eye.slash" : "eye").foregroundColor(.orange)
                }
                .buttonStyle(.plain)
            }
            Button(action: { if let url = URL(string: "https://console.anthropic.com/settings/keys") { openURL(url) } }) {
                HStack { Image(systemName: "info.circle"); Text("How to get API keys") }
                    .foregroundColor(.orange)
            }
            .buttonStyle(.plain)
            Text("Anthropic Claude: excellent reasoning for detailed analysis.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var geminiKeyRow: some View {
        Group {
            HStack(spacing: 8) {
                Image(systemName: "sparkles").foregroundColor(.green)
                Text("Gemini Configuration").font(.headline).foregroundColor(.green)
            }
            HStack {
                StableSecureField(placeholder: "Enter your Google Gemini API key", text: $googleGeminiKey, isSecure: !showGoogleGeminiKey)
                Button(action: { showGoogleGeminiKey.toggle() }) {
                    Image(systemName: showGoogleGeminiKey ? "eye.slash" : "eye").foregroundColor(.green)
                }
                .buttonStyle(.plain)
            }
            Button(action: { if let url = URL(string: "https://aistudio.google.com/app/apikey") { openURL(url) } }) {
                HStack { Image(systemName: "info.circle"); Text("How to get API keys") }
                    .foregroundColor(.green)
            }
            .buttonStyle(.plain)
            Text("Google Gemini: great recognition with generous free limits.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var bringYourOwnRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles").foregroundColor(.purple)
                Text("Bring your own (OpenAI-compatible)").font(.headline).foregroundColor(.purple)
                if byoLastTestOK && !hasUnsavedBYOChanges {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                } else if hasUnsavedBYOChanges {
                    Text("Unsaved")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.yellow.opacity(0.2))
                        .foregroundColor(.orange)
                        .cornerRadius(6)
                }
            }
            TextField("Base URL (e.g., https://api.openai.com)", text: $customAPIBaseURL)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .autocapitalization(.none)
                .autocorrectionDisabled()
                .onChange(of: customAPIBaseURL) { _ in byoLastTestOK = false }
                .modifier(ClearButton(text: $customAPIBaseURL))
            HStack {
                StableSecureField(placeholder: "Enter your API key", text: $customAPIKey, isSecure: !showCustomKey)
                Button(action: { showCustomKey.toggle() }) {
                    Image(systemName: showCustomKey ? "eye.slash" : "eye").foregroundColor(.purple)
                }
                .buttonStyle(.plain)
            }
            .onChange(of: customAPIKey) { _ in byoLastTestOK = false }
            TextField(customAPIBaseURL.lowercased().contains(".openai.azure.com") ? "Deployment name (Azure), e.g., gpt-5-test" : "Model (OpenAI), e.g., gpt-4o", text: $customModel)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .autocapitalization(.none)
                .autocorrectionDisabled()
                .onChange(of: customModel) { _ in byoLastTestOK = false }
                .modifier(ClearButton(text: $customModel))
            TextField("API version (Azure only, e.g., 2024-06-01)", text: $customAPIVersion)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .autocapitalization(.none)
                .autocorrectionDisabled()
                .onChange(of: customAPIVersion) { _ in byoLastTestOK = false }
                .modifier(ClearButton(text: $customAPIVersion))
            TextField("Custom endpoint path (non-Azure), e.g., /v1/chat/completions or /openai/v1/chat/completions", text: $customAPIEndpointPath)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .autocapitalization(.none)
                .autocorrectionDisabled()
                .onChange(of: customAPIEndpointPath) { _ in byoLastTestOK = false }
                .modifier(ClearButton(text: $customAPIEndpointPath))
            if let pathError = endpointPathError {
                Text(pathError)
                    .font(.caption2)
                    .foregroundColor(.red)
            } else {
                Text("Leave blank for most providers. Only needed for non-Azure providers whose Chat Completions path differs from the OpenAI default. For example: Together.ai uses '/v1/chat/completions', Groq uses '/openai/v1/chat/completions'. Azure ignores this field because it uses the deployment-based path.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            if !endpointPreview.isEmpty {
                Text("This will call: \(endpointPreview)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            TextField("Organization ID (optional)", text: $customOrganizationID)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .autocapitalization(.none)
                .autocorrectionDisabled()
                .onChange(of: customOrganizationID) { _ in byoLastTestOK = false }
                .modifier(ClearButton(text: $customOrganizationID))
            HStack {
                Button(action: testBYOConnection) {
                    if isTestingBYO {
                        HStack { ProgressView(); Text("Testing…") }
                    } else {
                        HStack { Image(systemName: "checkmark.shield"); Text("Test connection") }
                    }
                }
                .disabled(isTestingBYO)
                .buttonStyle(.bordered)
                .tint(.purple)
                Spacer()
            }
            Text("BYO is for AI Image Analysis only (OpenAI-compatible endpoints, including Azure). Test connection only checks connectivity/auth — it does not validate model compatibility. GPT-5 support may be limited across many API providers at this time. BYO is experimental and unsupported; your mileage may vary.")
                .font(.caption)
                .foregroundColor(.secondary)
            if hasUnsavedBYOChanges {
                Text("Unsaved changes aren’t persisted. Tap Save (top-right) to keep them. Testing does not save.")
                    .font(.caption2)
                    .foregroundColor(.orange)
            }
        }
    }

    private func testBYOConnection() {
        let base = customAPIBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = customAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty, !key.isEmpty else {
            byoTestMessage = "Please enter Base URL and API key first."
            showBYOTestAlert = true
            return
        }
        isTestingBYO = true
        byoLastTestOK = false
        let model = customModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let version = customAPIVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        let org = customOrganizationID.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            do {
                let status = try await OpenAIFoodAnalysisService.shared.testConnection(
                    baseURL: base,
                    apiKey: key,
                    model: model.isEmpty ? nil : model,
                    apiVersion: version.isEmpty ? nil : version,
                    organizationID: org.isEmpty ? nil : org,
                    customPath: customAPIEndpointPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : customAPIEndpointPath.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                byoTestMessage = status
                byoLastTestOK = true
            } catch {
                byoTestMessage = "Test failed: \(error.localizedDescription)"
                byoLastTestOK = false
            }
            isTestingBYO = false
            showBYOTestAlert = true
        }
    }

    // (inline provider configuration is embedded directly in body)
    @ViewBuilder
    private var analysisModeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "burst").foregroundColor(.yellow)
                Text("ANALYSIS MODE")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
            }

            // Mode picker
            Picker("Analysis Mode", selection: Binding(
                get: { aiService.analysisMode },
                set: { newMode in aiService.setAnalysisMode(newMode) }
            )) {
                ForEach(ConfigurableAIService.AnalysisMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            
            currentModeDetails
            modelInformation
        }
    }

   
    @ViewBuilder
    private var currentModeDetails: some View {

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: aiService.analysisMode.iconName)
                    .foregroundColor(aiService.analysisMode.iconColor)
                Text("Current Mode: \(aiService.analysisMode.displayName)")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            
            Text(aiService.analysisMode.detailedDescription)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(aiService.analysisMode.backgroundColor)
        .cornerRadius(8)
    }

    @ViewBuilder
    private var modelInformation: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Models Used:")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 4) {
                modelRow(provider: "Google Gemini:", model: ConfigurableAIService.optimalModel(for: .googleGemini, mode: aiService.analysisMode))
                modelRow(provider: "OpenAI:", model: ConfigurableAIService.optimalModel(for: .openAI, mode: aiService.analysisMode))
                modelRow(provider: "Claude:", model: ConfigurableAIService.optimalModel(for: .claude, mode: aiService.analysisMode))
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }

    @ViewBuilder
    private func modelRow(provider: String, model: String) -> some View {
        HStack {
            Text(provider)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(model)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(.primary)
        }
    }

    private var advancedOptionsSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "syringe")
                        .foregroundColor(.orange)
                    Text("ADVANCED OPTIONS")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                        .lineLimit(1)
                        .layoutPriority(1)
                }
                Toggle("Advanced Dosing Insights", isOn: $advancedDosingRecommendationsEnabled)
                    .disabled(!foodSearchEnabled)
                Text("Enable advanced dosing advice including Fat/Protein Units (FPUs) calculations.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func saveSettings() {
        // Save all current settings to UserDefaults
        // Feature flag settings
        UserDefaults.standard.foodSearchEnabled = foodSearchEnabled
        UserDefaults.standard.advancedDosingRecommendationsEnabled = advancedDosingRecommendationsEnabled
        UserDefaults.standard.useGPT5ForOpenAI = useGPT5ForOpenAI
        
        // API key and query settings
        aiService.setAPIKey(claudeKey.trimmingCharacters(in: .whitespacesAndNewlines), for: .claude)
        aiService.setAPIKey(openAIKey.trimmingCharacters(in: .whitespacesAndNewlines), for: .openAI)
        aiService.setAPIKey(googleGeminiKey.trimmingCharacters(in: .whitespacesAndNewlines), for: .googleGemini)
        aiService.setQuery(claudeQuery, for: .claude)
        aiService.setQuery(openAIQuery, for: .openAI)
        aiService.setQuery(googleGeminiQuery, for: .googleGemini)
        // USDA key
        UserDefaults.standard.usdaAPIKey = usdaAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)

        // BYO settings
        UserDefaults.standard.customAIBaseURL = customAPIBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.customAIAPIKey = customAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.customAIModel = customModel.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.customAIAPIVersion = customAPIVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.customAIOrganization = customOrganizationID.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.customAIEndpointPath = customAPIEndpointPath.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Search type provider settings are automatically saved via the Binding
        // No additional action needed as they update UserDefaults directly
        
        // Dismiss the settings view
        presentationMode.wrappedValue.dismiss()
    }

private func getBindingForSearchType(_ searchType: SearchType) -> Binding<SearchProvider> {
    switch searchType {
    case .textSearch:
        return Binding(
            get: { aiService.textSearchProvider },
            set: { newValue in
                aiService.textSearchProvider = newValue
                UserDefaults.standard.textSearchProvider = newValue.rawValue
            }
        )
    case .barcodeSearch:
        return Binding(
            get: { aiService.barcodeSearchProvider },
            set: { newValue in
                aiService.barcodeSearchProvider = newValue
                UserDefaults.standard.barcodeSearchProvider = newValue.rawValue
            }
        )
    case .aiImageSearch:
        return Binding(
            get: { aiService.aiImageSearchProvider },
            set: { newValue in
                aiService.aiImageSearchProvider = newValue
                UserDefaults.standard.aiImageProvider = newValue.rawValue
            }
        )
    }
}

}

// MARK: - Preview

#if DEBUG
struct AISettingsView_Previews: PreviewProvider {
    static var previews: some View {
        AISettingsView()
    }
}
#endif
