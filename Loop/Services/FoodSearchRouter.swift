//
//  FoodSearchRouter.swift
//  Loop
//
//  Created by Taylor Patterson. Coded by Claude Code in June 2025
//  Copyright © 2025 LoopKit Authors. All rights reserved.
//

import UIKit
import Foundation
import os.log

/// Service that routes different types of food searches to the appropriate configured provider
class FoodSearchRouter {
    
    // MARK: - Singleton
    
    static let shared = FoodSearchRouter()
    
    private init() {}
    
    // MARK: - Properties
    
    private let log = OSLog(category: "FoodSearchRouter")
    private let aiService = ConfigurableAIService.shared
    private let openFoodFactsService = OpenFoodFactsService() // Uses optimized configuration by default
    
    // MARK: - Text/Voice Search Routing
    
    /// Perform text-based food search using the configured provider
    func searchFoodsByText(_ query: String) async throws -> [OpenFoodFactsProduct] {
        let provider = aiService.getProviderForSearchType(.textSearch)
        
        log.info("🔍 Routing text search '%{public}@' to provider: %{public}@", query, provider.rawValue)
        print("🔍 DEBUG: Text search using provider: \(provider.rawValue)")
        print("🔍 DEBUG: Available providers for text search: \(aiService.getAvailableProvidersForSearchType(.textSearch).map { $0.rawValue })")
        print("🔍 DEBUG: UserDefaults textSearchProvider: \(UserDefaults.standard.textSearchProvider)")
        print("🔍 DEBUG: Google Gemini API key configured: \(!UserDefaults.standard.googleGeminiAPIKey.isEmpty)")
        
        switch provider {
        case .openFoodFacts:
            return try await openFoodFactsService.searchProducts(query: query, pageSize: 15)
            
        case .usdaFoodData:
            return try await USDAFoodDataService.shared.searchProducts(query: query, pageSize: 15)
            
        case .claude:
            return try await searchWithClaude(query: query)
            
        case .googleGemini:
            return try await searchWithGoogleGemini(query: query)
            
            
        case .openAI:
            return try await searchWithOpenAI(query: query)
            
            
            
        }
    }
    
    // MARK: - Barcode Search Routing
    
    /// Perform barcode-based food search using the configured provider
    func searchFoodsByBarcode(_ barcode: String) async throws -> OpenFoodFactsProduct? {
        let provider = aiService.getProviderForSearchType(.barcodeSearch)
        
        log.info("📱 Routing barcode search '%{public}@' to provider: %{public}@", barcode, provider.rawValue)
        
        switch provider {
        case .openFoodFacts:
            return try await openFoodFactsService.fetchProduct(barcode: barcode)
            
            
            
        case .claude, .openAI, .usdaFoodData, .googleGemini:
            // These providers don't support barcode search, fall back to OpenFoodFacts
            log.info("⚠️ %{public}@ doesn't support barcode search, falling back to OpenFoodFacts", provider.rawValue)
            return try await openFoodFactsService.fetchProduct(barcode: barcode)
        }
    }
    
    // MARK: - AI Image Search Routing
    
