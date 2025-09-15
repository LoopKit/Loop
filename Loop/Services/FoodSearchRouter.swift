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
            
        case .claude, .googleGemini, .openAI:
            // Unify prompts: AI prompts live in AIFoodAnalysis.swift and are for image analysis only.
            // For text search, stick to structured databases for reliability.
            log.info("ℹ️ AI providers are not used for text search; using USDA with OFF fallback")
            do {
                return try await USDAFoodDataService.shared.searchProducts(query: query, pageSize: 15)
            } catch {
                return try await openFoodFactsService.searchProducts(query: query, pageSize: 15)
            }
        case .bringYourOwn:
            // BYO is not supported for text search; fall back to OpenFoodFacts
            log.info("⚠️ Bring Your Own is not available for text search; using OpenFoodFacts")
            return try await openFoodFactsService.searchProducts(query: query, pageSize: 15)
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
            
            
            
        case .claude, .openAI, .usdaFoodData, .googleGemini, .bringYourOwn:
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
            let query = "" // Always use centralized prompts from AIFoodAnalysis.swift
            guard !key.isEmpty else {
                throw AIFoodAnalysisError.noApiKey
            }
            return try await ClaudeFoodAnalysisService.shared.analyzeFoodImage(image, apiKey: key, query: query)
            
        case .openAI:
            let key = aiService.getAPIKey(for: .openAI) ?? ""
            let query = "" // Always use centralized prompts from AIFoodAnalysis.swift
            guard !key.isEmpty else {
                throw AIFoodAnalysisError.noApiKey
            }
            return try await OpenAIFoodAnalysisService.shared.analyzeFoodImage(image, apiKey: key, query: query)
            
            
            
        case .googleGemini:
            let key = UserDefaults.standard.googleGeminiAPIKey
            let query = "" // Always use centralized prompts from AIFoodAnalysis.swift
            guard !key.isEmpty else {
                throw AIFoodAnalysisError.noApiKey
            }
            return try await GoogleGeminiFoodAnalysisService.shared.analyzeFoodImage(image, apiKey: key, query: query)



        case .bringYourOwn:
            // Use OpenAI-compatible custom endpoint for image analysis
            // Prefer temporary BYO test override if enabled (DEBUG), else UserDefaults.
            let key: String
            let base: String
            let model: String?
            let version: String?
            let org: String?

            if BYOTestConfig.enabled {
                os_log("🧪 Using BYO test override configuration", log: log, type: .info)
                key = BYOTestConfig.apiKey
                base = BYOTestConfig.baseURL
                model = BYOTestConfig.model
                version = BYOTestConfig.apiVersion
                org = BYOTestConfig.organizationID
            } else {
                key = UserDefaults.standard.customAIAPIKey
                base = UserDefaults.standard.customAIBaseURL
                let m = UserDefaults.standard.customAIModel
                let v = UserDefaults.standard.customAIAPIVersion
                let o = UserDefaults.standard.customAIOrganization
                model = m.isEmpty ? nil : m
                version = v.isEmpty ? nil : v
                org = o.isEmpty ? nil : o
            }

            guard !key.isEmpty, !base.isEmpty else {
                throw AIFoodAnalysisError.noApiKey
            }

            return try await OpenAIFoodAnalysisService.shared.analyzeFoodImage(
                image,
                apiKey: key,
                query: "", // rely on internal optimized prompt
                baseURL: base,
                model: model,
                apiVersion: version,
                organizationID: org,
                customPath: {
                    let path = UserDefaults.standard.customAIEndpointPath.trimmingCharacters(in: .whitespacesAndNewlines)
                    return path.isEmpty ? nil : path
                }(),
                telemetryCallback: nil
            )

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

    // Removed AI-based text search implementations. Text search now uses OFF/USDA only.
    
    
    
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
