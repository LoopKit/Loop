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
import LoopKitUI
import LoopCore
import WidgetKit
import LoopAlgorithm


struct AlgorithmDisplayState {
    var input: StoredDataAlgorithmInput?
    var output: AlgorithmOutput<StoredCarbEntry>?

    var activeInsulin: InsulinValue? {
        guard let input, let value = output?.activeInsulin else {
            return nil
        }
        return InsulinValue(startDate: input.predictionStart, value: value)
    }

    var activeCarbs: CarbValue? {
        guard let input, let value = output?.activeCarbs else {
            return nil
        }
        return CarbValue(startDate: input.predictionStart, value: value)
    }

    var asTuple: (algoInput: StoredDataAlgorithmInput?, algoOutput: AlgorithmOutput<StoredCarbEntry>?) {
        return (algoInput: input, algoOutput: output)
    }
}

protocol DeliveryDelegate: AnyObject {
    var isSuspended: Bool { get }
    var isManualTempBasalRunning: Bool { get }
    var pumpInsulinType: InsulinType? { get }
    var basalDeliveryState: PumpManagerStatus.BasalDeliveryState? { get }
    var isPumpConfigured: Bool { get }
    var pumpManagerStatus: PumpManagerStatus? { get }
    var pumpStatusHighlight: DeviceStatusHighlight? { get }
    var cgmManagerStatus: CGMManagerStatus? { get }

    func enact(bolus: Double?, tempBasal: TempBasalRecommendation?, decisionId: UUID?) async throws
    func enactBolus(units: Double, decisionId: UUID?, activationType: BolusActivationType) async throws
    func roundBasalRate(unitsPerHour: Double) -> Double
    func roundBolusVolume(units: Double) -> Double
}

extension PumpManagerStatus.BasalDeliveryState {
    var currentTempBasal: DoseEntry? {
        switch self {
        case .tempBasal(let dose):
            return dose
        default:
            return nil
        }
    }
    