    /// Perform AI image analysis using the configured provider
    func analyzeFood(image: UIImage) async throws -> AIFoodAnalysisResult {
        let provider = aiService.getProviderForSearchType(.aiImageSearch)
        
        log.info("🤖 Routing AI image analysis to provider: %{public}@", provider.rawValue)
        
        switch provider {
        case .claude:
            let key = aiService.getAPIKey(for: .claude) ?? ""
            let query = aiService.getQuery(for: .claude) ?? ""
            guard !key.isEmpty else {
                throw AIFoodAnalysisError.noApiKey
            }
            return try await ClaudeFoodAnalysisService.shared.analyzeFoodImage(image, apiKey: key, query: query)
            
        case .openAI:
            let key = aiService.getAPIKey(for: .openAI) ?? ""
            let query = aiService.getQuery(for: .openAI) ?? ""
            guard !key.isEmpty else {
                throw AIFoodAnalysisError.noApiKey
            }
            return try await OpenAIFoodAnalysisService.shared.analyzeFoodImage(image, apiKey: key, query: query)
            
            
            
        case .googleGemini:
            let key = UserDefaults.standard.googleGeminiAPIKey
            let query = UserDefaults.standard.googleGeminiQuery
            guard !key.isEmpty else {
                throw AIFoodAnalysisError.noApiKey
            }
            return try await GoogleGeminiFoodAnalysisService.shared.analyzeFoodImage(image, apiKey: key, query: query)
            
            
            
        case .openFoodFacts, .usdaFoodData:
            // OpenFoodFacts and USDA don't support AI image analysis, fall back to Google Gemini
            log.info("⚠️ %{public}@ doesn't support AI image analysis, falling back to Google Gemini", provider.rawValue)
            let key = UserDefaults.standard.googleGeminiAPIKey
            let query = UserDefaults.standard.googleGeminiQuery
            guard !key.isEmpty else {
                throw AIFoodAnalysisError.noApiKey
            }
            return try await GoogleGeminiFoodAnalysisService.shared.analyzeFoodImage(image, apiKey: key, query: query)
        }
    }
    
    // MARK: - Provider-Specific Implementations
    
    // MARK: Text Search Implementations
    
    private func searchWithGoogleGemini(query: String) async throws -> [OpenFoodFactsProduct] {
        let key = UserDefaults.standard.googleGeminiAPIKey
        guard !key.isEmpty else {
            log.info("🔑 Google Gemini API key not configured, falling back to USDA")
            return try await USDAFoodDataService.shared.searchProducts(query: query, pageSize: 15)
        }
        
        log.info("🍱 Using Google Gemini for text-based nutrition search")
        
        // Use Google Gemini to analyze the food query and return nutrition data
        let nutritionQuery = """
        Provide detailed nutrition information for "\(query)". Return the data as JSON with this exact format:
        {
          "food_name": "name of the food",
          "serving_size": "typical serving size",
          "carbohydrates": number (grams per serving),
          "protein": number (grams per serving),
          "fat": number (grams per serving),
          "calories": number (calories per serving)
        }
        
        If multiple foods match the query, provide information for the most common one. Use standard serving sizes (e.g., "1 medium apple", "1 cup cooked rice", "2 slices bread").
        """
        
        do {
            // Create a placeholder image since Gemini needs an image, but we'll rely on the text prompt
            let placeholderImage = createPlaceholderImage()
            let result = try await GoogleGeminiFoodAnalysisService.shared.analyzeFoodImage(
                placeholderImage, 
                apiKey: key, 
                query: nutritionQuery
            )
            
            // Convert AI result to OpenFoodFactsProduct
            let geminiProduct = OpenFoodFactsProduct(
                id: "gemini_text_\(UUID().uuidString.prefix(8))",
                productName: result.foodItems.first ?? query.capitalized,
                brands: "Google Gemini AI",
                categories: nil,
                nutriments: Nutriments(
                    carbohydrates: result.carbohydrates,
                    proteins: result.protein,
                    fat: result.fat,
                    calories: result.calories,
                    sugars: nil,
                    fiber: result.totalFiber
                ),
                servingSize: result.portionSize.isEmpty ? "1 serving" : result.portionSize,
                servingQuantity: 100.0,
                imageURL: nil,
                imageFrontURL: nil,
                code: nil,
                dataSource: .aiAnalysis
            )
            
            log.info("✅ Google Gemini text search completed for: %{public}@", query)
            return [geminiProduct]
            
        } catch {
            log.error("❌ Google Gemini text search failed: %{public}@, falling back to USDA", error.localizedDescription)
            return try await USDAFoodDataService.shared.searchProducts(query: query, pageSize: 15)
        }
    }
    
    
    private func searchWithClaude(query: String) async throws -> [OpenFoodFactsProduct] {
        let key = UserDefaults.standard.claudeAPIKey
        guard !key.isEmpty else {
            log.info("🔑 Claude API key not configured, falling back to USDA")
            return try await USDAFoodDataService.shared.searchProducts(query: query, pageSize: 15)
        }
        
        log.info("🧠 Using Claude for text-based nutrition search")
        
        // Use Claude to analyze the food query and return nutrition data
        let nutritionQuery = """
        Provide detailed nutrition information for "\(query)". Return the data as JSON with this exact format:
        {
          "food_name": "name of the food",
          "serving_size": "typical serving size",
          "carbohydrates": number (grams per serving),
          "protein": number (grams per serving),
          "fat": number (grams per serving),
          "calories": number (calories per serving)
        }
        
        If multiple foods match the query, provide information for the most common one. Use standard serving sizes (e.g., "1 medium apple", "1 cup cooked rice", "2 slices bread"). Focus on accuracy for diabetes carbohydrate counting.
        """
        
        do {
            // Create a placeholder image since Claude needs an image for the vision API
            let placeholderImage = createPlaceholderImage()
            let result = try await ClaudeFoodAnalysisService.shared.analyzeFoodImage(
                placeholderImage, 
                apiKey: key, 
                query: nutritionQuery
            )
            
            // Convert Claude analysis result to OpenFoodFactsProduct
            let syntheticID = "claude_\(abs(query.hashValue))"
            let nutriments = Nutriments(
                carbohydrates: result.totalCarbohydrates,
                proteins: result.totalProtein,
                fat: result.totalFat,
                calories: result.totalCalories,
                sugars: nil,
                fiber: result.totalFiber
            )
            
            let placeholderProduct = OpenFoodFactsProduct(
                id: syntheticID,
                productName: result.foodItems.first ?? query.capitalized,
                brands: "Claude AI Analysis",
                categories: nil,
                nutriments: nutriments,
                servingSize: result.foodItemsDetailed.first?.portionEstimate ?? "1 serving",
                servingQuantity: 100.0,
                imageURL: nil,
                imageFrontURL: nil,
                code: nil,
                dataSource: .aiAnalysis
            )
            
            return [placeholderProduct]
        } catch {
            log.error("❌ Claude search failed: %{public}@", error.localizedDescription)
            // Fall back to USDA if Claude fails
            return try await USDAFoodDataService.shared.searchProducts(query: query, pageSize: 15)
        }
    }
    
