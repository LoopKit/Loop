//
//  FoodFinder_SecureStorage.swift
//  Loop
//
//  FoodFinder — Keychain wrapper for secure API key storage.
//
//  Idea by Taylor Patterson. Coded by Claude Code.
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Foundation
import Security

struct FoodFinder_SecureStorage {

    private static let service = "com.loopkit.loop.foodfinder"

    // MARK: - AI API Key

    static func saveAPIKey(_ key: String) throws {
        try save(key, account: "ai-api-key")
    }

    static func loadAPIKey() -> String? {
        return load(account: "ai-api-key")
    }

    static func deleteAPIKey() throws {
        try delete(account: "ai-api-key")
    }

    // MARK: - USDA API Key

    static func saveUSDAKey(_ key: String) throws {
        try save(key, account: "usda-api-key")
    }

    static func loadUSDAKey() -> String? {
        return load(account: "usda-api-key")
    }

    static func deleteUSDAKey() throws {
        try delete(account: "usda-api-key")
    }

    // MARK: - Generic Keychain Operations

    private static func save(_ value: String, account: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }

        // Delete existing item first (update = delete + add)
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Add new item
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    private static func load(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }

        return string
    }

    private static func delete(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }

    // MARK: - Errors

    enum KeychainError: LocalizedError {
        case encodingFailed
        case saveFailed(OSStatus)
        case deleteFailed(OSStatus)

        var errorDescription: String? {
            switch self {
            case .encodingFailed:
                return "Failed to encode API key for storage."
            case .saveFailed(let status):
                return "Keychain save failed (status: \(status))."
            case .deleteFailed(let status):
                return "Keychain delete failed (status: \(status))."
            }
        }
    }
}
