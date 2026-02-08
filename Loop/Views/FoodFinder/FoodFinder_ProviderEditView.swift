//
//
//  Created by Taylor Patterson, Coded by Claude for AI Settings Configuration
//  Copyright © 2025 LoopKit Authors. All rights reserved.
//

import SwiftUI

struct AIProviderEditView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var configuration: AIProviderConfiguration
    private let onSave: (AIProviderConfiguration) -> Void

    @State private var isTesting = false
    @State private var testResult: TestResult?
    @State private var showingTestAlert = false

    enum TestResult: Equatable {
        case success(String)
        case failure(String)

        var message: String {
            switch self {
            case .success(let text): return text
            case .failure(let text): return text
            }
        }

        var isSuccess: Bool {
            if case .success = self { return true }
            return false
        }
    }

    init(configuration: AIProviderConfiguration? = nil, onSave: @escaping (AIProviderConfiguration) -> Void) {
        _configuration = State(initialValue: configuration ?? AIProviderConfiguration(
            name: "",
            baseURL: "https://",
            model: "",
            apiKey: "",
            endpointPath: "/v1/chat/completions",
            authType: .bearer,
            requestTemplate: AIProviderConfiguration.openAITemplate,
            responseKeyPath: "choices.0.message.content",
            supportsVision: true
        ))
        self.onSave = onSave
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Provider Details")) {
                    TextField("Name", text: $configuration.name)

                    Picker("Authentication Type", selection: $configuration.authType) {
                        ForEach(AuthType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }

                    TextField("Base URL", text: $configuration.baseURL)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)

                    TextField("Endpoint Path", text: $configuration.endpointPath)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }

                Section(header: Text("Model")) {
                    TextField("Model Name", text: $configuration.model)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)

                    Toggle("Supports Vision", isOn: $configuration.supportsVision)
                }

                Section(header: Text("Authentication")) {
                    SecureField("API Key", text: $configuration.apiKey)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)

                    if configuration.authType == .bearer {
                        Text("API Key will be sent as: Bearer YOUR_API_KEY")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("API Key will be sent in header: \(configuration.authType.headerField)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if !configuration.apiKey.isEmpty {
                        Button(action: testConnection) {
                            HStack {
                                if isTesting {
                                    ProgressView()
                                } else {
                                    Image(systemName: "bolt.fill")
                                }
                                Text("Test Connection")
                            }
                        }
                        .disabled(isTesting)
                        .alert("Test Connection", isPresented: $showingTestAlert) {
                            Button("OK") {}
                        } message: {
                            if let result = testResult {
                                Text(result.message)
                                    .foregroundColor(result.isSuccess ? .green : .red)
                            }
                        }
                    }
                }

                Section(header: Text("Advanced")) {
                    TextField("API Version (optional)", text: Binding(
                        get: { configuration.apiVersion ?? "" },
                        set: { configuration.apiVersion = $0.isEmpty ? nil : $0 }
                    ))
                    .autocapitalization(.none)
                    .disableAutocorrection(true)

                    TextField("Organization ID (optional)", text: Binding(
                        get: { configuration.organizationID ?? "" },
                        set: { configuration.organizationID = $0.isEmpty ? nil : $0 }
                    ))
                    .autocapitalization(.none)
                    .disableAutocorrection(true)

                    NavigationLink("Request Template") {
                        RequestTemplateEditor(template: $configuration.requestTemplate)
                    }

                    TextField("Response Key Path", text: $configuration.responseKeyPath)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }
            }
            .navigationTitle(configuration.id.isEmpty ? "Add Provider" : "Edit Provider")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(configuration)
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
        }
    }

    private var isValid: Bool {
        !configuration.name.isEmpty &&
        !configuration.baseURL.isEmpty &&
        !configuration.model.isEmpty &&
        !configuration.apiKey.isEmpty &&
        !configuration.endpointPath.isEmpty &&
        !configuration.requestTemplate.isEmpty &&
        !configuration.responseKeyPath.isEmpty
    }

    private func testConnection() {
        isTesting = true
        testResult = nil

        Task {
            do {
                let success = try await AIServiceManager.shared.testConnection(to: configuration)
                if success {
                    testResult = .success("✅ Connection successful!")
                } else {
                    testResult = .failure("❌ Connection failed: Invalid response")
                }
            } catch {
                testResult = .failure("❌ Connection failed: \(error.localizedDescription)")
            }

            isTesting = false
            showingTestAlert = true
        }
    }
}

// MARK: - Request Template Editor

struct RequestTemplateEditor: View {
    @Binding var template: String
    @State private var showingPlaceholderMenu = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Available placeholders:")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Menu {
                    Button(action: { insertPlaceholder("{{MODEL}}") }) {
                        Label("Model", systemImage: "cpu")
                    }
                    Button(action: { insertPlaceholder("{{PROMPT}}") }) {
                        Label("Prompt", systemImage: "text.quote")
                    }
                    Button(action: { insertPlaceholder("{{IMAGE_BASE64}}") }) {
                        Label("Image (Base64)", systemImage: "photo")
                    }
                } label: {
                    Text("Insert Placeholder")
                        .font(.caption)
                        .padding(6)
                        .background(Color(.systemGray6))
                        .cornerRadius(6)
                }

                Spacer()
            }
            .padding()

            TextEditor(text: $template)
                .font(.system(.body, design: .monospaced))
                .disableAutocorrection(true)
                .autocapitalization(.none)
                .padding()
        }
        .navigationTitle("Request Template")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func insertPlaceholder(_ placeholder: String) {
        template += placeholder
    }
}

// MARK: - Preview

struct AIProviderEditView_Previews: PreviewProvider {
    static var previews: some View {
        AIProviderEditView { _ in }
    }
}