    private func searchWithOpenAI(query: String) async throws -> [OpenFoodFactsProduct] {
        // TODO: Implement OpenAI text search using natural language processing
        // This would involve sending the query to OpenAI and parsing the response
        log.info("🤖 OpenAI text search not yet implemented, falling back to OpenFoodFacts")
        return try await openFoodFactsService.searchProducts(query: query, pageSize: 15)
    }
    
    
    
    // MARK: Barcode Search Implementations
    
    
    
    // MARK: - Helper Methods
    
    /// Creates a small placeholder image for text-based Gemini queries
    private func createPlaceholderImage() -> UIImage {
        let size = CGSize(width: 100, height: 100)
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        
        // Create a simple gradient background
        let context = UIGraphicsGetCurrentContext()!
        let colors = [UIColor.systemBlue.cgColor, UIColor.systemGreen.cgColor]
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: nil)!
        
        context.drawLinearGradient(gradient, start: CGPoint.zero, end: CGPoint(x: size.width, y: size.height), options: [])
        
        // Add a food icon in the center
        let iconSize: CGFloat = 40
        let iconFrame = CGRect(
            x: (size.width - iconSize) / 2,
            y: (size.height - iconSize) / 2,
            width: iconSize,
            height: iconSize
        )
        
        context.setFillColor(UIColor.white.cgColor)
        context.fillEllipse(in: iconFrame)
        
        let image = UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
        UIGraphicsEndImageContext()
        
        return image
    }
}
