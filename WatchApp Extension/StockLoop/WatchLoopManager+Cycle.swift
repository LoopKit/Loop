//
//  WatchLoopManager+Cycle.swift
//  WatchApp Extension
//
//  Stock's `loop()` on the wrist, synchronous on `dataAccessQueue` (`runBlocking` bridges the
//  stores' async API). One CYCLE VERDICT line per cycle.
//

import Foundation
import HealthKit
import LoopKit
import LoopAlgorithm
import LoopCore
import WatchConnectivity
import os.log

extension WatchLoopManager {

    /// Stock `DeviceDataManager.checkPumpDataAndLoop`, but returns with no pump (between loans
    /// there is nothing to decide), noting a reading awaited by a rebuild.
    func checkPumpDataAndLoop() {
        guard let pumpManager = pumpManager else {
            awaitedPumpLock.lock()
            if awaitingPumpManager { readingArrivedWithoutPump = true }
            awaitedPumpLock.unlock()

            if !loggedIdleNoPump {
                loggedIdleNoPump = true
                SportLog.event("loop", "idle — no pod on the watch; cycles paused until the next grant (glucose still ingesting)")
            }
            return
        }
        loggedIdleNoPump = false

        // The only entry point that refreshes the pod before computing.
        pumpManager.ensureCurrentPumpData { _ in self.loop() }
    }

