//
//  AIProviderConfiguration.swift
//  Loop
//
//  Created by Taylor Patterson on 9/30/25.
//  Copyright © 2025 LoopKit Authors. All rights reserved.
//

import Foundation

// MARK: - Authentication Type

/// Authentication types supported by AI providers
enum AuthType: String, CaseIterable, Codable, Equatable {
    case bearer = "Bearer Token"
    case apiKey = "API Key Header"
    case custom = "Custom Header"

    /// The header field name for this auth type
    var headerField: String {
        switch self {
        case .bearer:
            return "Authorization"
        case .apiKey:
            return "x-api-key"
        case .custom:
            return "Custom"
        }
    }
}

// MARK: - AI Provider Configuration

/// Configuration for an AI provider that can be used for food analysis
struct AIProviderConfiguration: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var baseURL: String
    var model: String
    var apiKey: String
    var endpointPath: String
    var authType: AuthType
    var requestTemplate: String
    var responseKeyPath: String
    var supportsVision: Bool
    var headers: [String: String]
    var testEndpointPath: String?
    var apiVersion: String?
    var organizationID: String?
    // Custom auth fields (used when authType == .custom)
    var customHeaderName: String?
    var customHeaderValue: String?

    init(
        id: String = UUID().uuidString,
        name: String,
        baseURL: String,
        model: String,
        apiKey: String,
        endpointPath: String = "/v1/chat/completions",
        authType: AuthType = .bearer,
        requestTemplate: String = AIProviderConfiguration.openAITemplate,
        responseKeyPath: String = "choices.0.message.content",
        supportsVision: Bool = true,
        headers: [String: String] = ["Content-Type": "application/json"],
        testEndpointPath: String? = nil,
        apiVersion: String? = nil,
        organizationID: String? = nil,
        customHeaderName: String? = nil,
        customHeaderValue: String? = nil
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.model = model
        self.apiKey = apiKey
        self.endpointPath = endpointPath
        self.authType = authType
        self.requestTemplate = requestTemplate
        self.responseKeyPath = responseKeyPath
        self.supportsVision = supportsVision
        self.headers = headers
        self.testEndpointPath = testEndpointPath
        self.apiVersion = apiVersion
        self.organizationID = organizationID
        self.customHeaderName = customHeaderName
        self.customHeaderValue = customHeaderValue
    }

    // MARK: - Request Templates

    /// OpenAI-compatible request template for vision models
    static let openAITemplate = """
{
  "model": "{{MODEL}}",
  "messages": [
    {
      "role": "user",
      "content": [
        {
          "type": "text",
          "text": "{{PROMPT}}"
        },
        {
          "type": "image_url",
          "image_url": {
            "url": "data:image/jpeg;base64,{{IMAGE_BASE64}}"
          }
        }
      ]
    }
  ],
  "max_tokens": 4096
}
"""

    /// Claude/Anthropic request template for vision
    static let claudeTemplate = """
{
  "model": "{{MODEL}}",
  "max_tokens": 4096,
  "messages": [
    {
      "role": "user",
      "content": [
        {
          "type": "image",
          "source": {
            "type": "base64",
            "media_type": "image/jpeg",
            "data": "{{IMAGE_BASE64}}"
          }
        },
        {
          "type": "text",
          "text": "{{PROMPT}}"
        }
      ]
    }
  ]
}
"""

    /// Google Gemini request template
    static let geminiTemplate = """
{
  "contents": [
    {
      "parts": [
        {
          "text": "{{PROMPT}}"
        },
        {
          "inline_data": {
            "mime_type": "image/jpeg",
            "data": "{{IMAGE_BASE64}}"
          }
        }
      ]
    }
  ],
  "generationConfig": {
    "maxOutputTokens": 4096
  }
}
"""
}

// MARK: - UserDefaults Extension

extension UserDefaults {
    private enum AIConfigKey: String {
        case aiProviderConfigurations = "com.loopkit.Loop.aiProviderConfigurations"
        case activeAIProviderConfigurationId = "com.loopkit.Loop.activeAIProviderConfigurationId"
    }

    /// All stored AI provider configurations
    var aiProviderConfigurations: [AIProviderConfiguration] {
        get {
            guard let data = data(forKey: AIConfigKey.aiProviderConfigurations.rawValue) else {
                return []
            }
            let decoder = JSONDecoder()
            return (try? decoder.decode([AIProviderConfiguration].self, from: data)) ?? []
        }
        set {
            let encoder = JSONEncoder()
            if let data = try? encoder.encode(newValue) {
                set(data, forKey: AIConfigKey.aiProviderConfigurations.rawValue)
            }
        }
    }

    /// The ID of the currently active AI provider configuration
    var activeAIProviderConfigurationId: String? {
        get {
            return string(forKey: AIConfigKey.activeAIProviderConfigurationId.rawValue)
        }
        set {
            set(newValue, forKey: AIConfigKey.activeAIProviderConfigurationId.rawValue)
        }
    }

    /// The currently active AI provider configuration (computed from ID)
    var activeAIProviderConfiguration: AIProviderConfiguration? {
        guard let activeId = activeAIProviderConfigurationId else {
            return nil
        }
        return aiProviderConfigurations.first { $0.id == activeId }
    }
}
