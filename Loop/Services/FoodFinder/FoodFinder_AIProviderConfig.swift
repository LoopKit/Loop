//
//  FoodFinder_AIProviderConfig.swift
//  Loop
//
//  FoodFinder — BYO API configuration model supporting OpenAI-compatible,
//  Anthropic, and Google AI providers.
//
//  Idea by Taylor Patterson. Coded by Claude Code.
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Foundation
import os.log

// MARK: - Request Format

/// Determines how the HTTP request body is built and how the response is parsed.
enum RequestFormat: String, Codable, CaseIterable, Equatable {
    /// OpenAI chat completion format. Works for OpenAI, Azure, Groq, Together, Ollama, etc.
    case openAICompatible

    /// Anthropic Messages API format.
    case anthropicMessages

    /// Google Generative AI (Gemini) format.
    case googleGenerativeAI

    var displayName: String {
        switch self {
        case .openAICompatible: return "OpenAI Compatible"
        case .anthropicMessages: return "Anthropic Messages"
        case .googleGenerativeAI: return "Google Generative AI"
        }
    }

    /// Default response JSON path for extracting text content.
    var defaultResponseKeyPath: String {
        switch self {
        case .openAICompatible: return "choices.0.message.content"
        case .anthropicMessages: return "content.0.text"
        case .googleGenerativeAI: return "candidates.0.content.parts.0.text"
        }
    }

    /// Default API key header name.
    var defaultAPIKeyHeader: String {
        switch self {
        case .openAICompatible: return "Authorization"
        case .anthropicMessages: return "x-api-key"
        case .googleGenerativeAI: return "x-goog-api-key"
        }
    }

    /// Default API key prefix (e.g., "Bearer " for OpenAI).
    var defaultAPIKeyPrefix: String {
        switch self {
        case .openAICompatible: return "Bearer "
        case .anthropicMessages: return ""
        case .googleGenerativeAI: return ""
        }
    }

    /// Default endpoint path.
    var defaultEndpoint: String {
        switch self {
        case .openAICompatible: return "/chat/completions"
        case .anthropicMessages: return "/messages"
        case .googleGenerativeAI: return "/models/{MODEL}:generateContent"
        }
    }

    /// Auto-detect request format from a base URL.
    /// Falls back to `.openAICompatible` for any unrecognized URL.
    static func detect(from baseURL: String) -> RequestFormat {
        let lower = baseURL.lowercased()
        if lower.contains("anthropic.com") {
            return .anthropicMessages
        } else if lower.contains("googleapis.com") || lower.contains("generativelanguage") {
            return .googleGenerativeAI
        }
        return .openAICompatible
    }
}

// MARK: - Authentication Type

/// Authentication types supported by AI providers.
enum AuthType: String, CaseIterable, Codable, Equatable {
    case bearer = "Bearer Token"
    case apiKey = "API Key Header"
    case custom = "Custom Header"

    var headerField: String {
        switch self {
        case .bearer: return "Authorization"
        case .apiKey: return "x-api-key"
        case .custom: return "Custom"
        }
    }
}

// MARK: - AI Provider Configuration

/// User-configurable API endpoint for AI food analysis.
///
/// The `apiKey` field is populated at runtime from the Keychain and is NOT
/// persisted to UserDefaults. Use `FoodFinder_SecureStorage` to read/write keys.
struct AIProviderConfiguration: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var baseURL: String
    var model: String
    var endpointPath: String
    var requestFormat: RequestFormat
    var responseKeyPath: String
    var supportsVision: Bool
    var headers: [String: String]

    // Auth
    var apiKeyHeader: String
    var apiKeyPrefix: String

    // Tuning
    var maxTokens: Int
    var temperature: Double

    // Optional
    var apiVersion: String?
    var organizationID: String?

    /// Transient — populated from Keychain at load time, NOT stored in UserDefaults.
    var apiKey: String

    init(
        id: String = UUID().uuidString,
        name: String,
        baseURL: String,
        model: String,
        endpointPath: String? = nil,
        requestFormat: RequestFormat = .openAICompatible,
        responseKeyPath: String? = nil,
        supportsVision: Bool = true,
        headers: [String: String] = ["Content-Type": "application/json"],
        apiKeyHeader: String? = nil,
        apiKeyPrefix: String? = nil,
        maxTokens: Int = 2500,
        temperature: Double = 0.3,
        apiVersion: String? = nil,
        organizationID: String? = nil,
        apiKey: String = ""
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.model = model
        self.endpointPath = endpointPath ?? requestFormat.defaultEndpoint
        self.requestFormat = requestFormat
        self.responseKeyPath = responseKeyPath ?? requestFormat.defaultResponseKeyPath
        self.supportsVision = supportsVision
        self.headers = headers
        self.apiKeyHeader = apiKeyHeader ?? requestFormat.defaultAPIKeyHeader
        self.apiKeyPrefix = apiKeyPrefix ?? requestFormat.defaultAPIKeyPrefix
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.apiVersion = apiVersion
        self.organizationID = organizationID
        self.apiKey = apiKey
    }

    /// Returns a copy with the API key loaded from Keychain.
    func withKeychainAPIKey() -> AIProviderConfiguration {
        var copy = self
        copy.apiKey = FoodFinder_SecureStorage.loadAPIKey() ?? ""
        return copy
    }

    // MARK: - Codable (exclude apiKey from persistence)

    enum CodingKeys: String, CodingKey {
        case id, name, baseURL, model, endpointPath, requestFormat, responseKeyPath
        case supportsVision, headers, apiKeyHeader, apiKeyPrefix
        case maxTokens, temperature, apiVersion, organizationID
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        baseURL = try c.decode(String.self, forKey: .baseURL)
        model = try c.decode(String.self, forKey: .model)
        endpointPath = try c.decode(String.self, forKey: .endpointPath)
        requestFormat = try c.decode(RequestFormat.self, forKey: .requestFormat)
        responseKeyPath = try c.decode(String.self, forKey: .responseKeyPath)
        supportsVision = try c.decode(Bool.self, forKey: .supportsVision)
        headers = try c.decode([String: String].self, forKey: .headers)
        apiKeyHeader = try c.decode(String.self, forKey: .apiKeyHeader)
        apiKeyPrefix = try c.decode(String.self, forKey: .apiKeyPrefix)
        maxTokens = try c.decode(Int.self, forKey: .maxTokens)
        temperature = try c.decode(Double.self, forKey: .temperature)
        apiVersion = try c.decodeIfPresent(String.self, forKey: .apiVersion)
        organizationID = try c.decodeIfPresent(String.self, forKey: .organizationID)
        apiKey = "" // Never decoded — loaded from Keychain at runtime
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(baseURL, forKey: .baseURL)
        try c.encode(model, forKey: .model)
        try c.encode(endpointPath, forKey: .endpointPath)
        try c.encode(requestFormat, forKey: .requestFormat)
        try c.encode(responseKeyPath, forKey: .responseKeyPath)
        try c.encode(supportsVision, forKey: .supportsVision)
        try c.encode(headers, forKey: .headers)
        try c.encode(apiKeyHeader, forKey: .apiKeyHeader)
        try c.encode(apiKeyPrefix, forKey: .apiKeyPrefix)
        try c.encode(maxTokens, forKey: .maxTokens)
        try c.encode(temperature, forKey: .temperature)
        try c.encodeIfPresent(apiVersion, forKey: .apiVersion)
        try c.encodeIfPresent(organizationID, forKey: .organizationID)
        // apiKey intentionally NOT encoded — stored in Keychain
    }
}

