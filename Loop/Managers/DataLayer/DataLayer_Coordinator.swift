//
//  DataLayer_Coordinator.swift
//  Loop
//
//  DataLayer — Singleton coordinator. Wires event collection, consent, and polling.
//
//  Idea by Taylor Patterson. Coded by Claude Code.
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit

/// Main coordinator for the DataLayer health data sharing platform.
/// Singleton pattern following LoopInsights_Coordinator.
/// Manages event collection lifecycle and data store polling.
final class DataLayer_Coordinator: ObservableObject {

    static let shared = DataLayer_Coordinator()

    // MARK: - Properties

    private let collector = DataLayer_EventCollector.shared
    private let consent = DataLayer_ConsentManager.shared
    private var pollTimer: Timer?
    private static let pollInterval: TimeInterval = 300 // 5 minutes

    /// Type-erased store references: (GlucoseStoreProtocol, DoseStoreProtocol, CarbStoreProtocol)
    /// Set once from StatusTableViewController when Settings is first opened.
    private var glucoseStore: AnyObject?
    private var doseStore: AnyObject?
    private var carbStore: AnyObject?
    private var lastPollDate: Date?

    // MARK: - Initialization

    private init() {
        observeFeatureNotifications()
        DataLayer_FeatureFlags.log.info("DataLayer_Coordinator initialized")
    }

    // MARK: - Lifecycle

    /// Call on app launch to start event collection if enabled.
    func start() {
        guard DataLayer_FeatureFlags.isEnabled else {
            DataLayer_FeatureFlags.log.info("DataLayer disabled, not starting")
            return
        }

        collector.startSession()
        startPolling()
        DataLayer_SyncService.shared.start()

        DataLayer_FeatureFlags.log.info("DataLayer started — \(self.consent.grantedCount) categories consented")
    }

    /// Call when app enters background.
    func stop() {
        stopPolling()
        DataLayer_SyncService.shared.stop()
        collector.endSession()
    }

    // MARK: - Data Deletion

    /// Delete all local DataLayer data and revoke all consent.
    /// Called from the "Delete All My Data" button in the consent view.
    func deleteAllData() {
        // Stop uploads
        DataLayer_SyncService.shared.stop()

        // Revoke all consent
        consent.revokeAll()

        // Wipe local SQLite store
        collector.eventStore.deleteAll()

        // Clear secure storage
        DataLayer_SecureStorage.deleteAll()

        // Disable the feature
        DataLayer_FeatureFlags.isEnabled = false
        DataLayer_FeatureFlags.researchEnabled = false

        DataLayer_FeatureFlags.log.info("All DataLayer data deleted")
    }

    // MARK: - Store Configuration

    /// Configure store references for polling. Called once from StatusTableViewController.
    /// Uses the same store objects that LoopInsights uses — no extra LoopKit integration.
    func configureStores(glucose: AnyObject, dose: AnyObject, carb: AnyObject) {
        self.glucoseStore = glucose
        self.doseStore = dose
        self.carbStore = carb
        DataLayer_FeatureFlags.log.info("DataLayer stores configured for polling")
    }

    // MARK: - Polling

