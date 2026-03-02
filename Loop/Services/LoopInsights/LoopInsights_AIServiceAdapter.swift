//
//  LoopInsights_AIServiceAdapter.swift
//  Loop
//
//  Concept & design by Taylor Patterson. Coded & tested by Claude Code in February 2026.
//  Copyright (c) 2025-2026 LoopKit Authors. All rights reserved.
//

import Foundation

/// Provider-agnostic HTTP client for LoopInsights AI analysis.
///
/// Supports any OpenAI-compatible endpoint (OpenAI, Azure, Groq, Together, Ollama, etc.),
/// Anthropic Messages API, and Google Generative AI (Gemini). The request format, auth headers,
/// and endpoint path are all derived from the user's `LoopInsightsAIProviderConfiguration`.
final class LoopInsights_AIServiceAdapter {

    static let shared = LoopInsights_AIServiceAdapter()

    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 120
        self.session = URLSession(configuration: config)
    }

    // MARK: - Public API

    /// Send a prompt to the configured AI provider and return the text response.
    func sendPrompt(_ systemPrompt: String, userPrompt: String) async throws -> String {
        var config = LoopInsights_FeatureFlags.aiConfiguration.withKeychainAPIKey()

        // Cap completion tokens — analysis JSON responses are typically <1500 tokens.
        // Prevents context_length_exceeded on smaller models (e.g. 8K context).
        config.maxTokens = min(config.maxTokens, 2048)

        guard !config.apiKey.isEmpty else {
            throw LoopInsightsError.noAPIKeyConfigured
        }

        let request = try buildRequest(config: config, systemPrompt: systemPrompt, userPrompt: userPrompt)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LoopInsightsError.networkError(URLError(.badServerResponse))
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw LoopInsightsError.aiProviderError("HTTP \(httpResponse.statusCode): \(errorBody)")
        }

        return try extractTextFromResponse(data: data, config: config)
    }

    /// Test connectivity with the configured provider. Returns true if reachable.
    func testConnection() async throws -> Bool {
        let config = LoopInsights_FeatureFlags.aiConfiguration.withKeychainAPIKey()

        guard !config.apiKey.isEmpty else {
            throw LoopInsightsError.noAPIKeyConfigured
        }

        // Use minimal tokens to minimize cost.
        // Thinking models (Gemini 2.5 Pro) need headroom for internal reasoning tokens.
        var testConfig = config
        testConfig.maxTokens = 128

        let request = try buildRequest(config: testConfig, systemPrompt: "You are a test.", userPrompt: "Reply with exactly: OK")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LoopInsightsError.networkError(URLError(.badServerResponse))
        }

        switch httpResponse.statusCode {
        case 200...299:
            return true
        case 401:
            throw LoopInsightsError.aiProviderError("Invalid API key (HTTP 401)")
        case 402, 429:
            // Key is valid, but billing or rate-limited
            return true
        case 403:
            throw LoopInsightsError.aiProviderError("Access denied — check API key permissions (HTTP 403)")
        case 404:
            throw LoopInsightsError.aiProviderError("Endpoint not found — check Base URL (HTTP 404)")
        default:
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw LoopInsightsError.aiProviderError("HTTP \(httpResponse.statusCode): \(errorBody)")
        }
    }

    // MARK: - Request Building

    private func buildRequest(
        config: LoopInsightsAIProviderConfiguration,
        systemPrompt: String,
        userPrompt: String
    ) throws -> URLRequest {
        let url = try buildURL(config: config)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Auth header
        let keyValue = config.apiKeyPrefix + config.apiKey
        request.setValue(keyValue, forHTTPHeaderField: config.apiKeyHeader)

        // Organization ID (OpenAI / Azure)
        if let orgID = config.organizationID, !orgID.isEmpty {
            request.setValue(orgID, forHTTPHeaderField: "OpenAI-Organization")
        }

        // Format-specific extra headers
        if config.requestFormat == .anthropicMessages {
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        }

        // Build body based on request format
        let body: Data
        switch config.requestFormat {
        case .openAICompatible:
            body = try buildOpenAIBody(config: config, systemPrompt: systemPrompt, userPrompt: userPrompt)
        case .anthropicMessages:
            body = try buildAnthropicBody(config: config, systemPrompt: systemPrompt, userPrompt: userPrompt)
        case .googleGenerativeAI:
            body = try buildGoogleBody(config: config, systemPrompt: systemPrompt, userPrompt: userPrompt)
        }

        request.httpBody = body
        return request
    }

    private func buildURL(config: LoopInsightsAIProviderConfiguration) throws -> URL {
        let base = config.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        var endpoint = config.endpointPath

        // Substitute {MODEL} in endpoint (used by Google Gemini)
        endpoint = endpoint.replacingOccurrences(of: "{MODEL}", with: config.model)

        // Ensure endpoint starts with /
        if !endpoint.hasPrefix("/") {
            endpoint = "/" + endpoint
        }

        // Azure: append api-version if present
        var urlString = base + endpoint
        if let apiVersion = config.apiVersion, !apiVersion.isEmpty, !urlString.contains("api-version") {
            let separator = urlString.contains("?") ? "&" : "?"
            urlString += "\(separator)api-version=\(apiVersion)"
        }

        // Google Gemini: append API key as query param
        if config.requestFormat == .googleGenerativeAI {
            let separator = urlString.contains("?") ? "&" : "?"
            urlString += "\(separator)key=\(config.apiKey)"
        }

        guard let url = URL(string: urlString) else {
            throw LoopInsightsError.aiProviderError("Invalid URL: \(urlString)")
        }
        return url
    }

    // MARK: - Format-Specific Body Builders

    private func buildOpenAIBody(
        config: LoopInsightsAIProviderConfiguration,
        systemPrompt: String,
        userPrompt: String
    ) throws -> Data {
        let body: [String: Any] = [
            "model": config.model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt]
            ],
            "temperature": config.temperature,
            "max_tokens": config.maxTokens
        ]
        return try JSONSerialization.data(withJSONObject: body)
    }

    private func buildAnthropicBody(
        config: LoopInsightsAIProviderConfiguration,
        systemPrompt: String,
        userPrompt: String
    ) throws -> Data {
        let body: [String: Any] = [
            "model": config.model,
            "system": systemPrompt,
            "messages": [
                ["role": "user", "content": userPrompt]
            ],
            "temperature": config.temperature,
            "max_tokens": config.maxTokens
        ]
        return try JSONSerialization.data(withJSONObject: body)
    }

    private func buildGoogleBody(
        config: LoopInsightsAIProviderConfiguration,
        systemPrompt: String,
        userPrompt: String
    ) throws -> Data {
        // Thinking models (Gemini 2.5 Pro) use internal reasoning tokens that count
        // against maxOutputTokens. Set a separate thinking budget so actual response
        // tokens aren't starved. Non-thinking models ignore this field.
        var generationConfig: [String: Any] = [
            "temperature": config.temperature,
            "maxOutputTokens": config.maxTokens,
            "thinkingConfig": [
                "thinkingBudget": 1024
            ]
        ]

        let body: [String: Any] = [
            "system_instruction": [
                "parts": [["text": systemPrompt]]
            ],
            "contents": [
                [
                    "role": "user",
                    "parts": [["text": userPrompt]]
                ]
            ],
            "generationConfig": generationConfig
        ]
        return try JSONSerialization.data(withJSONObject: body)
    }

    // MARK: - Response Parsing

    /// Extract text content from the AI response using the format's key path.
    private func extractTextFromResponse(data: Data, config: LoopInsightsAIProviderConfiguration) throws -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LoopInsightsError.parseError("Response is not valid JSON")
        }

        let keyPath = config.requestFormat.defaultResponseKeyPath
        let components = keyPath.split(separator: ".").map(String.init)

        var current: Any = json
        for component in components {
            if let index = Int(component), let array = current as? [Any], index < array.count {
                current = array[index]
            } else if let dict = current as? [String: Any], let value = dict[component] {
                current = value
            } else {
                throw LoopInsightsError.parseError("Unable to extract content at key path '\(keyPath)' from response")
            }
        }

        guard let text = current as? String else {
            throw LoopInsightsError.parseError("Value at key path '\(keyPath)' is not a string")
        }

        return text
    }
}
