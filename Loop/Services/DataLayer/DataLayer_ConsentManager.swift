//
//  DataLayer_ConsentManager.swift
//  Loop
//
//  DataLayer — Per-category consent tracking with audit trail.
//
//  Idea by Taylor Patterson. Coded by Claude Code.
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Foundation

/// Manages per-category consent state for the DataLayer.
/// All categories default to OFF. Consent changes are logged for audit trail.
final class DataLayer_ConsentManager: ObservableObject {

    static let shared = DataLayer_ConsentManager()

    // MARK: - Keys

    private enum Keys {
        static func consentKey(for category: DataLayer_ConsentCategory) -> String {
            return "DataLayer_consent_\(category.rawValue)"
        }
        static let consentLog = "DataLayer_consentLog"
    }

    private let defaults = UserDefaults.standard

    @Published private(set) var consentStates: [DataLayer_ConsentCategory: Bool] = [:]

    private init() {
        loadConsentStates()
    }

    // MARK: - Query

    /// Whether consent is granted for a specific category.
    func isGranted(for category: DataLayer_ConsentCategory) -> Bool {
        return consentStates[category] ?? false
    }

    /// Whether any category has consent granted.
    var hasAnyConsent: Bool {
        return consentStates.values.contains(true)
    }

    /// Number of categories with consent granted.
    var grantedCount: Int {
        return consentStates.values.filter { $0 }.count
    }

    // MARK: - Mutate

    /// Set consent for a specific category.
    func setConsent(for category: DataLayer_ConsentCategory, granted: Bool) {
        let key = Keys.consentKey(for: category)
        defaults.set(granted, forKey: key)
        consentStates[category] = granted

        // Log the change
        appendConsentLog(DataLayer_ConsentRecord(category: category, granted: granted))

        DataLayer_FeatureFlags.log.info("Consent \(granted ? "granted" : "revoked") for \(category.rawValue)")
    }

    /// Revoke all consent (used by "Delete All My Data").
    func revokeAll() {
        for category in DataLayer_ConsentCategory.allCases {
            setConsent(for: category, granted: false)
        }
        DataLayer_FeatureFlags.researchEnabled = false
    }

    // MARK: - Audit Log

    /// Load the full consent change log.
    func consentLog() -> [DataLayer_ConsentRecord] {
        guard let data = defaults.data(forKey: Keys.consentLog),
              let records = try? JSONDecoder().decode([DataLayer_ConsentRecord].self, from: data) else {
            return []
        }
        return records
    }

    // MARK: - Private

    private func loadConsentStates() {
        var states: [DataLayer_ConsentCategory: Bool] = [:]
        for category in DataLayer_ConsentCategory.allCases {
            let key = Keys.consentKey(for: category)
            states[category] = defaults.bool(forKey: key)
        }
        consentStates = states
    }

    private func appendConsentLog(_ record: DataLayer_ConsentRecord) {
        var log = consentLog()
        log.append(record)
        // Keep last 500 entries
        if log.count > 500 {
            log = Array(log.suffix(500))
        }
        if let data = try? JSONEncoder().encode(log) {
            defaults.set(data, forKey: Keys.consentLog)
        }
    }
}