    /// Start the 5-minute polling timer for glucose/insulin/carb store data.
    private func startPolling() {
        stopPolling()
        pollTimer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            self?.pollStores()
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    /// Poll Loop data stores for new glucose, insulin, and carb data.
    /// Queries since last poll (or last 5 minutes on first run). Silently no-ops if stores aren't configured.
    private func pollStores() {
        guard DataLayer_FeatureFlags.isEnabled else { return }
        guard glucoseStore != nil || doseStore != nil || carbStore != nil else { return }

        let end = Date()
        let start = lastPollDate ?? end.addingTimeInterval(-Self.pollInterval)
        lastPollDate = end

        pollGlucose(start: start, end: end)
        pollInsulin(start: start, end: end)
        pollCarbs(start: start, end: end)
    }

    // MARK: - Glucose Polling

    private func pollGlucose(start: Date, end: Date) {
        guard consent.isGranted(for: .glucose) else { return }
        guard let store = glucoseStore as? GlucoseStoreProtocol else { return }

        store.getGlucoseSamples(start: start, end: end) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let samples) where !samples.isEmpty:
                let readings = samples.map { sample in
                    DataLayer_GlucoseSamplePayload.GlucoseReading(
                        timestamp: sample.startDate,
                        mgdl: sample.quantity.doubleValue(for: .milligramsPerDeciliter),
                        trend: sample.trend?.symbol
                    )
                }
                self.collector.record(type: .glucoseSample, payload: DataLayer_GlucoseSamplePayload(readings: readings))
            default:
                break
            }
        }
    }

    // MARK: - Insulin Polling

    private func pollInsulin(start: Date, end: Date) {
        guard consent.isGranted(for: .insulin) else { return }
        guard let store = doseStore as? DoseStoreProtocol else { return }

        store.getNormalizedDoseEntries(start: start, end: end) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let entries) where !entries.isEmpty:
                let deliveries = entries.map { entry in
                    DataLayer_InsulinDeliveryPayload.Delivery(
                        startDate: entry.startDate,
                        endDate: entry.endDate,
                        units: entry.deliveredUnits ?? entry.programmedUnits,
                        type: entry.type.pumpEventType.rawValue,
                        isAutomatic: entry.automatic ?? false
                    )
                }
                self.collector.record(type: .insulinDelivery, payload: DataLayer_InsulinDeliveryPayload(deliveries: deliveries))
            default:
                break
            }
        }
    }

    // MARK: - Carb Polling

    private func pollCarbs(start: Date, end: Date) {
        guard consent.isGranted(for: .carbsAndMeals) else { return }
        guard let store = carbStore as? CarbStoreProtocol else { return }
        // CarbStoreProtocol doesn't expose getCarbEntries; cast to concrete CarbStore
        guard let concreteStore = store as? CarbStore else { return }

        concreteStore.getCarbEntries(start: start, end: end) { [weak self] (result: CarbStoreResult<[StoredCarbEntry]>) in
            guard let self = self else { return }
            switch result {
            case .success(let entries) where !entries.isEmpty:
                let carbEntries = entries.map { entry in
                    DataLayer_CarbEntryPayload.Entry(
                        date: entry.startDate,
                        grams: entry.quantity.doubleValue(for: .gram()),
                        absorptionTimeMinutes: entry.absorptionTime.map { $0 / 60.0 },
                        foodType: entry.foodType
                    )
                }
                self.collector.record(type: .carbEntry, payload: DataLayer_CarbEntryPayload(entries: carbEntries))
            default:
                break
            }
        }
    }

    // MARK: - Feature Notification Observers

    /// Feature files may be in different compilation modules, so we use notifications
    /// instead of direct DataLayer calls (same pattern as .foodFinderMealLogged).
    private func observeFeatureNotifications() {
        observeFoodFinderNotifications()
        observeSuggestionNotifications()
        observeCaffeineNotifications()
        observeAlcoholNotifications()
        observeAutoPresetsNotifications()
    }

    private func observeFoodFinderNotifications() {
        NotificationCenter.default.addObserver(
            forName: Notification.Name("com.loopkit.Loop.foodFinderMealAnalyzed"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            guard let info = notification.userInfo,
                  let analysisType = info["analysisType"] as? String,
                  let foodName = info["foodName"] as? String,
                  let carbsGrams = info["carbsGrams"] as? Double,
                  let absorptionTimeHours = info["absorptionTimeHours"] as? Double,
                  let itemCount = info["itemCount"] as? Int else { return }
            self.collector.record(type: .mealAnalysis, payload: DataLayer_MealAnalysisPayload(
                analysisType: analysisType,
                foodName: foodName,
                carbsGrams: carbsGrams,
                originalAICarbs: info["originalAICarbs"] as? Double,
                aiConfidencePercent: info["aiConfidencePercent"] as? Int,
                proteinGrams: info["proteinGrams"] as? Double,
                fatGrams: info["fatGrams"] as? Double,
                fiberGrams: info["fiberGrams"] as? Double,
                calories: info["calories"] as? Double,
                absorptionTimeHours: absorptionTimeHours,
                locationName: info["locationName"] as? String,
                itemCount: itemCount
            ))
        }

        NotificationCenter.default.addObserver(
            forName: Notification.Name("com.loopkit.Loop.foodFinderMealConfirmedForDataLayer"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            guard let info = notification.userInfo,
                  let mealEventID = info["mealEventID"] as? String,
                  let finalCarbsGrams = info["finalCarbsGrams"] as? Double else { return }
            self.collector.record(type: .mealConfirmed, payload: DataLayer_MealConfirmedPayload(
                mealEventID: mealEventID,
                finalCarbsGrams: finalCarbsGrams,
                carbDeltaFromAI: info["carbDeltaFromAI"] as? Double
            ))
        }
    }

    private func observeSuggestionNotifications() {
        NotificationCenter.default.addObserver(
            forName: Notification.Name("com.loopkit.Loop.loopInsightsSuggestionEvent"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            guard let info = notification.userInfo,
                  let action = info["action"] as? String,
                  let settingType = info["settingType"] as? String,
                  let timeBlockCount = info["timeBlockCount"] as? Int,
                  let confidenceLevel = info["confidenceLevel"] as? String,
                  let analysisPeriodDays = info["analysisPeriodDays"] as? Int else { return }

            let eventType: DataLayer_EventType
            switch action {
            case "generated": eventType = .aiSuggestionGenerated
            case "applied":   eventType = .aiSuggestionApplied
            case "dismissed": eventType = .aiSuggestionDismissed
            case "reverted":  eventType = .aiSuggestionReverted
            default: return
            }

            self.collector.record(type: eventType, payload: DataLayer_AISuggestionPayload(
                settingType: settingType,
                timeBlockCount: timeBlockCount,
                confidenceLevel: confidenceLevel,
                applyMode: info["applyMode"] as? String,
                analysisPeriodDays: analysisPeriodDays
            ))
        }
    }

    private func observeCaffeineNotifications() {
        NotificationCenter.default.addObserver(
            forName: Notification.Name("com.loopkit.Loop.loopInsightsCaffeineLogged"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            guard let userInfo = notification.userInfo,
                  let milligrams = userInfo["milligrams"] as? Double,
                  let source = userInfo["source"] as? String,
                  let currentLevelMg = userInfo["currentLevelMg"] as? Double else { return }
            self.collector.record(type: .caffeineLogged, payload: DataLayer_CaffeineLoggedPayload(
                milligrams: milligrams,
                source: source,
                currentLevelMg: currentLevelMg
            ))
        }
    }

    private func observeAlcoholNotifications() {
        NotificationCenter.default.addObserver(
            forName: Notification.Name("com.loopkit.Loop.loopInsightsAlcoholLogged"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            guard let userInfo = notification.userInfo,
                  let standardDrinks = userInfo["standardDrinks"] as? Double,
                  let source = userInfo["source"] as? String,
                  let currentLevel = userInfo["currentLevel"] as? Double,
                  let hypoRiskLevel = userInfo["hypoRiskLevel"] as? String else { return }
            self.collector.record(type: .alcoholLogged, payload: DataLayer_AlcoholLoggedPayload(
                standardDrinks: standardDrinks,
                source: source,
                currentLevel: currentLevel,
                hypoRiskLevel: hypoRiskLevel
            ))
        }
    }

    private func observeAutoPresetsNotifications() {
        NotificationCenter.default.addObserver(
            forName: Notification.Name("com.loopkit.Loop.autoPresetsPresetActivated"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            guard let userInfo = notification.userInfo,
                  let activityType = userInfo["activityType"] as? String,
                  let presetName = userInfo["presetName"] as? String else { return }
            self.collector.record(type: .presetActivated, payload: DataLayer_PresetEventPayload(
                activityType: activityType,
                presetName: presetName,
                durationMinutes: nil
            ))
        }

        NotificationCenter.default.addObserver(
            forName: Notification.Name("com.loopkit.Loop.autoPresetsPresetDeactivated"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            guard let userInfo = notification.userInfo,
                  let activityType = userInfo["activityType"] as? String,
                  let presetName = userInfo["presetName"] as? String else { return }
            self.collector.record(type: .presetDeactivated, payload: DataLayer_PresetEventPayload(
                activityType: activityType,
                presetName: presetName,
                durationMinutes: nil
            ))
        }
    }

    // MARK: - Debug

    /// Total number of events in the local store.
    var totalEventCount: Int {
        return collector.eventStore.eventCount()
    }

    /// Event count for a specific type.
    func eventCount(for type: DataLayer_EventType) -> Int {
        return collector.eventStore.eventCount(type: type)
    }
}
