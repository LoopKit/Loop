//
//  LoopDataManager.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 3/12/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation
import Combine
import LoopKit
import LoopAlgorithm
import LoopKitUI
import LoopCore
import WidgetKit


protocol DosingManagerDelegate {
    func didMakeDosingDecision(_ decision: StoredDosingDecision)
}

enum LoopUpdateContext: Int {
    case insulin
    case carbs
    case glucose
    case preferences
    case forecast
}

@MainActor
final class LoopDataManager: ObservableObject {
    nonisolated static let LoopUpdateContextKey = "com.loudnate.Loop.LoopDataManager.LoopUpdateContext"

    // Represents the current state of the loop algorithm for display
    var displayState = AlgorithmDisplayState()

    // Display state convenience accessors
    var predictedGlucose: [PredictedGlucoseValue]? {
        displayState.output?.predictedGlucose.map(\.loopKit)
    }

    var tempBasalRecommendation: TempBasalRecommendation? {
        displayState.output?.recommendation?.automatic?.basalAdjustment.loopKit
    }

    var automaticBolusRecommendation: Double? {
        displayState.output?.recommendation?.automatic?.bolusUnits
    }

    var automaticRecommendation: AutomaticDoseRecommendation? {
        displayState.output?.recommendation?.automatic?.loopKit
    }

    @Published private(set) var lastLoopCompleted: Date?

    /// Display only: at reclaim the watch's last cycle seeds the phone's loop-recency clock.
    /// Forward-only; dosing never reads it.
    func seedLastLoopCompleted(fromWatch date: Date) {
        guard (lastLoopCompleted ?? .distantPast) < date else { return }
        lastLoopCompleted = date
    }
    @Published private(set) var publishedMostRecentGlucoseDataDate: Date?
    @Published private(set) var publishedMostRecentPumpDataDate: Date?
    @Published private(set) var lastManualBolus: LastManualBolus?


    var deliveryDelegate: DeliveryDelegate?

    let analyticsServicesManager: AnalyticsServicesManager?
    let carbStore: CarbStoreProtocol
    let doseStore: DoseStoreProtocol
    let temporaryPresetsManager: TemporaryPresetsManager
    let settingsProvider: SettingsProvider
    let dosingDecisionStore: DosingDecisionStoreProtocol
    let glucoseStore: GlucoseStoreProtocol
    let crashRecoveryManager: CrashRecoveryManager

    let logger = DiagnosticLog(category: "LoopDataManager")

    private let widgetLog = DiagnosticLog(category: "LoopWidgets")

    private let trustedTimeOffset: () async -> TimeInterval

    private var now: Date { TestingDate.currentTestingDate() }

    /// The dosing loop both apps run (`LoopCycle.swift`); this manager is its host on the phone.
    private(set) lazy var cycle = LoopCycle(doseStore: doseStore, carbStore: carbStore, glucoseStore: glucoseStore,
                                            dosingDecisionStore: dosingDecisionStore, settingsProvider: settingsProvider,
                                            host: self, now: { TestingDate.currentTestingDate() })

    // References to registered notification center observers
    private var notificationObservers: [Any] = []
    private var overrideIntentObserver: NSKeyValueObservation? = nil

    var activeInsulin: InsulinValue? {
        displayState.activeInsulin
    }
    var activeCarbs: CarbValue? {
        displayState.activeCarbs
    }

    var latestGlucose: GlucoseSampleValue? {
        displayState.input?.glucoseHistory.last
    }

    private var insulinOnBoard: InsulinValue?
    
    private var liveActivityManager: LiveActivityManagerProxy?
    var lastReservoirValue: ReservoirValue? {
        doseStore.lastReservoirValue
    }


    var carbAbsorptionModel: CarbAbsorptionModel


    private(set) var volatilityBaseline: (value: Double?, date: Date)?

    private(set) var dosingStrategySelectionEnabled: Bool

    var usePositiveMomentumAndRCForManualBoluses: Bool

    var automationHistory: [AutomationHistoryEntry] {
        didSet {
            UserDefaults.standard.automationHistory = automationHistory
        }
    }

    lazy private var cancellables = Set<AnyCancellable>()

    init(
        lastLoopCompleted: Date?,
        temporaryPresetsManager: TemporaryPresetsManager,
        settingsProvider: SettingsProvider,
        doseStore: DoseStoreProtocol,
        glucoseStore: GlucoseStoreProtocol,
        carbStore: CarbStoreProtocol,
        crashRecoveryManager: CrashRecoveryManager,
        dosingDecisionStore: DosingDecisionStoreProtocol,
        trustedTimeOffset: @escaping () async -> TimeInterval,
        analyticsServicesManager: AnalyticsServicesManager?,
        carbAbsorptionModel: CarbAbsorptionModel,
        usePositiveMomentumAndRCForManualBoluses: Bool = true,
        dosingStrategySelectionEnabled: Bool = true,
    ) {

        self.lastLoopCompleted = lastLoopCompleted
        self.temporaryPresetsManager = temporaryPresetsManager
        self.settingsProvider = settingsProvider
        self.doseStore = doseStore
        self.glucoseStore = glucoseStore
        self.carbStore = carbStore
        self.crashRecoveryManager = crashRecoveryManager
        self.dosingDecisionStore = dosingDecisionStore
        self.trustedTimeOffset = trustedTimeOffset
        self.analyticsServicesManager = analyticsServicesManager
        self.carbAbsorptionModel = carbAbsorptionModel
        self.usePositiveMomentumAndRCForManualBoluses = usePositiveMomentumAndRCForManualBoluses
        self.automationHistory = UserDefaults.standard.automationHistory
        self.publishedMostRecentGlucoseDataDate = glucoseStore.latestGlucose?.startDate
        self.dosingStrategySelectionEnabled = dosingStrategySelectionEnabled
        self.publishedMostRecentPumpDataDate = mostRecentPumpDataDate
        
        if #available(iOS 16.2, *) {
            self.liveActivityManager = LiveActivityManager(
                glucoseStore: self.glucoseStore,
                doseStore: self.doseStore
            )
        }

