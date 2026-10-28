//
//  LoopHistoryProvider.swift
//  Loop
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Foundation
import HealthKit
import LoopKit
import LoopCore
import LoopAlgorithm
import os.log

/// Reads glucose, insulin, carbs and loop runs for the redesigned screens.
///
/// Loop keeps `LOOP_LOCAL_CACHE_DURATION_DAYS` (7) days in its own stores. Inside that window everything comes from
/// those stores, so manual and automatic doses, temp basals and the schedule are known. Older days come from Apple
/// Health, which has glucose, carbs and insulin split only into basal and bolus.
final class LoopHistoryProvider {

    private let deviceManager: DeviceDataManager
    private let loopDataManager: LoopDataManager
    private let settingsManager: SettingsManager
    private let temporaryPresetsManager: TemporaryPresetsManager
    private let dosingDecisionStore: DosingDecisionStoreProtocol
    private let doseStore: DoseStore
    private let carbStore: CarbStore
    private let glucoseStore: GlucoseStore
    private let healthStore = HKHealthStore()
    private let log = OSLog(category: "LoopHistoryProvider")

    @MainActor
    init(deviceManager: DeviceDataManager, loopDataManager: LoopDataManager, settingsManager: SettingsManager, temporaryPresetsManager: TemporaryPresetsManager) {
        self.deviceManager = deviceManager
        self.loopDataManager = loopDataManager
        self.settingsManager = settingsManager
        self.temporaryPresetsManager = temporaryPresetsManager
        self.dosingDecisionStore = loopDataManager.dosingDecisionStore
        self.doseStore = deviceManager.doseStore
        self.carbStore = deviceManager.carbStore
        self.glucoseStore = deviceManager.glucoseStore
    }

    @MainActor
    var unitStyle: GlucoseUnitStyle {
        GlucoseUnitStyle(unit: deviceManager.displayGlucosePreference.unit)
    }

    /// Match the classic carb editor's eligibility rule, including mode changes while a screen is open.
    @MainActor
    var allowsCarbEditing: Bool {
        settingsManager.dosingEnabled || !FeatureFlags.simpleBolusCalculatorEnabled
    }

    /// The start of what Loop keeps locally.
    var localHistoryStart: Date {
        Date().addingTimeInterval(-Bundle.main.localCacheDuration)
    }

    @MainActor
    var glucoseTargetRange: ClosedRange<Double>? {
        guard let range = temporaryPresetsManager.effectiveCorrectionRange() else { return nil }
        return range.lowerBound.doubleValue(for: .milligramsPerDeciliter)...range.upperBound.doubleValue(for: .milligramsPerDeciliter)
    }

    /// The correction range schedule across `interval`, with any preset or pre-meal range over the time it runs,
    /// as the classic glucose chart draws it.
    @MainActor
    func glucoseTargetBands(in interval: DateInterval) -> [TargetBand] {
        guard let schedule = settingsManager.settings.glucoseTargetRangeSchedule else { return [] }
        func mgdl(_ range: ClosedRange<LoopQuantity>) -> ClosedRange<Double> {
            range.lowerBound.doubleValue(for: .milligramsPerDeciliter)...range.upperBound.doubleValue(for: .milligramsPerDeciliter)
        }
        var bands = schedule.quantityBetween(start: interval.start, end: interval.end).map {
            TargetBand(start: max($0.startDate, interval.start), end: min($0.endDate, interval.end), range: mgdl($0.value))
        }
        // Pre-meal goes last so it wins where both run, as in TemporaryPresetsManager.effectiveCorrectionRangeSchedule.
        for override in [temporaryPresetsManager.scheduleOverride, temporaryPresetsManager.preMealOverride].compactMap({ $0 }) {
            guard let target = override.settings.targetRange,
                  let active = override.activeInterval.intersection(with: interval), active.duration > 0 else { continue }
            bands = bands.flatMap { band -> [TargetBand] in
                var pieces: [TargetBand] = []
                if band.start < active.start {
                    pieces.append(TargetBand(start: band.start, end: min(band.end, active.start), range: band.range))
                }
                if band.end > active.end {
                    pieces.append(TargetBand(start: max(band.start, active.end), end: band.end, range: band.range))
                }
                return pieces
            } + [TargetBand(start: active.start, end: active.end, range: mgdl(target))]
        }
        return bands.sorted { $0.start < $1.start }
    }

