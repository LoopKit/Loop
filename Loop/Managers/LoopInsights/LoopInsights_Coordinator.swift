//
//  LoopInsights_Coordinator.swift
//  Loop
//
//  Concept & design by Taylor Patterson. Coded & tested by Claude Code in February 2026.
//  Copyright (c) 2025-2026 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit
import LoopCore
import HealthKit

/// Closure type for writing therapy settings changes back to Loop.
/// Accepts a mutation block that modifies LoopSettings in place.
typealias LoopInsightsSettingsWriter = ((_ mutate: (inout LoopSettings) -> Void) -> Void)

/// Orchestrates all LoopInsights services and manages the feature lifecycle.
/// Created when LoopInsights is accessed from Settings. Owns the DataAggregator,
/// SuggestionStore, and AIAnalysis service, and provides the data access bridge
/// between Loop's stores and LoopInsights' analysis engine.
final class LoopInsights_Coordinator: ObservableObject {

    // MARK: - Services

    let dataAggregator: LoopInsights_DataAggregator
    let aiAnalysis: LoopInsights_AIAnalysis
    let suggestionStore: LoopInsights_SuggestionStore
    let goalStore: LoopInsights_GoalStore
    let healthKitManager: LoopInsights_HealthKitManager?
    let caffeineTracker: LoopInsights_CaffeineTracker
    let alcoholTracker: LoopInsights_AlcoholTracker

    /// Background monitor for proactive suggestions (lazy-initialized)
    lazy var backgroundMonitor: LoopInsights_BackgroundMonitor = LoopInsights_BackgroundMonitor(coordinator: self)

    // MARK: - Data Provider Bridge

    private var dataProviderBridge: DataProviderBridge?

    /// Retained reference to test data provider (when using fixtures).
    private var testDataProvider: LoopInsights_TestDataProvider?

    /// Closure to write therapy settings back to Loop via LoopDataManager.mutateSettings
    var settingsWriter: LoopInsightsSettingsWriter?

    // MARK: - Initialization

    /// Initialize with Loop's existing store references.
    /// The coordinator only reads from these stores — it never writes glucose, dose, or carb data.
    init(
        glucoseStore: GlucoseStoreProtocol,
        doseStore: DoseStoreProtocol,
        carbStore: CarbStoreProtocol,
        settingsProvider: LatestStoredSettingsProvider,
        settingsWriter: LoopInsightsSettingsWriter? = nil
    ) {
        let bridge = DataProviderBridge(
            glucoseStore: glucoseStore,
            doseStore: doseStore,
            carbStore: carbStore,
            settingsProvider: settingsProvider
        )
        self.dataProviderBridge = bridge
        self.settingsWriter = settingsWriter

        let hkManager: LoopInsights_HealthKitManager? = LoopInsights_FeatureFlags.biometricsEnabled
            ? LoopInsights_HealthKitManager() : nil
        self.healthKitManager = hkManager
        self.dataAggregator = LoopInsights_DataAggregator(dataProvider: bridge, healthKitManager: hkManager)
        self.aiAnalysis = LoopInsights_AIAnalysis()
        self.suggestionStore = LoopInsights_SuggestionStore.shared
        self.goalStore = LoopInsights_GoalStore.shared
        self.caffeineTracker = LoopInsights_CaffeineTracker.shared
        self.caffeineTracker.healthKitManager = hkManager
        self.alcoholTracker = LoopInsights_AlcoholTracker.shared
    }

    /// Initialize with test data fixtures (for simulator/developer mode).
    /// Loads JSON fixtures from Documents/LoopInsights/ or the app bundle.
    init(testDataProvider: LoopInsights_TestDataProvider) {
        self.testDataProvider = testDataProvider
        self.dataProviderBridge = nil
        self.settingsWriter = nil
        self.healthKitManager = nil
        self.dataAggregator = LoopInsights_DataAggregator(dataProvider: testDataProvider)
        self.aiAnalysis = LoopInsights_AIAnalysis()
        self.suggestionStore = LoopInsights_SuggestionStore.shared
        self.goalStore = LoopInsights_GoalStore.shared
        self.caffeineTracker = LoopInsights_CaffeineTracker.shared
        self.alcoholTracker = LoopInsights_AlcoholTracker.shared
    }