        overrideIntentObserver = UserDefaults.appGroup?.observe(\.intentExtensionOverrideToSet, options: [.new], changeHandler: {[weak self] (defaults, change) in
            guard let name = change.newValue??.lowercased(), let appGroup = UserDefaults.appGroup else {
                return
            }

            guard let preset = self?.settings.overridePresets.first(where: {$0.name.lowercased() == name}) else {
                self?.logger.error("Override Intent: Unable to find override named '%s'", String(describing: name))
                return
            }
            
            self?.logger.default("Override Intent: setting override named '%s'", String(describing: name))
            // TemporaryPresetsManager handles presetActivated/Deactivated observers automatically
            self?.temporaryPresetsManager.scheduleOverride = preset.createOverride(enactTrigger: .remote("Siri"))
            Task { @MainActor in
                await self?.updateDisplayState()
            }
            // Remove the override from UserDefaults so we don't set it multiple times
            appGroup.intentExtensionOverrideToSet = nil
        })


        // Required for device settings in stored dosing decisions
        UIDevice.current.isBatteryMonitoringEnabled = true

        // Observe changes
        notificationObservers = [
            NotificationCenter.default.addObserver(
                forName: CarbStore.carbEntriesDidChange,
                object: self.carbStore,
                queue: nil
            ) { (note) -> Void in
                Task { @MainActor in
                    await self.updateDisplayState()
                    self.notify(forChange: .carbs)
                }
            },
            NotificationCenter.default.addObserver(
                forName: GlucoseStore.glucoseSamplesDidChange,
                object: self.glucoseStore,
                queue: nil
            ) { (note) in
                Task { @MainActor in
                    self.restartGlucoseValueStalenessTimer()
                    await self.updateDisplayState()
                    self.notify(forChange: .glucose)
                }
            },
            NotificationCenter.default.addObserver(
                forName: DoseStore.valuesDidChange,
                object: self.doseStore,
                queue: OperationQueue.main
            ) { (note) in
                Task { @MainActor in
                    await self.updateDisplayState()
                    self.notify(forChange: .insulin)
                }
            },
            NotificationCenter.default.addObserver(
                forName: .LoopDataUpdated,
                object: nil,
                queue: nil
            ) { (note) in
                let context = note.userInfo?[LoopDataManager.LoopUpdateContextKey] as! LoopUpdateContext.RawValue
                if case .preferences = LoopUpdateContext(rawValue: context) {
                    Task { @MainActor in
                        await self.updateDisplayState()
                        self.notify(forChange: .forecast)
                    }
                }
            }
        ]

        // Turn off preMeal when going into closed loop off mode
        // Cancel any active temp basal when going into closed loop off mode
        // The dispatch is necessary in case this is coming from a didSet already on the settings struct.
        
