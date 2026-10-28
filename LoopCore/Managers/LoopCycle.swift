//
//  LoopCycle.swift
//  Loop
//
//  One cycle of the dosing loop, as both apps run it: the algorithm's input, its recommendation,
//  the dose as the pump will take it, the checks before sending it, the send, and the cycle's
//  dosing decision. LoopDataManager runs it on the phone; the watch's loop runs it while the watch
//  holds the pump. What only the device running it knows comes from its `LoopCycleHost`.
//

import Foundation
import LoopKit
import LoopAlgorithm
import os.log

public protocol DeliveryDelegate: AnyObject {
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

/// A delivery delegate over the pump manager it holds: the phone's `DeviceDataManager`, and the
/// watch over a lent pod. Its delivery members are the ones below; sending a dose that passed their
/// checks, a pump status highlight and a manual bolus are each device's own.
public protocol PumpManagerDeliveryDelegate: DeliveryDelegate {
    var pumpManager: PumpManager? { get }
    var cgmManager: CGMManager? { get }

    /// Sends a dose `enact` has checked, logged the device's way.
    func send(bolus: Double?, tempBasal: TempBasalRecommendation?, decisionId: UUID?, to pumpManager: PumpManager) async throws
}

public extension PumpManagerDeliveryDelegate {
    var isPumpConfigured: Bool {
        return pumpManager != nil
    }

    func roundBasalRate(unitsPerHour: Double) -> Double {
        guard let pumpManager = pumpManager else {
            return unitsPerHour
        }

        return pumpManager.roundToSupportedBasalRate(unitsPerHour: unitsPerHour)
    }

    func roundBolusVolume(units: Double) -> Double {
        guard let pumpManager = pumpManager else {
            return units
        }

        return pumpManager.roundToSupportedBolusVolume(units: units)
    }

    var pumpInsulinType: InsulinType? {
        return pumpManager?.status.insulinType
    }

    var isSuspended: Bool {
        return pumpManager?.status.basalDeliveryState?.isSuspended ?? false
    }

    var isManualTempBasalRunning: Bool {
        guard case .tempBasal(let dose) = pumpManager?.status.basalDeliveryState else {
            return false
        }
        return dose.automatic == false && dose.endDate > Date()
    }

    var basalDeliveryState: PumpManagerStatus.BasalDeliveryState? {
        return pumpManager?.status.basalDeliveryState
    }

    var pumpManagerStatus: PumpManagerStatus? {
        return pumpManager?.status
    }

    var cgmManagerStatus: CGMManagerStatus? {
        return cgmManager?.cgmManagerStatus
    }

    /// Refused while the pump's last command is unconfirmed: its driver settles it at its next session.
    func enact(bolus: Double?, tempBasal: TempBasalRecommendation?, decisionId: UUID?) async throws {
        guard let pumpManager = pumpManager else {
            throw LoopError.configurationError(.pumpManager)
        }

        guard !pumpManager.status.deliveryIsUncertain else {
            throw LoopError.connectionError
        }

        try await send(bolus: bolus, tempBasal: tempBasal, decisionId: decisionId, to: pumpManager)
    }
}

public enum CancelActiveTempBasalReason: String {
    case automaticDosingDisabled
    case unreliableCGMData
    case maximumBasalRateChanged
    case pumpControlReturned
    case pumpControlReleased
}

/// What a loop cycle needs from the device running it.
public protocol LoopCycleHost: AnyObject {
    var deliveryDelegate: DeliveryDelegate? { get }

    var overrideHistory: TemporaryScheduleOverrideHistory { get }
    /// The override in effect now, if any.
    var activeOverride: TemporaryScheduleOverride? { get }

    var enabledAlgorithmExperiments: Set<ExperimentOption> { get }
    /// Guard + runway's volatility baseline; asked only while that experiment is enabled.
    func currentVolatilityBaseline(at date: Date) async -> Double?
    func algorithmExperiments(for dosingStrategy: AutomaticDosingStrategy, guardAndRunway: GuardAndRunwayOutput?) -> [AlgorithmExperiment]