    // MARK: - Days

    /// Everything in `window`; IOB and COB only when asked, as they are the slowest part.
    func dayHistory(_ window: DateInterval, includeOnBoard: Bool = true) async throws -> DayHistory {
        var history = DayHistory(window: window)
        let boundary = localHistoryStart

        if window.end > boundary {
            let local = DateInterval(start: max(window.start, boundary), end: window.end)
            async let glucose = localGlucose(local)
            async let insulin = localInsulin(local)
            async let carbs = localCarbs(local)
            history.glucose = try await glucose
            (history.boluses, history.basal, history.scheduledBasal) = try await insulin
            history.carbs = try await carbs
            if includeOnBoard {
                async let iob = localIOB(local)
                async let cob = localCOB(local)
                history.iob = try await iob
                history.cob = try await cob
            }
        }

        if window.start < boundary {
            let older = DateInterval(start: window.start, end: min(window.end, boundary))
            async let glucose = healthGlucose(older)
            async let insulin = healthInsulin(older)
            async let carbs = healthCarbs(older)
            let (boluses, basal) = try await insulin
            history.glucose = try await glucose + history.glucose
            history.boluses = boluses + history.boluses
            history.basal = basal + history.basal
            history.carbs = try await carbs + history.carbs
            if window.end <= boundary {
                history.source = .health
            }
        }
        try Task.checkCancellation()
        return history
    }

    /// CGM readings for any period, local and Health combined.
    func glucose(_ interval: DateInterval) async throws -> [GlucosePoint] {
        let boundary = localHistoryStart
        var points: [GlucosePoint] = []
        if interval.start < boundary {
            points += try await healthGlucose(DateInterval(start: interval.start, end: min(interval.end, boundary)))
        }
        if interval.end > boundary {
            points += try await localGlucose(DateInterval(start: max(interval.start, boundary), end: interval.end))
        }
        return points
    }

    // MARK: - Loop runs

    /// Fetch each snapshot independently: overlapping reloads must not append the same anchored page twice.
    func loopRuns() async throws -> (runs: [LoopHistoryMath.LoopRun], coverageStart: Date?) {
        var anchor: DosingDecisionStore.QueryAnchor?
        var runs: [LoopHistoryMath.LoopRun] = []
        while true {
            let page: (DosingDecisionStore.QueryAnchor, [StoredDosingDecision]) = try await withCheckedThrowingContinuation { continuation in
                dosingDecisionStore.executeDosingDecisionQuery(fromQueryAnchor: anchor, limit: 1000) { result in
                    switch result {
                    case .success(let anchor, let decisions): continuation.resume(returning: (anchor, decisions))
                    case .failure(let error): continuation.resume(throwing: error)
                    }
                }
            }
            try Task.checkCancellation()
            anchor = page.0
            runs += page.1.filter { $0.reason == "loop" }.map { decision in
                LoopHistoryMath.LoopRun(date: decision.date, succeeded: decision.errors.isEmpty,
                                       error: decision.errors.first.map { Self.describe(issue: $0.id) })
            }
            if page.1.count < 1000 { break }
        }
        runs = runs.filter { $0.date >= localHistoryStart }.sorted { $0.date < $1.date }
        return (runs, runs.first?.date)
    }

    /// "glucoseTooOld" → "Glucose too old". Loop's own issue ids are localised; any other id falls back to the
    /// id split into English words.
    static func describe(issue id: String) -> String {
        switch id {
        case "configurationError": return NSLocalizedString("Configuration error", comment: "Reason Loop could not run: its settings are incomplete")
        case "connectionError": return NSLocalizedString("Connection error", comment: "Reason Loop could not run: no connected devices, or a device connection failed")
        case "missingDataError": return NSLocalizedString("Missing data error", comment: "Reason Loop could not run: data it needs was missing")
        case "glucoseTooOld": return NSLocalizedString("Glucose too old", comment: "Reason Loop could not run: the latest glucose reading was too old")
        case "invalidFutureGlucose": return NSLocalizedString("Invalid future glucose", comment: "Reason Loop could not run: a glucose reading had a timestamp in the future")
        case "pumpDataTooOld": return NSLocalizedString("Pump data too old", comment: "Reason Loop could not run: the latest pump data was too old")
        case "recommendationExpired": return NSLocalizedString("Recommendation expired", comment: "Reason Loop could not run: its dosing recommendation expired before it was used")
        case "pumpSuspended": return NSLocalizedString("Pump suspended", comment: "Reason Loop could not run: insulin delivery on the pump was suspended")
        case "pumpManagerError": return NSLocalizedString("Pump manager error", comment: "Reason Loop could not run: the pump reported an error")
        case "unknownError": return NSLocalizedString("Unknown error", comment: "Reason Loop could not run: an unexpected error")
        default: break
        }
        var words: [String] = []
        var current = ""
        for character in id {
            if character.isUppercase, !current.isEmpty {
                words.append(current)
                current = ""
            }
            current.append(character)
        }
        words.append(current)
        let sentence = words.joined(separator: " ").lowercased()
        return sentence.prefix(1).uppercased() + sentence.dropFirst()
    }