        withObservationTracking(of: settingsProvider.dosingEnabled) { [weak self] enabled in
            if let self, self.automationHistory.last?.enabled != enabled {
                self.automationHistory.append(AutomationHistoryEntry(startDate: self.now, enabled: enabled))

                // Clean up entries older than 36 hours; we should not be interpolating basal data before then.
                let now = now
                self.automationHistory = self.automationHistory.filter({ entry in
                    now.timeIntervalSince(entry.startDate) < .hours(36)
                })

                Task {
                    await self.updateDisplayState()
                }
            }

            if !enabled {
                temporaryPresetsManager.endPreMealOverride()
                Task {
                    try? await self?.cancelActiveTempBasal(for: .automaticDosingDisabled)
                }
            }
        }
    }

    // MARK: - Calculation state
    // Note: settings are now accessed via settingsProvider.settings (StoredSettings)
    // and overrides via temporaryPresetsManager. DIY's lockedSettings/mutateSettings
    // were removed as part of the Swift Concurrency migration.

    fileprivate let dataAccessQueue: DispatchQueue = DispatchQueue(label: "com.loudnate.Naterade.LoopDataManager.dataAccessQueue", qos: .utility)


    // MARK: - Background task management

    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    private func startBackgroundTask() {
        endBackgroundTask()
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "PersistenceController save") {
            self.endBackgroundTask()
        }
    }

    private func endBackgroundTask() {
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }

    func insulinModel(for type: InsulinType?) -> InsulinModel {
        switch type {
        case .fiasp:
            return ExponentialInsulinModelPreset.fiasp
        case .lyumjev:
            return ExponentialInsulinModelPreset.lyumjev
        case .afrezza:
            return ExponentialInsulinModelPreset.afrezza
        default:
            return settings.defaultRapidActingModel?.presetForRapidActingInsulin?.model ?? ExponentialInsulinModelPreset.rapidActingAdult
        }
    }

    func fetchData(
        for baseTime: Date? = nil,
        presumePresetEndingNow: Bool = false,
        ensureDosingCoverageStart: Date? = nil,
        ensureCarbCoverageStart: Date? = nil,
        projectOngoingDoses: Bool = false
    ) async throws -> StoredDataAlgorithmInput {
        try await cycle.fetchData(for: baseTime, presumePresetEndingNow: presumePresetEndingNow,
                                  ensureDosingCoverageStart: ensureDosingCoverageStart, ensureCarbCoverageStart: ensureCarbCoverageStart,
                                  projectOngoingDoses: projectOngoingDoses)
    }

    var enabledAlgorithmExperiments: Set<ExperimentOption> {
        var experiments: Set<ExperimentOption> = []
        if UserDefaults.standard.integralRetrospectiveCorrectionEnabled {
            experiments.insert(.integralRetrospectiveCorrection)
        }
        if UserDefaults.standard.glucoseBasedApplicationFactorEnabled {
            experiments.insert(.glucoseBasedApplicationFactor)
        }
        if UserDefaults.standard.guardAndRunwayEnabled {
            experiments.insert(.guardAndRunway)
        }
        return experiments
    }

    func loopingReEnabled() async {
        await updateDisplayState()
        self.notify(forChange: .forecast)
    }

    func updateDisplayState(forceStoreRemoteRecommendation: Bool = false) async {

        let newState = await cycle.displayState()
        if let input = newState.input {
            let lastManualBolusVisibilityWindowStartDate = now.addingTimeInterval(.days(-1))

            let lastStoredManualBolus = input.doses.last(
                where: {
                    $0.startDate >= lastManualBolusVisibilityWindowStartDate && $0.deliveryType == .bolus && $0.automatic == false
                })

            // Reflect the most recent user-entered bolus still present in the store. This
            // both updates to a newer bolus and clears/downgrades the value when the shown
            // bolus is no longer there (e.g. the user deleted it) — the previous logic only
            // ever moved forward, so a deleted bolus lingered in the "Last Bolus" footer.
            // A just-enacted bolus that the store may not have persisted yet is preserved.
            let recentlyEnactedCutoff = now.addingTimeInterval(-.minutes(1))
            if let lastStoredManualBolus {
                let shownIsNewerThanStored = (self.lastManualBolus?.startDate).map { $0 > lastStoredManualBolus.startDate } ?? false
                let shownWasJustEnacted = (self.lastManualBolus?.startDate).map { $0 >= recentlyEnactedCutoff } ?? false
                if !(shownIsNewerThanStored && shownWasJustEnacted) {
                    self.lastManualBolus = LastManualBolus(amount: lastStoredManualBolus.volume, startDate: lastStoredManualBolus.startDate)
                }
            } else if let lastManualBolus = self.lastManualBolus, lastManualBolus.startDate < recentlyEnactedCutoff {
                self.lastManualBolus = nil
            }
        }
        displayState = newState
        publishedMostRecentGlucoseDataDate = glucoseStore.latestGlucose?.startDate
        publishedMostRecentPumpDataDate = mostRecentPumpDataDate

        // DIY: Update Live Activity with current override and target range state
        liveActivityManager?.update(
            scheduleOverride: temporaryPresetsManager.scheduleOverride,
            preMealOverride: temporaryPresetsManager.preMealOverride,
            glucoseTargetRangeSchedule: settingsProvider.settings.glucoseTargetRangeSchedule,
            activeInsulin: displayState.activeInsulin
        )

        await updateRemoteRecommendation(force: forceStoreRemoteRecommendation)
    }

    /// True while the pod is loaned out, or until a force reclaim's audit rules; injected at wiring — see `LoopDataManager+PodLoan.swift`.
    var isPumpConnectionReleased: () -> Bool = { false }

    /// Cancel the active temp basal if it was automatically issued
    func cancelActiveTempBasal(for reason: CancelActiveTempBasalReason) async throws {
        let cancelled: Bool
        do {
            cancelled = try await cycle.cancelActiveTempBasal(
                for: reason,
                dosingStarted: { self.crashRecoveryManager.dosingStarted(dose: $0) },
                dosingFinished: { self.crashRecoveryManager.dosingFinished() })
        } catch {
            if reason == .maximumBasalRateChanged {
                throw CancelTempBasalFailedMaximumBasalRateChangedError(reason: error)
            } else {
                throw error
            }
        }
        guard cancelled else { return }

        // DIY: refresh post-dose forecast and persist an "updateRemoteRecommendation"
        // decision so Nightscout sees the post-cancel state.
        await updateDisplayState(forceStoreRemoteRecommendation: true)
    }

    func loop() async {
        let loopBaseTime = now

        logger.debug("Running Loop at %{public}@", String(describing: loopBaseTime))
        NotificationCenter.default.post(name: .LoopRunning, object: self)

        let outcome = await cycle.run(at: loopBaseTime)

        if outcome.enacted {
            logger.default("loop() completed successfully.")
            lastLoopCompleted = now
            let duration = lastLoopCompleted!.timeIntervalSince(loopBaseTime)
            analyticsServicesManager?.loopDidSucceed(duration)
        }
        if let loopError = outcome.error {
            analyticsServicesManager?.loopDidError(error: loopError)
        }
        NotificationCenter.default.post(name: .LoopCycleCompleted, object: self)

        // DIY: refresh post-dose forecast and persist an "updateRemoteRecommendation"
        // decision (Nightscout's Loop pill + forecast source — paired with the just-stored
        // "loop" decision by NightscoutService). Runs for both success and error paths.
        await updateDisplayState(forceStoreRemoteRecommendation: true)

        logger.default("Loop ended")
    }

    func recommendManualBolus(
        manualGlucoseSample: NewGlucoseSample? = nil,
        carbEntryChange: CarbEntryChange? = nil,
        truncatingActiveOverride: Bool = false
    ) async throws -> ManualBolusRecommendation? {
        try await cycle.recommendManualBolus(manualGlucoseSample: manualGlucoseSample, carbEntryChange: carbEntryChange,
                                             truncatingActiveOverride: truncatingActiveOverride)
    }

    public func totalDeliveredToday() async -> InsulinValue?
    {
        guard let data = displayState.input else {
            return nil
        }

        let now = data.predictionStart
        let midnight = Calendar.current.startOfDay(for: now)
        let history = InsulinDeliveryHistory(doses: data.doses, scheduledBasal: data.basal.loopKitSchedule(), coverageStart: midnight, end: now)

        return InsulinValue(
            startDate: midnight,
            value: history.totals(from: midnight, to: now).total
        )
    }

    /// Delivery history from midnight `days` days ago until now.
    func insulinDeliveryHistory(days: Int) async throws -> InsulinDeliveryHistory {
        let calendar = Calendar.current
        let end = now
        let start = calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: end)) ?? end.addingTimeInterval(.days(-Double(days)))

        let doses = try await doseStore.getNormalizedDoseEntries(start: start, end: nil)
        let earliestDose = doses.map(\.startDate).min()
        let basalStart = min(start, earliestDose ?? start)

        var basal = try await settingsProvider.getBasalHistory(startDate: basalStart, endDate: end)
        let basalHistoryStart = basal.first?.startDate ?? end
        if basalHistoryStart > basalStart, let schedule = settingsProvider.settings.basalRateSchedule {
            basal = schedule.truncatingBetween(start: basalStart, end: basalHistoryStart) + basal
        }

        return InsulinDeliveryHistory(
            doses: doses.map { $0.simpleDose(with: insulinModel(for: $0.insulinType)) },
            scheduledBasal: basal,
            coverageStart: max(start, earliestDose ?? end),
            end: end
        )
    }

    var iobValues: [InsulinValue] {
        dosesRelativeToBasal.insulinOnBoardTimeline().map(\.loopKit)
    }

    var dosesRelativeToBasal: [BasalRelativeDose] {
        displayState.output?.dosesRelativeToBasal ?? []
    }

    func updateRemoteRecommendation(force: Bool = false) async {
        await cycle.storeRemoteRecommendation(displayState: displayState, force: force)
    }

    // MARK: - Glucose Staleness

    private var glucoseValueStalenessTimer: Timer?

    private func restartGlucoseValueStalenessTimer() {
        stopGlucoseValueStalenessTimer()
        startGlucoseValueStalenessTimerIfNeeded()
    }

    private func stopGlucoseValueStalenessTimer() {
        glucoseValueStalenessTimer?.invalidate()
        glucoseValueStalenessTimer = nil
    }
       
    func startGlucoseValueStalenessTimerIfNeeded() {
        guard let fireDate = glucoseValueStaleDate,
              glucoseValueStalenessTimer == nil
        else { return }
        
        glucoseValueStalenessTimer = Timer(fire: fireDate, interval: 0, repeats: false) { (_) in
            Task { @MainActor in
                self.notify(forChange: .glucose)
            }
        }
        RunLoop.main.add(glucoseValueStalenessTimer!, forMode: .default)
    }

    private var glucoseValueStaleDate: Date? {
        guard let latestGlucoseDataDate = glucoseStore.latestGlucose?.startDate else { return nil }
        return latestGlucoseDataDate.addingTimeInterval(LoopCoreConstants.inputDataRecencyInterval)
    }
}