    /// Stock `LoopDataManager.loop()`: the input is `fetchData(for: now)` with basal-type doses
    /// trimmed at now (a bolus in flight counts whole), the recommendation type is the phone's
    /// dosing strategy, stock's glucose and pump-data recency checks run before the algorithm,
    /// the temp is rounded by the pump manager, and every cycle (both arms) ends with the display
    /// run, `updateDisplayState`, which force-stores the "updateRemoteRecommendation" decision.
    /// The "loop" decision is built and stored as stock builds it, on both arms, and its id goes to
    /// the pod with the dose. `lastLoopCompleted` moves, as in stock, only on an error-free
    /// closed-loop cycle. Remaining differences from stock:
    /// - enact is gated on the watch's loop mode (`_closedLoopEnabled`), not the phone's `dosingEnabled`;
    /// - decisions are stored only while the pod is held (`storeDosingDecision`);
    /// - the dead-man watchdog (`LoopStallWatchdog`) is refreshed on any error-free cycle, open or
    ///   closed, with a pod held (stock's loop-failure notification keys off `lastLoopCompleted`).
    func loop() {
        dataAccessQueue.async {
            self.log.default("Loop running")
            self.lastLoopError = nil
            self.lastRecommendation = nil
            let loopBaseTime = self.now()

            var dosingDecision = StoredDosingDecision(
                date: loopBaseTime,
                reason: "loop",
                settings: StoredDosingDecision.Settings(self.settingsProvider.settings)
            )

            // The recommendation as it will be enacted, and what it sends (nil: nothing of that kind).
            var decided: AutomaticDoseRecommendation?
            var basalAdjustment: TempBasalRecommendation?
            var computeError: LoopError?
            var enactError: LoopError?

            do {
                var input = try self.runBlocking { try await self.fetchData(for: loopBaseTime) }

                // Trim future basal
                input.doses = input.doses.trimmed(to: loopBaseTime)

                var dosingStrategy: AutomaticDosingStrategy = .automaticBolus

                if FeatureFlags.dosingStrategySelectionEnabled {
                    dosingStrategy = self.settingsProvider.settings.automaticDosingStrategy
                }
                input.recommendationType = dosingStrategy.recommendationType

                if let error = self.loopInputRecencyError(input, at: loopBaseTime) {
                    throw error
                }

                var output = LoopAlgorithm.run(input: input)
                self.loopRunState = AlgorithmDisplayState(input: input, output: output)

                switch output.recommendationResult {
                case .success(let recommendation):
                    // Stock force-unwraps this; an automatic run always carries one.
                    guard let algoRecommendation = recommendation.automatic else {
                        dosingDecision.updateFrom(input: input, output: output)
                        self.log.default("No dose recommended.")
                        break
                    }

                    var recommendationToEnact = algoRecommendation
                    // Round bolus recommendation based on pump bolus precision
                    if let bolus = algoRecommendation.bolusUnits, bolus > 0 {
                        recommendationToEnact.bolusUnits = self.roundBolusVolume(units: bolus)
                    }

                    var basal = algoRecommendation.basalAdjustment
                    basal.unitsPerHour = self.roundBasalRate(unitsPerHour: basal.unitsPerHour)
                    let scheduledBasalRate = input.basal.closestPrior(to: loopBaseTime)?.value ?? 0

                    // Stock's call: `continuationInterval` leaves a matching temp alone;
                    // `neutralBasalRateMatchesPump` is false under an override. Nil means no command.
                    basalAdjustment = basal.adjustForCurrentDelivery(
                        at: loopBaseTime,
                        neutralBasalRate: scheduledBasalRate,
                        currentTempBasal: self.runningTempBasal(),
                        continuationInterval: .minutes(11),
                        neutralBasalRateMatchesPump: self.overrideHistory.activeOverride(at: loopBaseTime) == nil
                    )

                    if let basalAdjustment {
                        recommendationToEnact.basalAdjustment = basalAdjustment
                    }

                    // As stock: the decision records the recommendation as it will be enacted.
                    output.recommendationResult = .success(.init(automatic: recommendationToEnact))
                    dosingDecision.updateFrom(input: input, output: output)
                    decided = recommendationToEnact
                    self.lastRecommendation = recommendationToEnact

                    let bolus = recommendationToEnact.bolusUnits.flatMap { $0 > 0 ? $0 : nil }
                    if basalAdjustment == nil, bolus == nil {
                        SportLog.event("dosemath", String(format: "no command needed — pod already at %.2f U/hr", basal.unitsPerHour))
                    } else {
                        SportLog.event("dosemath", self.algorithmSummary(input: input, output: output, enacting: basalAdjustment ?? basal)
                            + (basalAdjustment == nil ? " (temp unchanged)" : "")
                            + (bolus.map { String(format: " + auto-bolus %.2f U", $0) } ?? ""))
                    }

                case .failure(let error):
                    SportLog.event("dosemath", "algorithm declined: \(String(describing: error))")
                    throw error
                }
            } catch {
                // As stock's `loop()` catch.
                computeError = error as? LoopError ?? .unknownError(error)
            }

            if let computeError {
                SportLog.event("loop", "NOT DOSING — \(computeError.localizedDescription) (\(computeError.issueId))")
            }

            if computeError == nil, self._closedLoopEnabled {
                enactError = self.enactAutomaticDose(bolus: decided?.bolusUnits, tempBasal: basalAdjustment, decisionId: dosingDecision.id)
                if enactError == nil {
                    dosingDecision.enactedTempBasal = basalAdjustment
                    dosingDecision.enactedBolusAmount = decided?.bolusUnits
                }
            } else if computeError == nil {
                self.log.default("Advisory (open loop) — computed but not enacting.")
            }

            let error = computeError ?? enactError
            self.lastLoopError = error

            // Both arms, as stock.
            if let error { dosingDecision.appendError(error) }
            self.storeDosingDecision(dosingDecision)

            // Open loop first: it still computes with no error, so later arms would report an unsent command.
            let enactVerdict: String
            if !self._closedLoopEnabled { enactVerdict = "none(open-loop)" }
            else if computeError != nil { enactVerdict = "not-attempted(compute failed)" }
            else if let enactError {
                // The pod's or the loop's refusal before sending, versus a send that failed.
                switch enactError {
                case .pumpInoperable, .pumpSuspended, .manualTempBasalRunning, .configurationError, .connectionError, .recommendationExpired:
                    enactVerdict = "not-attempted(\(enactError.issueId))"
                default:
                    enactVerdict = "FAILED \(enactError)"
                }
            }
            else if decided == nil { enactVerdict = "none(nothing-decided)" }
            else if basalAdjustment == nil && (decided?.bolusUnits ?? 0) <= 0 { enactVerdict = "none(no-change)" }
            else { enactVerdict = "ok" }

            let watchdogRefreshed = (error == nil && self.pumpManager != nil)
            if watchdogRefreshed { LoopStallWatchdog.refresh(); self.onCycleLanded?() }
            let sinceCompleted = self.lastLoopCompleted.map { Int(self.now().timeIntervalSince($0)) }

            // Compute and enact judged by the stage that failed.
            let computeSucceeded = computeError == nil

            // Battery rides this line because it is the one line guaranteed every cycle.
            SportLog.event("loop", String(format: "CYCLE VERDICT computed=%@ enact=%@ watchdog=%@ lastCompletedAge=%@",
                                          computeSucceeded ? "ok" : "FAILED",
                                          enactVerdict,
                                          watchdogRefreshed ? "refreshed" : "HELD",
                                          sinceCompleted.map { "\($0)s" } ?? "never") + " · " + batteryTag())

            if let error {
                self.log.error("Loop ended with error: %{public}@", String(describing: error))

                if computeError == nil {
                    SportLog.event("loop", "cycle ended with error: \(error)")
                }
            } else {
                // As stock: only after a successful enact with the loop closed; an open-loop
                // cycle never moves it.
                if self._closedLoopEnabled {
                    self.lastLoopCompleted = self.now()
                }
                self.log.default("Loop ended (duration %.1fs)", self.now().timeIntervalSince(loopBaseTime))
                let bg = self.glucoseStore.latestGlucose.map { String(format: "%.0f", $0.quantity.doubleValue(for: .milligramsPerDeciliter)) } ?? "—"

                let rec = decided.map { r in
                    String(format: "%.2f U/h", r.basalAdjustment.unitsPerHour) + (r.bolusUnits.map { String(format: " + auto-bolus %.2f U", $0) } ?? "")
                } ?? "none"
                SportLog.event("loop", "cycle OK — BG \(bg), IOB \(self.loopRunState.output?.activeInsulin.map { String(format: "%.2f", $0) } ?? "—"), temp \(rec)")
                // Success only, so the debug screen may describe an older cycle.
                self.logPredictionBreakdown(decided: decided)
            }

            // Both arms, as stock's `loop()` ends: the display run, its forced
            // "updateRemoteRecommendation" decision, then the stock pages' context.
            self.updateDisplayStateOnQueue(forceStoreRemoteRecommendation: true)

            // Stock's predicted-low alert reads `LoopDataManager.predictedGlucose`, the display
            // run's forecast, on both arms.
            self.evaluatePredictedLowAlert(self.displayState.output?.predictedGlucose)
        }
    }

