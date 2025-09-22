//
//  BYOTestConfig.swift
//  Loop
//
//  Temporary test override for Bring Your Own (BYO) AI provider
//  Populate values and set `enabled = true` in DEBUG builds while developing.
//  Do NOT ship real secrets in release builds.
//

import Foundation

// Toggle and credentials for BYO testing. Keep disabled by default.
// Enable only in local DEBUG builds when you want to bypass UI/UserDefaults.
enum BYOTestConfig {
    #if DEBUG
    static let enabled: Bool = false // Disabled now that BYO config is stable
    #else
    static let enabled: Bool = false // Always false in non-DEBUG builds
    #endif

    // Paste your temporary test configuration here when enabled
    // Example: "https://api.myproxy.example.com/v1"
    static let baseURL: String = "https:/"

    // Example: "sk-..."
    static let apiKey: String = ""

    // Optional model/version/org overrides for OpenAI-compatible endpoints
    // Leave empty to let the service use its defaults
    // Azure: this is the DEPLOYMENT name (not the base model name)
    static let model: String? = "gpt-4o-test"
    static let apiVersion: String? = "2024-12-01-preview"
    static let organizationID: String? = nil
}