// MARK: - Background task management
extension LoopDataManager: LoopCycleHost {
    var overrideHistory: TemporaryScheduleOverrideHistory {
        temporaryPresetsManager.presetHistory
    }

    var activeOverride: TemporaryScheduleOverride? {
        temporaryPresetsManager.activeOverride
    }

    /// While the pod is lent the cycle computes but never enacts (dosingEnabled is untouched), and the
    /// watch stores the cycles' decisions; the phone stores none.
    var holdsPump: Bool {
        !isPumpConnectionReleased()
    }

    var isClosedLoop: Bool {
        settingsProvider.dosingEnabled
    }

    var controllerStatus: StoredDosingDecision.ControllerStatus {
        UIDevice.current.controllerStatus
    }
}

extension LoopDataManager: PersistenceControllerDelegate {
    nonisolated func persistenceControllerWillSave(_ controller: PersistenceController) {
        Task {
            await startBackgroundTask()
        }
    }

    nonisolated func persistenceControllerDidSave(_ controller: PersistenceController, error: PersistenceController.PersistenceControllerError?) {
        Task {
            await endBackgroundTask()
        }
    }
}


// MARK: - Intake
extension LoopDataManager {
    /// Adds and stores glucose samples
    ///
    /// - Parameters:
    ///   - samples: The new glucose samples to store
    ///   - completion: A closure called once upon completion
    ///   - result: The stored glucose values
    func addGlucose(_ samples: [NewGlucoseSample]) async throws -> [StoredGlucoseSample] {
        return try await glucoseStore.addGlucoseSamples(samples)
    }

    /// Adds and stores carb data, and recommends a bolus if needed
    ///
    /// - Parameters:
    ///   - carbEntry: The new carb value, stored once however often it is retried
    func addCarbEntry(_ carbEntry: NewCarbEntry) async throws -> StoredCarbEntry {
        let storedCarbEntry = try await carbStore.addCarbEntry(carbEntry)
        self.temporaryPresetsManager.endPreMealOverride()
        return storedCarbEntry
    }

    func replaceCarbEntry(_ oldEntry: StoredCarbEntry, with update: CarbEntryUpdate) async throws -> StoredCarbEntry {
        let storedCarbEntry = try await carbStore.replaceCarbEntry(oldEntry, withEntry: update)
        self.temporaryPresetsManager.endPreMealOverride()
        return storedCarbEntry
    }

    @discardableResult
    func deleteCarbEntry(_ oldEntry: StoredCarbEntry) async throws -> Bool {
        try await carbStore.deleteCarbEntry(oldEntry)
    }

    /// Logs a new external bolus insulin dose in the DoseStore and HealthKit
    ///
    /// - Parameters:
    ///   - startDate: The date the dose was started at.
    ///   - value: The number of Units in the dose.
    ///   - insulinModel: The type of insulin model that should be used for the dose.
    func addManuallyEnteredDose(startDate: Date, units: Double, insulinType: InsulinType? = nil) async {
        let syncIdentifier = Data(UUID().uuidString.utf8).hexadecimalString
        let dose = DoseEntry(type: .bolus, startDate: startDate, value: units, unit: .units, decisionId: nil, syncIdentifier: syncIdentifier, insulinType: insulinType, manuallyEntered: true)

        do {
            try await doseStore.addDoses([dose], from: nil)
            self.notify(forChange: .insulin)
        } catch {
            logger.error("Error storing manual dose: %{public}@", error.localizedDescription)
        }
    }

    var currentDosingStrategy: AutomaticDosingStrategy {
        dosingStrategySelectionEnabled ? settingsProvider.settings.automaticDosingStrategy : .automaticBolus
    }

    func algorithmExperiments(for dosingStrategy: AutomaticDosingStrategy, guardAndRunway: GuardAndRunwayOutput? = nil) -> [AlgorithmExperiment] {
        AlgorithmExperiment.records(enabled: enabledAlgorithmExperiments, dosingStrategy: dosingStrategy,
                                    volatilityBaseline: volatilityBaseline?.value, guardAndRunway: guardAndRunway)
    }

    /// The median σ5 over the last four weeks, for guard + runway's volatility band. Nil until there is a day of glucose.
    func currentVolatilityBaseline(at date: Date) async -> Double? {
        if let volatilityBaseline, abs(date.timeIntervalSince(volatilityBaseline.date)) < (volatilityBaseline.value == nil ? .hours(1) : .days(1)) {
            return volatilityBaseline.value
        }
        do {
            let glucose = try await glucoseStore.getGlucoseSamples(start: date.addingTimeInterval(.days(-28)), end: date)
            let baseline = GlucoseVolatility.baseline(glucose)
            volatilityBaseline = (baseline, date)
            return baseline
        } catch {
            logger.error("Error fetching glucose for volatility baseline: %{public}@", error.localizedDescription)
            return volatilityBaseline?.value
        }
    }

