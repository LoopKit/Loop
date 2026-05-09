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
        DataLayer_FeatureFlags.registerDefaultsIfNeeded()
        observeFeatureNotifications()

        // BolusPro — register UserDefaults defaults and start the
        // BehaviorAnalyzer observer. This is the central app-launch
        // wiring point; piggy-backing on the DataLayer singleton init
        // keeps BolusPro out of AppDelegate / LoopAppManager.
        BolusPro_FeatureFlags.registerDefaults()
        BolusPro_BehaviorAnalyzer.shared.start()

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
        pollBiometrics()
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
        observeBarcodeNotifications()
        observeChatNotifications()
        observeMealDebriefNotifications()
        observeTherapySettingsNotifications()
        observeOverrideNotifications()
        observeActivityDetectedNotifications()
        observeBolusProNotifications()
        observeGraphDetailViewNotifications()
        observeSiteAtlasNotifications()
    }

    /// GraphDetailView broadcasts when its long-press detail popup appears.
    /// Translate to a DataLayer event so the dashboard's Feature Adoption
    /// block sees real GraphDetailView usage data.
    private func observeGraphDetailViewNotifications() {
        NotificationCenter.default.addObserver(
            forName: Notification.Name("com.loopkit.Loop.graphDetailViewOpened"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let info = notification.userInfo
            else { return }

            let payload = DataLayer_GraphDetailViewOpenedPayload(
                hasGlucose:    (info["hasGlucose"]    as? Bool) ?? false,
                hasIOB:        (info["hasIOB"]        as? Bool) ?? false,
                hasCOB:        (info["hasCOB"]        as? Bool) ?? false,
                hasBolus:      (info["hasBolus"]      as? Bool) ?? false,
                hasBasalRate:  (info["hasBasalRate"]  as? Bool) ?? false,
                hasPreset:     (info["hasPreset"]     as? Bool) ?? false,
                hasAutoPreset: (info["hasAutoPreset"] as? Bool) ?? false,
                hasHeartRate:  (info["hasHeartRate"]  as? Bool) ?? false
            )
            self.collector.record(type: .graphDetailViewOpened, payload: payload)
        }
    }

    /// SiteAtlas broadcasts when a new site entry is added. Translate to
    /// a DataLayer event with type/bodySide/zone for the dashboard.
    private func observeSiteAtlasNotifications() {
        NotificationCenter.default.addObserver(
            forName: Notification.Name("com.loopkit.Loop.siteAtlasPlaced"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let info = notification.userInfo,
                  let type = info["type"] as? String,
                  let bodySide = info["bodySide"] as? String
            else { return }

            let payload = DataLayer_SiteAtlasPlacedPayload(
                type: type,
                bodySide: bodySide,
                zoneID: info["zoneID"] as? String,
                replacementOfHidden: (info["replacementOfHidden"] as? Bool) ?? false
            )
            self.collector.record(type: .siteAtlasPlaced, payload: payload)
        }
    }

    /// BolusPro broadcasts a snapshot every time a BolusPro-aware carb
    /// entry is saved (toggle on or off). Translate to a DataLayer event
    /// here so the BolusPro feature itself stays decoupled from DataLayer.
    private func observeBolusProNotifications() {
        NotificationCenter.default.addObserver(
            forName: BolusPro_DataLayerHook.notificationName,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let snapshot = notification.userInfo?[BolusPro_DataLayerHook.snapshotUserInfoKey] as? BolusProAnalyticsSnapshot
            else { return }

            let payload = DataLayer_BolusProPayload(
                enabled: snapshot.enabled,
                autoDetected: snapshot.autoDetected,
                macrosSource: snapshot.macrosSource?.rawValue,
                fpuScore: snapshot.fpuScore,
                bonusGrams: snapshot.bonusGrams,
                sliderPosition: snapshot.sliderPosition,
                coverageFactorPercent: snapshot.coverageFactorPercent,
                fpuDelayMinutes: snapshot.fpuDelayMinutes,
                fpuAbsorptionHours: snapshot.fpuAbsorptionHours,
                fatGramsInput: snapshot.fatGramsInput,
                proteinGramsInput: snapshot.proteinGramsInput,
                primaryCarbGrams: snapshot.primaryCarbGrams
            )
            self.collector.record(type: .bolusProEntry, payload: payload)
        }
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

    private func observeBarcodeNotifications() {
        NotificationCenter.default.addObserver(
            forName: Notification.Name("com.loopkit.Loop.foodFinderBarcodeScanned"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            guard let info = notification.userInfo,
                  let barcode = info["barcode"] as? String,
                  let source = info["source"] as? String,
                  let found = info["found"] as? Bool else { return }
            self.collector.record(type: .barcodeScanned, payload: DataLayer_BarcodeScannedPayload(
                barcode: barcode,
                productName: info["productName"] as? String,
                carbsGrams: info["carbsGrams"] as? Double,
                source: source,
                found: found
            ))
        }
    }

    private func observeChatNotifications() {
        NotificationCenter.default.addObserver(
            forName: Notification.Name("com.loopkit.Loop.loopInsightsChatMessage"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            guard let info = notification.userInfo,
                  let isVoiceInitiated = info["isVoiceInitiated"] as? Bool,
                  let responseTimeSeconds = info["responseTimeSeconds"] as? Double else { return }
            self.collector.record(type: .chatMessage, payload: DataLayer_ChatTopicPayload(
                isVoiceInitiated: isVoiceInitiated,
                responseTimeSeconds: responseTimeSeconds,
                topicCategory: info["topicCategory"] as? String
            ))
        }
    }

    private func observeMealDebriefNotifications() {
        NotificationCenter.default.addObserver(
            forName: Notification.Name("com.loopkit.Loop.loopInsightsMealDebrief"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            guard let info = notification.userInfo,
                  let learningCount = info["learningCount"] as? Int else { return }
            self.collector.record(type: .mealDebrief, payload: DataLayer_MealDebriefPayload(
                predictedPeakMgDl: info["predictedPeakMgDl"] as? Double,
                actualPeakMgDl: info["actualPeakMgDl"] as? Double,
                effectiveCarbsEstimate: info["effectiveCarbsEstimate"] as? Double,
                timeToPeakMinutes: info["timeToPeakMinutes"] as? Double,
                learningCount: learningCount
            ))
        }
    }

    private func observeTherapySettingsNotifications() {
        NotificationCenter.default.addObserver(
            forName: Notification.Name("com.loopkit.Loop.therapySettingsChanged"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            guard let info = notification.userInfo,
                  let settingType = info["settingType"] as? String,
                  let timeBlocksChanged = info["timeBlocksChanged"] as? Int,
                  let wasAISuggested = info["wasAISuggested"] as? Bool,
                  let source = info["source"] as? String else { return }
            self.collector.record(type: .therapySettingsChanged, payload: DataLayer_TherapySettingsChangedPayload(
                settingType: settingType,
                timeBlocksChanged: timeBlocksChanged,
                wasAISuggested: wasAISuggested,
                source: source
            ))
        }
    }

    private func observeOverrideNotifications() {
        NotificationCenter.default.addObserver(
            forName: Notification.Name("com.loopkit.Loop.overrideActivated"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            guard let info = notification.userInfo,
                  let overrideType = info["overrideType"] as? String else { return }
            self.collector.record(type: .overrideActivated, payload: DataLayer_OverridePayload(
                overrideType: overrideType,
                presetName: info["presetName"] as? String,
                insulinNeedsScale: info["insulinNeedsScale"] as? Double,
                targetRangeLow: info["targetRangeLow"] as? Double,
                targetRangeHigh: info["targetRangeHigh"] as? Double
            ))
        }

        NotificationCenter.default.addObserver(
            forName: Notification.Name("com.loopkit.Loop.overrideDeactivated"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            guard let info = notification.userInfo,
                  let overrideType = info["overrideType"] as? String else { return }
            self.collector.record(type: .overrideDeactivated, payload: DataLayer_OverridePayload(
                overrideType: overrideType,
                presetName: info["presetName"] as? String,
                insulinNeedsScale: nil,
                targetRangeLow: nil,
                targetRangeHigh: nil
            ))
        }
    }

    private func observeActivityDetectedNotifications() {
        NotificationCenter.default.addObserver(
            forName: Notification.Name("com.loopkit.Loop.autoPresetsActivityDetected"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            guard let info = notification.userInfo,
                  let activityType = info["activityType"] as? String else { return }
            self.collector.record(type: .activityDetected, payload: DataLayer_PresetEventPayload(
                activityType: activityType,
                presetName: "detected",
                durationMinutes: nil
            ))
        }
    }

    // MARK: - Biometric Polling

    /// Poll biometric data from HealthKit via LoopInsights_HealthKitManager.
    /// Called alongside glucose/insulin/carb polling every 5 minutes,
    /// but only records a snapshot every 4 hours to avoid excessive data volume.
    private var lastBiometricSnapshot: Date?
    private lazy var hkManager = LoopInsights_HealthKitManager()

    private func pollBiometrics() {
        guard consent.isGranted(for: .biometrics) else { return }
        guard LoopInsights_HealthKitManager.isHealthDataAvailable else { return }

        // Only snapshot every 4 hours
        if let last = lastBiometricSnapshot, Date().timeIntervalSince(last) < 14400 { return }
        lastBiometricSnapshot = Date()

        let end = Date()
        let start = end.addingTimeInterval(-14400) // 4 hours

        Task {
            guard let bio = try? await hkManager.fetchAllBiometrics(start: start, end: end) else { return }
            self.collector.record(type: .biometricSnapshot, payload: DataLayer_BiometricSnapshotPayload(
                periodHours: 4,
                avgHeartRate: bio.heartRate?.averageRestingHR,
                avgHRV: bio.hrv?.averageSDNN,
                totalSteps: bio.steps.map { Int($0.averageDailySteps) },
                sleepHours: bio.sleep?.averageDurationHours,
                activeCalories: bio.activeEnergy?.averageDailyCalories,
                weightKg: bio.weight?.latestWeight,
                menstrualPhase: bio.menstrualCycle?.currentPhase.rawValue
            ))
        }
    }

    // MARK: - Provider Sharing

    /// Generate a time-scoped share link. Posts events to the share endpoint, returns the URL.
    func generateShareLink(days: Int, completion: @escaping (Result<DataLayer_ShareLink, Error>) -> Void) {
        guard let endpoint = DataLayer_FeatureFlags.shareEndpointURL else {
            completion(.failure(ShareError.noEndpoint))
            return
        }

        let end = Date()
        let start = end.addingTimeInterval(-Double(days) * 86400)
        let events = collector.eventStore.events(from: start, to: end)

        guard !events.isEmpty else {
            completion(.failure(ShareError.noData))
            return
        }

        // Filter to consented categories only
        let consentedEvents = events.filter { consent.isGranted(for: $0.eventType.consentCategory) }
        guard !consentedEvents.isEmpty else {
            completion(.failure(ShareError.noData))
            return
        }

        // Convert to upload format
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let uploadEvents: [[String: Any]] = consentedEvents.compactMap { event in
            guard let payload = try? JSONSerialization.jsonObject(with: event.payload, options: []) as? [String: Any] else { return nil }
            return [
                "id": event.id.uuidString,
                "deviceID": event.deviceID,
                "eventType": event.eventType.rawValue,
                "timestamp": ISO8601DateFormatter().string(from: event.timestamp),
                "appVersion": event.appVersion,
                "payload": payload
            ]
        }

        let categories = Set(consentedEvents.map { $0.eventType.consentCategory })

        let body: [String: Any] = [
            "action": "create",
            "days": days,
            "events": uploadEvents,
            "categories": categories.map { $0.rawValue },
            "deviceID": DataLayer_SecureStorage.anonymizedDeviceID
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: body, options: []) else {
            completion(.failure(ShareError.encodingFailed))
            return
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey = DataLayer_FeatureFlags.ingestAPIKey {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = jsonData

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let url = json["url"] as? String,
                  let token = json["token"] as? String else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                completion(.failure(ShareError.serverError(statusCode)))
                return
            }

            let link = DataLayer_ShareLink(
                token: token,
                url: url,
                createdAt: Date(),
                expiresAt: end.addingTimeInterval(Double(days) * 86400),
                daysCovered: days,
                categoryCount: categories.count
            )

            DataLayer_FeatureFlags.addShare(link)
            completion(.success(link))
        }.resume()
    }

    /// Revoke an active share link.
    func revokeShareLink(token: String, completion: @escaping (Bool) -> Void) {
        guard let endpoint = DataLayer_FeatureFlags.shareEndpointURL else {
            DataLayer_FeatureFlags.removeShare(token: token)
            completion(true)
            return
        }

        let body: [String: Any] = ["action": "revoke", "token": token]
        guard let jsonData = try? JSONSerialization.data(withJSONObject: body, options: []) else {
            completion(false)
            return
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey = DataLayer_FeatureFlags.ingestAPIKey {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = jsonData

        URLSession.shared.dataTask(with: request) { _, _, _ in
            DataLayer_FeatureFlags.removeShare(token: token)
            completion(true)
        }.resume()
    }

    private enum ShareError: LocalizedError {
        case noEndpoint
        case noData
        case encodingFailed
        case serverError(Int)

        var errorDescription: String? {
            switch self {
            case .noEndpoint: return "Share endpoint not configured"
            case .noData: return "No data available for the selected time range"
            case .encodingFailed: return "Failed to prepare share data"
            case .serverError(let code): return "Server error (\(code))"
            }
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

    /// Query events of a specific type within a date range (for report generation).
    func events(from start: Date, to end: Date, type: DataLayer_EventType) -> [DataLayer_Event] {
        return collector.eventStore.events(from: start, to: end, type: type)
    }
}