    var currentDosingStrategy: AutomaticDosingStrategy { get }
    var usePositiveMomentumAndRCForManualBoluses: Bool { get }
    var carbAbsorptionModel: CarbAbsorptionModel { get }
    func insulinModel(for type: InsulinType?) -> InsulinModel

    /// This device holds the pump: it may command it, and its dosing decisions are the record.
    var holdsPump: Bool { get }
    /// The device's loop is closed: its cycles may dose automatically while it holds the pump.
    var isClosedLoop: Bool { get }

    /// The device's battery, for the dosing decisions it stores.
    var controllerStatus: StoredDosingDecision.ControllerStatus { get }
}

public final class LoopCycle {
    /// What one cycle computed and did.
    public struct Outcome {
        public var dosingDecision: StoredDosingDecision
        public var input: StoredDataAlgorithmInput?
        public var output: AlgorithmOutput<StoredCarbEntry>?
        /// The automatic recommendation as it was to be enacted: rounded and adjusted for the
        /// pump's current temp.
        public var recommendation: AutomaticDoseRecommendation?
        /// The temp basal command; nil when the pump's current temp already serves.
        public var basalAdjustment: TempBasalRecommendation?
        /// The dose went to the pump and the pump took it.
        public var enacted = false
        public var error: LoopError?
    }

    public let doseStore: DoseStoreProtocol
    public let carbStore: CarbStoreProtocol
    public let glucoseStore: GlucoseStoreProtocol
    /// Nil only in suites that do not look at decisions.
    public let dosingDecisionStore: DosingDecisionStoreProtocol?
    public let settingsProvider: SettingsProvider
    public weak var host: LoopCycleHost?

    private let now: () -> Date
    private let log = OSLog(subsystem: "com.loopkit.Loop", category: "LoopCycle")

    /// The manual recommendation in the last stored remote recommendation.
    private var lastManualBolusRecommendation: ManualBolusRecommendation?

    public init(doseStore: DoseStoreProtocol, carbStore: CarbStoreProtocol, glucoseStore: GlucoseStoreProtocol,
         dosingDecisionStore: DosingDecisionStoreProtocol?, settingsProvider: SettingsProvider,
         host: LoopCycleHost?, now: @escaping () -> Date) {
        self.doseStore = doseStore
        self.carbStore = carbStore
        self.glucoseStore = glucoseStore
        self.dosingDecisionStore = dosingDecisionStore
        self.settingsProvider = settingsProvider
        self.host = host
        self.now = now
    }

    private var requiredHost: LoopCycleHost {
        guard let host else { preconditionFailure("A loop cycle runs for a host.") }
        return host
    }

    public func fetchData(
        for baseTime: Date? = nil,
        presumePresetEndingNow: Bool = false,
        ensureDosingCoverageStart: Date? = nil,
        projectOngoingDoses: Bool = false,
        isolation: isolated (any Actor)? = #isolation
    ) async throws -> StoredDataAlgorithmInput {
        let host = requiredHost
        let now = self.now()
        let experiments = host.enabledAlgorithmExperiments
        let volatilityBaseline = experiments.contains(.guardAndRunway) ? await host.currentVolatilityBaseline(at: baseTime ?? now) : nil
        return try await StoredDataAlgorithmInput.fetch(
            for: baseTime,
            presumePresetEndingNow: presumePresetEndingNow,
            ensureDosingCoverageStart: ensureDosingCoverageStart,
            projectOngoingDoses: projectOngoingDoses,
            now: now,
            doseStore: doseStore,
            carbStore: carbStore,
            glucoseStore: glucoseStore,
            settingsProvider: settingsProvider,
            overrideHistory: host.overrideHistory,
            activeOverride: host.activeOverride,
            pumpInsulinType: host.deliveryDelegate?.pumpInsulinType,
            insulinModel: host.insulinModel(for:),
            experiments: experiments,
            volatilityBaseline: volatilityBaseline,
            carbAbsorptionModel: host.carbAbsorptionModel)
    }