// MARK: - UserDefaults Extension

extension UserDefaults {
    private enum AIConfigKey: String {
        case aiProviderConfigurations = "com.loopkit.Loop.aiProviderConfigurations"
        case activeAIProviderConfigurationId = "com.loopkit.Loop.activeAIProviderConfigurationId"
    }

    /// All stored AI provider configurations.
    var aiProviderConfigurations: [AIProviderConfiguration] {
        get {
            guard let data = data(forKey: AIConfigKey.aiProviderConfigurations.rawValue) else {
                return []
            }
            return (try? JSONDecoder().decode([AIProviderConfiguration].self, from: data)) ?? []
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                set(data, forKey: AIConfigKey.aiProviderConfigurations.rawValue)
            }
        }
    }

    /// The ID of the currently active AI provider configuration.
    var activeAIProviderConfigurationId: String? {
        get { string(forKey: AIConfigKey.activeAIProviderConfigurationId.rawValue) }
        set { set(newValue, forKey: AIConfigKey.activeAIProviderConfigurationId.rawValue) }
    }

    /// The currently active AI provider configuration with API key loaded from Keychain.
    var activeAIProviderConfiguration: AIProviderConfiguration? {
        guard let activeId = activeAIProviderConfigurationId else { return nil }
        return aiProviderConfigurations.first { $0.id == activeId }?.withKeychainAPIKey()
    }
}

// MARK: - AI Settings Manager

/// Thin persistence manager for AI provider configurations.
class AISettingsManager {
    static let shared = AISettingsManager()
    private let log = OSLog(category: "AISettingsManager")

    private init() {}

    /// Loads the active AI provider configuration
    func loadActiveConfiguration() async throws -> AIProviderConfiguration? {
        return UserDefaults.standard.activeAIProviderConfiguration
    }

    /// Saves the active AI provider configuration
    func saveActiveConfiguration(_ configuration: AIProviderConfiguration) async throws {
        var configs = UserDefaults.standard.aiProviderConfigurations

        if let index = configs.firstIndex(where: { $0.id == configuration.id }) {
            configs[index] = configuration
        } else {
            configs.append(configuration)
        }

        UserDefaults.standard.aiProviderConfigurations = configs
        UserDefaults.standard.activeAIProviderConfigurationId = configuration.id

        log.debug("Saved active AI provider configuration: %{public}@", configuration.name)
    }

    /// Deletes an AI provider configuration
    func deleteConfiguration(id: String) async throws {
        var configs = UserDefaults.standard.aiProviderConfigurations
        configs.removeAll { $0.id == id }
        UserDefaults.standard.aiProviderConfigurations = configs

        if UserDefaults.standard.activeAIProviderConfigurationId == id {
            UserDefaults.standard.activeAIProviderConfigurationId = nil
        }

        log.debug("Deleted AI provider configuration with ID: %{public}@", id)
    }

    /// Tests a connection to the AI provider with the given configuration
    func testConnection(to configuration: AIProviderConfiguration) async -> AIServiceManager.TestConnectionResult {
        return await AIServiceManager.shared.testConnection(to: configuration)
    }
}
