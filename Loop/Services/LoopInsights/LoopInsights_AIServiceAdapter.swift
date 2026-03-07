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

        // Cap output tokens to 8192 — enough for thinking overhead (~6K) plus the
        // JSON response (~1.5K), but not so high that thinking models burn 60K+ tokens.
        config.maxTokens = min(config.maxTokens, 8192)

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
            "generationConfig": [
                "temperature": config.temperature,
                "maxOutputTokens": config.maxTokens
            ]
        ]
        return try JSONSerialization.data(withJSONObject: body)
    }

    // MARK: - Response Parsing

    /// Extract text content from the AI response. Tries multiple strategies to handle
    /// different response formats across providers and model versions (including thinking models).
    private func extractTextFromResponse(data: Data, config: LoopInsightsAIProviderConfiguration) throws -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LoopInsightsError.parseError("Response is not valid JSON")
        }

        // Gemini thinking models: extract non-thought content first.
        // Thinking models put chain-of-thought in parts[0] with thought:true flag,
        // and the actual response in subsequent parts. The default key path
        // (parts.0.text) would return thinking text instead of the real response.
        if config.requestFormat == .googleGenerativeAI || json.keys.contains("candidates") {
            if let text = extractGeminiNonThoughtText(from: json) {
                return text
            }
            // No non-thought text found — if thinking tokens were consumed,
            // the model used its entire output budget on thinking.
            if hasThinkingTokens(json) {
                throw LoopInsightsError.emptyThinkingResponse
            }
        }

        // Strategy 1: Try the configured key path (works for most standard models)
        if let text = extractViaKeyPath(from: json, keyPath: config.requestFormat.defaultResponseKeyPath) {
            return text
        }

        // Strategy 2: Deep search — find any string in the response that looks like
        // our expected JSON format (contains "suggestions"). Handles thinking models,
        // unexpected response structures, and API version differences.
        if let text = deepSearchForContent(in: json) {
            return text
        }

        // Strategy 3: Stringify the entire response and let the caller's extractJSON handle it
        if let responseData = try? JSONSerialization.data(withJSONObject: json),
           let responseString = String(data: responseData, encoding: .utf8) {
            return responseString
        }

        let topKeys = json.keys.sorted().joined(separator: ", ")
        throw LoopInsightsError.parseError("Unable to extract text from response. Top-level keys: \(topKeys)")
    }

    /// Try to extract text via a dot-separated key path (e.g. "candidates.0.content.parts.0.text")
    private func extractViaKeyPath(from json: [String: Any], keyPath: String) -> String? {
        let components = keyPath.split(separator: ".").map(String.init)
        var current: Any = json

        for component in components {
            if let index = Int(component), let array = current as? [Any], index < array.count {
                current = array[index]
            } else if let dict = current as? [String: Any], let value = dict[component] {
                current = value
            } else {
                return nil
            }
        }

        return current as? String
    }

    /// Recursively search the response JSON for text content. Collects all non-thought
    /// text strings and returns the best one (preferring JSON-like content, then longest).
    private func deepSearchForContent(in value: Any) -> String? {
        var candidates: [String] = []
        collectTextStrings(from: value, into: &candidates)

        // Prefer text that looks like our expected JSON response
        if let jsonCandidate = candidates.first(where: { $0.contains("suggestions") || $0.contains("{") }) {
            return jsonCandidate
        }

        // Otherwise return the longest text (most likely the actual response)
        return candidates.max(by: { $0.count < $1.count })
    }

    /// For Google Gemini thinking models: extract the last non-thought text from parts.
    /// Thinking models put chain-of-thought reasoning in early parts (with thought:true)
    /// and the actual response in later parts. Returns nil if no non-thought text exists.
    private func extractGeminiNonThoughtText(from json: [String: Any]) -> String? {
        guard let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]] else {
            return nil
        }

        // Find the last part that is NOT a thought part
        for part in parts.reversed() {
            if part["thought"] as? Bool == true { continue }
            if let text = part["text"] as? String, !text.isEmpty {
                return text
            }
        }

        return nil
    }

    /// Check if the API response contains thinking token metadata (Gemini thinking models).
    private func hasThinkingTokens(_ json: [String: Any]) -> Bool {
        guard let usageMetadata = json["usageMetadata"] as? [String: Any],
              let thoughts = usageMetadata["thoughtsTokenCount"] as? Int else {
            return false
        }
        return thoughts > 0
    }

    /// Collect all non-thought text strings from the response tree.
    private func collectTextStrings(from value: Any, into results: inout [String]) {
        if let dict = value as? [String: Any] {
            // Skip thought parts
            if dict["thought"] as? Bool == true { return }

            // Collect text from this dict
            if let text = dict["text"] as? String, !text.isEmpty {
                results.append(text)
            }

            // Recurse into values (prioritize content-bearing keys)
            let priorityKeys = ["candidates", "content", "parts", "message", "choices"]
            for key in priorityKeys {
                if let child = dict[key] {
                    collectTextStrings(from: child, into: &results)
                }
            }
            // Then try remaining keys
            for (key, child) in dict where !priorityKeys.contains(key) {
                collectTextStrings(from: child, into: &results)
            }
        } else if let array = value as? [Any] {
            for item in array {
                collectTextStrings(from: item, into: &results)
            }
        }
    }
}
