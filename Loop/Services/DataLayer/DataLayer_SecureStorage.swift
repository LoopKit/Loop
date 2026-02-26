//
//  DataLayer_SecureStorage.swift
//  Loop
//
//  DataLayer — Keychain storage for anonymized device ID and upload token.
//
//  Idea by Taylor Patterson. Coded by Claude Code.
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Foundation
import Security
import UIKit
import CryptoKit

/// Manages Keychain-stored secrets for the DataLayer.
/// Stores an anonymized device ID (SHA-256 hash of IDFV) and an optional upload token.
struct DataLayer_SecureStorage {

    // MARK: - Keychain Service & Account Keys

    private static let service = "com.loopkit.Loop.DataLayer"
    private static let deviceIDAccount = "anonymized_device_id"
    private static let uploadTokenAccount = "upload_token"

    // MARK: - Anonymized Device ID

    /// Returns a stable anonymized device ID (SHA-256 hash of IDFV).
    /// Generated once and cached in Keychain so it survives app reinstalls on same device.
    static var anonymizedDeviceID: String {
        if let cached = loadString(account: deviceIDAccount) {
            return cached
        }
        let raw = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        let hash = SHA256.hash(data: Data(raw.utf8))
        let hex = hash.compactMap { String(format: "%02x", $0) }.joined()
        let truncated = String(hex.prefix(32))
        try? saveString(truncated, account: deviceIDAccount)
        return truncated
    }

    // MARK: - Upload Token

    /// Save the upload bearer token received from device registration.
    static func saveUploadToken(_ token: String) throws {
        try saveString(token, account: uploadTokenAccount)
    }

    /// Load the upload bearer token.
    static func loadUploadToken() -> String? {
        return loadString(account: uploadTokenAccount)
    }

    /// Delete the upload token (on logout / data deletion).
    static func deleteUploadToken() {
        deleteItem(account: uploadTokenAccount)
    }

    /// Whether an upload token is stored.
    static var hasUploadToken: Bool {
        return loadUploadToken() != nil
    }

    // MARK: - Delete All

    /// Wipe all DataLayer Keychain entries.
    static func deleteAll() {
        deleteItem(account: deviceIDAccount)
        deleteItem(account: uploadTokenAccount)
    }

    // MARK: - Private Keychain Helpers

    private static func saveString(_ value: String, account: String) throws {
        guard let data = value.data(using: .utf8) else { return }
        deleteItem(account: account)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            DataLayer_FeatureFlags.log.error("Keychain save failed for \(account): \(status)")
            throw KeychainError.saveFailed(status)
        }
    }

    private static func loadString(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func deleteItem(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    enum KeychainError: Error {
        case saveFailed(OSStatus)
    }
}