    // MARK: - Pump events

    func pumpEvents(since start: Date) async throws -> [PumpLogEvent] {
        let events = try await doseStore.getPumpEventValues(since: start)
        let items: [PumpLogEvent] = events.compactMap { event in
            let id = event.objectIDURL.absoluteString
            switch event.type {
            case .replaceComponent(let component)?:
                let name: String
                switch component {
                case .pump: name = NSLocalizedString("Pod changed", comment: "Pump event in the history: the pump or pod was replaced")
                case .reservoir: name = NSLocalizedString("Reservoir changed", comment: "Pump event in the history: the insulin reservoir was replaced")
                case .infusionSet: name = NSLocalizedString("Infusion set changed", comment: "Pump event in the history: the infusion set was replaced")
                }
                return PumpLogEvent(id: id, date: event.date, kind: .siteChange(name))
            case .rewind?:
                return PumpLogEvent(id: id, date: event.date, kind: .siteChange(NSLocalizedString("Reservoir rewound", comment: "Pump event in the history: the pump rewound its reservoir")))
            case .prime?:
                return PumpLogEvent(id: id, date: event.date, kind: .siteChange(NSLocalizedString("Primed", comment: "Pump event in the history: the pump primed the tubing or cannula")))
            case .alarm?:
                return PumpLogEvent(id: id, date: event.date, kind: .alarm(event.title ?? NSLocalizedString("Pump alarm", comment: "Pump event in the history: an alarm whose pump gave no title")))
            default:
                return nil
            }
        }
        return items
    }

    // MARK: - Editing

    /// Edits an entry the way Loop's carb absorption screen does.
    @MainActor
    func carbEntryViewModel(editing entry: StoredCarbEntry) -> CarbEntryViewModel {
        let viewModel = CarbEntryViewModel(delegate: loopDataManager, originalCarbEntry: entry)
        viewModel.analyticsServicesManager = loopDataManager.analyticsServicesManager
        viewModel.deliveryDelegate = deviceManager
        return viewModel
    }

    func delete(carb entry: StoredCarbEntry) async throws {
        _ = try await loopDataManager.deleteCarbEntry(entry)
    }

    func delete(dose: DoseEntry) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            doseStore.deleteDose(dose) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    // MARK: - Loop's stores

    private func localGlucose(_ interval: DateInterval) async throws -> [GlucosePoint] {
        do {
            let samples = try await glucoseStore.getGlucoseSamples(start: interval.start, end: interval.end)
            return samples
                .filter { !$0.isDisplayOnly }
                .map { GlucosePoint(date: $0.startDate, mgdl: $0.quantity.doubleValue(for: .milligramsPerDeciliter)) }
        } catch {
            os_log("Glucose fetch failed: %{public}@", log: log, type: .error, String(describing: error))
            throw error
        }
    }

