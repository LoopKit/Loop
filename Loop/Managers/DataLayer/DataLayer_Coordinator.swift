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

        DataLayer_FeatureFlags.log.info("DataLayer started — \(self.consent.grantedCount) categories consented")
    }

    /// Call when app enters background.
    func stop() {
        stopPolling()
        collector.endSession()
    }

    // MARK: - Data Deletion

    /// Delete all local DataLayer data and revoke all consent.
    /// Called from the "Delete All My Data" button in the consent view.
    func deleteAllData() {
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

    // MARK: - Polling

    /// Start the 5-minute polling timer for glucose/insulin/carb store data.
    /// Actual store polling will be wired in Phase 2+ when store references are available.
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
    /// Store references will be wired the same way LoopInsights_Coordinator does it —
    /// via the type-erased tuple from StatusTableViewController.
    private func pollStores() {
        guard DataLayer_FeatureFlags.isEnabled else { return }
        // Phase 3+: Poll glucose/insulin/carb stores and emit batch events
        // For now, this is a no-op placeholder. Feature hooks in Phase 2 handle
        // FoodFinder, LoopInsights, and AutoPresets events.
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
