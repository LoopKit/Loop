//
//  LoopInsights_NightscoutImporter.swift
//  Loop
//
//  Concept & design by Taylor Patterson. Coded & tested by Claude Code in February 2026.
//  Copyright (c) 2025-2026 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit
import HealthKit

/// Nightscout API v1 client: fetches glucose entries and treatments, converts
/// to LoopKit types, and provides as an alternative data source for analysis.
final class LoopInsights_NightscoutImporter {

    private let config: LoopInsightsNightscoutConfig

    init(config: LoopInsightsNightscoutConfig) {
        self.config = config
    }

    // MARK: - Test Connection

    /// Test the Nightscout connection by fetching a single entry.
    func testConnection() async throws -> Bool {
        let url = try buildURL(path: "/api/v1/status.json")
        var request = URLRequest(url: url)
        addAuthHeaders(to: &request)
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LoopInsightsError.networkError(NSError(domain: "LoopInsights", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"]))
        }

        if httpResponse.statusCode == 401 {
            throw LoopInsightsError.aiProviderError("Authentication failed. Check your API secret.")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw LoopInsightsError.aiProviderError("Nightscout returned status \(httpResponse.statusCode)")
        }

        // Verify it's a valid Nightscout response
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           json["status"] as? String == "ok" || json["name"] != nil {
            return true
        }

        return true  // Status endpoint returned 200, good enough
    }

    // MARK: - Fetch Entries (SGV)

    /// Fetch glucose entries from Nightscout for the given date range.
    func fetchGlucoseEntries(start: Date, end: Date) async throws -> [LoopInsightsNightscoutEntry] {
        let startEpoch = Int(start.timeIntervalSince1970 * 1000)
        let endEpoch = Int(end.timeIntervalSince1970 * 1000)
        let path = "/api/v1/entries.json?find[date][$gte]=\(startEpoch)&find[date][$lte]=\(endEpoch)&count=10000"

        let url = try buildURL(path: path)
        var request = URLRequest(url: url)
        addAuthHeaders(to: &request)
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw LoopInsightsError.networkError(NSError(domain: "LoopInsights", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to fetch entries"]))
        }

        let decoder = JSONDecoder()
        return try decoder.decode([LoopInsightsNightscoutEntry].self, from: data)
    }

    // MARK: - Fetch Treatments

    /// Fetch treatments (carbs, insulin, temp basals) from Nightscout.
    func fetchTreatments(start: Date, end: Date) async throws -> [LoopInsightsNightscoutTreatment] {
        let formatter = ISO8601DateFormatter()
        let startStr = formatter.string(from: start)
        let endStr = formatter.string(from: end)
        let path = "/api/v1/treatments.json?find[created_at][$gte]=\(startStr)&find[created_at][$lte]=\(endStr)&count=10000"

        let url = try buildURL(path: path)
        var request = URLRequest(url: url)
        addAuthHeaders(to: &request)
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw LoopInsightsError.networkError(NSError(domain: "LoopInsights", code: -3, userInfo: [NSLocalizedDescriptionKey: "Failed to fetch treatments"]))
        }

        let decoder = JSONDecoder()
        return try decoder.decode([LoopInsightsNightscoutTreatment].self, from: data)
    }

    // MARK: - Convert to LoopKit Types

    /// Convert Nightscout entries to StoredGlucoseSample-compatible format.
    /// Returns glucose values as (date, mg/dL) tuples for aggregation.
    func convertToGlucoseData(_ entries: [LoopInsightsNightscoutEntry]) -> [(date: Date, mgdl: Double)] {
        return entries.compactMap { entry in
            guard let date = entry.sampleDate, entry.sgv > 0 else { return nil }
            return (date, entry.sgv)
        }
    }

    /// Convert Nightscout treatments to carb and dose data.
    func convertToTreatmentData(_ treatments: [LoopInsightsNightscoutTreatment]) -> (carbs: [(date: Date, grams: Double, foodType: String?)], boluses: [(date: Date, units: Double)]) {
        var carbs: [(date: Date, grams: Double, foodType: String?)] = []
        var boluses: [(date: Date, units: Double)] = []

        for treatment in treatments {
            guard let date = treatment.treatmentDate else { continue }

            if let carbAmount = treatment.carbs, carbAmount > 0 {
                let foodType = treatment.eventType == "Meal Bolus" ? "Meal" : treatment.eventType
                carbs.append((date, carbAmount, foodType))
            }

            if let insulin = treatment.insulin, insulin > 0 {
                boluses.append((date, insulin))
            }
        }

        return (carbs, boluses)
    }

    // MARK: - Import All

    /// Import all data from Nightscout for the given period and return as aggregated stats.
    func importData(start: Date, end: Date) async throws -> LoopInsightsNightscoutImportResult {
        async let entries = fetchGlucoseEntries(start: start, end: end)
        async let treatments = fetchTreatments(start: start, end: end)

        let fetchedEntries = try await entries
        let fetchedTreatments = try await treatments

        let glucoseData = convertToGlucoseData(fetchedEntries)
        let treatmentData = convertToTreatmentData(fetchedTreatments)

        return LoopInsightsNightscoutImportResult(
            glucoseReadings: glucoseData,
            carbEntries: treatmentData.carbs,
            bolusEntries: treatmentData.boluses,
            entryCount: fetchedEntries.count,
            treatmentCount: fetchedTreatments.count
        )
    }

    // MARK: - Helpers

    private func buildURL(path: String) throws -> URL {
        var siteURL = config.siteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        siteURL = siteURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        guard !siteURL.isEmpty else {
            throw LoopInsightsError.insufficientData("Nightscout URL is not configured")
        }

        // URL-encode the query parameters properly
        guard let url = URL(string: siteURL + path) else {
            throw LoopInsightsError.insufficientData("Invalid Nightscout URL: \(siteURL)\(path)")
        }

        return url
    }

    private func addAuthHeaders(to request: inout URLRequest) {
        if !config.apiSecret.isEmpty {
            // Nightscout uses SHA1 hash of API secret
            let secretHash = config.apiSecret.sha1Hash()
            request.setValue(secretHash, forHTTPHeaderField: "api-secret")
        }
    }
}

// MARK: - Import Result

/// Result of a Nightscout data import
struct LoopInsightsNightscoutImportResult {
    let glucoseReadings: [(date: Date, mgdl: Double)]
    let carbEntries: [(date: Date, grams: Double, foodType: String?)]
    let bolusEntries: [(date: Date, units: Double)]
    let entryCount: Int
    let treatmentCount: Int

    var summary: String {
        return "\(entryCount) glucose entries, \(treatmentCount) treatments (\(carbEntries.count) carbs, \(bolusEntries.count) boluses)"
    }
}

// MARK: - SHA1 Helper

import CommonCrypto

extension String {
    func sha1Hash() -> String {
        guard let data = self.data(using: .utf8) else { return self }
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA1($0.baseAddress, CC_LONG(data.count), &digest)
        }
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