    /// One cycle at `loopBaseTime`. The decision is stored, on both arms, by a host that holds the pump.
    public func run(at loopBaseTime: Date, isolation: isolated (any Actor)? = #isolation) async -> Outcome {
        let host = requiredHost
        var outcome = Outcome(dosingDecision: StoredDosingDecision(
            date: loopBaseTime,
            reason: "loop",
            settings: StoredDosingDecision.Settings(settingsProvider.settings)
        ))

        do {
            guard let deliveryDelegate = host.deliveryDelegate else {
                preconditionFailure("Unable to dose without dosing delegate.")
            }

            var input = try await fetchData(for: loopBaseTime)

            // Trim future basal
            input.doses = input.doses.trimmed(to: loopBaseTime)

            let dosingStrategy = host.currentDosingStrategy
            input.recommendationType = dosingStrategy.recommendationType
            outcome.dosingDecision.algorithmExperiments = host.algorithmExperiments(for: dosingStrategy, guardAndRunway: nil)
            outcome.input = input

            try input.checkRecency(at: loopBaseTime, lastAddedPumpData: doseStore.lastAddedPumpData)

            var output = LoopAlgorithm.run(input: input)
            outcome.output = output
            outcome.dosingDecision.algorithmExperiments = host.algorithmExperiments(for: dosingStrategy, guardAndRunway: output.guardAndRunway)

            switch output.recommendationResult {
            case .success(let recommendation):
                // Round delivery amounts to pump supported amounts,
                // And determine if a change in dosing should be made.

                let algoRecommendation = recommendation.automatic!
                os_log("Algorithm recommendation: %{public}@", log: log, type: .default, String(describing: algoRecommendation))

                var recommendationToEnact = algoRecommendation
                // Round bolus recommendation based on pump bolus precision
                if let bolus = algoRecommendation.bolusUnits, bolus > 0 {
                    recommendationToEnact.bolusUnits = deliveryDelegate.roundBolusVolume(units: bolus)
                }

                var basal = algoRecommendation.basalAdjustment

                basal.unitsPerHour = deliveryDelegate.roundBasalRate(unitsPerHour: basal.unitsPerHour)

                let scheduledBasalRate = input.basal.closestPrior(to: loopBaseTime)!.value
                let activeOverride = host.overrideHistory.activeOverride(at: loopBaseTime)

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
                outcome.output = output
                outcome.recommendation = recommendationToEnact
                outcome.basalAdjustment = basalAdjustment

                if recommendationToEnact != algoRecommendation {
                    os_log("Recommendation changed to: %{public}@", log: log, type: .default, String(describing: recommendationToEnact))
                }

                outcome.dosingDecision.updateFrom(input: input, output: output)

                if host.isClosedLoop, host.holdsPump {
                    if deliveryDelegate.basalDeliveryState == .pumpInoperable {
                        throw LoopError.pumpInoperable
                    }

                    if deliveryDelegate.isSuspended {
                        throw LoopError.pumpSuspended
                    }

                    if deliveryDelegate.isManualTempBasalRunning {
                        throw LoopError.manualTempBasalRunning
                    }

                    os_log("Enacting: %{public}@", log: log, type: .default, String(describing: recommendationToEnact))

                    try await deliveryDelegate.enact(bolus: recommendationToEnact.bolusUnits, tempBasal: basalAdjustment, decisionId: outcome.dosingDecision.id)

                    outcome.enacted = true
                    outcome.dosingDecision.enactedTempBasal = basalAdjustment
                    outcome.dosingDecision.enactedBolusAmount = recommendationToEnact.bolusUnits
                } else {
                    os_log("Not adjusting dosing during open loop.", log: log, type: .default)
                }

            case .failure(let error):
                throw error
            }
        } catch {
            os_log("loop() did error: %{public}@", log: log, type: .error, String(describing: error))
            let loopError = error as? LoopError ?? .unknownError(error)
            outcome.error = loopError
            outcome.dosingDecision.appendError(loopError)
        }

        if host.holdsPump {
            await dosingDecisionStore?.storeDosingDecision(outcome.dosingDecision)
        }
        return outcome
    }

