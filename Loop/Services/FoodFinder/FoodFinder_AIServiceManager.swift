//
//  AIServiceManager.swift
//  Loop
//
//  Created by Taylor Patterson on 9/30/25.
//  Copyright © 2025 LoopKit Authors. All rights reserved.
//

import Foundation
import os.log
import UIKit
import LoopKit

/// Manages AI service operations using the provider-agnostic configuration
final class AIServiceManager {
    static let shared = AIServiceManager()
    
    private let log = OSLog(category: "AIServiceManager")
    private let session = URLSession.shared
    private let jsonDecoder = JSONDecoder()
    private let imageCache = NSCache<NSString, AnyObject>()
    
    private init() {
        jsonDecoder.keyDecodingStrategy = .convertFromSnakeCase
        imageCache.countLimit = 20 // Cache up to 20 images
    }
    
    // MARK: - Public Methods
    
    /// Analyzes a food image using the specified AI provider configuration
    /// - Parameters:
    ///   - image: The image to analyze
    ///   - configuration: The AI provider configuration to use
    ///   - query: Optional search query to guide the analysis
    /// - Returns: The analysis result
    func analyzeFoodImage(
        _ image: UIImage,
        using configuration: AIProviderConfiguration,
        query: String = ""
    ) async throws -> AIFoodAnalysisResult {
        // 1. Validate configuration
        guard configuration.supportsVision else {
            throw AIFoodAnalysisError.invalidModel
        }
        
        // 2. Prepare the image
        let preparedImage = await prepareImageForAnalysis(image)
        
        // 3. Create the request
        let request = try createRequest(
            with: configuration,
            image: preparedImage,
            query: query
        )
        
        // 4. Make the request with timeout
        let (data, response): (Data, URLResponse) = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(Data, URLResponse), Error>) in
            let task = session.dataTask(with: request) { data, response, error in
                if let error = error {
                    continuation.resume(throwing: AIFoodAnalysisError.networkError(error))
                    return
                }

                guard let data = data, let response = response else {
                    continuation.resume(throwing: AIFoodAnalysisError.invalidResponse)
                    return
                }

                continuation.resume(returning: (data, response))
            }

