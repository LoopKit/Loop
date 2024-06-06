//
//  LoopDataManager.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 3/12/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation
import Combine
import HealthKit
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
    var pumpInsulinType: InsulinType? { get }
    var basalDeliveryState: PumpManagerStatus.BasalDeliveryState? { get }
    var isPumpConfigured: Bool { get }

    func enact(_ recommendation: AutomaticDoseRecommendation) async throws
    func enactBolus(units: Double, activationType: BolusActivationType) async throws
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

    var deliveryDelegate: DeliveryDelegate?

    let analyticsServicesManager: AnalyticsServicesManager?
    let carbStore: CarbStoreProtocol
    let doseStore: DoseStoreProtocol
    let temporaryPresetsManager: TemporaryPresetsManager
    let settingsProvider: SettingsProvider
    let dosingDecisionStore: DosingDecisionStoreProtocol
    let glucoseStore: GlucoseStoreProtocol

    let logger = DiagnosticLog(category: "LoopDataManager")

    private let widgetLog = DiagnosticLog(category: "LoopWidgets")

    private let trustedTimeOffset: () async -> TimeInterval

    private let now: () -> Date

    private let automaticDosingStatus: AutomaticDosingStatus

    // References to registered notification center observers
    private var notificationObservers: [Any] = []

    var activeInsulin: InsulinValue? {
        displayState.activeInsulin
    }
    var activeCarbs: CarbValue? {
        displayState.activeCarbs
    }

    var latestGlucose: GlucoseSampleValue? {
        displayState.input?.glucoseHistory.last
    }

    var lastReservoirValue: ReservoirValue? {
        doseStore.lastReservoirValue
    }

    var carbAbsorptionModel: CarbAbsorptionModel

    private var lastManualBolusRecommendation: ManualBolusRecommendation?

    var usePositiveMomentumAndRCForManualBoluses: Bool

    lazy private var cancellables = Set<AnyCancellable>()

    init(
        lastLoopCompleted: Date?,
        temporaryPresetsManager: TemporaryPresetsManager,
        settingsProvider: SettingsProvider,
        doseStore: DoseStoreProtocol,
        glucoseStore: GlucoseStoreProtocol,
        carbStore: CarbStoreProtocol,
        dosingDecisionStore: DosingDecisionStoreProtocol,
        now: @escaping () -> Date = { Date() },
        automaticDosingStatus: AutomaticDosingStatus,
        trustedTimeOffset: @escaping () async -> TimeInterval,
        analyticsServicesManager: AnalyticsServicesManager?,
        carbAbsorptionModel: CarbAbsorptionModel,
        usePositiveMomentumAndRCForManualBoluses: Bool = true
    ) {

        self.lastLoopCompleted = lastLoopCompleted
        self.temporaryPresetsManager = temporaryPresetsManager
        self.settingsProvider = settingsProvider
        self.doseStore = doseStore
        self.glucoseStore = glucoseStore
        self.carbStore = carbStore
        self.dosingDecisionStore = dosingDecisionStore
        self.now = now
        self.automaticDosingStatus = automaticDosingStatus
        self.trustedTimeOffset = trustedTimeOffset
        self.analyticsServicesManager = analyticsServicesManager
        self.carbAbsorptionModel = carbAbsorptionModel
        self.usePositiveMomentumAndRCForManualBoluses = usePositiveMomentumAndRCForManualBoluses

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
                    self.logger.default("Received notification of carb entries changing")
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
                    self.logger.default("Received notification of glucose samples changing")
                    await self.updateDisplayState()
                    self.notify(forChange: .glucose)
                }
            },
            NotificationCenter.default.addObserver(
                forName: nil,
                object: self.doseStore,
                queue: OperationQueue.main
            ) { (note) in
                Task { @MainActor in
                    self.logger.default("Received notification of dosing changing")
                    await self.updateDisplayState()
                    self.notify(forChange: .insulin)
                }
            }
        ]

        // Turn off preMeal when going into closed loop off mode
        // Cancel any active temp basal when going into closed loop off mode
        // The dispatch is necessary in case this is coming from a didSet already on the settings struct.
        automaticDosingStatus.$automaticDosingEnabled
            .removeDuplicates()
            .dropFirst()
            .sink {
                if !$0 {
                    self.temporaryPresetsManager.clearOverride(matching: .preMeal)
                    Task {
                        try? await self.cancelActiveTempBasal(for: .automaticDosingDisabled)
                    }
                } else {
                    Task {
                        await self.updateDisplayState()
                    }
                }
            }
            .store(in: &cancellables)


    }

    // MARK: - Calculation state

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
        for baseTime: Date = Date(),
        disablingPreMeal: Bool = false
    ) async throws -> StoredDataAlgorithmInput {
        // Need to fetch doses back as far as t - (DIA + DCA) for Dynamic carbs
        let dosesInputHistory = CarbMath.maximumAbsorptionTimeInterval + InsulinMath.defaultInsulinActivityDuration

        var dosesStart = baseTime.addingTimeInterval(-dosesInputHistory)
        let doses = try await doseStore.getNormalizedDoseEntries(
            start: dosesStart,
            end: baseTime
        )

        dosesStart = doses.map { $0.startDate }.min() ?? dosesStart

        let basal = try await settingsProvider.getBasalHistory(startDate: dosesStart, endDate: baseTime)

        guard !basal.isEmpty else {
            throw LoopError.configurationError(.basalRateSchedule)
        }

        let forecastEndTime = baseTime.addingTimeInterval(InsulinMath.defaultInsulinActivityDuration).dateCeiledToTimeInterval(.minutes(GlucoseMath.defaultDelta))

        let carbsStart = baseTime.addingTimeInterval(CarbMath.dateAdjustmentPast + .minutes(-1)) // additional minute to handle difference in seconds between carb entry and carb ratio

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

        let sensitivityStart = min(carbsStart, dosesStart)

        let sensitivity = try await settingsProvider.getInsulinSensitivityHistory(startDate: sensitivityStart, endDate: forecastEndTime)

        let target = try await settingsProvider.getTargetRangeHistory(startDate: baseTime, endDate: forecastEndTime)

        let dosingLimits = try await settingsProvider.getDosingLimits(at: baseTime)

        guard let maxBolus = dosingLimits.maxBolus else {
            throw LoopError.configurationError(.maximumBolus)
        }

        guard let maxBasalRate = dosingLimits.maxBasalRate else {
            throw LoopError.configurationError(.maximumBasalRatePerHour)
        }

        var overrides = temporaryPresetsManager.overrideHistory.getOverrideHistory(startDate: sensitivityStart, endDate: forecastEndTime)

        // Bug (https://tidepool.atlassian.net/browse/LOOP-4759) pre-meal is not recorded in override history
        // So currently we handle automatic forecast by manually adding it in, and when meal bolusing, we do not do this.
        // Eventually, when pre-meal is stored in override history, during meal bolusing we should scan for it and adjust the end time
        if !disablingPreMeal, let preMeal = temporaryPresetsManager.preMealOverride {
            overrides.append(preMeal)
            overrides.sort { $0.startDate < $1.startDate }
        }

        guard !sensitivity.isEmpty else {
            throw LoopError.configurationError(.insulinSensitivitySchedule)
        }

        let sensitivityWithOverrides = overrides.apply(over: sensitivity) { (quantity, override) in
            let value = quantity.doubleValue(for: .milligramsPerDeciliter)
            return HKQuantity(
                unit: .milligramsPerDeciliter,
                doubleValue: value / override.settings.effectiveInsulinNeedsScaleFactor
            )
        }

        guard !basal.isEmpty else {
            throw LoopError.configurationError(.basalRateSchedule)
        }
        let basalWithOverrides = overrides.apply(over: basal) { (value, override) in
            value * override.settings.effectiveInsulinNeedsScaleFactor
        }

        guard !carbRatio.isEmpty else {
            throw LoopError.configurationError(.carbRatioSchedule)
        }
        let carbRatioWithOverrides = overrides.apply(over: carbRatio) { (value, override) in
            value * override.settings.effectiveInsulinNeedsScaleFactor
        }

        guard !target.isEmpty else {
            throw LoopError.configurationError(.glucoseTargetRangeSchedule)
        }
        let targetWithOverrides = overrides.apply(over: target) { (range, override) in
            override.settings.targetRange ?? range
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
            doses: doses.map { $0.simpleDose(with: insulinModel(for: $0.insulinType)) },
            carbEntries: carbEntries,
            predictionStart: baseTime,
            basal: basalWithOverrides,
            sensitivity: sensitivityWithOverrides,
            carbRatio: carbRatioWithOverrides,
            target: targetWithOverrides,
            suspendThreshold: dosingLimits.suspendThreshold,
            maxBolus: maxBolus,
            maxBasalRate: maxBasalRate,
            useIntegralRetrospectiveCorrection: UserDefaults.standard.integralRetrospectiveCorrectionEnabled,
            includePositiveVelocityAndRC: true,
            carbAbsorptionModel: carbAbsorptionModel,
            recommendationInsulinModel: insulinModel(for: deliveryDelegate?.pumpInsulinType ?? .novolog),
            recommendationType: .manualBolus,
            automaticBolusApplicationFactor: effectiveBolusApplicationFactor)
    }

    func loopingReEnabled() async {
        await updateDisplayState()
        self.notify(forChange: .forecast)
    }

    func updateDisplayState() async {
        var newState = AlgorithmDisplayState()
        do {
            var input = try await fetchData(for: now())
            input.recommendationType = .manualBolus
            newState.input = input
            newState.output = LoopAlgorithm.run(input: input)
        } catch {
            let loopError = error as? LoopError ?? .unknownError(error)
            logger.error("Error updating Loop state: %{public}@", String(describing: loopError))
        }
        displayState = newState
        await updateRemoteRecommendation()
    }

    /// Cancel the active temp basal if it was automatically issued
    func cancelActiveTempBasal(for reason: CancelActiveTempBasalReason) async throws {
        guard case .tempBasal(let dose) = deliveryDelegate?.basalDeliveryState, (dose.automatic ?? true) else { return }

        logger.default("Cancelling active temp basal for reason: %{public}@", String(describing: reason))

        let recommendation = AutomaticDoseRecommendation(basalAdjustment: .cancel)

        var dosingDecision = StoredDosingDecision(reason: reason.rawValue)
        dosingDecision.settings = StoredDosingDecision.Settings(settingsProvider.settings)
        dosingDecision.automaticDoseRecommendation = recommendation

        do {
            try await deliveryDelegate?.enact(recommendation)
        } catch {
            dosingDecision.appendError(error as? LoopError ?? .unknownError(error))
            if reason == .maximumBasalRateChanged {
                throw CancelTempBasalFailedMaximumBasalRateChangedError(reason: error)
            } else {
                throw error
            }
        }

        await dosingDecisionStore.storeDosingDecision(dosingDecision)
    }

    func loop() async {
        let loopBaseTime = now()

        var dosingDecision = StoredDosingDecision(
            date: loopBaseTime,
            reason: "loop"
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

            let dosingStrategy = settingsProvider.settings.automaticDosingStrategy
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

                if var basal = algoRecommendation.basalAdjustment {
                    basal.unitsPerHour = deliveryDelegate.roundBasalRate(unitsPerHour: basal.unitsPerHour)

                    let scheduledBasalRate = input.basal.closestPrior(to: loopBaseTime)!.value
                    let activeOverride = temporaryPresetsManager.overrideHistory.activeOverride(at: loopBaseTime)

                    let basalAdjustment = basal.adjustForCurrentDelivery(
                        at: loopBaseTime,
                        neutralBasalRate: scheduledBasalRate,
                        currentTempBasal: deliveryDelegate.basalDeliveryState?.currentTempBasal,
                        continuationInterval: .minutes(11),
                        neutralBasalRateMatchesPump: activeOverride == nil
                    )

                    recommendationToEnact.basalAdjustment = basalAdjustment
                }
                output.recommendationResult = .success(.init(automatic: recommendationToEnact))

                if recommendationToEnact != algoRecommendation {
                    logger.default("Recommendation changed to: %{public}@", String(describing: recommendationToEnact))
                }

                dosingDecision.updateFrom(input: input, output: output)

                if self.automaticDosingStatus.automaticDosingEnabled {
                    if deliveryDelegate.isSuspended {
                        throw LoopError.pumpSuspended
                    }

                    if recommendationToEnact.hasDosingChange {
                        logger.default("Enacting: %{public}@", String(describing: recommendationToEnact))
                        try await deliveryDelegate.enact(recommendationToEnact)
                    }

                    logger.default("loop() completed successfully.")
                    lastLoopCompleted = Date()
                    let duration = lastLoopCompleted!.timeIntervalSince(loopBaseTime)

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
        }
        logger.default("Loop ended")
    }

    func recommendManualBolus(
        manualGlucoseSample: NewGlucoseSample? = nil,
        potentialCarbEntry: NewCarbEntry? = nil,
        originalCarbEntry: StoredCarbEntry? = nil
    ) async throws -> ManualBolusRecommendation? {

        var input = try await self.fetchData(for: now(), disablingPreMeal: potentialCarbEntry != nil)
            .addingGlucoseSample(sample: manualGlucoseSample?.asStoredGlucoseStample)
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

    var iobValues: [InsulinValue] {
        dosesRelativeToBasal.insulinOnBoardTimeline()
    }

    var dosesRelativeToBasal: [BasalRelativeDose] {
        displayState.output?.dosesRelativeToBasal ?? []
    }

    func updateRemoteRecommendation() async {
        if lastManualBolusRecommendation == nil {
            lastManualBolusRecommendation = displayState.output?.recommendation?.manual
        }

        guard lastManualBolusRecommendation != displayState.output?.recommendation?.manual else {
            // no change
            return
        }

        lastManualBolusRecommendation = displayState.output?.recommendation?.manual

        if let output = displayState.output {
            var dosingDecision = StoredDosingDecision(date: Date(), reason: "updateRemoteRecommendation")
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
            self.logger.debug("Manual bolus rec = %{public}@", String(describing: dosingDecision.manualBolusRecommendation))
            await self.dosingDecisionStore.storeDosingDecision(dosingDecision)
        }
    }
}

// MARK: Background task management
extension LoopDataManager: PersistenceControllerDelegate {
    func persistenceControllerWillSave(_ controller: PersistenceController) {
        startBackgroundTask()
    }

    func persistenceControllerDidSave(_ controller: PersistenceController, error: PersistenceController.PersistenceControllerError?) {
        endBackgroundTask()
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
        self.temporaryPresetsManager.clearOverride(matching: .preMeal)
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
        let dose = DoseEntry(type: .bolus, startDate: startDate, value: units, unit: .units, syncIdentifier: syncIdentifier, insulinType: insulinType, manuallyEntered: true)

        do {
            try await doseStore.addDoses([dose], from: nil)
            self.notify(forChange: .insulin)
        } catch {
            logger.error("Error storing manual dose: %{public}@", error.localizedDescription)
        }
    }

    func storeManualBolusDosingDecision(_ bolusDosingDecision: BolusDosingDecision, withDate date: Date) async {
        let dosingDecision = StoredDosingDecision(date: date,
                                                  reason: bolusDosingDecision.reason.rawValue,
                                                  settings: StoredDosingDecision.Settings(settingsProvider.settings),
                                                  scheduleOverride: bolusDosingDecision.scheduleOverride,
                                                  controllerStatus: UIDevice.current.controllerStatus,
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
        await dosingDecisionStore.storeDosingDecision(dosingDecision)
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

    func computeSimpleBolusRecommendation(at date: Date, mealCarbs: HKQuantity?, manualGlucose: HKQuantity?) -> BolusDosingDecision? {

        var dosingDecision = BolusDosingDecision(for: .simpleBolus)

        guard let iob = displayState.activeInsulin?.value,
              let suspendThreshold = settingsProvider.settings.suspendThreshold?.quantity,
              let carbRatioSchedule = temporaryPresetsManager.carbRatioScheduleApplyingOverrideHistory,
              let correctionRangeSchedule = temporaryPresetsManager.effectiveGlucoseTargetRangeSchedule(presumingMealEntry: mealCarbs != nil),
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
            activeInsulin: HKQuantity.init(unit: .internationalUnit(), doubleValue: iob),
            carbRatioSchedule: carbRatioSchedule,
            correctionRangeSchedule: correctionRangeSchedule,
            sensitivitySchedule: sensitivitySchedule,
            at: date)

        dosingDecision.manualBolusRecommendation = ManualBolusRecommendationWithDate(recommendation: ManualBolusRecommendation(amount: bolusAmount.doubleValue(for: .internationalUnit()), notice: notice),
                                                                                     date: Date())

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
    var asStoredGlucoseStample: StoredGlucoseSample {
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
        
        guard amountInGrams <= LoopConstants.maxCarbEntryQuantity.doubleValue(for: .gram()) else {
            throw CarbActionError.exceedsMaxCarbs
        }
        
        if let startDate = startDate {
            let maxStartDate = Date().addingTimeInterval(LoopConstants.maxCarbEntryFutureTime)
            let minStartDate = Date().addingTimeInterval(LoopConstants.maxCarbEntryPastTime)
            guard startDate <= maxStartDate  && startDate >= minStartDate else {
                throw CarbActionError.invalidStartDate(startDate)
            }
        }
        
        let quantity = HKQuantity(unit: .gram(), doubleValue: amountInGrams)
        let candidateCarbEntry = NewCarbEntry(quantity: quantity, startDate: startDate ?? Date(), foodType: foodType, absorptionTime: absorptionTime)
        
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
    
    var suspendThreshold: HKQuantity? {
        settingsProvider.settings.suspendThreshold?.quantity
    }
    
    func enactBolus(units: Double, activationType: BolusActivationType) async throws {
        try await deliveryDelegate?.enactBolus(units: units, activationType: activationType)
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
        temporaryPresetsManager.effectiveGlucoseTargetRangeSchedule(presumingMealEntry: presumingMealEntry)
    }

    func generatePrediction(input: StoredDataAlgorithmInput) throws -> [PredictedGlucoseValue] {
        try input.predictGlucose()
    }
}


extension LoopDataManager: CarbEntryViewModelDelegate {
    func scheduleOverrideEnabled(at date: Date) -> Bool {
        temporaryPresetsManager.scheduleOverrideEnabled(at: date)
    }
    
    var defaultAbsorptionTimes: DefaultAbsorptionTimes {
        LoopCoreConstants.defaultCarbAbsorptionTimes
    }

    func getGlucoseSamples(start: Date?, end: Date?) async throws -> [StoredGlucoseSample] {
        try await glucoseStore.getGlucoseSamples(start: start, end: end)
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

extension AutomaticDoseRecommendation {
    public var hasDosingChange: Bool {
        return basalAdjustment != nil || bolusUnits != nil
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

extension LoopDataManager: LoopControl { }

extension CarbMath {
    public static let dateAdjustmentPast: TimeInterval = .hours(-12)
    public static let dateAdjustmentFuture: TimeInterval = .hours(1)
}
