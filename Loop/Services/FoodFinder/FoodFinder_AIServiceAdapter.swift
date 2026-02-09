//
//  AIServiceAdapter.swift
//  Loop
//
//  Created by Taylor Patterson on 9/30/25.
//  Copyright © 2025 LoopKit Authors. All rights reserved.
//

import Foundation
import UIKit
import os.log

/// Adapter that bridges between the new AIServiceManager and the existing AIFoodAnalysisService interface
class AIServiceAdapter {
    static let shared = AIServiceAdapter()
    
    private let log = OSLog(category: "AIServiceAdapter")
    private let settingsManager = AISettingsManager.shared
    private let aiServiceManager = AIServiceManager.shared
    
    private init() {}
    
    /// Analyze a food image using the active AI provider configuration
    /// - Parameters:
    ///   - image: The image to analyze
    ///   - query: Optional search query
    ///   - telemetryCallback: Callback for progress updates
    /// - Returns: AIFoodAnalysisResult with analysis
    func analyzeFoodImage(
        _ image: UIImage,
        query: String = "",
        telemetryCallback: ((String) -> Void)? = nil
    ) async throws -> AIFoodAnalysisResult {
        // Get the active configuration
        guard let config = try? await settingsManager.loadActiveConfiguration() else {
            throw AIFoodAnalysisError.configurationError("No active AI provider configuration")
        }
        
        telemetryCallback?("⚙️ Using \(config.name) for analysis...")
        
        do {
            // Use the new AIServiceManager to perform the analysis
            let result = try await aiServiceManager.analyzeFoodImage(
                image,
                using: config,
                query: query
            )
            
            telemetryCallback?("✅ Analysis complete")
            return result
            
        } catch {
            telemetryCallback?("❌ Analysis failed: \(error.localizedDescription)")
            throw error
        }
    }
    
    /// Test the connection to the active AI provider
    func testConnection() async -> AIServiceManager.TestConnectionResult {
        guard let config = try? await settingsManager.loadActiveConfiguration() else {
            return AIServiceManager.TestConnectionResult(success: false, statusCode: nil, message: "No active AI provider configuration", supportsVision: nil)
        }

        return await aiServiceManager.testConnection(to: config)
    }
    
    /// Get the active provider name for display
    func getActiveProviderName() async -> String {
        do {
            guard let config = try? await settingsManager.loadActiveConfiguration() else {
                return "No Active Provider"
            }
            return config.name
            
        } catch {
            log.error("Failed to get active provider: %{public}@", error.localizedDescription)
            return "Unknown Provider"
        }
    }
}

