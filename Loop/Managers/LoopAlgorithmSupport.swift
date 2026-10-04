//
//  LoopAlgorithmSupport.swift
//  Loop
//
//  Moved unchanged from LoopDataManager.swift so the watch app compiles the same definitions.
//  LastReservoirValue and Settings were private there; the watch and
//  LoopDataManager+PodLoan.swift use them.
//

import Foundation
import LoopKit
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

extension StoredDosingDecision.LastReservoirValue {
    init?(_ reservoirValue: ReservoirValue?) {
        guard let reservoirValue = reservoirValue else {
            return nil
        }
        self.init(startDate: reservoirValue.startDate, unitVolume: reservoirValue.unitVolume)
    }
}

extension StoredDosingDecision.Settings {
    init?(_ settings: StoredSettings?) {
        guard let settings = settings else {
            return nil
        }
        self.init(syncIdentifier: settings.syncIdentifier)
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

extension StoredDataAlgorithmInput {
    /// The body of `LoopDataManager.fetchData`, shared with the watch app. Each caller passes its own
    /// sources; `isolation` keeps the work on the caller's actor (the main actor for LoopDataManager).
    static func fetch(
        for baseTime: Date?,
        presumePresetEndingNow: Bool,
        ensureDosingCoverageStart: Date?,
        projectOngoingDoses: Bool,
        now: Date,
        doseStore: DoseStoreProtocol,
        carbStore: CarbStoreProtocol,
        glucoseStore: GlucoseStoreProtocol,
        settingsProvider: SettingsProvider,
        overrideHistory: TemporaryScheduleOverrideHistory,
        activeOverride: TemporaryScheduleOverride?,
        pumpInsulinType: InsulinType?,
        insulinModel insulinModelForType: (InsulinType?) -> InsulinModel,
        useIntegralRetrospectiveCorrection: Bool,
        applicationFactorStrategy: ApplicationFactorStrategy,
        carbAbsorptionModel: CarbAbsorptionModel,
        isolation: isolated (any Actor)? = #isolation
    ) async throws -> StoredDataAlgorithmInput {
        func insulinModel(for type: InsulinType?) -> InsulinModel { insulinModelForType(type) }

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

        let recommendationInsulinModel = insulinModel(for: pumpInsulinType ?? .novolog)

        let recommendationEffectInterval = DateInterval(
            start: baseTime,
            duration: recommendationInsulinModel.effectDuration
        )
        let neededSensitivityTimeline = LoopAlgorithm.timelineIntervalForSensitivity(
            doses: dosesWithModel,
            glucoseHistoryStart: glucose.first?.startDate ?? baseTime,
            recommendationEffectInterval: recommendationEffectInterval
        )

        // Carb entries (and a backdated manual-bolus entry) can extend back to carbsStart, and
        // CarbMath.map(to:) preconditionFailures if the ISF/carb-ratio timelines don't cover every
        // carb entry's start date. timelineIntervalForSensitivity derives its window from dose and
        // glucose history only — which can be more recent than carbsStart (e.g. after a CGM gap) —
        // so extend the ISF (and override) window back to cover the carb window, matching carbRatio.
        let sensitivityStart = min(neededSensitivityTimeline.start, carbsStart)

        let sensitivity = try await settingsProvider.getInsulinSensitivityHistory(
            startDate: sensitivityStart,
            endDate: neededSensitivityTimeline.end
        )

        let dosingLimits = try await settingsProvider.getDosingLimits(at: baseTime)

        guard let maxBolus = dosingLimits.maxBolus else {
            throw LoopError.configurationError(.maximumBolus)
        }

        guard let maxBasalRate = dosingLimits.maxBasalRate else {
            throw LoopError.configurationError(.maximumBasalRatePerHour)
        }

        var overrides = overrideHistory.getOverrideHistory(startDate: sensitivityStart, endDate: forecastEndTime)

        // For recommendation, we should consider preMeal override to be ending at time of dose
        if presumePresetEndingNow,
           let activeOverride,
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
        if let activeOverride,
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
            useIntegralRetrospectiveCorrection: useIntegralRetrospectiveCorrection,
            includePositiveVelocityAndRC: true,
            carbAbsorptionModel: carbAbsorptionModel,
            recommendationInsulinModel: recommendationInsulinModel,
            recommendationType: .manualBolus,
            automaticBolusApplicationFactor: effectiveBolusApplicationFactor)
    }
}