    /// Factory method: creates a Coordinator with test data if available and enabled,
    /// otherwise returns nil (caller should fall back to real stores).
    static func withTestDataIfAvailable() -> LoopInsights_Coordinator? {
        guard LoopInsights_FeatureFlags.useTestData else { return nil }

        let provider = LoopInsights_TestDataProvider()
        guard provider.hasTestData else {
            LoopInsights_FeatureFlags.log.info("Test data mode enabled but no fixtures found")
            return nil
        }

        LoopInsights_FeatureFlags.log.info("Using test data: \(provider.dataSummary)")
        return LoopInsights_Coordinator(testDataProvider: provider)
    }

    // MARK: - Background Monitoring

    /// Start background monitoring if enabled and using real stores (not test data).
    func startBackgroundMonitoring() {
        guard dataProviderBridge != nil else {
            LoopInsights_FeatureFlags.log.debug("Skipping background monitor — test data mode")
            return
        }
        backgroundMonitor.start()
    }

    /// Stop background monitoring.
    func stopBackgroundMonitoring() {
        backgroundMonitor.stop()
    }

    // MARK: - Supplemental AI Context (Phase 5)

    /// Build supplemental context for AI prompt enrichment from Phase 5 analyzers.
    /// Returns nil if no Phase 5 features are enabled.
    /// P3: Accept pre-fetched glucose + carbs to avoid duplicate data fetches.
    /// P10: Pass hourly averages to circadian profile builder.
    func buildSupplementalContext(
        stats: LoopInsightsAggregatedStats,
        glucoseSamples: [StoredGlucoseSample]? = nil,
        carbEntries: [StoredCarbEntry]? = nil
    ) async -> String? {
        var context: [String] = []

        let start = Date().addingTimeInterval(-stats.period.timeInterval)
        let end = Date()

        // P3: Use pre-fetched glucose, fall back to bridge only if not provided
        var resolvedGlucose: [StoredGlucoseSample]? = glucoseSamples
        if resolvedGlucose == nil, let bridge = dataProviderBridge {
            do { resolvedGlucose = try await bridge.getGlucoseSamples(start: start, end: end) }
            catch { LoopInsights_FeatureFlags.log.error("Supplemental context: glucose fetch failed: \(error)") }
        }

        // Circadian + Dawn Phenomenon + Negative Basal + Stress
        if LoopInsights_FeatureFlags.circadianEnabled {
            // Circadian profile from glucose + sleep data
            if let samples = resolvedGlucose {
                // P10: Pass pre-computed hourly averages to avoid re-bucketing
                if let profile = LoopInsights_AdvancedAnalyzers.buildCircadianProfile(
                    glucoseSamples: samples,
                    sleepStats: stats.biometricStats?.sleep,
                    precomputedHourlyAverages: stats.glucoseStats.hourlyAverages
                ) {
                    context.append(LoopInsights_AdvancedAnalyzers.buildCircadianPromptContext(profile))
                }
            }

            // Negative basal stats (already computed in aggregation, just need prompt context)
            if let negBasal = stats.insulinStats.negativeBasalStats {
                context.append(LoopInsights_AdvancedAnalyzers.buildNegativeBasalPromptContext(negBasal))
            }

            // Stress score (already computed in aggregation)
            if let stressScore = stats.biometricStats?.stressScore {
                context.append(LoopInsights_AdvancedAnalyzers.buildStressPromptContext(stressScore))
            }
        }

        // Food response patterns
        if LoopInsights_FeatureFlags.foodResponseEnabled {
            // P3: Use pre-fetched carbs, fall back to bridge only if not provided
            var resolvedCarbs: [StoredCarbEntry]? = carbEntries
            if resolvedCarbs == nil, let bridge = dataProviderBridge {
                do { resolvedCarbs = try await bridge.getCarbEntries(start: start, end: end) }
                catch { LoopInsights_FeatureFlags.log.error("Supplemental context: carbs fetch failed: \(error)") }
            }
            if let carbs = resolvedCarbs, let glucSamples = resolvedGlucose {
                let patterns = LoopInsights_FoodResponseAnalyzer.analyzeFoodResponses(
                    carbEntries: carbs,
                    glucoseSamples: glucSamples
                )
                let foodCtx = LoopInsights_FoodResponseAnalyzer.buildFoodResponsePromptContext(patterns)
                if !foodCtx.isEmpty { context.append(foodCtx) }
            }
        }

        // Caffeine context
        if LoopInsights_FeatureFlags.caffeineTrackingEnabled {
            let caffeineCtx = caffeineTracker.buildCaffeinePromptContext()
            if !caffeineCtx.isEmpty { context.append(caffeineCtx) }
        }

        // Alcohol context
        if LoopInsights_FeatureFlags.alcoholTrackingEnabled {
            let alcoholCtx = alcoholTracker.buildAlcoholPromptContext()
            if !alcoholCtx.isEmpty { context.append(alcoholCtx) }
        }

        // FoodFinder meal history + nutritional glucose correlation
        if FoodFinder_FeatureFlags.isEnabled {
            let foodCtx = Self.buildFoodFinderPromptContext(start: start, end: end)
            if !foodCtx.isEmpty { context.append(foodCtx) }

            // Correlate FoodFinder nutritional profiles with glucose spikes
            if let glucSamples = resolvedGlucose {
                let archiveMeals = MealArchive.meals(from: start, to: end)
                if !archiveMeals.isEmpty {
                    let nutritionCtx = LoopInsights_FoodResponseAnalyzer.analyzeNutritionalCorrelations(
                        meals: archiveMeals,
                        glucoseSamples: glucSamples
                    )
                    if !nutritionCtx.isEmpty { context.append(nutritionCtx) }
                }
            }
        }

        // Menstrual cycle context (if user tracks in Apple Health)
        if let menstrualStats = stats.biometricStats?.menstrualCycle {
            let menstrualCtx = LoopInsights_AdvancedAnalyzers.buildMenstrualCyclePromptContext(menstrualStats)
            if !menstrualCtx.isEmpty { context.append(menstrualCtx) }
        }

        // Nightscout supplemental data
        if LoopInsights_FeatureFlags.nightscoutImportEnabled {
            let nsCtx = await buildNightscoutPromptContext(start: start, end: end)
            if !nsCtx.isEmpty { context.append(nsCtx) }
        }

        guard !context.isEmpty else { return nil }
        return context.joined(separator: "\n")
    }