    func storeManualBolusDosingDecision(_ bolusDosingDecision: BolusDosingDecision, withDate date: Date) async {
        guard let dosingDecision = cycle.manualBolusDosingDecision(bolusDosingDecision, withDate: date) else { return }
        Task { await dosingDecisionStore.storeDosingDecision(dosingDecision) }
    }


    private func notify(forChange context: LoopUpdateContext) {
        NotificationCenter.default.post(name: .LoopDataUpdated,
            object: self,
            userInfo: [
                type(of: self).LoopUpdateContextKey: context.rawValue
            ]
        )
    }

    /// Estimate glucose effects of suspending insulin delivery over duration of insulin action starting at the specified date
    func insulinDeliveryEffect(at date: Date, insulinType: InsulinType) async throws -> [GlucoseEffect] {
        let startSuspend = date
        let insulinEffectDuration = insulinModel(for: insulinType).effectDuration
        let endSuspend = startSuspend.addingTimeInterval(insulinEffectDuration)

        var suspendDoses: [BasalRelativeDose] = []

        let basal = try await settingsProvider.getBasalHistory(startDate: startSuspend, endDate: endSuspend)
        let sensitivity = try await settingsProvider.getInsulinSensitivityHistory(startDate: startSuspend, endDate: endSuspend)

        // Iterate over basal entries during suspension of insulin delivery
        for (index, basalItem) in basal.enumerated() {
            var startSuspendDoseDate: Date
            var endSuspendDoseDate: Date

            guard basalItem.endDate > startSuspend && basalItem.startDate < endSuspend else {
                continue
            }

            if index == 0 {
                startSuspendDoseDate = startSuspend
            } else {
                startSuspendDoseDate = basalItem.startDate
            }

            if index == basal.count - 1 {
                endSuspendDoseDate = endSuspend
            } else {
                endSuspendDoseDate = basal[index + 1].startDate
            }

            let suspendDose = BasalRelativeDose(
                type: .basal(scheduledRate: basalItem.value),
                startDate: startSuspendDoseDate,
                endDate: endSuspendDoseDate,
                volume: 0
            )

            suspendDoses.append(suspendDose)
        }

        // Calculate predicted glucose effect of suspending insulin delivery
        return suspendDoses.glucoseEffects(
            insulinSensitivityHistoryMgdlPerUnit: sensitivity.algorithmMgdlSchedule()
        ).filterDateRange(startSuspend, endSuspend).map(\.loopKit)
    }

    func computeSimpleBolusRecommendation(at date: Date, mealCarbs: LoopQuantity?, manualGlucose: LoopQuantity?) -> BolusDosingDecision? {

        var dosingDecision = BolusDosingDecision(for: .simpleBolus)

        // Determine activeInsulin
        let activeInsulin: LoopQuantity
        if let iob = displayState.activeInsulin?.value {
            activeInsulin = LoopQuantity.init(unit: .internationalUnit, doubleValue: iob)
        } else if let input = displayState.input {
            let basal = input.basal
            let dosesRelativeToBasal: [BasalRelativeDose] = input.doses.annotated(with: basal)
            let iob = dosesRelativeToBasal.insulinOnBoard(at: date)
            activeInsulin = LoopQuantity.init(unit: .internationalUnit, doubleValue: iob)
        } else {
            return nil
        }
        

        guard let suspendThreshold = settingsProvider.settings.suspendThreshold?.quantity,
              let carbRatioSchedule = temporaryPresetsManager.carbRatioScheduleApplyingOverrideHistory,
              let correctionRangeSchedule = temporaryPresetsManager.effectiveCorrectionRangeSchedule(presumingMealEntry: mealCarbs != nil),
              let sensitivitySchedule = temporaryPresetsManager.insulinSensitivityScheduleApplyingOverrideHistory
        else {
            // Settings incomplete; should never get here; remove when therapy settings non-optional
            return nil
        }

        if let scheduleOverride = temporaryPresetsManager.scheduleOverride, !scheduleOverride.hasFinished() {
            dosingDecision.scheduleOverride = temporaryPresetsManager.scheduleOverride
        }

        dosingDecision.glucoseTargetRangeSchedule = correctionRangeSchedule

        var notice: BolusRecommendationNotice? = nil
        if let manualGlucose = manualGlucose {
            let glucoseValue = SimpleGlucoseValue(startDate: date, quantity: manualGlucose)
            if manualGlucose < suspendThreshold {
                notice = .glucoseBelowSuspendThreshold(minGlucose: glucoseValue)
            } else {
                let correctionRange = correctionRangeSchedule.quantityRange(at: date)
                if manualGlucose < correctionRange.lowerBound {
                    notice = .currentGlucoseBelowTarget(glucose: glucoseValue)
                }
            }
        }

        let bolusAmount = SimpleBolusCalculator.recommendedInsulin(
            mealCarbs: mealCarbs,
            manualGlucose: manualGlucose,
            activeInsulin: activeInsulin,
            carbRatioSchedule: carbRatioSchedule,
            correctionRangeSchedule: correctionRangeSchedule,
            sensitivitySchedule: sensitivitySchedule,
            at: date)

        dosingDecision.manualBolusRecommendation = ManualBolusRecommendationWithDate(
            recommendation: ManualBolusRecommendation(amount: bolusAmount.doubleValue(for: .internationalUnit), notice: notice),
            date: now
        )

        return dosingDecision
    }


}


protocol BolusDurationEstimator: AnyObject {
    func estimateBolusDuration(bolusUnits: Double) -> TimeInterval?
}

private extension TemporaryScheduleOverride {
    func isBasalRateScheduleOverriden(at date: Date) -> Bool {
        guard isActive(at: date), let basalRateMultiplier = settings.basalRateMultiplier else {
            return false
        }
        return abs(basalRateMultiplier - 1.0) >= .ulpOfOne
    }
}

extension ManualBolusRecommendationWithDate {
    init?(_ bolusRecommendationDate: (recommendation: ManualBolusRecommendation, date: Date)?) {
        guard let bolusRecommendationDate = bolusRecommendationDate else {
            return nil
        }
        self.init(recommendation: bolusRecommendationDate.recommendation, date: bolusRecommendationDate.date)
    }
}

