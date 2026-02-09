//
//  AISettingsManager.swift
//  Loop
//
//  Created by Taylor Patterson on 9/30/25.
//  Copyright © 2025 LoopKit Authors. All rights reserved.
//

import Foundation
import os.log

class AISettingsManager {
    static let shared = AISettingsManager()
    private let log = OSLog(category: "AISettingsManager")
    
    private init() {}
    
    /// Loads the active AI provider configuration
    /// - Returns: The active AI provider configuration, or nil if none is set
    func loadActiveConfiguration() async throws -> AIProviderConfiguration? {
        return UserDefaults.standard.activeAIProviderConfiguration
    }
    
    /// Saves the active AI provider configuration
    /// - Parameter configuration: The configuration to set as active
    func saveActiveConfiguration(_ configuration: AIProviderConfiguration) async throws {
        var configs = UserDefaults.standard.aiProviderConfigurations
        
        // Update or add the configuration
        if let index = configs.firstIndex(where: { $0.id == configuration.id }) {
            configs[index] = configuration
        } else {
            configs.append(configuration)
        }
        
        // Save the updated configurations
        UserDefaults.standard.aiProviderConfigurations = configs
        
        // Set as active
        UserDefaults.standard.activeAIProviderConfigurationId = configuration.id
        
        log.debug("Saved active AI provider configuration: %{public}@", configuration.name)
    }
    
    /// Deletes an AI provider configuration
    /// - Parameter id: The ID of the configuration to delete
    func deleteConfiguration(id: String) async throws {
        var configs = UserDefaults.standard.aiProviderConfigurations
        configs.removeAll { $0.id == id }
        UserDefaults.standard.aiProviderConfigurations = configs
        
        // If the deleted config was active, clear the active config
        if UserDefaults.standard.activeAIProviderConfigurationId == id {
            UserDefaults.standard.activeAIProviderConfigurationId = nil
        }
        
        log.debug("Deleted AI provider configuration with ID: %{public}@", id)
    }
    
    /// Tests a connection to the AI provider with the given configuration
    /// - Parameter configuration: The configuration to test
    /// - Returns: Result with success/failure status and message
    func testConnection(to configuration: AIProviderConfiguration) async -> AIServiceManager.TestConnectionResult {
        return await AIServiceManager.shared.testConnection(to: configuration)
    }
}