    // MARK: - FoodFinder Context

    /// Build prompt context from FoodFinder meal analysis history.
    /// Reads from the long-term archive for full history. Includes per-item
    /// nutritional detail (protein, fat, fiber, calories) and AI accuracy stats.
    private static func buildFoodFinderPromptContext(start: Date, end: Date) -> String {
        // Read from long-term archive first, fall back to 7-day store
        var meals = MealArchive.meals(from: start, to: end)
        if meals.isEmpty {
            meals = FoodFinder_AnalysisHistoryStore.meals(from: start, to: end)
        }
        guard !meals.isEmpty else { return "" }

        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short

        let archiveTotal = MealArchive.count
        var lines: [String] = ["FOODFINDER MEAL HISTORY (\(meals.count) meals in period, \(archiveTotal) total archived):"]

        // Per-meal detail (most recent 15 to keep prompt size reasonable)
        for meal in meals.prefix(15) {
            var line = "  \(formatter.string(from: meal.date)): \(meal.name)"
            line += " — \(String(format: "%.0f", meal.carbsGrams))g carbs"

            // Full nutritional profile from AI analysis
            if let result = meal.analysisResult {
                var macros: [String] = []
                if let protein = result.totalProtein, protein > 0 {
                    macros.append("\(String(format: "%.0f", protein))g protein")
                }
                if let fat = result.totalFat, fat > 0 {
                    macros.append("\(String(format: "%.0f", fat))g fat")
                }
                if let fiber = result.totalFiber, fiber > 0 {
                    macros.append("\(String(format: "%.0f", fiber))g fiber")
                }
                if let cal = result.totalCalories, cal > 0 {
                    macros.append("\(String(format: "%.0f", cal)) cal")
                }
                if !macros.isEmpty {
                    line += " (\(macros.joined(separator: ", ")))"
                }
                if let absorb = result.absorptionTimeHours {
                    line += " ~\(String(format: "%.1f", absorb))h absorption"
                }
            }

            // AI vs user carb delta
            if let aiCarbs = meal.originalAICarbs {
                let delta = meal.carbsGrams - aiCarbs
                line += " | AI: \(String(format: "%.0f", aiCarbs))g"
                if abs(delta) > 1 {
                    line += " (user \(delta > 0 ? "+" : "")\(String(format: "%.0f", delta))g)"
                }
            }

            if let confidence = meal.aiConfidencePercent {
                line += " [\(confidence)%]"
            }

            lines.append(line)

            // Per-item breakdown for multi-item meals (compact)
            if let items = meal.analysisResult?.foodItemsDetailed, items.count > 1 {
                for item in items {
                    var itemLine = "    · \(item.name): \(String(format: "%.0f", item.carbohydrates))g carbs"
                    if let fat = item.fat, fat > 0 { itemLine += ", \(String(format: "%.0f", fat))g fat" }
                    if let protein = item.protein, protein > 0 { itemLine += ", \(String(format: "%.0f", protein))g protein" }
                    lines.append(itemLine)
                }
            }
        }

        // Aggregate AI accuracy stats
        let mealsWithAI = meals.filter { $0.originalAICarbs != nil }
        if mealsWithAI.count >= 3 {
            let deltas = mealsWithAI.compactMap { meal -> Double? in
                guard let aiCarbs = meal.originalAICarbs else { return nil }
                return meal.carbsGrams - aiCarbs
            }
            let avgDelta = deltas.reduce(0, +) / Double(deltas.count)
            let overCount = deltas.filter { $0 > 2 }.count
            let underCount = deltas.filter { $0 < -2 }.count
            let accurateCount = deltas.filter { abs($0) <= 2 }.count

            lines.append("  AI Accuracy: avg adjustment \(avgDelta >= 0 ? "+" : "")\(String(format: "%.1f", avgDelta))g, accurate ±2g: \(accurateCount)/\(mealsWithAI.count), user added: \(overCount), user reduced: \(underCount)")
        }

        // Nutritional composition summary
        let mealsWithNutrition = meals.filter { $0.analysisResult?.totalFat != nil }
        if mealsWithNutrition.count >= 3 {
            let avgFat = mealsWithNutrition.compactMap { $0.analysisResult?.totalFat }.reduce(0, +) / Double(mealsWithNutrition.count)
            let avgProtein = mealsWithNutrition.compactMap { $0.analysisResult?.totalProtein }.reduce(0, +) / Double(mealsWithNutrition.count)
            let avgFiber = mealsWithNutrition.compactMap { $0.analysisResult?.totalFiber }.reduce(0, +) / Double(mealsWithNutrition.count)
            lines.append("  Avg meal composition: \(String(format: "%.0f", avgFat))g fat, \(String(format: "%.0f", avgProtein))g protein, \(String(format: "%.0f", avgFiber))g fiber")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Nightscout Context

    /// Cached Nightscout import result to avoid repeated network calls
    private static var cachedNightscoutResult: LoopInsightsNightscoutImportResult?
    private static var nightscoutCacheTimestamp: Date?

    /// Build prompt context from Nightscout data. Uses a 5-minute cache to
    /// avoid hammering the server on every chat message.
    private func buildNightscoutPromptContext(start: Date, end: Date) async -> String {
        let config = LoopInsightsNightscoutConfig.load()
        guard config.isConnected, !config.siteURL.isEmpty else { return "" }

        // Use cached result if fresh (< 5 min)
        let result: LoopInsightsNightscoutImportResult
        if let cached = Self.cachedNightscoutResult,
           let ts = Self.nightscoutCacheTimestamp,
           Date().timeIntervalSince(ts) < 300 {
            result = cached
        } else {
            let importer = LoopInsights_NightscoutImporter(config: config)
            do {
                result = try await importer.importData(start: start, end: end)
                Self.cachedNightscoutResult = result
                Self.nightscoutCacheTimestamp = Date()
            } catch {
                LoopInsights_FeatureFlags.log.error("Nightscout import for context failed: \(error)")
                return ""
            }
        }

        guard result.entryCount > 0 || result.treatmentCount > 0 else { return "" }

        var lines: [String] = ["NIGHTSCOUT DATA (\(result.summary)):"]

        // Recent glucose from Nightscout (last 12 hours, sampled every ~30 min)
        let twelveHoursAgo = Date().addingTimeInterval(-12 * 3600)
        let recentGlucose = result.glucoseReadings
            .filter { $0.date >= twelveHoursAgo }
            .sorted { $0.date < $1.date }

        if !recentGlucose.isEmpty {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            lines.append("  Recent Glucose (Nightscout):")
            var lastShown: Date?
            for reading in recentGlucose {
                if let prev = lastShown, reading.date.timeIntervalSince(prev) < 25 * 60 { continue }
                lines.append("    \(formatter.string(from: reading.date)): \(String(format: "%.0f", reading.mgdl)) mg/dL")
                lastShown = reading.date
            }
        }

        // Recent treatments
        let recentCarbs = result.carbEntries
            .filter { $0.date >= twelveHoursAgo }
            .sorted { $0.date > $1.date }

        if !recentCarbs.isEmpty {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            lines.append("  Recent Meals (Nightscout):")
            for entry in recentCarbs.prefix(10) {
                var line = "    \(formatter.string(from: entry.date)): \(String(format: "%.0f", entry.grams))g carbs"
                if let foodType = entry.foodType { line += " (\(foodType))" }
                lines.append(line)
            }
        }

        let recentBoluses = result.bolusEntries
            .filter { $0.date >= twelveHoursAgo }
            .sorted { $0.date > $1.date }

        if !recentBoluses.isEmpty {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            lines.append("  Recent Boluses (Nightscout):")
            for bolus in recentBoluses.prefix(10) {
                lines.append("    \(formatter.string(from: bolus.date)): \(String(format: "%.1f", bolus.units)) U")
            }
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Raw Data Access

    /// Fetch raw glucose samples for the given date range.
    /// Tries HealthKit first for longer history, falls back to Loop stores.
    func fetchGlucoseSamples(start: Date, end: Date) async throws -> [StoredGlucoseSample] {
        guard let bridge = dataProviderBridge else {
            throw LoopInsightsError.insufficientData("Data provider not available")
        }
        return try await bridge.getGlucoseSamples(start: start, end: end)
    }

    /// Fetch raw carb entries for the given date range.
    func fetchCarbEntries(start: Date, end: Date) async throws -> [StoredCarbEntry] {
        guard let bridge = dataProviderBridge else {
            throw LoopInsightsError.insufficientData("Data provider not available")
        }
        return try await bridge.getCarbEntries(start: start, end: end)
    }

    // MARK: - Live Loop Status for Chat

    /// Build a live status context string for the chat, pulling IOB, COB, active
    /// overrides, predicted glucose, and loop freshness from existing read-only sources.
    /// Zero changes to Loop core files — reads from protocol methods and UserDefaults.
    func buildLiveStatusContext() async -> String? {
        var parts: [String] = []

        // IOB
        if let bridge = dataProviderBridge {
            do {
                let iob = try await bridge.getInsulinOnBoard()
                parts.append("  IOB (Insulin On Board): \(String(format: "%.2f", iob.value)) U")
            } catch {
                LoopInsights_FeatureFlags.log.error("Live status: IOB fetch failed: \(error)")
            }

            // COB
            do {
                let cob = try await bridge.getCarbsOnBoard()
                parts.append("  COB (Carbs On Board): \(String(format: "%.0f", cob.quantity.doubleValue(for: .gram()))) g")
            } catch {
                LoopInsights_FeatureFlags.log.error("Live status: COB fetch failed: \(error)")
            }
        }

        // Active overrides + dosing strategy from settings
        if let bridge = dataProviderBridge {
            let settings = bridge.settingsProvider.latestSettings

            let loopMode = settings.dosingEnabled ? "Closed Loop" : "Open Loop"
            let strategy: String
            switch settings.automaticDosingStrategy {
            case .tempBasalOnly:
                strategy = "Temp Basal Only"
            case .automaticBolus:
                strategy = "Automatic Bolus"
            default:
                strategy = "Unknown"
            }
            parts.append("  Loop Mode: \(loopMode) (\(strategy))")

            if let override = settings.scheduleOverride, override.isActive() {
                var overrideDesc = "  Active Override:"
                switch override.context {
                case .preset(let preset):
                    overrideDesc += " \(preset.name)"
                case .legacyWorkout:
                    overrideDesc += " Workout"
                case .custom:
                    overrideDesc += " Custom"
                case .preMeal:
                    overrideDesc += " Pre-Meal"
                }
                if let factor = override.settings.insulinNeedsScaleFactor {
                    overrideDesc += " (insulin needs \(String(format: "%.0f", factor * 100))%)"
                }
                if let range = override.settings.targetRange {
                    let low = range.lowerBound.doubleValue(for: .milligramsPerDeciliter)
                    let high = range.upperBound.doubleValue(for: .milligramsPerDeciliter)
                    overrideDesc += " target \(String(format: "%.0f", low))-\(String(format: "%.0f", high)) mg/dL"
                }
                let remaining = override.scheduledEndDate.timeIntervalSinceNow
                if remaining.isFinite && remaining > 0 {
                    let mins = Int(remaining / 60)
                    overrideDesc += " (\(mins / 60)h \(mins % 60)m remaining)"
                } else if override.duration.isInfinite {
                    overrideDesc += " (indefinite)"
                }
                parts.append(overrideDesc)
            }

            if let preMeal = settings.preMealOverride, preMeal.isActive() {
                parts.append("  Pre-Meal Override: Active")
            }
        }

        // Predicted glucose + loop freshness from StatusExtensionContext (UserDefaults)
        if let statusCtx = UserDefaults.appGroup?.statusExtensionContext {
            if let lastLoop = statusCtx.lastLoopCompleted {
                let minsAgo = Int(Date().timeIntervalSince(lastLoop) / 60)
                parts.append("  Last Loop: \(minsAgo) min ago")
            }

            if let netBasal = statusCtx.netBasal {
                parts.append("  Current Delivery: \(String(format: "%.2f", netBasal.rate)) U/hr (\(String(format: "%.0f", netBasal.percentage))% of scheduled)")
            }

            if let predicted = statusCtx.predictedGlucose {
                let samples = predicted.samples
                if let first = samples.first, let last = samples.last, samples.count >= 2 {
                    let formatter = DateFormatter()
                    formatter.timeStyle = .short
                    let current = String(format: "%.0f", first.value)
                    let predicted30 = samples.count > 6 ? String(format: "%.0f", samples[6].value) : nil
                    let predictedEnd = String(format: "%.0f", last.value)
                    var predLine = "  Predicted Glucose: \(current) now"
                    if let p30 = predicted30 {
                        predLine += " → \(p30) in 30 min"
                    }
                    predLine += " → \(predictedEnd) at \(formatter.string(from: last.startDate))"
                    parts.append(predLine)
                }
            }

            if let battery = statusCtx.batteryPercentage {
                parts.append("  Pump Battery: \(String(format: "%.0f", battery * 100))%")
            }

            if let reservoir = statusCtx.reservoirCapacity {
                parts.append("  Reservoir: \(String(format: "%.0f", reservoir)) U remaining")
            }
        }

        guard !parts.isEmpty else { return nil }
        return "LIVE LOOP STATUS:\n" + parts.joined(separator: "\n")
    }

    // MARK: - Therapy Settings Write Access

    /// Capture a snapshot of the current therapy settings
    func captureCurrentSnapshot() throws -> LoopInsightsTherapySnapshot {
        return try dataAggregator.captureTherapySnapshot()
    }

    /// Apply a suggestion's time block changes to the actual therapy settings.
    /// Returns true if the write succeeded.
    @discardableResult
    func applyTherapyChanges(suggestion: LoopInsightsSuggestion) -> Bool {
        guard let writer = settingsWriter else {
            LoopInsights_FeatureFlags.log.error("Cannot apply: no settings writer available (test data mode?)")
            return false
        }

        let blocks = suggestion.timeBlocks
        guard !blocks.isEmpty else { return false }

        writer { settings in
            switch suggestion.settingType {
            case .carbRatio:
                guard let schedule = settings.carbRatioSchedule else { return }
                let updatedItems = Self.applyBlockChanges(blocks, to: schedule.items)
                if let newSchedule = CarbRatioSchedule(unit: schedule.unit, dailyItems: updatedItems, timeZone: schedule.timeZone) {
                    settings.carbRatioSchedule = newSchedule
                }

            case .insulinSensitivity:
                guard let schedule = settings.insulinSensitivitySchedule else { return }
                let updatedItems = Self.applyBlockChanges(blocks, to: schedule.items)
                if let newSchedule = InsulinSensitivitySchedule(unit: schedule.unit, dailyItems: updatedItems, timeZone: schedule.timeZone) {
                    settings.insulinSensitivitySchedule = newSchedule
                }

            case .basalRate:
                guard let schedule = settings.basalRateSchedule else { return }
                let updatedItems = Self.applyBlockChanges(blocks, to: schedule.items)
                if let newSchedule = BasalRateSchedule(dailyItems: updatedItems, timeZone: schedule.timeZone) {
                    settings.basalRateSchedule = newSchedule
                }
            }
        }

        LoopInsights_FeatureFlags.log.info("Applied \(suggestion.settingType.displayName) changes: \(blocks.count) time block(s)")
        return true
    }

    /// Revert therapy settings to a previously captured snapshot.
    /// Restores all three schedule types (CR, ISF, Basal) from the snapshot.
    /// Returns true if the write succeeded.
    @discardableResult
    func revertToSnapshot(_ snapshot: LoopInsightsTherapySnapshot) -> Bool {
        guard let writer = settingsWriter else {
            LoopInsights_FeatureFlags.log.error("Cannot revert: no settings writer available")
            return false
        }

        writer { settings in
            // Restore carb ratio schedule
            if !snapshot.carbRatioItems.isEmpty,
               let existingSchedule = settings.carbRatioSchedule {
                let items = snapshot.carbRatioItems.map {
                    RepeatingScheduleValue(startTime: $0.startTime, value: $0.value)
                }
                if let restored = CarbRatioSchedule(unit: existingSchedule.unit, dailyItems: items, timeZone: existingSchedule.timeZone) {
                    settings.carbRatioSchedule = restored
                }
            }

            // Restore insulin sensitivity schedule
            if !snapshot.insulinSensitivityItems.isEmpty,
               let existingSchedule = settings.insulinSensitivitySchedule {
                let items = snapshot.insulinSensitivityItems.map {
                    RepeatingScheduleValue(startTime: $0.startTime, value: $0.value)
                }
                if let restored = InsulinSensitivitySchedule(unit: existingSchedule.unit, dailyItems: items, timeZone: existingSchedule.timeZone) {
                    settings.insulinSensitivitySchedule = restored
                }
            }

            // Restore basal rate schedule
            if !snapshot.basalRateItems.isEmpty,
               let existingSchedule = settings.basalRateSchedule {
                let items = snapshot.basalRateItems.map {
                    RepeatingScheduleValue(startTime: $0.startTime, value: $0.value)
                }
                if let restored = BasalRateSchedule(dailyItems: items, timeZone: existingSchedule.timeZone) {
                    settings.basalRateSchedule = restored
                }
            }
        }

        LoopInsights_FeatureFlags.log.info("Reverted settings to previous snapshot")
        return true
    }

    /// Match time blocks to schedule items and apply proposed values.
    /// If no existing entry matches a block's start time, inserts new entries
    /// to split the schedule at the suggested time boundaries.
    private static func applyBlockChanges(
        _ blocks: [LoopInsightsTimeBlock],
        to items: [RepeatingScheduleValue<Double>]
    ) -> [RepeatingScheduleValue<Double>] {
        var updated = items

        for block in blocks {
            // Try to find an existing entry matching this block's start time
            let matchIndex = updated.firstIndex(where: { abs($0.startTime - block.startTime) < 60 })

            if let idx = matchIndex {
                // Exact match — update the value
                updated[idx] = RepeatingScheduleValue(startTime: updated[idx].startTime, value: block.proposedValue)
            } else {
                // No matching entry — insert a new entry at the block's start time
                // with the proposed value, and another at the block's end time to
                // restore the original value for the remainder of the period.
                let originalValue = valueAt(time: block.startTime, in: updated)

                updated.append(RepeatingScheduleValue(startTime: block.startTime, value: block.proposedValue))

                // Only insert an end-time entry if it doesn't already exist
                // and the block doesn't extend to end-of-day
                let endAlreadyExists = updated.contains(where: { abs($0.startTime - block.endTime) < 60 })
                let endOfDay: TimeInterval = 24 * 3600
                if !endAlreadyExists && block.endTime < endOfDay {
                    updated.append(RepeatingScheduleValue(startTime: block.endTime, value: originalValue))
                }
            }
        }

        // Sort by start time to maintain schedule order
        updated.sort { $0.startTime < $1.startTime }
        return updated
    }

    /// Find the effective value at a given time in a sorted schedule.
    /// Returns the value of the last entry whose startTime <= the given time.
    private static func valueAt(time: TimeInterval, in items: [RepeatingScheduleValue<Double>]) -> Double {
        let sorted = items.sorted { $0.startTime < $1.startTime }
        var result = sorted.first?.value ?? 0
        for item in sorted {
            if item.startTime <= time {
                result = item.value
            } else {
                break
            }
        }
        return result
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

    func getInsulinOnBoard() async throws -> InsulinValue {
        return try await withCheckedThrowingContinuation { continuation in
            doseStore.insulinOnBoard(at: Date()) { result in
                switch result {
                case .success(let value):
                    continuation.resume(returning: value)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func getCarbsOnBoard() async throws -> CarbValue {
        return try await withCheckedThrowingContinuation { continuation in
            carbStore.carbsOnBoard(at: Date(), effectVelocities: nil) { result in
                switch result {
                case .success(let value):
                    continuation.resume(returning: value)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