            task.resume()
        }
        
        // 5. Validate the response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIFoodAnalysisError.invalidResponse
        }
        
        // Handle rate limiting and quota errors
        switch httpResponse.statusCode {
        case 429:
            throw AIFoodAnalysisError.rateLimitExceededGeneric
        case 402, 403:
            throw AIFoodAnalysisError.insufficientQuota
        case 400..<500:
            let errorMessage = String(data: data, encoding: .utf8) ?? "Client error"
            throw AIFoodAnalysisError.apiErrorWithMessage(statusCode: httpResponse.statusCode, message: errorMessage)
        case 500..<600:
            let errorMessage = String(data: data, encoding: .utf8) ?? "Server error"
            throw AIFoodAnalysisError.serverError(errorMessage)
        default:
            break
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            log.error("AI API error: %{public}@", errorMessage)
            throw AIFoodAnalysisError.apiErrorWithMessage(statusCode: httpResponse.statusCode, message: errorMessage)
        }
        
        // 6. Parse the response
        do {
            return try parseResponse(data: data, configuration: configuration)
        } catch let error as AIFoodAnalysisError {
            throw error
        } catch {
            log.error("Failed to parse AI response: %{public}@", error.localizedDescription)
            throw AIFoodAnalysisError.invalidResponseFormat
        }
    }
    
    /// Tests the connection to an AI provider
    /// - Parameter configuration: The configuration to test
    /// - Returns: True if the connection was successful
    func testConnection(to configuration: AIProviderConfiguration) async -> Bool {
        do {
            // Create a simple test request
            let request = try createTestRequest(with: configuration)
            
            // Make the request with a timeout
            let (data, response): (Data, URLResponse) = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(Data, URLResponse), Error>) in
                let task = session.dataTask(with: request) { data, response, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                        return
                    }

                    guard let data = data, let response = response else {
                        continuation.resume(throwing: AIFoodAnalysisError.invalidResponse)
                        return
                    }

                    continuation.resume(returning: (data, response))
                }

                task.resume()
            }
            
            // Check if the response is valid
            guard let httpResponse = response as? HTTPURLResponse else {
                return false
            }
            
            // Log the response for debugging
            let statusCode = httpResponse.statusCode
            let responseBody = String(data: data, encoding: .utf8) ?? ""
            let truncatedResponse = String(responseBody.prefix(200))
            log.debug("Test connection to %{public}@: Status %d, Response: %{public}@",
                     configuration.name, statusCode, truncatedResponse)

            // Consider 2xx and 4xx (auth errors) as valid responses
            // since they indicate the endpoint is reachable
            let isValid = (200...499).contains(statusCode)

            if !isValid {
                log.error("Connection test failed with status %d: %{public}@",
                         statusCode, truncatedResponse)
            }
            
            return isValid
        } catch {
            log.error("Connection test failed: %{public}@", error.localizedDescription)
            return false
        }
    }
    
    // MARK: - Private Methods
    
    private func prepareImageForAnalysis(_ image: UIImage) async -> UIImage {
        // Optimize the image for analysis
        let targetSize = CGSize(width: 1024, height: 1024)
        let resizedImage = await image.byPreparingForAnalysis(targetSize: targetSize)
        return resizedImage
    }
    
    private func createRequest(
        with configuration: AIProviderConfiguration,
        image: UIImage,
        query: String
    ) throws -> URLRequest {
        // 1. Construct the URL
        let baseURL = configuration.baseURL.trimmingCharacters(in: ["/"])
        let endpoint = configuration.endpointPath.starts(with: "/") ? 
            String(configuration.endpointPath.dropFirst()) : 
            configuration.endpointPath
        
        let urlString = "\(baseURL)/\(endpoint)"
        guard let url = URL(string: urlString) else {
            throw AIFoodAnalysisError.invalidURL(urlString)
        }
        
        // 2. Prepare the request body
        var requestBody = configuration.requestTemplate
            .replacingOccurrences(of: "{{MODEL}}", with: configuration.model)
            .replacingOccurrences(of: "{{PROMPT}}", with: query)
        
        // Add the image if the provider supports vision
        if configuration.supportsVision, let imageData = image.jpegData(compressionQuality: 0.8) {
            let base64Image = imageData.base64EncodedString()
            requestBody = requestBody.replacingOccurrences(of: "{{IMAGE_BASE64}}", with: base64Image)
        }
        
        // 3. Create the request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = requestBody.data(using: .utf8)
        
        // 4. Set headers
        configuration.headers.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        // 5. Add authentication
        switch configuration.authType {
        case .bearer:
            request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        case .apiKey:
            request.setValue(configuration.apiKey, forHTTPHeaderField: "x-api-key")
        case .custom:
            if let header = configuration.customHeaderName, let value = configuration.customHeaderValue {
                let finalValue = value.replacingOccurrences(of: "{{API_KEY}}", with: configuration.apiKey)
                request.setValue(finalValue, forHTTPHeaderField: header)
            }
        }

        return request
    }

    private func createTestRequest(with configuration: AIProviderConfiguration) throws -> URLRequest {
        // Create a lightweight test request to validate the connection
        let baseURL = configuration.baseURL.trimmingCharacters(in: ["/"])
        let testEndpoint = configuration.testEndpointPath ?? configuration.endpointPath
        let urlString = "\(baseURL)/\(testEndpoint)"

        guard let url = URL(string: urlString) else {
            throw AIFoodAnalysisError.invalidURL(urlString)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10 // Shorter timeout for connection tests

        // Add authentication
        switch configuration.authType {
        case .bearer:
            request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        case .apiKey:
            request.setValue(configuration.apiKey, forHTTPHeaderField: "x-api-key")
        case .custom:
            if let header = configuration.customHeaderName, let value = configuration.customHeaderValue {
                let finalValue = value.replacingOccurrences(of: "{{API_KEY}}", with: configuration.apiKey)
                request.setValue(finalValue, forHTTPHeaderField: header)
            }
        }

        return request
    }
    
    private func parseResponse(data: Data, configuration: AIProviderConfiguration) throws -> AIFoodAnalysisResult {
        // Parse the JSON response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIFoodAnalysisError.invalidResponseFormat
        }

        // Extract the content using the configured key path
        let content: String
        if !configuration.responseKeyPath.isEmpty {
            // Use key path to extract content
            let keys = configuration.responseKeyPath.components(separatedBy: ".")
            var current: Any? = json

            for key in keys {
                if let dict = current as? [String: Any] {
                    current = dict[key]
                } else if let array = current as? [Any], let index = Int(key), array.indices.contains(index) {
                    current = array[index]
                } else {
                    throw AIFoodAnalysisError.invalidResponseFormat
                }
            }

            guard let resultContent = current as? String else {
                throw AIFoodAnalysisError.invalidResponseFormat
            }

            content = resultContent
        } else {
            // Fallback to direct string conversion
            guard let resultContent = String(data: data, encoding: .utf8) else {
                throw AIFoodAnalysisError.invalidResponseFormat
            }
            content = resultContent
        }

        // Try to parse the content as JSON
        guard let contentData = content.data(using: .utf8),
              let contentJson = try? JSONSerialization.jsonObject(with: contentData) as? [String: Any] else {
            // If not valid JSON, return a basic result with the raw content
            return AIFoodAnalysisResult(
                imageType: nil,
                foodItemsDetailed: [
                    FoodItemAnalysis(
                        name: "Unparsed Content",
                        portionEstimate: "1 serving",
                        usdaServingSize: nil,
                        servingMultiplier: 1.0,
                        preparationMethod: nil,
                        visualCues: nil,
                        carbohydrates: 0,
                        calories: nil,
                        fat: nil,
                        fiber: nil,
                        protein: nil,
                        assessmentNotes: "The AI response could not be parsed as structured data.",
                        absorptionTimeHours: nil
                    )
                ],
                overallDescription: "Analysis completed with unparsed content",
                confidence: .low,
                numericConfidence: nil,
                totalFoodPortions: 1,
                totalUsdaServings: nil,
                totalCarbohydrates: 0,
                totalProtein: nil,
                totalFat: nil,
                totalFiber: nil,
                totalCalories: nil,
                portionAssessmentMethod: nil,
                diabetesConsiderations: nil,
                visualAssessmentDetails: nil,
                notes: nil,
                originalServings: 1.0,
                fatProteinUnits: nil,
                netCarbsAdjustment: nil,
                insulinTimingRecommendations: nil,
                fpuDosingGuidance: nil,
                exerciseConsiderations: nil,
                absorptionTimeHours: nil,
                absorptionTimeReasoning: nil,
                mealSizeImpact: nil,
                individualizationFactors: nil,
                safetyAlerts: nil
            )
        }

        // Parse the structured response
        return try parseStructuredResponse(contentJson)
    }

    private func parseStructuredResponse(_ json: [String: Any]) throws -> AIFoodAnalysisResult {
        // Extract basic information
        let imageTypeString = json["image_type"] as? String
        let imageType: ImageAnalysisType? = imageTypeString.flatMap { ImageAnalysisType(rawValue: $0) }

        // Parse food items
        var foodItems: [FoodItemAnalysis] = []
        if let foodItemsArray = json["food_items"] as? [[String: Any]] {
            for item in foodItemsArray {
                let name = item["name"] as? String ?? "Unknown Food"
                let portionEstimate = item["portion_estimate"] as? String ?? "1 serving"

                // Create food item using the actual FoodItemAnalysis structure
                let foodItem = FoodItemAnalysis(
                    name: name,
                    portionEstimate: portionEstimate,
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
                )

                foodItems.append(foodItem)
            }
        }

        // Calculate totals from food items
        let totalCarbs = foodItems.map { $0.carbohydrates }.reduce(0, +)
        let totalProtein = foodItems.compactMap { $0.protein }.reduce(0, +)
        let totalFat = foodItems.compactMap { $0.fat }.reduce(0, +)
        let totalCalories = foodItems.compactMap { $0.calories }.reduce(0, +)
        let totalFiber = foodItems.compactMap { $0.fiber }.reduce(0, +)

        // Create and return the result using the actual AIFoodAnalysisResult structure
        return AIFoodAnalysisResult(
            imageType: imageType,
            foodItemsDetailed: foodItems,
            overallDescription: json["overall_description"] as? String,
            confidence: AIConfidenceLevel(rawValue: (json["confidence_level"] as? String) ?? "") ?? .medium,
            numericConfidence: json["confidence"] as? Double,
            totalFoodPortions: foodItems.count,
            totalUsdaServings: json["total_usda_servings"] as? Double,
            totalCarbohydrates: json["total_carbohydrates"] as? Double ?? totalCarbs,
            totalProtein: totalProtein > 0 ? totalProtein : (json["total_protein"] as? Double),
            totalFat: totalFat > 0 ? totalFat : (json["total_fat"] as? Double),
            totalFiber: totalFiber > 0 ? totalFiber : (json["total_fiber"] as? Double),
            totalCalories: totalCalories > 0 ? totalCalories : (json["total_calories"] as? Double),
            portionAssessmentMethod: json["portion_assessment_method"] as? String,
            diabetesConsiderations: json["diabetes_considerations"] as? String,
            visualAssessmentDetails: json["visual_assessment_details"] as? String,
            notes: json["notes"] as? String,
            originalServings: (json["original_servings"] as? Double) ?? 1.0,
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
}

// MARK: - Image Processing

extension UIImage {
    func byPreparingForAnalysis(targetSize: CGSize) -> UIImage {
        // 1. Crop to square aspect ratio
        let squareImage = byCroppingToSquare()
        
        // 2. Resize to target size
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true
        
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let resizedImage = renderer.image { _ in
            squareImage.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        
        return resizedImage
    }
    
    private func byCroppingToSquare() -> UIImage {
        let originalWidth = size.width
        let originalHeight = size.height
        
        // Check if already square
        if originalWidth == originalHeight {
            return self
        }
        
        // Calculate square dimensions
        let squareSize = min(originalWidth, originalHeight)
        let x = (originalWidth - squareSize) / 2
        let y = (originalHeight - squareSize) / 2
        let squareRect = CGRect(x: x, y: y, width: squareSize, height: squareSize)
        
        // Crop to square
        guard let cgImage = cgImage?.cropping(to: squareRect) else {
            return self
        }
        
        return UIImage(cgImage: cgImage, scale: scale, orientation: imageOrientation)
    }
}
