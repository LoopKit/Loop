//
//  FoodFinder_SearchRouter.swift
//  Loop
//
//  FoodFinder — Routes food search queries to the appropriate data source.
//
//  Idea by Taylor Patterson. Coded by Claude Code.
//  Copyright © 2026 LoopKit Authors. All rights reserved.
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

        switch provider {
        case .openFoodFacts:
            return try await openFoodFactsService.searchProducts(query: query, pageSize: 15)

        case .usdaFoodData:
            do {
                return try await USDAFoodDataService.shared.searchProducts(query: query, pageSize: 15)
            } catch {
                log.error("❌ USDA search failed: %{public}@ — falling back to OpenFoodFacts", error.localizedDescription)
                return try await openFoodFactsService.searchProducts(query: query, pageSize: 15)
            }

        case .aiProvider:
            // AI providers are not used for text search; use USDA with OFF fallback
            log.info("ℹ️ AI provider not used for text search; using USDA with OFF fallback")
            do {
                return try await USDAFoodDataService.shared.searchProducts(query: query, pageSize: 15)
            } catch {
                return try await openFoodFactsService.searchProducts(query: query, pageSize: 15)
            }
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

        case .usdaFoodData, .aiProvider:
            // These providers don't support barcode search, fall back to OpenFoodFacts
            log.info("⚠️ %{public}@ doesn't support barcode search, falling back to OpenFoodFacts", provider.rawValue)
            return try await openFoodFactsService.fetchProduct(barcode: barcode)
        }
    }

    // MARK: - AI Image Search Routing

    /// Perform AI image analysis using the configured BYO provider
    func analyzeFood(image: UIImage) async throws -> AIFoodAnalysisResult {
        log.info("🤖 Routing AI image analysis to configured BYO provider")

        guard let config = UserDefaults.standard.activeAIProviderConfiguration else {
            throw AIFoodAnalysisError.noApiKey
        }
        guard !config.apiKey.isEmpty else {
            throw AIFoodAnalysisError.noApiKey
        }

        let prompt = getAnalysisPrompt()
        return try await AIServiceManager.shared.analyzeFoodImage(
            image,
            using: config,
            query: prompt
        )
    }

    // MARK: - Voice / Generative Text Search Routing

    /// Perform AI-based food analysis from a text description (voice search).
    /// Routes through the same AI provider and prompt infrastructure as image analysis,
    /// using a placeholder image with the user's description as context.
    func analyzeFoodByDescription(_ description: String) async throws -> AIFoodAnalysisResult {
        let basePrompt = getAnalysisPrompt()
        let locationContext = FoodFinder_LocationService.shared.locationContextForPrompt()
        let voiceContext = "\(basePrompt)\(locationContext)\n\nThe user described their food verbally: \"\(description)\". There is no photo — analyze the food based solely on this text description. Provide the same detailed nutritional analysis you would for a food photo."

        log.info("🎙️ Routing voice/generative search '%{public}@' to configured BYO provider", description)

        guard let config = UserDefaults.standard.activeAIProviderConfiguration else {
            throw AIFoodAnalysisError.noApiKey
        }
        guard !config.apiKey.isEmpty else {
            throw AIFoodAnalysisError.noApiKey
        }

        return try await AIServiceManager.shared.analyzeFoodByText(
            using: config,
            query: voiceContext
        )
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