extension LoopDataManager: ServicesManagerDelegate {
    
    // Remote Overrides
    func enactOverride(name: String, duration: TemporaryScheduleOverride.Duration?, remoteAddress: String) async throws {
        
        guard let preset = settingsProvider.settings.overridePresets.first(where: { $0.name == name }) else {
            throw EnactOverrideError.unknownPreset(name)
        }
        
        var remoteOverride = preset.createOverride(enactTrigger: .remote(remoteAddress))
        
        if let duration {
            remoteOverride.duration = duration
        }

        temporaryPresetsManager.scheduleOverride = remoteOverride
    }
    
    
    func cancelCurrentOverride() async throws {
        temporaryPresetsManager.scheduleOverride = nil
    }
    

    enum EnactOverrideError: LocalizedError {
        
        case unknownPreset(String)
        
        var errorDescription: String? {
            switch self {
            case .unknownPreset(let presetName):
                return String(format: NSLocalizedString("Unknown preset: %1$@", comment: "Override error description: unknown preset (1: preset name)."), presetName)
            }
        }
    }
    
    //Carb Entry
    
    func deliverCarbs(amountInGrams: Double, absorptionTime: TimeInterval?, foodType: String?, startDate: Date?) async throws {
        
        let absorptionTime = absorptionTime ?? LoopCoreConstants.defaultCarbAbsorptionTimes.medium
        if absorptionTime < LoopConstants.minCarbAbsorptionTime || absorptionTime > LoopConstants.maxCarbAbsorptionTime {
            throw CarbActionError.invalidAbsorptionTime(absorptionTime)
        }
        
        guard amountInGrams > 0.0 else {
            throw CarbActionError.invalidCarbs
        }
        
        guard amountInGrams <= LoopConstants.maxCarbEntryQuantity.doubleValue(for: .gram) else {
            throw CarbActionError.exceedsMaxCarbs
        }
        
        if let startDate = startDate {
            let maxStartDate = now.addingTimeInterval(LoopConstants.maxCarbEntryFutureTime)
            let minStartDate = now.addingTimeInterval(LoopConstants.maxCarbEntryPastTime)
            guard startDate <= maxStartDate  && startDate >= minStartDate else {
                throw CarbActionError.invalidStartDate(startDate)
            }
        }
        
        let quantity = LoopQuantity(unit: .gram, doubleValue: amountInGrams)
        let candidateCarbEntry = NewCarbEntry(syncIdentifier: UUID().uuidString, quantity: quantity, startDate: startDate ?? now, foodType: foodType, absorptionTime: absorptionTime)

        let _ = try await carbStore.addCarbEntry(candidateCarbEntry)
    }
    
    enum CarbActionError: LocalizedError {
        
        case invalidAbsorptionTime(TimeInterval)
        case invalidStartDate(Date)
        case exceedsMaxCarbs
        case invalidCarbs
        
        var errorDescription: String? {
            switch  self {
            case .exceedsMaxCarbs:
                return NSLocalizedString("Exceeds maximum allowed carbs", comment: "Carb error description: carbs exceed maximum amount.")
            case .invalidCarbs:
                return NSLocalizedString("Invalid carb amount", comment: "Carb error description: invalid carb amount.")
            case .invalidAbsorptionTime(let absorptionTime):
                let absorptionHoursFormatted = Self.numberFormatter.string(from: absorptionTime.hours) ?? ""
                return String(format: NSLocalizedString("Invalid absorption time: %1$@ hours", comment: "Carb error description: invalid absorption time. (1: Input duration in hours)."), absorptionHoursFormatted)
            case .invalidStartDate(let startDate):
                let startDateFormatted = Self.dateFormatter.string(from: startDate)
                return String(format: NSLocalizedString("Start time is out of range: %@", comment: "Carb error description: invalid start time is out of range."), startDateFormatted)
            }
        }
        
        static var numberFormatter: NumberFormatter = {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            return formatter
        }()
        
        static var dateFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.timeStyle = .medium
            return formatter
        }()
    }
}

extension LoopDataManager: SimpleBolusViewModelDelegate {

    func insulinOnBoard(at date: Date) async -> InsulinValue? {
        displayState.activeInsulin
    }

    var maximumBolus: Double? {
        settingsProvider.settings.maximumBolus
    }
    
    var suspendThreshold: LoopQuantity? {
        settingsProvider.settings.suspendThreshold?.quantity
    }
    
    func enactBolus(units: Double, decisionId: UUID?, activationType: BolusActivationType) async throws {
        let startDate = now
        try await deliveryDelegate?.enactBolus(units: units, decisionId: decisionId, activationType: activationType)
        lastManualBolus = LastManualBolus(amount: units, startDate: startDate)
    }
    
}

extension LoopDataManager: BolusEntryViewModelDelegate {    
    func saveGlucose(sample: LoopKit.NewGlucoseSample) async throws -> LoopKit.StoredGlucoseSample {
        let storedSamples = try await addGlucose([sample])
        return storedSamples.first!
    }

    var preMealOverride: TemporaryScheduleOverride? {
        temporaryPresetsManager.preMealOverride
    }

    var mostRecentGlucoseDataDate: Date? {
        displayState.input?.glucoseHistory.last?.startDate
    }

    var mostRecentPumpDataDate: Date? {
        let date = doseStore.lastAddedPumpData
        return date == .distantPast ? nil : date
    }

    func effectiveGlucoseTargetRangeSchedule(presumingMealEntry: Bool) -> GlucoseRangeSchedule? {
        temporaryPresetsManager.effectiveCorrectionRangeSchedule(presumingMealEntry: presumingMealEntry)
    }

