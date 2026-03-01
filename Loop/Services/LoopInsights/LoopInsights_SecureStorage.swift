//
//  LoopInsights_SecureStorage.swift
//  Loop
//
//  Concept & design by Taylor Patterson. Coded & tested by Claude Code in February 2026.
//  Copyright (c) 2025-2026 LoopKit Authors. All rights reserved.
//

import Foundation
import Security

/// Keychain wrapper for storing AI API keys and MFP credentials securely.
/// Shares the same Keychain entry as FoodFinder so users only configure once.
struct LoopInsights_SecureStorage {

    // Uses the same key name as FoodFinder for shared API key access
    private static let apiKeyService = "com.loopkit.Loop.AIServiceAPIKey"
    private static let apiKeyAccount = "ai_api_key"

    // MFP bearer token + user ID
    private static let mfpService = "com.loopkit.Loop.MFPAuth"
    private static let mfpTokenAccount = "mfp_access_token"
    private static let mfpUserIdAccount = "mfp_user_id"

    // MARK: - API Key

    static func saveAPIKey(_ key: String) throws {
        try saveKeychainItem(service: apiKeyService, account: apiKeyAccount, data: Data(key.utf8))
    }

    static func loadAPIKey() -> String? {
        guard let data = loadKeychainItem(service: apiKeyService, account: apiKeyAccount) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func deleteAPIKey() {
        deleteKeychainItem(service: apiKeyService, account: apiKeyAccount)
    }

    static var hasAPIKey: Bool {
        return loadAPIKey() != nil
    }

    // MARK: - MFP Authentication

    static func saveMFPAuth(_ auth: LoopInsights_MFPAuthData) throws {
        try saveKeychainItem(service: mfpService, account: mfpTokenAccount, data: Data(auth.accessToken.utf8))
        try saveKeychainItem(service: mfpService, account: mfpUserIdAccount, data: Data(auth.userId.utf8))
    }

    static func loadMFPAuth() -> LoopInsights_MFPAuthData? {
        guard let tokenData = loadKeychainItem(service: mfpService, account: mfpTokenAccount),
              let token = String(data: tokenData, encoding: .utf8),
              let userIdData = loadKeychainItem(service: mfpService, account: mfpUserIdAccount),
              let userId = String(data: userIdData, encoding: .utf8) else {
            return nil
        }
        return LoopInsights_MFPAuthData(userId: userId, accessToken: token)
    }

    static func deleteMFPAuth() {
        deleteKeychainItem(service: mfpService, account: mfpTokenAccount)
        deleteKeychainItem(service: mfpService, account: mfpUserIdAccount)
    }

    static var hasMFPAuth: Bool {
        return loadMFPAuth() != nil
    }

    // MARK: - Generic Keychain Helpers

    private static func saveKeychainItem(service: String, account: String, data: Data) throws {
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw LoopInsightsError.keychainError("Failed to save keychain item: \(status)")
        }
    }

    private static func loadKeychainItem(service: String, account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return data
    }

    private static func deleteKeychainItem(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
