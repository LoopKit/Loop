//
//  FoodFinder_AIServiceManager.swift
//  Loop
//
//  FoodFinder — Generic AI HTTP client for food analysis across all providers.
//
//  Idea by Taylor Patterson. Coded by Claude Code.
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Foundation
import os.log
import UIKit
import LoopKit

/// Single generic AI client that handles all providers via RequestFormat.
final class AIServiceManager {
    static let shared = AIServiceManager()

    private let log = OSLog(category: "AIServiceManager")
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 90
        session = URLSession(configuration: config)
    }

    // MARK: - Public Methods

    /// Analyzes a food image using the configured AI provider.
    func analyzeFoodImage(
        _ image: UIImage,
        using configuration: AIProviderConfiguration,
        query: String = ""
    ) async throws -> AIFoodAnalysisResult {
        guard !configuration.apiKey.isEmpty else {
            throw AIFoodAnalysisError.noApiKey
        }

        let preparedImage = await prepareImageForAnalysis(image)

        guard let imageData = preparedImage.jpegData(compressionQuality: 0.6) else {
            throw AIFoodAnalysisError.imageProcessingFailed
        }
        let imageBase64 = imageData.base64EncodedString()

        // Ensure sufficient token budget for menus, recipes, and multi-item plates
        var adjustedConfig = configuration
        adjustedConfig.maxTokens = max(configuration.maxTokens, 4096)

        var request = try buildRequest(config: adjustedConfig, prompt: query, imageBase64: imageBase64)

        // Advanced dosing prompts are much larger and produce longer responses
        let isAdvanced = UserDefaults.standard.advancedDosingRecommendationsEnabled
        request.timeoutInterval = isAdvanced ? 120 : 60

        let requestStart = Date()
        let (data, response) = try await executeRequest(request)
        let requestDuration = Date().timeIntervalSince(requestStart)

        log.default("AI request completed in %.1f seconds (%d bytes)", requestDuration, data.count)

        try validateHTTPResponse(response, data: data)

        return try parseResponse(data: data, config: configuration)
    }

    /// Analyze a food image that has already been pre-encoded (cropped, resized, JPEG-compressed).
    /// Skips the internal `prepareImageForAnalysis` pipeline to avoid double-processing.
    /// Used by `ConfigurableAIService` which pre-encodes images via `preencodeImageForProviders`.
    func analyzeFoodImagePreencoded(
        base64: String,
        using configuration: AIProviderConfiguration,
        query: String = ""
    ) async throws -> AIFoodAnalysisResult {
        guard !configuration.apiKey.isEmpty else {
            throw AIFoodAnalysisError.noApiKey
        }

        var adjustedConfig = configuration
        adjustedConfig.maxTokens = max(configuration.maxTokens, 4096)

        var request = try buildRequest(config: adjustedConfig, prompt: query, imageBase64: base64)

        let isAdvanced = UserDefaults.standard.advancedDosingRecommendationsEnabled
        request.timeoutInterval = isAdvanced ? 120 : 60

        let requestStart = Date()
        let (data, response) = try await executeRequest(request)
        let requestDuration = Date().timeIntervalSince(requestStart)

        log.default("AI request (preencoded) completed in %.1f seconds (%d bytes)", requestDuration, data.count)

        try validateHTTPResponse(response, data: data)

        return try parseResponse(data: data, config: configuration)
    }

    /// Text-only food analysis (no image). Used for voice/dictation searches.
    func analyzeFoodByText(
        using configuration: AIProviderConfiguration,
        query: String
    ) async throws -> AIFoodAnalysisResult {
        guard !configuration.apiKey.isEmpty else {
            throw AIFoodAnalysisError.noApiKey
        }

        // Ensure sufficient token budget for menus, recipes, and multi-item descriptions
        var adjustedConfig = configuration
        adjustedConfig.maxTokens = max(configuration.maxTokens, 4096)

        var request = try buildRequest(config: adjustedConfig, prompt: query, imageBase64: nil)

        let isAdvanced = UserDefaults.standard.advancedDosingRecommendationsEnabled
        request.timeoutInterval = isAdvanced ? 120 : 60

        let requestStart = Date()
        let (data, response) = try await executeRequest(request)
        let requestDuration = Date().timeIntervalSince(requestStart)

        log.default("AI text-only request completed in %.1f seconds (%d bytes)", requestDuration, data.count)

        try validateHTTPResponse(response, data: data)

        return try parseResponse(data: data, config: configuration)
    }

    /// Tests connectivity to the configured endpoint. Returns true if reachable.
    /// Result of a connection test with status details.
    struct TestConnectionResult {
        let success: Bool
        let statusCode: Int?
        let message: String
        let supportsVision: Bool?  // nil = not tested, true = confirmed, false = rejected
    }

    func testConnection(to configuration: AIProviderConfiguration) async -> TestConnectionResult {
        do {
            // Use minimal tokens for a lightweight connectivity check
            var testConfig = configuration
            testConfig.maxTokens = 128
            testConfig.temperature = 0

            let testPrompt = "Say hi"
            let request = try buildRequest(config: testConfig, prompt: testPrompt, imageBase64: nil)

            log.debug("Test connection URL: %{public}@", request.url?.absoluteString ?? "nil")
            log.debug("Test connection format: %{public}@, endpoint: %{public}@", configuration.requestFormat.displayName, configuration.endpointPath)

            let (data, response) = try await executeRequest(request)

            guard let http = response as? HTTPURLResponse else {
                return TestConnectionResult(success: false, statusCode: nil, message: "Invalid response", supportsVision: nil)
            }
            let body = String(data: data, encoding: .utf8) ?? ""
            log.debug("Test connection: status=%d body=%{public}@", http.statusCode, String(body.prefix(200)))

            switch http.statusCode {
            case 200...299:
                let visionSupport = await testVisionSupport(config: testConfig)
                return TestConnectionResult(success: true, statusCode: http.statusCode, message: "Connected successfully", supportsVision: visionSupport)
            case 401:
                return TestConnectionResult(success: false, statusCode: 401, message: "Invalid API key", supportsVision: nil)
            case 402:
                // 402 = payment required — key and endpoint are valid, billing issue
                return TestConnectionResult(success: true, statusCode: 402, message: "Connected — but billing/quota issue on your account", supportsVision: nil)
            case 403:
                return TestConnectionResult(success: false, statusCode: 403, message: "Access denied — check API key permissions", supportsVision: nil)
            case 404:
                return TestConnectionResult(success: false, statusCode: 404, message: "Endpoint not found — check Base URL", supportsVision: nil)
            case 405:
                return TestConnectionResult(success: false, statusCode: 405, message: "Wrong endpoint — check Base URL and model", supportsVision: nil)
            case 429:
                // 429 = rate limited — key and endpoint are valid, just throttled
                return TestConnectionResult(success: true, statusCode: 429, message: "Connected — rate limited, try again shortly", supportsVision: nil)
            default:
                let shortBody = String(body.prefix(100))
                return TestConnectionResult(success: false, statusCode: http.statusCode, message: "HTTP \(http.statusCode): \(shortBody)", supportsVision: nil)
            }
        } catch {
            log.error("Test connection failed: %{public}@", error.localizedDescription)
            return TestConnectionResult(success: false, statusCode: nil, message: "Network error: \(error.localizedDescription)", supportsVision: nil)
        }
    }

    // MARK: - Vision Support Detection

    /// Minimal 1x1 white JPEG for vision capability testing (~600 bytes).
    private static let minimalTestImageBase64: String = {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1))
        let data = renderer.jpegData(withCompressionQuality: 0.1) { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: CGSize(width: 1, height: 1)))
        }
        return data.base64EncodedString()
    }()

    /// Vision-rejection keywords found in error responses from various AI providers.
    private static let visionRejectionKeywords = [
        "vision", "image", "does not support", "multimodal",
        "not capable", "image_url", "cannot process image",
        "not support image", "image input", "not available"
    ]

    /// Tests whether the model supports vision/image input.
    /// Returns `true` if confirmed, `false` if rejected, `nil` if inconclusive.
    private func testVisionSupport(config: AIProviderConfiguration) async -> Bool? {
        do {
            let request = try buildRequest(
                config: config,
                prompt: "Describe this image",
                imageBase64: Self.minimalTestImageBase64
            )

            let (data, response) = try await executeRequest(request)

            guard let http = response as? HTTPURLResponse else { return nil }

            switch http.statusCode {
            case 200...299:
                return true
            case 400, 404, 422:
                let body = (String(data: data, encoding: .utf8) ?? "").lowercased()
                let isVisionRejection = Self.visionRejectionKeywords.contains { body.contains($0) }
                return isVisionRejection ? false : nil
            default:
                return nil
            }
        } catch {
            log.debug("Vision support test inconclusive: %{public}@", error.localizedDescription)
            return nil
        }
    }

    // MARK: - Request Building

    private func buildRequest(
        config: AIProviderConfiguration,
        prompt: String,
        imageBase64: String?
    ) throws -> URLRequest {
        let url = try buildURL(config: config)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Auth header
        let keyValue = config.apiKeyPrefix + config.apiKey
        request.setValue(keyValue, forHTTPHeaderField: config.apiKeyHeader)

        // Extra headers from config
        for (key, value) in config.headers where key != "Content-Type" {
            request.setValue(value, forHTTPHeaderField: key)
        }

        // Format-specific extra headers
        if config.requestFormat == .anthropicMessages {
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        }

        // Build body
        let body: Data
        switch config.requestFormat {
        case .openAICompatible:
            body = try buildOpenAIBody(config: config, prompt: prompt, imageBase64: imageBase64)
        case .anthropicMessages:
            body = try buildAnthropicBody(config: config, prompt: prompt, imageBase64: imageBase64)
        case .googleGenerativeAI:
            body = try buildGoogleBody(config: config, prompt: prompt, imageBase64: imageBase64)
        }

        request.httpBody = body
        return request
    }

    private func buildURL(config: AIProviderConfiguration) throws -> URL {
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
            throw AIFoodAnalysisError.invalidURL(urlString)
        }
        return url
    }

    // MARK: - Format-Specific Body Builders

    private func buildOpenAIBody(
        config: AIProviderConfiguration,
        prompt: String,
        imageBase64: String?
    ) throws -> Data {
        var contentParts: [[String: Any]] = [
            ["type": "text", "text": prompt]
        ]

        if let img = imageBase64 {
            contentParts.append([
                "type": "image_url",
                "image_url": ["url": "data:image/jpeg;base64,\(img)", "detail": "high"]
            ])
        }

        let body: [String: Any] = [
            "model": config.model,
            "messages": [
                ["role": "user", "content": contentParts]
            ],
            "max_tokens": config.maxTokens,
            "temperature": config.temperature
        ]

        return try JSONSerialization.data(withJSONObject: body)
    }

    private func buildAnthropicBody(
        config: AIProviderConfiguration,
        prompt: String,
        imageBase64: String?
    ) throws -> Data {
        var contentParts: [[String: Any]] = []

        if let img = imageBase64 {
            contentParts.append([
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": "image/jpeg",
                    "data": img
                ]
            ])
        }

        contentParts.append(["type": "text", "text": prompt])

        let body: [String: Any] = [
            "model": config.model,
            "max_tokens": config.maxTokens,
            "temperature": config.temperature,
            "messages": [
                ["role": "user", "content": contentParts]
            ]
        ]

        return try JSONSerialization.data(withJSONObject: body)
    }

    private func buildGoogleBody(
        config: AIProviderConfiguration,
        prompt: String,
        imageBase64: String?
    ) throws -> Data {
        var parts: [[String: Any]] = [
            ["text": prompt]
        ]

        if let img = imageBase64 {
            parts.append([
                "inline_data": [
                    "mime_type": "image/jpeg",
                    "data": img
                ]
            ])
        }

        let body: [String: Any] = [
            "contents": [
                ["parts": parts]
            ],
            "generationConfig": [
                "maxOutputTokens": config.maxTokens,
                "temperature": config.temperature,
                "topP": 0.95,
                "topK": 8
            ],
            // Disable thinking for Gemini 2.5+ models — we need structured JSON,
            // not chain-of-thought. Non-thinking models ignore this field.
            "thinkingConfig": [
                "thinkingBudget": 0
            ]
        ]

        return try JSONSerialization.data(withJSONObject: body)
    }

    // MARK: - Request Execution

    private func executeRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch let error as URLError {
            if error.code == .timedOut {
                throw AIFoodAnalysisError.timeout
            }
            throw AIFoodAnalysisError.networkError(error)
        } catch {
            throw AIFoodAnalysisError.networkError(error)
        }
    }

    private func validateHTTPResponse(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw AIFoodAnalysisError.invalidResponse
        }

        switch http.statusCode {
        case 200...299:
            return // Success
        case 429:
            throw AIFoodAnalysisError.rateLimitExceededGeneric
        case 402, 403:
            throw AIFoodAnalysisError.insufficientQuota
        case 400..<500:
            let msg = String(data: data, encoding: .utf8) ?? "Client error"
            throw AIFoodAnalysisError.apiErrorWithMessage(statusCode: http.statusCode, message: msg)
        case 500..<600:
            let msg = String(data: data, encoding: .utf8) ?? "Server error"
            throw AIFoodAnalysisError.serverError(msg)
        default:
            let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AIFoodAnalysisError.apiErrorWithMessage(statusCode: http.statusCode, message: msg)
        }
    }

    // MARK: - Response Parsing

    private func parseResponse(data: Data, config: AIProviderConfiguration) throws -> AIFoodAnalysisResult {
        #if DEBUG
        let rawResponse = String(data: data, encoding: .utf8) ?? "<non-utf8>"
        print("🤖 [PARSE] Raw response (\(data.count) bytes): \(String(rawResponse.prefix(500)))")
        print("🤖 [PARSE] Using keyPath: \(config.responseKeyPath)")
        #endif

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            #if DEBUG
            print("🤖 [PARSE] FAILED: Could not parse top-level JSON")
            #endif
            throw AIFoodAnalysisError.invalidResponseFormat
        }

        // Extract text content using the configured key path
        let textContent = try extractTextContent(from: json, keyPath: config.responseKeyPath)

        #if DEBUG
        print("🤖 [PARSE] Extracted text content (\(textContent.count) chars): \(String(textContent.prefix(300)))")
        #endif

        // Clean markdown code fences if present
        let cleaned = textContent
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Find JSON bounds (first { to last })
        guard let jsonStart = cleaned.firstIndex(of: "{"),
              let jsonEnd = cleaned.lastIndex(of: "}") else {
            #if DEBUG
            print("🤖 [PARSE] FAILED: No JSON braces found in cleaned text: \(String(cleaned.prefix(200)))")
            #endif
            throw AIFoodAnalysisError.invalidResponseFormat
        }

        var jsonString = String(cleaned[jsonStart...jsonEnd])

        // Try parsing as-is first
        if let jsonData = jsonString.data(using: .utf8),
           let contentJson = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
            return try parseStructuredResponse(contentJson)
        }

        // JSON may be truncated (max_tokens exceeded). Try to repair by closing open braces/brackets.
        jsonString = repairTruncatedJSON(jsonString)

        guard let jsonData = jsonString.data(using: .utf8),
              let contentJson = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            #if DEBUG
            print("🤖 [PARSE] FAILED: Could not parse inner JSON (even after repair): \(String(jsonString.prefix(300)))")
            #endif
            throw AIFoodAnalysisError.invalidResponseFormat
        }

        #if DEBUG
        print("🤖 [PARSE] Recovered truncated JSON via brace repair")
        #endif
        return try parseStructuredResponse(contentJson)
    }

    private func extractTextContent(from json: [String: Any], keyPath: String) throws -> String {
        // Gemini thinking models return thinking in parts[0] and the actual response
        // in subsequent parts. Handle this before the generic key path traversal.
        if keyPath.contains("candidates") && keyPath.contains("parts") {
            if let text = extractGeminiText(from: json) {
                return text
            }
        }

        let keys = keyPath.components(separatedBy: ".")
        var current: Any? = json

        for key in keys {
            if let dict = current as? [String: Any] {
                current = dict[key]
            } else if let array = current as? [Any], let index = Int(key), array.indices.contains(index) {
                current = array[index]
            } else {
                log.error("Failed to navigate key path '%{public}@' at key '%{public}@'", keyPath, key)
                #if DEBUG
                print("🤖 [PARSE] FAILED at keyPath '\(keyPath)' key '\(key)'. Current value type: \(type(of: current as Any))")
                if let dict = json["choices"] {
                    print("🤖 [PARSE] choices value: \(String(describing: dict).prefix(300))")
                }
                #endif
                throw AIFoodAnalysisError.invalidResponseFormat
            }
        }

        // Handle string content directly
        if let text = current as? String {
            return text
        }

        // Handle content returned as an array (e.g., [{"type": "text", "text": "..."}])
        if let contentArray = current as? [[String: Any]] {
            let texts = contentArray.compactMap { $0["text"] as? String }
            if !texts.isEmpty {
                return texts.joined()
            }
        }

        #if DEBUG
        print("🤖 [PARSE] FAILED: Final value is not String or content array, got \(type(of: current as Any)): \(String(describing: current).prefix(200))")
        #endif
        throw AIFoodAnalysisError.invalidResponseFormat
    }

    /// Extract text from a Gemini response, handling thinking models that return
    /// multiple parts (thought parts + actual response part).
    private func extractGeminiText(from json: [String: Any]) -> String? {
        guard let candidates = json["candidates"] as? [[String: Any]],
              let first = candidates.first,
              let content = first["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]] else {
            return nil
        }

        // Find the last part that is not a thought
        for part in parts.reversed() {
            if part["thought"] as? Bool == true { continue }
            if let text = part["text"] as? String {
                return text
            }
        }

        return parts.first?["text"] as? String
    }

    /// Attempts to repair truncated JSON by closing unclosed braces, brackets, and strings.
    private func repairTruncatedJSON(_ json: String) -> String {
        var result = json
        // Remove trailing incomplete key-value pairs (e.g., `"key": "unfinished...`)
        // Strip trailing content after the last complete value
        if let lastComma = result.lastIndex(of: ",") {
            let afterComma = result[result.index(after: lastComma)...].trimmingCharacters(in: .whitespacesAndNewlines)
            // If what's after the last comma doesn't end with } or ], it's likely incomplete
            if !afterComma.hasSuffix("}") && !afterComma.hasSuffix("]") && !afterComma.isEmpty {
                result = String(result[...lastComma])
                // Remove the trailing comma
                result = String(result.dropLast())
            }
        }

        // Count open vs close braces/brackets and append closers
        var openBraces = 0
        var openBrackets = 0
        var inString = false
        var prevChar: Character = " "
        for ch in result {
            if ch == "\"" && prevChar != "\\" { inString.toggle() }
            if !inString {
                if ch == "{" { openBraces += 1 }
                else if ch == "}" { openBraces -= 1 }
                else if ch == "[" { openBrackets += 1 }
                else if ch == "]" { openBrackets -= 1 }
            }
            prevChar = ch
        }

        // Close any unclosed strings
        if inString { result += "\"" }

        // Close brackets before braces (inner structures first)
        for _ in 0..<max(0, openBrackets) { result += "]" }
        for _ in 0..<max(0, openBraces) { result += "}" }

        return result
    }

    private func parseStructuredResponse(_ json: [String: Any]) throws -> AIFoodAnalysisResult {
        let imageTypeString = json["image_type"] as? String
        let imageType: ImageAnalysisType? = imageTypeString.flatMap { ImageAnalysisType(rawValue: $0) }

        // Parse food items
        var foodItems: [FoodItemAnalysis] = []
        if let items = json["food_items"] as? [[String: Any]] {
            for item in items {
                foodItems.append(FoodItemAnalysis(
                    name: item["name"] as? String ?? "Unknown Food",
                    portionEstimate: item["portion_estimate"] as? String ?? "1 serving",
                    usdaServingSize: item["usda_serving_size"] as? String,
                    servingMultiplier: item["serving_multiplier"] as? Double ?? 1.0,
                    preparationMethod: item["preparation_method"] as? String,
                    visualCues: item["visual_cues"] as? String,
                    carbohydrates: item["carbohydrates"] as? Double ?? 0,
                    calories: item["calories"] as? Double,
                    fat: item["fat"] as? Double,
                    fiber: item["fiber"] as? Double,
                    protein: item["protein"] as? Double,
                    assessmentNotes: item["assessment_notes"] as? String,
                    absorptionTimeHours: item["absorption_time_hours"] as? Double
                ))
            }
        }

        // Calculate totals from items (fallback to JSON-level totals)
        let itemCarbs = foodItems.map { $0.carbohydrates }.reduce(0, +)
        let itemProtein = foodItems.compactMap { $0.protein }.reduce(0, +)
        let itemFat = foodItems.compactMap { $0.fat }.reduce(0, +)
        let itemCalories = foodItems.compactMap { $0.calories }.reduce(0, +)
        let itemFiber = foodItems.compactMap { $0.fiber }.reduce(0, +)

        // Parse servings
        let totalServings = json["total_usda_servings"] as? Double
        let totalPortions = json["total_food_portions"] as? Int ?? foodItems.count

        return AIFoodAnalysisResult(
            imageType: imageType,
            foodItemsDetailed: foodItems,
            overallDescription: json["overall_description"] as? String,
            confidence: AIConfidenceLevel(rawValue: json["confidence_level"] as? String ?? "") ?? .medium,
            numericConfidence: json["confidence"] as? Double,
            totalFoodPortions: totalPortions,
            totalUsdaServings: totalServings,
            totalCarbohydrates: json["total_carbohydrates"] as? Double ?? itemCarbs,
            totalProtein: itemProtein > 0 ? itemProtein : (json["total_protein"] as? Double),
            totalFat: itemFat > 0 ? itemFat : (json["total_fat"] as? Double),
            totalFiber: itemFiber > 0 ? itemFiber : (json["total_fiber"] as? Double),
            totalCalories: itemCalories > 0 ? itemCalories : (json["total_calories"] as? Double),
            portionAssessmentMethod: json["portion_assessment_method"] as? String,
            diabetesConsiderations: json["diabetes_considerations"] as? String,
            visualAssessmentDetails: json["visual_assessment_details"] as? String,
            notes: json["notes"] as? String,
            originalServings: totalServings ?? 1.0,
            fatProteinUnits: json["fat_protein_units"] as? String,
            netCarbsAdjustment: json["net_carbs_adjustment"] as? String,
            insulinTimingRecommendations: json["insulin_timing_recommendations"] as? String,
            fpuDosingGuidance: json["fpu_dosing_guidance"] as? String,
            exerciseConsiderations: json["exercise_considerations"] as? String,
            absorptionTimeHours: json["absorption_time_hours"] as? Double,
            absorptionTimeReasoning: json["absorption_time_reasoning"] as? String,
            mealSizeImpact: json["meal_size_impact"] as? String,
            individualizationFactors: json["individualization_factors"] as? String,
            safetyAlerts: json["safety_alerts"] as? String
        )
    }

    // MARK: - Image Preparation

    private func prepareImageForAnalysis(_ image: UIImage) async -> UIImage {
        let targetSize = CGSize(width: 768, height: 768)
        return image.byPreparingForAnalysis(targetSize: targetSize)
    }
}

// MARK: - Image Processing

extension UIImage {
    func byPreparingForAnalysis(targetSize: CGSize) -> UIImage {
        let squareImage = byCroppingToSquare()

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { _ in
            squareImage.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    private func byCroppingToSquare() -> UIImage {
        let w = size.width, h = size.height
        guard w != h else { return self }

        let side = min(w, h)
        let rect = CGRect(x: (w - side) / 2, y: (h - side) / 2, width: side, height: side)

        guard let cg = cgImage?.cropping(to: rect) else { return self }
        return UIImage(cgImage: cg, scale: scale, orientation: imageOrientation)
    }
}