    func generatePrediction(
        carbEntryChange: CarbEntryChange?,
        potentialDose: SimpleInsulinDose?,
        manualGlucose: NewGlucoseSample?
    ) async throws -> (historicGlucose: [StoredGlucoseSample], predictedGlucose: [PredictedGlucoseValue]) {

        var endingPremealOverride = false

        if carbEntryChange != nil,
            let activeOverride = temporaryPresetsManager.activeOverride,
            activeOverride.context == .preMeal
        {
            endingPremealOverride = true
        }

        var input = try await fetchData(
            for: now,
            presumePresetEndingNow: endingPremealOverride,
            ensureCarbCoverageStart: carbEntryChange?.startDate
        )

        // Add potential bolus, carbs, manual glucose
        input = input
            .addingDose(dose: potentialDose)
            .addingGlucoseSample(sample: manualGlucose?.asStoredGlucoseSample)
            .removingCarbEntry(carbEntry: carbEntryChange?.originalEntry)
            .addingCarbEntry(carbEntry: carbEntryChange?.asStoredCarbEntry)

        let prediction = try input.predictGlucose()

        return (historicGlucose: input.glucoseHistory, predictedGlucose: prediction.map(\.loopKit))
    }
}


extension LoopDataManager: CarbEntryViewModelDelegate {
    func isScheduleOverrideActive(at date: Date) -> Bool {
        temporaryPresetsManager.isScheduleOverrideActive(at: date)
    }
    
    var defaultAbsorptionTimes: DefaultAbsorptionTimes {
        LoopCoreConstants.defaultCarbAbsorptionTimes
    }
    func getGlucoseSamples(start: Date?, end: Date?) async throws -> [StoredGlucoseSample] {
        try await glucoseStore.getGlucoseSamples(start: start, end: end)
    }
}

extension LoopDataManager: FavoriteFoodInsightsViewModelDelegate {
    func selectedFavoriteFoodLastEaten(_ favoriteFood: StoredFavoriteFood) async throws -> Date? {
        try await carbStore.getCarbEntries(start: nil, end: nil, dateAscending: false, fetchLimit: 1, with: favoriteFood.id).first?.startDate
    }

    
    func getFavoriteFoodCarbEntries(_ favoriteFood: StoredFavoriteFood) async throws -> [LoopKit.StoredCarbEntry] {
        try await carbStore.getCarbEntries(start: nil, end: nil, dateAscending: false, fetchLimit: nil, with: favoriteFood.id)
    }
    
    func getHistoricalChartsData(start: Date, end: Date) async throws -> HistoricalChartsData {
        // Need to get insulin data from any active doses that might affect this time range
        var dosesStart = start.addingTimeInterval(-InsulinMath.defaultInsulinActivityDuration)
        let doses = try await doseStore.getNormalizedDoseEntries(
            start: dosesStart,
            end: end
        )

        dosesStart = doses.map { $0.startDate }.min() ?? dosesStart

        let basal = try await settingsProvider.getBasalHistory(startDate: dosesStart, endDate: end)

        let carbEntries = try await carbStore.getCarbEntries(start: start, end: end)

        let carbRatio = try await settingsProvider.getCarbRatioHistory(startDate: start, endDate: end)

        let glucose = try await glucoseStore.getGlucoseSamples(start: start, end: end)

        let sensitivityStart = min(start, dosesStart)

        let sensitivity = try await settingsProvider.getInsulinSensitivityHistory(startDate: sensitivityStart, endDate: end)

        let overrides = temporaryPresetsManager.presetHistory.getOverrideHistory(startDate: sensitivityStart, endDate: end)

        guard !sensitivity.isEmpty else {
            throw LoopError.configurationError(.insulinSensitivitySchedule)
        }

        let sensitivityWithOverrides = overrides.applySensitivity(over: sensitivity)

        guard !basal.isEmpty else {
            throw LoopError.configurationError(.basalRateSchedule)
        }
        let basalWithOverrides = overrides.applyBasal(over: basal)

        guard !carbRatio.isEmpty else {
            throw LoopError.configurationError(.carbRatioSchedule)
        }
        let carbRatioWithOverrides = overrides.applyCarbRatio(over: carbRatio)

        // Overlay basal history on basal doses, splitting doses to get amount delivered relative to basal.
        // annotated() can emit segments out of startDate order when input doses overlap (e.g. a bolus
        // during a temp basal, or overlapping pending/committed doses), so sort for downstream
        // binary-search filterDateRange.
        let annotatedDoses = doses
            .map({ $0.simpleDose(with: insulinModel(for: $0.insulinType)) })
            .annotated(with: basalWithOverrides.algorithmSchedule())
            .sorted { $0.startDate < $1.startDate }

        // Standard mid-absorption ISF model, matching LoopAlgorithm's prediction
        // path — keeps this review's carb absorption consistent with the
        // algorithm (dose-time `glucoseEffects` is legacy backwards-compat).
        let insulinEffects = annotatedDoses.glucoseEffectsMidAbsorptionISF(
            insulinSensitivityHistoryMgdlPerUnit: sensitivityWithOverrides.algorithmMgdlSchedule(),
            from: start.addingTimeInterval(-CarbMath.maximumAbsorptionTimeInterval).dateFlooredToTimeInterval(GlucoseMath.defaultDelta),
            to: nil)

        // ICE
        let insulinCounteractionEffects = glucose.counteractionEffects(to: insulinEffects)

        // Carb Effects
        let carbStatus = carbEntries.map(
            to: insulinCounteractionEffects,
            carbRatio: carbRatioWithOverrides.algorithmSchedule(),
            insulinSensitivityMgdlPerUnit: sensitivityWithOverrides.algorithmMgdlSchedule()
        )

        let carbEffects = carbStatus.dynamicGlucoseEffects(
            from: start,
            to: end.addingTimeInterval(InsulinMath.defaultInsulinActivityDuration),
            carbRatios: carbRatioWithOverrides.algorithmSchedule(),
            insulinSensitivitiesMgdlPerUnit: sensitivityWithOverrides.algorithmMgdlSchedule(),
            absorptionModel: CarbAbsorptionModel.piecewiseLinear.model
        )
        
        let carbAbsorptionReview = CarbAbsorptionReview(
            carbEntries: carbEntries,
            carbStatuses: carbStatus,
            effectsVelocities: insulinCounteractionEffects.map(\.loopKit),
            carbEffects: carbEffects.map(\.loopKit)
        )
        
        let trimmedDoses = annotatedDoses.filterDateRange(start, end)
        let trimmedIOBValues = annotatedDoses.insulinOnBoardTimeline().filterDateRange(start, end).map(\.loopKit)
        
        let historicalChartsData = HistoricalChartsData(
            glucoseValues: glucose,
            carbEntries: carbEntries,
            doses: trimmedDoses,
            iobValues: trimmedIOBValues,
            carbAbsorptionReview: carbAbsorptionReview
        )

        return historicalChartsData
    }
}