    /// The manual bolus recommendation's input: the active preset presumed ending now when asked, or
    /// when a pre-meal preset meets a carb entry; no trim, since a bolus goes on top of a temp that
    /// keeps running.
    public func manualBolusInput(
        manualGlucoseSample: NewGlucoseSample? = nil,
        carbEntryChange: CarbEntryChange? = nil,
        truncatingActiveOverride: Bool = false,
        isolation: isolated (any Actor)? = #isolation
    ) async throws -> StoredDataAlgorithmInput {
        let host = requiredHost
        var endingPremealOverride = false

        if carbEntryChange != nil,
            let activeOverride = host.activeOverride,
            activeOverride.context == .preMeal
        {
            endingPremealOverride = true
        }

        var input = try await fetchData(for: now(), presumePresetEndingNow: truncatingActiveOverride || endingPremealOverride)
            .addingGlucoseSample(sample: manualGlucoseSample?.asStoredGlucoseSample)
            .removingCarbEntry(carbEntry: carbEntryChange?.originalEntry)
            .addingCarbEntry(carbEntry: carbEntryChange?.asStoredCarbEntry)

        input.includePositiveVelocityAndRC = host.usePositiveMomentumAndRCForManualBoluses
        input.recommendationType = .manualBolus
        return input
    }

    public func recommendManualBolus(
        manualGlucoseSample: NewGlucoseSample? = nil,
        carbEntryChange: CarbEntryChange? = nil,
        truncatingActiveOverride: Bool = false,
        isolation: isolated (any Actor)? = #isolation
    ) async throws -> ManualBolusRecommendation? {
        let input = try await manualBolusInput(manualGlucoseSample: manualGlucoseSample, carbEntryChange: carbEntryChange,
                                               truncatingActiveOverride: truncatingActiveOverride)

        let output = LoopAlgorithm.run(input: input)

        switch output.recommendationResult {
        case .success(let prediction):
            guard var manualBolusRecommendation = prediction.manual else { return nil }
            if let roundedAmount = requiredHost.deliveryDelegate?.roundBolusVolume(units: manualBolusRecommendation.amount) {
                manualBolusRecommendation.amount = roundedAmount
            }
            return manualBolusRecommendation
        case .failure(let error):
            throw error
        }
    }