    /// Blocks on a semaphore; call only from `dataAccessQueue`, never main.
    func runBlocking<T>(_ work: @escaping () async throws -> T) throws -> T {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<T, Error>!
        Task {
            do { result = .success(try await work()) }
            catch { result = .failure(error) }
            semaphore.signal()
        }
        semaphore.wait()
        return try result.get()
    }

    /// Stock `DeviceDataManager.roundBasalRate`: the pump manager's rounding (Omnipod rounds down).
    func roundBasalRate(unitsPerHour: Double) -> Double {
        guard let pumpManager = pumpManager else {
            return unitsPerHour
        }

        return pumpManager.roundToSupportedBasalRate(unitsPerHour: unitsPerHour)
    }

    /// Stock `DeviceDataManager.roundBolusVolume`: the pump manager's rounding.
    func roundBolusVolume(units: Double) -> Double {
        guard let pumpManager = pumpManager else {
            return units
        }

        return pumpManager.roundToSupportedBolusVolume(units: units)
    }

    /// A labelled copy of stock `LoopDataManager.fetchData`: same parameters, same body, adapted
    /// only where the watch's sources differ:
    /// - `settingsProvider` is `WatchSettingsProvider` (the grant's snapshot, with the phone's
    ///   settings history before the grant);
    /// - the override history is this manager's `overrideHistory`, and the active override is
    ///   `scheduleOverride` while active (stock: `temporaryPresetsManager.activeOverride`);
    /// - the carb window is stock's `LoopConstants.maxCarbEntryPastTime` (−12 h), a phone-only constant;
    /// - integral retrospective correction is the grant's flag, not this device's `UserDefaults`;
    /// - the application factor is stock's `ConstantApplicationFactorStrategy` only: the
    ///   glucose-based strategy is a parked experiment, deliberately off here.
    /// No recency check lives here, as in stock: `loop()` checks after it fetches.
    func fetchData(
        for baseTime: Date? = nil,
        presumePresetEndingNow: Bool = false,
        ensureDosingCoverageStart: Date? = nil,
        projectOngoingDoses: Bool = false
    ) async throws -> StoredDataAlgorithmInput {
        // Need to fetch doses back as far as t - (DIA + DCA) for Dynamic carbs
        let dosesInputHistory = CarbMath.maximumAbsorptionTimeInterval + InsulinMath.defaultInsulinActivityDuration

        let baseTime = baseTime ?? now()

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

        // Collapse contiguous same-rate basal entries split at local midnight (see stock).
        let basal: [AbsoluteScheduleValue<Double>] = rawBasal.reduce(into: []) { acc, entry in
            if let last = acc.last, last.value == entry.value, last.endDate == entry.startDate {
                acc[acc.count - 1] = AbsoluteScheduleValue(startDate: last.startDate, endDate: entry.endDate, value: last.value)
            } else {
                acc.append(entry)
            }
        }

        let forecastEndTime = baseTime.addingTimeInterval(InsulinMath.defaultInsulinActivityDuration).dateCeiledToTimeInterval(GlucoseMath.defaultDelta)

        // Watch: stock's `LoopConstants.maxCarbEntryPastTime` (−12 h) is phone-only.
        let carbsStart = baseTime.addingTimeInterval(.hours(-12) + .minutes(-1)) // additional minute to handle difference in seconds between carb entry and carb ratio

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

        let recommendationInsulinModel = insulinModel(for: pumpManager?.status.insulinType ?? .novolog)

        let recommendationEffectInterval = DateInterval(
            start: baseTime,
            duration: recommendationInsulinModel.effectDuration
        )
        let neededSensitivityTimeline = LoopAlgorithm.timelineIntervalForSensitivity(
            doses: dosesWithModel,
            glucoseHistoryStart: glucose.first?.startDate ?? baseTime,
            recommendationEffectInterval: recommendationEffectInterval
        )

        // Extend the ISF (and override) window back to cover every carb entry (see stock).
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

        // Watch: stock's `temporaryPresetsManager.activeOverride`.
        let activeOverride = scheduleOverride.flatMap { $0.isActive(at: now()) ? $0 : nil }

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

        // Watch: stock's `ConstantApplicationFactorStrategy` (the glucose-based strategy is a
        // parked experiment, off), which returns `LoopAlgorithm.defaultBolusPartialApplicationFactor`.
        let effectiveBolusApplicationFactor: Double? = glucose.last != nil
            ? LoopAlgorithm.defaultBolusPartialApplicationFactor
            : nil

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
            useIntegralRetrospectiveCorrection: integralRetrospectiveCorrectionEnabled,
            includePositiveVelocityAndRC: true,
            carbAbsorptionModel: .piecewiseLinear,
            recommendationInsulinModel: recommendationInsulinModel,
            recommendationType: .manualBolus,
            automaticBolusApplicationFactor: effectiveBolusApplicationFactor)
    }

    /// Stock `loop()`'s checks on its input, in stock's order, after the trim and before the
    /// algorithm. As in stock, `fetchData` queries glucose up to the base time only, so a
    /// future-dated reading never reaches the input and the future check cannot fire from `loop()`.
    func loopInputRecencyError(_ input: StoredDataAlgorithmInput, at loopBaseTime: Date) -> LoopError? {
        guard let latestGlucose = input.glucoseHistory.last else {
            return .missingDataError(.glucose)
        }

        guard loopBaseTime.timeIntervalSince(latestGlucose.startDate) <= LoopAlgorithm.inputDataRecencyInterval else {
            return .glucoseTooOld(date: latestGlucose.startDate)
        }

        guard latestGlucose.startDate.timeIntervalSince(loopBaseTime) <= LoopAlgorithm.inputDataRecencyInterval else {
            return .invalidFutureGlucose(date: latestGlucose.startDate)
        }

        guard loopBaseTime.timeIntervalSince(doseStore.lastAddedPumpData) <= LoopAlgorithm.inputDataRecencyInterval else {
            return .pumpDataTooOld(date: doseStore.lastAddedPumpData)
        }
        return nil
    }

    /// Stock `LoopDataManager.updateDisplayState`: the display run, fed with doses back a day,
    /// ongoing doses projected (no trim) and `.manualBolus`, stored as `displayState`. Then the
    /// stock pages' context and the glance are republished from it. As in stock, no recency
    /// check gates this run.
    func updateDisplayState(_ completion: ((AlgorithmDisplayState) -> Void)? = nil) {
        dataAccessQueue.async {
            self.updateDisplayStateOnQueue()
            completion?(self.displayState)
        }
    }

    /// Stock's other triggers for the display run: a change in the carb, glucose or dose store, an
    /// override set or cleared, and the loop mode. No debounce, as stock. Only while a pod is held:
    /// between loans the display run is not refreshed, as before. The run writes to none of the
    /// stores observed (only to the dosing decision store), so it cannot retrigger itself.
    func updateDisplayStateForChange() {
        dataAccessQueue.async {
            guard self.pumpManager != nil else { return }
            self.updateDisplayStateOnQueue()
        }
    }

    func updateDisplayStateOnQueue(forceStoreRemoteRecommendation: Bool = false) {
        dispatchPrecondition(condition: .onQueue(dataAccessQueue))
        let now = self.now()

        var newState = AlgorithmDisplayState()
        do {
            let lastManualBolusVisibilityWindowStartDate = now.addingTimeInterval(.days(-1))

            var input = try runBlocking {
                try await self.fetchData(for: now, ensureDosingCoverageStart: lastManualBolusVisibilityWindowStartDate, projectOngoingDoses: true)
            }
            input.recommendationType = .manualBolus
            newState.input = input
            newState.output = LoopAlgorithm.run(input: input)
        } catch {
            log.error("Error updating Loop state: %{public}@", String(describing: error))
        }
        displayState = newState

        publishHUDContext()
        refreshGlanceData()

        updateRemoteRecommendation(force: forceStoreRemoteRecommendation)
    }
}

/// A labelled copy of stock's extension (`Loop/Managers/LoopDataManager.swift`, phone-only).
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