    func currentBasalRate(currentScheduledBasalRate: Double) -> Double? {
        switch self {
        case .tempBasal(let dose):
            return dose.unitsPerHour
        case .suspended:
            return 0
        case .pumpInoperable:
            return nil
        default:
            return currentScheduledBasalRate
        }
    }
}

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
        displayState.output?.predictedGlucose
    }

    var tempBasalRecommendation: TempBasalRecommendation? {
        displayState.output?.recommendation?.automatic?.basalAdjustment
    }

    var automaticBolusRecommendation: Double? {
        displayState.output?.recommendation?.automatic?.bolusUnits
    }

    var automaticRecommendation: AutomaticDoseRecommendation? {
        displayState.output?.recommendation?.automatic
    }

    @Published private(set) var lastLoopCompleted: Date?
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

    private var lastManualBolusRecommendation: ManualBolusRecommendation?

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
        projectOngoingDoses: Bool = false
    ) async throws -> StoredDataAlgorithmInput {
        // Need to fetch doses back as far as t - (DIA + DCA) for Dynamic carbs
        let dosesInputHistory = CarbMath.maximumAbsorptionTimeInterval + InsulinMath.defaultInsulinActivityDuration

        let baseTime = baseTime ?? now

        var dosesStart = baseTime.addingTimeInterval(-dosesInputHistory)

        // Ensure dosing data goes back before ensureDosingCoverageStart, if specified
        if let ensureDosingCoverageStart {
            dosesStart = min(ensureDosingCoverageStart, dosesStart)
        }

        // When projectOngoingDoses is true (display path), pass end:nil so DoseStore
        // extends a mutable suspend to its insulin-activity-duration fallback. Doses
        // already in flight (e.g. a manual temp basal) keep their actual endDate
        // either way; only the suspend extension is gated on this flag.
        let doses = try await doseStore.getNormalizedDoseEntries(
            start: dosesStart,
            end: projectOngoingDoses ? nil : baseTime
        )

        // Doses that were included because they cover dosesStart might have a start time earlier than dosesStart
        // This moves the start time back to ensure basal covers
        dosesStart = min(dosesStart, doses.map { $0.startDate }.min() ?? dosesStart)

        // Doses with a start time before baseTime might still end after baseTime
        let dosesEnd = max(baseTime, doses.map { $0.endDate }.max() ?? baseTime)

        let rawBasal = try await settingsProvider.getBasalHistory(startDate: dosesStart, endDate: dosesEnd)

        guard !rawBasal.isEmpty else {
            throw LoopError.configurationError(.basalRateSchedule)
        }

        // Collapse contiguous same-rate basal entries. getBasalHistory projects the
        // daily BasalRateSchedule onto absolute time and splits at every local
        // midnight even when the rate doesn't change; InsulinDose.annotated(with:)
        // then splits the suspend (or any long basal-typed dose) at each of those
        // boundaries, and the continuous-delivery IOB integrator doesn't join the
        // resulting sub-doses perfectly across the boundary -- visible as a small
        // bump in Active Insulin at midnight even with a single-rate schedule.
        let basal: [AbsoluteScheduleValue<Double>] = rawBasal.reduce(into: []) { acc, entry in
            if let last = acc.last, last.value == entry.value, last.endDate == entry.startDate {
                acc[acc.count - 1] = AbsoluteScheduleValue(startDate: last.startDate, endDate: entry.endDate, value: last.value)
            } else {
                acc.append(entry)
            }
        }

        let forecastEndTime = baseTime.addingTimeInterval(InsulinMath.defaultInsulinActivityDuration).dateCeiledToTimeInterval(GlucoseMath.defaultDelta)

        let carbsStart = baseTime.addingTimeInterval(LoopConstants.maxCarbEntryPastTime + .minutes(-1)) // additional minute to handle difference in seconds between carb entry and carb ratio

        // Include future carbs in query, but filter out ones entered after basetime. The filtering is only applicable when running in a retrospective situation.
        let carbEntries = try await carbStore.getCarbEntries(
            start: carbsStart,
            end: forecastEndTime
        ).filter {
            $0.userCreatedDate ?? $0.startDate < baseTime
        }

        let carbRatio = try await settingsProvider.getCarbRatioHistory(
            startDate: carbsStart,
            endDate: forecastEndTime
        )

        guard !carbRatio.isEmpty else {
            throw LoopError.configurationError(.carbRatioSchedule)
        }

        let glucose = try await glucoseStore.getGlucoseSamples(start: carbsStart, end: baseTime)

        let dosesWithModel = doses.map { $0.simpleDose(with: insulinModel(for: $0.insulinType)) }

        let recommendationInsulinModel = insulinModel(for: deliveryDelegate?.pumpInsulinType ?? .novolog)

        let recommendationEffectInterval = DateInterval(
            start: baseTime,
            duration: recommendationInsulinModel.effectDuration
        )
        let neededSensitivityTimeline = LoopAlgorithm.timelineIntervalForSensitivity(
            doses: dosesWithModel,
            glucoseHistoryStart: glucose.first?.startDate ?? baseTime,
            recommendationEffectInterval: recommendationEffectInterval
        )

        let sensitivity = try await settingsProvider.getInsulinSensitivityHistory(
            startDate: neededSensitivityTimeline.start,
            endDate: neededSensitivityTimeline.end
        )

        let dosingLimits = try await settingsProvider.getDosingLimits(at: baseTime)

        guard let maxBolus = dosingLimits.maxBolus else {
            throw LoopError.configurationError(.maximumBolus)
        }

        guard let maxBasalRate = dosingLimits.maxBasalRate else {
            throw LoopError.configurationError(.maximumBasalRatePerHour)
        }

        var overrides = temporaryPresetsManager.presetHistory.getOverrideHistory(startDate: neededSensitivityTimeline.start, endDate: forecastEndTime)

        // For recommendation, we should consider preMeal override to be ending at time of dose
        if presumePresetEndingNow,
           let activeOverride = temporaryPresetsManager.activeOverride,
           let index = overrides.lastIndex(of: activeOverride) {
            overrides[index].scheduledEndDate = baseTime
        }

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


        var target: [AbsoluteScheduleValue<ClosedRange<LoopQuantity>>]

        guard var suspendThreshold = dosingLimits.suspendThreshold else {
            throw LoopError.configurationError(.suspendThreshold)
        }

        // If we have an active override, and it's not a preMeal override that should be disabled,
        // or ended for other reasons (like comparing effects without preset), then override the
        // target for the entire forecast.
        if let activeOverride = temporaryPresetsManager.activeOverride,
           !presumePresetEndingNow
        {
            guard let schedule = settingsProvider.settings.glucoseTargetRangeSchedule else
            {
                throw LoopError.configurationError(.glucoseTargetRangeSchedule)
            }
            let scheduledRange = schedule.quantityRange(at: baseTime)
            let overriddenTargetRange = activeOverride.effectiveCorrectionRangeDuring(scheduledRange: scheduledRange)
            target = [
                AbsoluteScheduleValue(
                    startDate: baseTime,
                    endDate: forecastEndTime,
                    value: overriddenTargetRange
                )
            ]

            if activeOverride.veryHighInsulinNeeds {
                suspendThreshold = max(TemporaryScheduleOverride.highInsulinNeedsMitigationCorrectionRangeLimit, suspendThreshold)
            }

        } else {
            target = try await settingsProvider.getTargetRangeHistory(startDate: baseTime, endDate: forecastEndTime)
        }

        guard !target.isEmpty else {
            throw LoopError.configurationError(.glucoseTargetRangeSchedule)
        }


        // Create dosing strategy based on user setting
        let applicationFactorStrategy: ApplicationFactorStrategy = UserDefaults.standard.glucoseBasedApplicationFactorEnabled
            ? GlucoseBasedApplicationFactorStrategy()
            : ConstantApplicationFactorStrategy()

        let correctionRange = target.closestPrior(to: baseTime)?.value

        let effectiveBolusApplicationFactor: Double?

        if let latestGlucose = glucose.last {
            effectiveBolusApplicationFactor = applicationFactorStrategy.calculateDosingFactor(
                for: latestGlucose.quantity,
                correctionRange: correctionRange!
            )
        } else {
            effectiveBolusApplicationFactor = nil
        }

        return StoredDataAlgorithmInput(
            glucoseHistory: glucose,
            doses: dosesWithModel,
            carbEntries: carbEntries,
            predictionStart: baseTime,
            basal: basalWithOverrides,
            sensitivity: sensitivityWithOverrides,
            carbRatio: carbRatioWithOverrides,
            target: target,
            suspendThreshold: suspendThreshold,
            maxBolus: maxBolus,
            maxBasalRate: maxBasalRate,
            useIntegralRetrospectiveCorrection: UserDefaults.standard.integralRetrospectiveCorrectionEnabled,
            includePositiveVelocityAndRC: true,
            carbAbsorptionModel: carbAbsorptionModel,
            recommendationInsulinModel: recommendationInsulinModel,
            recommendationType: .manualBolus,
            automaticBolusApplicationFactor: effectiveBolusApplicationFactor)
    }

    func loopingReEnabled() async {
        await updateDisplayState()
        self.notify(forChange: .forecast)
    }

    func updateDisplayState(forceStoreRemoteRecommendation: Bool = false) async {

        var newState = AlgorithmDisplayState()
        do {
            let lastManualBolusVisibilityWindowStartDate = now.addingTimeInterval(.days(-1))

            var input = try await fetchData(for: now, ensureDosingCoverageStart: lastManualBolusVisibilityWindowStartDate, projectOngoingDoses: true)
            input.recommendationType = .manualBolus
            newState.input = input
            newState.output = await runAlgorithm(input: input)

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
        } catch {
            let loopError = error as? LoopError ?? .unknownError(error)
            logger.error("Error updating Loop state: %{public}@", String(describing: loopError))
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

    private nonisolated func runAlgorithm(input: StoredDataAlgorithmInput) async -> AlgorithmOutput<StoredCarbEntry> {
        LoopAlgorithm.run(input: input)
    }

    /// Cancel the active temp basal if it was automatically issued
    func cancelActiveTempBasal(for reason: CancelActiveTempBasalReason) async throws {
        guard case .tempBasal(let dose) = deliveryDelegate?.basalDeliveryState, (dose.automatic ?? true) else { return }

        logger.default("Cancelling active temp basal for reason: %{public}@", String(describing: reason))

        let recommendation = AutomaticDoseRecommendation(basalAdjustment: .cancel, direction: .decrease)

        var dosingDecision = StoredDosingDecision(reason: reason.rawValue)
        dosingDecision.settings = StoredDosingDecision.Settings(settingsProvider.settings)
        dosingDecision.automaticDoseRecommendation = recommendation

        do {
            crashRecoveryManager.dosingStarted(dose: recommendation)
            try await deliveryDelegate?.enact(bolus: recommendation.bolusUnits, tempBasal: recommendation.basalAdjustment, decisionId: dosingDecision.id)
            self.crashRecoveryManager.dosingFinished()
        } catch {
            dosingDecision.appendError(error as? LoopError ?? .unknownError(error))
            if reason == .maximumBasalRateChanged {
                throw CancelTempBasalFailedMaximumBasalRateChangedError(reason: error)
            } else {
                throw error
            }
        }

        await dosingDecisionStore.storeDosingDecision(dosingDecision)

        // DIY: refresh post-dose forecast and persist an "updateRemoteRecommendation"
        // decision so Nightscout sees the post-cancel state.
        await updateDisplayState(forceStoreRemoteRecommendation: true)
    }

    func loop() async {
        let loopBaseTime = now

        var dosingDecision = StoredDosingDecision(
            date: loopBaseTime,
            reason: "loop",
            settings: StoredDosingDecision.Settings(settingsProvider.settings)
        )

        do {
            guard let deliveryDelegate else {
                preconditionFailure("Unable to dose without dosing delegate.")
            }

            logger.debug("Running Loop at %{public}@", String(describing: loopBaseTime))
            NotificationCenter.default.post(name: .LoopRunning, object: self)

            var input = try await fetchData(for: loopBaseTime)

            // Trim future basal
            input.doses =  input.doses.trimmed(to: loopBaseTime)

            var dosingStrategy: AutomaticDosingStrategy = .automaticBolus

            if dosingStrategySelectionEnabled {
                dosingStrategy = settingsProvider.settings.automaticDosingStrategy
            }
            input.recommendationType = dosingStrategy.recommendationType

            guard let latestGlucose = input.glucoseHistory.last else {
                throw LoopError.missingDataError(.glucose)
            }

            guard loopBaseTime.timeIntervalSince(latestGlucose.startDate) <= LoopAlgorithm.inputDataRecencyInterval else {
                throw LoopError.glucoseTooOld(date: latestGlucose.startDate)
            }

            guard latestGlucose.startDate.timeIntervalSince(loopBaseTime) <= LoopAlgorithm.inputDataRecencyInterval else {
                throw LoopError.invalidFutureGlucose(date: latestGlucose.startDate)
            }

            guard loopBaseTime.timeIntervalSince(doseStore.lastAddedPumpData) <= LoopAlgorithm.inputDataRecencyInterval else {
                throw LoopError.pumpDataTooOld(date: doseStore.lastAddedPumpData)
            }

            var output = LoopAlgorithm.run(input: input)

            switch output.recommendationResult {
            case .success(let recommendation):
                // Round delivery amounts to pump supported amounts,
                // And determine if a change in dosing should be made.

                let algoRecommendation = recommendation.automatic!
                logger.default("Algorithm recommendation: %{public}@", String(describing: algoRecommendation))

                var recommendationToEnact = algoRecommendation
                // Round bolus recommendation based on pump bolus precision
                if let bolus = algoRecommendation.bolusUnits, bolus > 0 {
                    recommendationToEnact.bolusUnits = deliveryDelegate.roundBolusVolume(units: bolus)
                }

                var basal = algoRecommendation.basalAdjustment
                
                basal.unitsPerHour = deliveryDelegate.roundBasalRate(unitsPerHour: basal.unitsPerHour)

                let scheduledBasalRate = input.basal.closestPrior(to: loopBaseTime)!.value
                let activeOverride = temporaryPresetsManager.presetHistory.activeOverride(at: loopBaseTime)

                let basalAdjustment = basal.adjustForCurrentDelivery(
                    at: loopBaseTime,
                    neutralBasalRate: scheduledBasalRate,
                    currentTempBasal: deliveryDelegate.basalDeliveryState?.currentTempBasal,
                    continuationInterval: .minutes(11),
                    neutralBasalRateMatchesPump: activeOverride == nil
                )
                
                if let basalAdjustment {
                    recommendationToEnact.basalAdjustment = basalAdjustment
                }
                
                output.recommendationResult = .success(.init(automatic: recommendationToEnact))

                if recommendationToEnact != algoRecommendation {
                    logger.default("Recommendation changed to: %{public}@", String(describing: recommendationToEnact))
                }

                dosingDecision.updateFrom(input: input, output: output)

                if self.settingsProvider.dosingEnabled {
                    if deliveryDelegate.basalDeliveryState == .pumpInoperable {
                        throw LoopError.pumpInoperable
                    }

                    if deliveryDelegate.isSuspended {
                        throw LoopError.pumpSuspended
                    }

                    if deliveryDelegate.isManualTempBasalRunning {
                        throw LoopError.manualTempBasalRunning
                    }

                    logger.default("Enacting: %{public}@", String(describing: recommendationToEnact))

                    try await deliveryDelegate.enact(bolus: recommendationToEnact.bolusUnits, tempBasal: basalAdjustment, decisionId: dosingDecision.id)

                    logger.default("loop() completed successfully.")
                    lastLoopCompleted = now
                    let duration = lastLoopCompleted!.timeIntervalSince(loopBaseTime)
                    
                    dosingDecision.enactedTempBasal = basalAdjustment
                    dosingDecision.enactedBolusAmount = recommendationToEnact.bolusUnits

                    analyticsServicesManager?.loopDidSucceed(duration)
                } else {
                    self.logger.default("Not adjusting dosing during open loop.")
                }

                await dosingDecisionStore.storeDosingDecision(dosingDecision)
                NotificationCenter.default.post(name: .LoopCycleCompleted, object: self)

            case .failure(let error):
                throw error
            }
        } catch {
            logger.error("loop() did error: %{public}@", String(describing: error))
            let loopError = error as? LoopError ?? .unknownError(error)
            dosingDecision.appendError(loopError)
            await dosingDecisionStore.storeDosingDecision(dosingDecision)
            analyticsServicesManager?.loopDidError(error: loopError)
            NotificationCenter.default.post(name: .LoopCycleCompleted, object: self)
        }

        // DIY: refresh post-dose forecast and persist an "updateRemoteRecommendation"
        // decision (Nightscout's Loop pill + forecast source — paired with the just-stored
        // "loop" decision by NightscoutService). Runs for both success and error paths.
        await updateDisplayState(forceStoreRemoteRecommendation: true)

        logger.default("Loop ended")
    }

    func recommendManualBolus(
        manualGlucoseSample: NewGlucoseSample? = nil,
        potentialCarbEntry: NewCarbEntry? = nil,
        originalCarbEntry: StoredCarbEntry? = nil,
        truncatingActiveOverride: Bool = false
    ) async throws -> ManualBolusRecommendation? {

        var endingPremealOverride = false

        if potentialCarbEntry != nil,
            let activeOverride = temporaryPresetsManager.activeOverride,
            activeOverride.context == .preMeal
        {
            endingPremealOverride = true
        }

        var input = try await self.fetchData(for: now, presumePresetEndingNow: truncatingActiveOverride || endingPremealOverride)
            .addingGlucoseSample(sample: manualGlucoseSample?.asStoredGlucoseSample)
            .removingCarbEntry(carbEntry: originalCarbEntry)
            .addingCarbEntry(carbEntry: potentialCarbEntry?.asStoredCarbEntry)

        input.includePositiveVelocityAndRC = usePositiveMomentumAndRCForManualBoluses
        input.recommendationType = .manualBolus

        let output = LoopAlgorithm.run(input: input)


        switch output.recommendationResult {
        case .success(let prediction):
            guard var manualBolusRecommendation = prediction.manual else { return nil }
            if let roundedAmount = deliveryDelegate?.roundBolusVolume(units: manualBolusRecommendation.amount) {
                manualBolusRecommendation.amount = roundedAmount
            }
            return manualBolusRecommendation
        case .failure(let error):
            throw error
        }
    }

    public func totalDeliveredToday() async -> InsulinValue?
    {
        guard let data = displayState.input else {
            return nil
        }

        let now = data.predictionStart
        let midnight = Calendar.current.startOfDay(for: now)

        let annotatedDoses = data.doses.annotated(with: data.basal, fillBasalGaps: true)
        let trimmed = annotatedDoses.map { $0.trimmed(from: midnight, to: now)}

        return InsulinValue(
            startDate: midnight,
            value: trimmed.reduce(0.0) { $0 + $1.volume }
        )
    }

    var iobValues: [InsulinValue] {
        dosesRelativeToBasal.insulinOnBoardTimeline()
    }

    var dosesRelativeToBasal: [BasalRelativeDose] {
        displayState.output?.dosesRelativeToBasal ?? []
    }

    func updateRemoteRecommendation(force: Bool = false) async {
        if lastManualBolusRecommendation == nil {
            lastManualBolusRecommendation = displayState.output?.recommendation?.manual
        }

        let recommendationChanged = lastManualBolusRecommendation != displayState.output?.recommendation?.manual

        // DIY: post-dose "updateRemoteRecommendation" decisions are also Nightscout's
        // Loop pill + forecast source (NightscoutService pairs them with the cached "loop"
        // decision). Force-store after every Loop cycle and temp basal cancel so NS stays
        // current even when the manual bolus recommendation hasn't changed.
        guard force || recommendationChanged else {
            return
        }

        lastManualBolusRecommendation = displayState.output?.recommendation?.manual

        if let output = displayState.output {
            var dosingDecision = StoredDosingDecision(date: now, reason: "updateRemoteRecommendation")
            dosingDecision.predictedGlucose = output.predictedGlucose
            dosingDecision.insulinOnBoard = displayState.activeInsulin
            dosingDecision.carbsOnBoard = displayState.activeCarbs
            switch output.recommendationResult {
            case .success(let recommendation):
                dosingDecision.automaticDoseRecommendation = recommendation.automatic
                if let recommendationDate = displayState.input?.predictionStart, let manualRec = recommendation.manual {
                    dosingDecision.manualBolusRecommendation = ManualBolusRecommendationWithDate(recommendation: manualRec, date: recommendationDate)
                }
            case .failure(let error):
                if let loopError = error as? LoopError {
                    dosingDecision.errors.append(loopError.issue)
                } else {
                    dosingDecision.errors.append(.init(id: "error", details: ["description": error.localizedDescription]))
                }
            }

            dosingDecision.controllerStatus = UIDevice.current.controllerStatus

            // Device status for the Nightscout devicestatus.pump payload.
            dosingDecision.pumpManagerStatus = deliveryDelegate?.pumpManagerStatus
            if let pumpStatusHighlight = deliveryDelegate?.pumpStatusHighlight {
                dosingDecision.pumpStatusHighlight = StoredDosingDecision.StoredDeviceHighlight(
                    localizedMessage: pumpStatusHighlight.localizedMessage,
                    imageName: pumpStatusHighlight.imageName,
                    state: pumpStatusHighlight.state)
            }
            dosingDecision.cgmManagerStatus = deliveryDelegate?.cgmManagerStatus
            dosingDecision.lastReservoirValue = StoredDosingDecision.LastReservoirValue(doseStore.lastReservoirValue)

            self.logger.debug("Manual bolus rec = %{public}@", String(describing: dosingDecision.manualBolusRecommendation))
            await self.dosingDecisionStore.storeDosingDecision(dosingDecision)
        }
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
        return latestGlucoseDataDate.addingTimeInterval(LoopAlgorithm.inputDataRecencyInterval)
    }
}

// MARK: - Background task management
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
    ///   - carbEntry: The new carb value
    ///   - completion: A closure called once upon completion
    ///   - result: The bolus recommendation
    func addCarbEntry(_ carbEntry: NewCarbEntry, replacing replacingEntry: StoredCarbEntry? = nil) async throws -> StoredCarbEntry {
        let storedCarbEntry: StoredCarbEntry
        if let replacingEntry = replacingEntry {
            storedCarbEntry = try await carbStore.replaceCarbEntry(replacingEntry, withEntry: carbEntry)
        } else {
            storedCarbEntry = try await carbStore.addCarbEntry(carbEntry)
        }
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

    func storeManualBolusDosingDecision(_ bolusDosingDecision: BolusDosingDecision, withDate date: Date) async {
        let dosingDecision = StoredDosingDecision(id: bolusDosingDecision.id,
                                                  date: date,
                                                  reason: bolusDosingDecision.reason.rawValue,
                                                  settings: StoredDosingDecision.Settings(settingsProvider.settings),
                                                  scheduleOverride: bolusDosingDecision.scheduleOverride,
                                                  controllerStatus: UIDevice.current.controllerStatus,
                                                  pumpManagerStatus: deliveryDelegate?.pumpManagerStatus,
                                                  cgmManagerStatus: deliveryDelegate?.cgmManagerStatus,
                                                  lastReservoirValue: StoredDosingDecision.LastReservoirValue(doseStore.lastReservoirValue),
                                                  historicalGlucose: bolusDosingDecision.historicalGlucose,
                                                  originalCarbEntry: bolusDosingDecision.originalCarbEntry,
                                                  carbEntry: bolusDosingDecision.carbEntry,
                                                  manualGlucoseSample: bolusDosingDecision.manualGlucoseSample,
                                                  carbsOnBoard: bolusDosingDecision.carbsOnBoard,
                                                  insulinOnBoard: bolusDosingDecision.insulinOnBoard,
                                                  glucoseTargetRangeSchedule: bolusDosingDecision.glucoseTargetRangeSchedule,
                                                  predictedGlucose: bolusDosingDecision.predictedGlucose,
                                                  manualBolusRecommendation: bolusDosingDecision.manualBolusRecommendation,
                                                  manualBolusRequested: bolusDosingDecision.manualBolusRequested)
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
            insulinSensitivityHistory: sensitivity
        ).filterDateRange(startSuspend, endSuspend)
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

extension NewCarbEntry {
    var asStoredCarbEntry: StoredCarbEntry {
        StoredCarbEntry(
            startDate: startDate,
            quantity: quantity,
            foodType: foodType,
            absorptionTime: absorptionTime,
            userCreatedDate: date
        )
    }
}

extension NewGlucoseSample {
    var asStoredGlucoseSample: StoredGlucoseSample {
        StoredGlucoseSample(
            syncIdentifier: syncIdentifier,
            syncVersion: syncVersion,
            startDate: date,
            quantity: quantity,
            condition: condition,
            trend: trend,
            trendRate: trendRate,
            isDisplayOnly: isDisplayOnly,
            wasUserEntered: wasUserEntered,
            device: device
        )
    }
}


extension StoredDataAlgorithmInput {

    func addingDose(dose: InsulinDoseType?) -> StoredDataAlgorithmInput {
        var rval = self
        if let dose {
            rval.doses = doses + [dose]
        }
        return rval
    }

    func addingGlucoseSample(sample: GlucoseType?) -> StoredDataAlgorithmInput {
        var rval = self
        if let sample {
            rval.glucoseHistory.append(sample)
        }
        return rval
    }

    func addingCarbEntry(carbEntry: CarbType?) -> StoredDataAlgorithmInput {
        var rval = self
        if let carbEntry {
            rval.carbEntries = carbEntries + [carbEntry]
        }
        return rval
    }

    func removingCarbEntry(carbEntry: CarbType?) -> StoredDataAlgorithmInput {
        guard let carbEntry else {
            return self
        }
        var rval = self
        var currentEntries = self.carbEntries
        if let index = currentEntries.firstIndex(of: carbEntry) {
            currentEntries.remove(at: index)
        }
        rval.carbEntries = currentEntries
        return rval
    }

    func predictGlucose(effectsOptions: AlgorithmEffectsOptions = .all) throws -> [PredictedGlucoseValue] {
        let prediction = LoopAlgorithm.generatePrediction(
            start: predictionStart,
            glucoseHistory: glucoseHistory,
            doses: doses,
            carbEntries: carbEntries,
            basal: basal,
            sensitivity: sensitivity,
            carbRatio: carbRatio,
            algorithmEffectsOptions: effectsOptions,
            useIntegralRetrospectiveCorrection: self.useIntegralRetrospectiveCorrection,
            useMidAbsorptionISF: true,
            carbAbsorptionModel: self.carbAbsorptionModel.model
        )
        return prediction.glucose
    }
}

extension Notification.Name {
    static let LoopDataUpdated = Notification.Name(rawValue: "com.loopkit.Loop.LoopDataUpdated")
    static let LoopRunning = Notification.Name(rawValue: "com.loopkit.Loop.LoopRunning")
    static let LoopCycleCompleted = Notification.Name(rawValue: "com.loopkit.Loop.LoopCycleCompleted")
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

private extension StoredDosingDecision.LastReservoirValue {
    init?(_ reservoirValue: ReservoirValue?) {
        guard let reservoirValue = reservoirValue else {
            return nil
        }
        self.init(startDate: reservoirValue.startDate, unitVolume: reservoirValue.unitVolume)
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

private extension StoredDosingDecision.Settings {
    init?(_ settings: StoredSettings?) {
        guard let settings = settings else {
            return nil
        }
        self.init(syncIdentifier: settings.syncIdentifier)
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
        let candidateCarbEntry = NewCarbEntry(quantity: quantity, startDate: startDate ?? now, foodType: foodType, absorptionTime: absorptionTime)

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
        return doseStore.lastAddedPumpData
    }

    func effectiveGlucoseTargetRangeSchedule(presumingMealEntry: Bool) -> GlucoseRangeSchedule? {
        temporaryPresetsManager.effectiveCorrectionRangeSchedule(presumingMealEntry: presumingMealEntry)
    }

    func generatePrediction(
        originalCarbEntry: StoredCarbEntry?,
        potentialCarbEntry: NewCarbEntry?,
        potentialDose: SimpleInsulinDose?,
        manualGlucose: NewGlucoseSample?
    ) async throws -> (historicGlucose: [StoredGlucoseSample], predictedGlucose: [PredictedGlucoseValue]) {

        var endingPremealOverride = false

        if potentialCarbEntry != nil,
            let activeOverride = temporaryPresetsManager.activeOverride,
            activeOverride.context == .preMeal
        {
            endingPremealOverride = true
        }

        var input = try await fetchData(for: now, presumePresetEndingNow: endingPremealOverride, ensureDosingCoverageStart: nil)

        // Add potential bolus, carbs, manual glucose
        input = input
            .addingDose(dose: potentialDose)
            .addingGlucoseSample(sample: manualGlucose?.asStoredGlucoseSample)
            .removingCarbEntry(carbEntry: originalCarbEntry)
            .addingCarbEntry(carbEntry: potentialCarbEntry?.asStoredCarbEntry)

        let prediction = try input.predictGlucose()

        return (historicGlucose: input.glucoseHistory, predictedGlucose: prediction)
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
            .annotated(with: basalWithOverrides)
            .sorted { $0.startDate < $1.startDate }

        let insulinEffects = annotatedDoses.glucoseEffects(
            insulinSensitivityHistory: sensitivityWithOverrides,
            from: start.addingTimeInterval(-CarbMath.maximumAbsorptionTimeInterval).dateFlooredToTimeInterval(GlucoseMath.defaultDelta),
            to: nil)

        // ICE
        let insulinCounteractionEffects = glucose.counteractionEffects(to: insulinEffects)

        // Carb Effects
        let carbStatus = carbEntries.map(
            to: insulinCounteractionEffects,
            carbRatio: carbRatioWithOverrides,
            insulinSensitivity: sensitivityWithOverrides
        )

        let carbEffects = carbStatus.dynamicGlucoseEffects(
            from: start,
            to: end.addingTimeInterval(InsulinMath.defaultInsulinActivityDuration),
            carbRatios: carbRatioWithOverrides,
            insulinSensitivities: sensitivityWithOverrides,
            absorptionModel: CarbAbsorptionModel.piecewiseLinear.model
        )
        
        let carbAbsorptionReview = CarbAbsorptionReview(
            carbEntries: carbEntries,
            carbStatuses: carbStatus,
            effectsVelocities: insulinCounteractionEffects,
            carbEffects: carbEffects
        )
        
        let trimmedDoses = annotatedDoses.filterDateRange(start, end)
        let trimmedIOBValues = annotatedDoses.insulinOnBoardTimeline().filterDateRange(start, end)
        
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

extension AutomaticDosingStrategy {
    var recommendationType: DoseRecommendationType {
        switch self {
        case .tempBasalOnly:
            return .tempBasal
        case .automaticBolus:
            return .automaticBolus
        }
    }
}

extension StoredDosingDecision {
    mutating func updateFrom(input: StoredDataAlgorithmInput, output: AlgorithmOutput<StoredCarbEntry>) {
        self.historicalGlucose = input.glucoseHistory.map { HistoricalGlucoseValue(startDate: $0.startDate, quantity: $0.quantity) }
        switch output.recommendationResult {
        case .success(let recommendation):
            self.automaticDoseRecommendation = recommendation.automatic
        case .failure(let error):
            self.appendError(error as? LoopError ?? .unknownError(error))
        }
        if let activeInsulin = output.activeInsulin {
            self.insulinOnBoard = InsulinValue(startDate: input.predictionStart, value: activeInsulin)
        }
        if let activeCarbs = output.activeCarbs {
            self.carbsOnBoard = CarbValue(startDate: input.predictionStart, value: activeCarbs)
        }
        self.predictedGlucose = output.predictedGlucose
    }
}

enum CancelActiveTempBasalReason: String {
    case automaticDosingDisabled
    case unreliableCGMData
    case maximumBasalRateChanged
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
                entries.append("* \(entry.startDate), \(entry.endDate), \(entry.quantity.doubleValue(for: GlucoseEffectVelocity.unit))\n")
            }),
            "]",

            "insulinEffect: [",
            "* GlucoseEffect(start, mg/dL)",
            (algoOutput?.effects.insulin ?? []).reduce(into: "", { (entries, entry) in
                entries.append("* \(entry.startDate), \(entry.quantity.doubleValue(for: .milligramsPerDeciliter))\n")
            }),
            "]",

            "carbEffect: [",
            "* GlucoseEffect(start, mg/dL)",
            (algoOutput?.effects.carbs ?? []).reduce(into: "", { (entries, entry) in
                entries.append("* \(entry.startDate), \(entry.quantity.doubleValue(for: .milligramsPerDeciliter))\n")
            }),
            "]",

            "predictedGlucose: [",
            "* PredictedGlucoseValue(start, mg/dL)",
            (algoOutput?.predictedGlucose ?? []).reduce(into: "", { (entries, entry) in
                entries.append("* \(entry.startDate), \(entry.quantity.doubleValue(for: .milligramsPerDeciliter))\n")
            }),
            "]",

            "integralRetrospectiveCorrectionEnabled: \(UserDefaults.standard.integralRetrospectiveCorrectionEnabled)",

            "retrospectiveCorrection: [",
            "* GlucoseEffect(start, mg/dL)",
            (algoOutput?.effects.retrospectiveCorrection ?? []).reduce(into: "", { (entries, entry) in
                entries.append("* \(entry.startDate), \(entry.quantity.doubleValue(for: .milligramsPerDeciliter))\n")
            }),
            "]",

            "glucoseMomentumEffect: \(algoOutput?.effects.momentum ?? [])",
            "recommendedAutomaticDose: \(String(describing: doseRecommendation))",
            "lastLoopCompleted: \(String(describing: lastLoopCompleted))",
            "carbsOnBoard: \(String(describing: algoOutput?.activeCarbs))",
            "insulinOnBoard: \(String(describing: algoOutput?.activeInsulin))",
            "error: \(String(describing: loopError))",
            "overrideInUserDefaults: \(String(describing: UserDefaults.appGroup?.intentExtensionOverrideToSet))",
            "glucoseBasedApplicationFactorEnabled: \(UserDefaults.standard.glucoseBasedApplicationFactorEnabled)",
            "integralRetrospectiveCorrectionEanbled: \(String(describing: algoInput?.useIntegralRetrospectiveCorrection))",
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