    private func localInsulin(_ interval: DateInterval) async throws -> ([BolusEvent], [BasalSegment], [ScheduledBasalPoint]) {
        let doses: [DoseEntry]
        do {
            doses = try await doseStore.getNormalizedDoseEntries(start: interval.start, end: interval.end)
        } catch {
            os_log("Dose fetch failed: %{public}@", log: log, type: .error, String(describing: error))
            throw error
        }

        let boluses = doses.compactMap { BolusEvent(dose: $0, in: interval) }

        let basalHistory = try await loopDataManager.settingsProvider.getBasalHistory(startDate: interval.start, endDate: interval.end)
        let temporaryPresetsManager = self.temporaryPresetsManager
        let overrides = await MainActor.run {
            temporaryPresetsManager.presetHistory.getOverrideHistory(startDate: interval.start, endDate: interval.end)
        }
        // A resolved daily schedule repeats recent presets on every day. Use the stored profile and dated overrides.
        let scheduleValues = overrides.applyBasal(over: basalHistory)
        let schedule = scheduleValues.map { LoopHistoryMath.ScheduleValue(start: $0.startDate, end: $0.endDate, rate: $0.value) }
        let deliveries = doses.compactMap { LoopHistoryMath.BasalDelivery(dose: $0) }
        let now = Date()
        let window = DateInterval(start: interval.start, end: max(interval.start, min(interval.end, now)))
        // Totals count pump records, as classic Loop does; an unreported gap is not confirmed delivery.
        let basal = window.duration > 0 ? LoopHistoryMath.basalSegments(window: window, schedule: schedule, deliveries: deliveries) : []
        let scheduled = schedule.map { ScheduledBasalPoint(start: max($0.start, interval.start), end: min($0.end, interval.end), rate: $0.rate) }
        return (boluses, basal, scheduled)
    }

    private func localCarbs(_ interval: DateInterval) async throws -> [CarbEvent] {
        do {
            let entries = try await carbStore.getCarbEntries(start: interval.start, end: interval.end)
            return entries.map { entry in
                CarbEvent(id: entry.syncIdentifier ?? "\(entry.startDate.timeIntervalSince1970)",
                          date: entry.startDate,
                          grams: entry.quantity.doubleValue(for: .gram),
                          absorptionHours: entry.absorptionTime.map { $0 / 3600 },
                          foodType: entry.foodType,
                          createdByLoop: entry.createdByCurrentApp,
                          entry: entry)
            }
        } catch {
            os_log("Carb fetch failed: %{public}@", log: log, type: .error, String(describing: error))
            throw error
        }
    }

    private func localIOB(_ interval: DateInterval) async throws -> [TimedValue] {
        try await loopDataManager.insulinOnBoardTimeline(in: interval).map { TimedValue(date: $0.startDate, value: $0.value) }
    }

    private func localCOB(_ interval: DateInterval) async throws -> [TimedValue] {
        try await loopDataManager.carbsOnBoardTimeline(in: interval).map { TimedValue(date: $0.startDate, value: $0.quantity.doubleValue(for: .gram)) }
    }

    // MARK: - Apple Health

    private func healthSamples(_ type: HKQuantityType, _ interval: DateInterval, options: HKQueryOptions = .strictStartDate) async throws -> [HKQuantitySample] {
        guard interval.duration > 0 else { return [] }
        let log = self.log
        return try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: interval.start, end: interval.end, options: options)
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, error in
                if let error {
                    os_log("Health query for %{public}@ failed: %{public}@", log: log, type: .error, type.identifier, String(describing: error))
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: (samples as? [HKQuantitySample]) ?? [])
                }
            }
            healthStore.execute(query)
        }
    }

    /// Several apps can write the same CGM reading to Health; keep one reading per 2½ minutes.
    private func healthGlucose(_ interval: DateInterval) async throws -> [GlucosePoint] {
        let samples = try await healthSamples(HKQuantityType(.bloodGlucose), interval)
        var points: [GlucosePoint] = []
        let own = HKSource.default().bundleIdentifier
        for sample in samples where !sample.isDisplayOnly
            && (FeatureFlags.observeHealthKitGlucoseSamplesFromOtherApps || sample.sourceRevision.source.bundleIdentifier == own) {
            if let last = points.last, sample.startDate.timeIntervalSince(last.date) < 150 { continue }
            points.append(GlucosePoint(date: sample.startDate, mgdl: sample.quantity.doubleValue(for: .milligramsPerDeciliter)))
        }
        return points
    }

    private func healthInsulin(_ interval: DateInterval) async throws -> ([BolusEvent], [BasalSegment]) {
        let samples = try await healthSamples(HKQuantityType(.insulinDelivery), interval, options: [])
        var boluses: [BolusEvent] = []
        var basal: [BasalSegment] = []
        let own = HKSource.default().bundleIdentifier
        for sample in samples where FeatureFlags.observeHealthKitDoseSamplesFromOtherApps || sample.sourceRevision.source.bundleIdentifier == own {
            let units = sample.quantity.doubleValue(for: .internationalUnit())
            let reason = (sample.metadata?[HKMetadataKeyInsulinDeliveryReason] as? NSNumber)?.intValue
            let automatic = (sample.metadata?["com.loopkit.InsulinKit.MetadataKeyAutomaticallyIssued"] as? NSNumber)?.boolValue ?? false
            if reason == HKInsulinDeliveryReason.basal.rawValue {
                if let segment = BasalSegment(healthSample: sample, in: interval) {
                    basal.append(segment)
                }
            } else if sample.startDate >= interval.start && sample.startDate < interval.end {
                boluses.append(BolusEvent(id: sample.uuid.uuidString, date: sample.startDate, units: units, automatic: automatic, manuallyEntered: false))
            }
        }
        return (boluses, basal)
    }

    private func healthCarbs(_ interval: DateInterval) async throws -> [CarbEvent] {
        let samples = try await healthSamples(HKQuantityType(.dietaryCarbohydrates), interval)
        let own = HKSource.default().bundleIdentifier
        return samples
            .filter { FeatureFlags.observeHealthKitCarbSamplesFromOtherApps || $0.sourceRevision.source.bundleIdentifier == own }
            .map { sample in
                CarbEvent(id: sample.uuid.uuidString, date: sample.startDate, grams: sample.quantity.doubleValue(for: .gram()),
                          absorptionHours: nil, foodType: sample.metadata?[HKMetadataKeyFoodType] as? String,
                          createdByLoop: sample.sourceRevision.source.bundleIdentifier == own)
            }
    }
}