    /// A manual bolus's decision as stored, as of `date`, with the settings, device status and
    /// experiments it was made under. Nil without a host. The host stores it.
    public func manualBolusDosingDecision(_ bolusDosingDecision: BolusDosingDecision, withDate date: Date) -> StoredDosingDecision? {
        guard let host else { return nil }
        var dosingDecision = StoredDosingDecision(id: bolusDosingDecision.id,
                                                  date: date,
                                                  reason: bolusDosingDecision.reason.rawValue,
                                                  settings: StoredDosingDecision.Settings(settingsProvider.settings),
                                                  scheduleOverride: bolusDosingDecision.scheduleOverride,
                                                  controllerStatus: host.controllerStatus,
                                                  pumpManagerStatus: host.deliveryDelegate?.pumpManagerStatus,
                                                  cgmManagerStatus: host.deliveryDelegate?.cgmManagerStatus,
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
        dosingDecision.algorithmExperiments = host.algorithmExperiments(for: host.currentDosingStrategy, guardAndRunway: nil)
        return dosingDecision
    }

    /// Cancels the running temp if the loop set it, for `reason`, and stores the decision. False when
    /// there is nothing to cancel, or this device does not hold the pump (the controller holding it
    /// owns the program). A failure stores nothing. The hooks bracket the send.
    public func cancelActiveTempBasal(
        for reason: CancelActiveTempBasalReason,
        dosingStarted: (AutomaticDoseRecommendation) -> Void = { _ in },
        dosingFinished: () -> Void = {},
        isolation: isolated (any Actor)? = #isolation
    ) async throws -> Bool {
        let host = requiredHost
        guard let deliveryDelegate = host.deliveryDelegate,
              case .tempBasal(let dose) = deliveryDelegate.basalDeliveryState, (dose.automatic ?? true) else { return false }

        guard host.holdsPump else {
            os_log("Temp-basal cancel SKIPPED (%{public}@) — this device does not hold the pump", log: log, type: .default, reason.rawValue)
            return false
        }

        os_log("Cancelling active temp basal for reason: %{public}@", log: log, type: .default, reason.rawValue)

        let recommendation = AutomaticDoseRecommendation(basalAdjustment: .cancel, direction: .decrease)

        var dosingDecision = StoredDosingDecision(date: now(), reason: reason.rawValue)
        dosingDecision.settings = StoredDosingDecision.Settings(settingsProvider.settings)
        dosingDecision.automaticDoseRecommendation = recommendation

        dosingStarted(recommendation)
        try await deliveryDelegate.enact(bolus: recommendation.bolusUnits, tempBasal: recommendation.basalAdjustment, decisionId: dosingDecision.id)
        dosingFinished()

        await dosingDecisionStore?.storeDosingDecision(dosingDecision)
        return true
    }

    /// The "updateRemoteRecommendation" decision for a display run: stored when forced, or when the
    /// manual recommendation changed, by a host that holds the pump.
    /// DIY: these decisions are also Nightscout's Loop pill and forecast source (NightscoutService pairs
    /// them with the cached "loop" decision), so callers force-store after every cycle and temp basal
    /// cancel, to keep Nightscout current even when the manual recommendation has not changed.
    public func storeRemoteRecommendation(displayState: AlgorithmDisplayState, force: Bool, isolation: isolated (any Actor)? = #isolation) async {
        let host = requiredHost
        guard host.holdsPump else { return }

        if lastManualBolusRecommendation == nil {
            lastManualBolusRecommendation = displayState.output?.recommendation?.manual
        }

        let recommendationChanged = lastManualBolusRecommendation != displayState.output?.recommendation?.manual

        guard force || recommendationChanged else {
            return
        }

        lastManualBolusRecommendation = displayState.output?.recommendation?.manual

        guard let output = displayState.output else { return }

        var dosingDecision = StoredDosingDecision(date: now(), reason: "updateRemoteRecommendation")
        dosingDecision.algorithmExperiments = host.algorithmExperiments(for: host.currentDosingStrategy, guardAndRunway: output.guardAndRunway)
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

        dosingDecision.controllerStatus = host.controllerStatus

        // Device status for the Nightscout devicestatus.pump payload.
        dosingDecision.pumpManagerStatus = host.deliveryDelegate?.pumpManagerStatus
        if let pumpStatusHighlight = host.deliveryDelegate?.pumpStatusHighlight {
            dosingDecision.pumpStatusHighlight = StoredDosingDecision.StoredDeviceHighlight(
                localizedMessage: pumpStatusHighlight.localizedMessage,
                imageName: pumpStatusHighlight.imageName,
                state: pumpStatusHighlight.state)
        }
        dosingDecision.cgmManagerStatus = host.deliveryDelegate?.cgmManagerStatus
        dosingDecision.lastReservoirValue = StoredDosingDecision.LastReservoirValue(doseStore.lastReservoirValue)

        os_log("Manual bolus rec = %{public}@", log: log, type: .debug, String(describing: dosingDecision.manualBolusRecommendation))
        await dosingDecisionStore?.storeDosingDecision(dosingDecision)
    }

    /// The display run: the forecast and recommendations shown between cycles, over a day of doses so
    /// the last manual bolus can be read from its input. Empty when the input cannot be fetched.
    public func displayState(isolation: isolated (any Actor)? = #isolation) async -> AlgorithmDisplayState {
        var state = AlgorithmDisplayState()
        do {
            let now = self.now()
            var input = try await fetchData(for: now, ensureDosingCoverageStart: now.addingTimeInterval(.days(-1)), projectOngoingDoses: true)
            input.recommendationType = .manualBolus
            state.input = input
            state.output = await Self.runAlgorithm(input: input)
        } catch {
            let loopError = error as? LoopError ?? .unknownError(error)
            os_log("Error updating Loop state: %{public}@", log: log, type: .error, String(describing: loopError))
        }
        return state
    }

    /// Off the caller's actor.
    private static func runAlgorithm(input: StoredDataAlgorithmInput) async -> AlgorithmOutput<StoredCarbEntry> {
        LoopAlgorithm.run(input: input)
    }
}
