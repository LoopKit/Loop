//
//  LoopInsights_Coordinator.swift
//  Loop
//
//  Concept & design by Taylor Patterson. Coded & tested by Claude Code in February 2026.
//  Copyright (c) 2025-2026 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit
import HealthKit

/// Orchestrates all LoopInsights services and manages the feature lifecycle.
/// Created when LoopInsights is accessed from Settings. Owns the DataAggregator,
/// SuggestionStore, and AIAnalysis service, and provides the data access bridge
/// between Loop's stores and LoopInsights' analysis engine.
final class LoopInsights_Coordinator: ObservableObject {

    // MARK: - Services

    let dataAggregator: LoopInsights_DataAggregator
    let aiAnalysis: LoopInsights_AIAnalysis
    let suggestionStore: LoopInsights_SuggestionStore

    // MARK: - Data Provider Bridge

    private var dataProviderBridge: DataProviderBridge?

    /// Retained reference to test data provider (when using fixtures).
    private var testDataProvider: LoopInsights_TestDataProvider?

    // MARK: - Initialization

    /// Initialize with Loop's existing store references.
    /// The coordinator only reads from these stores — it never writes glucose, dose, or carb data.
    init(
        glucoseStore: GlucoseStoreProtocol,
        doseStore: DoseStoreProtocol,
        carbStore: CarbStoreProtocol,
        settingsProvider: LatestStoredSettingsProvider
    ) {
        let bridge = DataProviderBridge(
            glucoseStore: glucoseStore,
            doseStore: doseStore,
            carbStore: carbStore,
            settingsProvider: settingsProvider
        )
        self.dataProviderBridge = bridge
        self.dataAggregator = LoopInsights_DataAggregator(dataProvider: bridge)
        self.aiAnalysis = LoopInsights_AIAnalysis()
        self.suggestionStore = LoopInsights_SuggestionStore.shared
    }

    /// Initialize with test data fixtures (for simulator/developer mode).
    /// Loads JSON fixtures from Documents/LoopInsights/ or the app bundle.
    init(testDataProvider: LoopInsights_TestDataProvider) {
        self.testDataProvider = testDataProvider
        self.dataProviderBridge = nil
        self.dataAggregator = LoopInsights_DataAggregator(dataProvider: testDataProvider)
        self.aiAnalysis = LoopInsights_AIAnalysis()
        self.suggestionStore = LoopInsights_SuggestionStore.shared
    }

    /// Factory method: creates a Coordinator with test data if available and enabled,
    /// otherwise returns nil (caller should fall back to real stores).
    static func withTestDataIfAvailable() -> LoopInsights_Coordinator? {
        guard LoopInsights_FeatureFlags.useTestData else { return nil }

        let provider = LoopInsights_TestDataProvider()
        guard provider.hasTestData else {
            print("[LoopInsights] Test data mode enabled but no fixtures found")
            return nil
        }

        print("[LoopInsights] Using test data: \(provider.dataSummary)")
        return LoopInsights_Coordinator(testDataProvider: provider)
    }

    // MARK: - Therapy Settings Write Access

    /// Reference to settings provider for write operations (one-tap apply)
    private var settingsProvider: LatestStoredSettingsProvider? {
        return dataProviderBridge?.settingsProvider
    }

    /// Capture a snapshot of the current therapy settings
    func captureCurrentSnapshot() throws -> LoopInsightsTherapySnapshot {
        return try dataAggregator.captureTherapySnapshot()
    }
}

// MARK: - Data Provider Bridge

/// Bridges Loop's concrete store types to the LoopInsightsDataProviderProtocol.
/// This keeps LoopInsights decoupled from the specific store implementations.
private final class DataProviderBridge: LoopInsightsDataProviderProtocol {

    private let glucoseStore: GlucoseStoreProtocol
    private let doseStore: DoseStoreProtocol
    private let carbStore: CarbStoreProtocol
    fileprivate let settingsProvider: LatestStoredSettingsProvider

    init(
        glucoseStore: GlucoseStoreProtocol,
        doseStore: DoseStoreProtocol,
        carbStore: CarbStoreProtocol,
        settingsProvider: LatestStoredSettingsProvider
    ) {
        self.glucoseStore = glucoseStore
        self.doseStore = doseStore
        self.carbStore = carbStore
        self.settingsProvider = settingsProvider
    }

    func getGlucoseSamples(start: Date, end: Date) async throws -> [StoredGlucoseSample] {
        return try await withCheckedThrowingContinuation { continuation in
            glucoseStore.getGlucoseSamples(start: start, end: end) { result in
                continuation.resume(with: result)
            }
        }
    }

    func getCarbEntries(start: Date, end: Date) async throws -> [StoredCarbEntry] {
        // CarbStoreProtocol doesn't expose getCarbEntries; cast to concrete CarbStore
        guard let store = carbStore as? CarbStore else {
            throw LoopInsightsError.insufficientData("CarbStore not available")
        }
        return try await withCheckedThrowingContinuation { continuation in
            store.getCarbEntries(start: start, end: end) { result in
                switch result {
                case .success(let entries):
                    continuation.resume(returning: entries)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func getNormalizedDoseEntries(start: Date, end: Date) async throws -> [DoseEntry] {
        return try await withCheckedThrowingContinuation { continuation in
            doseStore.getNormalizedDoseEntries(start: start, end: end) { result in
                switch result {
                case .success(let entries):
                    continuation.resume(returning: entries)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func getLatestStoredSettings() -> StoredSettings {
        return settingsProvider.latestSettings
    }
}