// MARK: - Loop mode history

/// Records when closed loop is switched on and off, because Loop's stored runs don't say which mode they ran in.
/// The Trends screen can only call time "open loop" from the first record on.
final class LoopModeHistory {
    static let shared = LoopModeHistory()

    private let defaults: UserDefaults
    private let key = "com.loopkit.Loop.redesign.loopModeChanges"
    private let maximumAge: TimeInterval = .days(100)

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var changes: [LoopHistoryMath.ModeChange] {
        guard let data = defaults.data(forKey: key),
              let changes = try? JSONDecoder().decode([LoopHistoryMath.ModeChange].self, from: data) else {
            return []
        }
        return changes
    }

    func record(closedLoop: Bool, at date: Date = Date()) {
        var changes = self.changes
        guard changes.last?.closedLoop != closedLoop else { return }
        changes.append(.init(date: date, closedLoop: closedLoop))
        // Keep the last change before the retention window: it establishes the mode at its start.
        let cutoff = date.addingTimeInterval(-maximumAge)
        if let anchor = changes.lastIndex(where: { $0.date < cutoff }), anchor > 0 {
            changes.removeFirst(anchor)
        }
        if let data = try? JSONEncoder().encode(changes) {
            defaults.set(data, forKey: key)
        }
    }
}

// MARK: - Loop's on-board history

extension LoopDataManager {
    /// Insulin on board across `interval`, from the doses and basal history Loop keeps, as `iobValues` is for the display window.
    func insulinOnBoardTimeline(in interval: DateInterval) async throws -> [InsulinValue] {
        let dosesStart = interval.start.addingTimeInterval(-InsulinMath.defaultInsulinActivityDuration)
        let doses = try await doseStore.getNormalizedDoseEntries(start: dosesStart, end: interval.end)
            .map { $0.simpleDose(with: insulinModel(for: $0.insulinType)) }
        let basalStart = min(dosesStart, doses.map(\.startDate).min() ?? dosesStart)
        let basal = try await settingsProvider.getBasalHistory(startDate: basalStart, endDate: interval.end)
        let overrides = temporaryPresetsManager.presetHistory.getOverrideHistory(startDate: basalStart, endDate: interval.end)
        return doses.annotated(with: overrides.applyBasal(over: basal)).insulinOnBoardTimeline(from: interval.start, to: interval.end)
    }

    /// Carbs on board across `interval`, using the same absorption review as Loop's carb screen.
    func carbsOnBoardTimeline(in interval: DateInterval) async throws -> [CarbValue] {
        let review = try await fetchCarbAbsorptionReview(start: interval.start.addingTimeInterval(-CarbMath.maximumAbsorptionTimeInterval), end: interval.end)
        return review.carbStatuses.dynamicCarbsOnBoard(from: interval.start, to: interval.end, absorptionModel: carbAbsorptionModel.model)
    }
}