extension LoopDataManager: ManualDoseViewModelDelegate {
    var pumpInsulinType: InsulinType? {
        deliveryDelegate?.pumpInsulinType
    }

    var settings: StoredSettings {
        settingsProvider.settings
    }
    
    var scheduleOverride: TemporaryScheduleOverride? {
        temporaryPresetsManager.scheduleOverride
    }
    
    func insulinActivityDuration(for type: InsulinType?) -> TimeInterval {
        return insulinModel(for: type).effectDuration
    }

    var algorithmDisplayState: AlgorithmDisplayState {
        get async { return displayState }
    }

}


extension LoopDataManager : AlgorithmDisplayStateProvider {
    var algorithmState: AlgorithmDisplayState {
        return displayState
    }
}

extension LoopDataManager: DiagnosticReportGenerator {
    func generateDiagnosticReport() async -> String {
        let (algoInput, algoOutput) = displayState.asTuple

        var loopError: Error?
        var doseRecommendation: LoopAlgorithmDoseRecommendation?

        if let algoOutput {
            switch algoOutput.recommendationResult {
            case .success(let recommendation):
                doseRecommendation = recommendation
            case .failure(let error):
                loopError = error
            }
        }

        let entries: [String] = [
            "## LoopDataManager",
            "settings: \(String(reflecting: settingsProvider.settings))",

            "* presetHistory: \(temporaryPresetsManager.presetHistory.recentEvents.map(String.init(describing:)))",

            "insulinCounteractionEffects: [",
            "* GlucoseEffectVelocity(start, end, mg/dL/min)",
            (algoOutput?.effects.insulinCounteraction ?? []).reduce(into: "", { (entries, entry) in
                entries.append("* \(entry.startDate), \(entry.endDate), \(entry.mgdlPerSecond * 60)\n")
            }),
            "]",

            "insulinEffect: [",
            "* GlucoseEffect(start, mg/dL)",
            (algoOutput?.effects.insulin ?? []).reduce(into: "", { (entries, entry) in
                entries.append("* \(entry.startDate), \(entry.mgdl)\n")
            }),
            "]",

            "carbEffect: [",
            "* GlucoseEffect(start, mg/dL)",
            (algoOutput?.effects.carbs ?? []).reduce(into: "", { (entries, entry) in
                entries.append("* \(entry.startDate), \(entry.mgdl)\n")
            }),
            "]",

            "predictedGlucose: [",
            "* PredictedGlucoseValue(start, mg/dL)",
            (algoOutput?.predictedGlucose ?? []).reduce(into: "", { (entries, entry) in
                entries.append("* \(entry.startDate), \(entry.mgdl)\n")
            }),
            "]",

            "integralRetrospectiveCorrectionEnabled: \(UserDefaults.standard.integralRetrospectiveCorrectionEnabled)",

            "retrospectiveCorrection: [",
            "* GlucoseEffect(start, mg/dL)",
            (algoOutput?.effects.retrospectiveCorrection ?? []).reduce(into: "", { (entries, entry) in
                entries.append("* \(entry.startDate), \(entry.mgdl)\n")
            }),
            "]",

            "glucoseMomentumEffect: \(algoOutput?.effects.momentum ?? [])",
            "recommendedAutomaticDose: \(String(describing: doseRecommendation))",
            "lastLoopCompleted: \(String(describing: lastLoopCompleted))",
            "carbsOnBoard: \(String(describing: algoOutput?.activeCarbs))",
            "insulinOnBoard: \(String(describing: algoOutput?.activeInsulin))",
            "error: \(String(describing: loopError))",
            "overrideInUserDefaults: \(String(describing: UserDefaults.appGroup?.intentExtensionOverrideToSet))",
            "algorithmExperiments: \(algoInput.map { $0.experiments.map(\.rawValue).sorted() } ?? [])",
            "volatilityBaseline: \(String(describing: algoInput?.volatilityBaseline))",
            ""
            ]
        return entries.joined(separator: "\n")

    }
}

extension LoopDataManager: LoopControl {
    
    func scheduledBasalRate(at date: Date? = nil) -> Double? {
        settings.basalRateSchedule?.value(at: date ?? now)
    }
    
    func currentBasalRate(at date: Date? = nil) -> Double? {
        guard let scheduledBasalRate = scheduledBasalRate(at: date ?? now) else {
            return nil
        }
        
        return deliveryDelegate?.basalDeliveryState?.currentBasalRate(currentScheduledBasalRate: scheduledBasalRate)
    }
    
    var automatedTreatmentState: AutomatedTreatmentState? {
        guard let input = displayState.input else {
            return nil
        }

        let now = now

        // need to compare amounts that the pump can actually deliver, instead of calculated amounts
        guard let neutralBasal = input.basal.closestPrior(to: now)?.value,
              let deliverableNeutralBasal = deliveryDelegate?.roundBolusVolume(units: neutralBasal),
              let currentlyDeliveredBasalRate = currentBasalRate(at: now)
        else {
            return nil
        }

        if currentlyDeliveredBasalRate > deliverableNeutralBasal {
            return .increasedInsulin
        } else if currentlyDeliveredBasalRate < deliverableNeutralBasal {
            if currentlyDeliveredBasalRate == 0 {
                return .minimumDelivery
            } else {
                return .decreasedInsulin
            }
        } else {
            let recentAutomaticBoluses = input.doses.filter({ dose in
                dose.deliveryType == .bolus &&
                dose.automatic &&
                dose.startDate.addingTimeInterval(.minutes(5)) > now
            })
            if !recentAutomaticBoluses.isEmpty {
                return .increasedInsulin
            }
            return scheduledBasalRate(at: now) != deliverableNeutralBasal ? .neutralOverride : .neutralNoOverride
        }
    }
}

extension LoopDataManager: AutomationHistoryProvider {
    func automationHistory(from start: Date, to end: Date) async throws -> [AbsoluteScheduleValue<Bool>] {
        return automationHistory.toTimeline(from: start, to: end)
    }
}
