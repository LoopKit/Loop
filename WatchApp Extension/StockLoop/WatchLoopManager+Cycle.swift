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
    /// run, `updateDisplayState`. `lastLoopCompleted` moves, as in stock, only on an error-free
    /// closed-loop cycle. Remaining differences from stock:
    /// - enact is gated on the watch's loop mode (`closedLoopEnabled`), not the phone's `dosingEnabled`;
    /// - no `StoredDosingDecision` is stored; a CYCLE VERDICT line is logged instead;
    /// - the dead-man watchdog (`LoopStallWatchdog`) is refreshed on any error-free cycle, open or
    ///   closed, with a pod held (stock's loop-failure notification keys off `lastLoopCompleted`);
    /// - the predicted-low alert reads the display run's forecast, as stock, but only after a
    ///   cycle whose compute succeeded (stock evaluates on both arms);
    /// - not stock: a recommendation older than five minutes is refused at enact.
    func loop() {
        dataAccessQueue.async {
            self.log.default("Loop running")
            self.lastLoopError = nil
            let startDate = self.now()

            var error: WatchLoopError? = nil
            if error == nil {
                error = self.updatePredictedGlucoseAndRecommendedDose()
            }

            if case .missingDataError(let what)? = error {
                SportLog.event("loop", "NOT DOSING — prediction missing \(what)")
            }

            let decided = self.recommendedAutomaticDose?.recommendation
            self.lastRecommendation = decided
            if error == nil, self._closedLoopEnabled {
                error = self.enactRecommendedAutomaticDose()
            } else if error == nil {
                self.log.default("Advisory (open loop) — computed but not enacting.")
            }

            self.lastLoopError = error

            // Open loop first: it still computes with no error, so later arms would report an unsent command.
            let enactVerdict: String
            if !self._closedLoopEnabled { enactVerdict = "none(open-loop)" }
            else if decided?.basalAdjustment == nil && decided != nil { enactVerdict = "none(no-change)" }
            else if decided == nil { enactVerdict = "none(nothing-decided)" }
            else if case .enactFailed(let why)? = error { enactVerdict = "FAILED \(why)" }
            else if error != nil { enactVerdict = "not-attempted(\(error!))" }
            else { enactVerdict = "ok" }

            let watchdogRefreshed = (error == nil && self.pumpManager != nil)
            if watchdogRefreshed { LoopStallWatchdog.refresh(); self.onCycleLanded?() }
            let sinceCompleted = self.lastLoopCompleted.map { Int(self.now().timeIntervalSince($0)) }

            // Compute and enact judged separately; never type an enact failure as `.missingDataError`.
            let computeSucceeded: Bool = {
                switch error {
                case .none: return true
                case .enactFailed, .pumpManagerUnconnected,
                     .pumpInoperable, .pumpSuspended, .manualTempBasalRunning: return true
                default: return false
                }
            }()

            // Battery rides this line because it is the one line guaranteed every cycle.
            SportLog.event("loop", String(format: "CYCLE VERDICT computed=%@ enact=%@ watchdog=%@ lastCompletedAge=%@",
                                          computeSucceeded ? "ok" : "FAILED",
                                          enactVerdict,
                                          watchdogRefreshed ? "refreshed" : "HELD",
                                          sinceCompleted.map { "\($0)s" } ?? "never") + " · " + batteryTag())

            if let error {
                self.log.error("Loop ended with error: %{public}@", String(describing: error))

                if case .missingDataError = error {} else {
                    SportLog.event("loop", "cycle ended with error: \(error)")
                }
            } else {
                // As stock: only after a successful enact with the loop closed; an open-loop
                // cycle never moves it.
                if self._closedLoopEnabled {
                    self.lastLoopCompleted = self.now()
                }
                self.log.default("Loop ended (duration %.1fs)", self.now().timeIntervalSince(startDate))
                let bg = self.glucoseStore.latestGlucose.map { String(format: "%.0f", $0.quantity.doubleValue(for: .milligramsPerDeciliter)) } ?? "—"

                let rec = decided.map { r in
                    String(format: "%.2f U/h", r.basalAdjustment.unitsPerHour) + (r.bolusUnits.map { String(format: " + auto-bolus %.2f U", $0) } ?? "")
                } ?? "none"
                SportLog.event("loop", "cycle OK — BG \(bg), IOB \(self.loopRunState.output?.activeInsulin.map { String(format: "%.2f", $0) } ?? "—"), temp \(rec)")
                // Success only, so the debug screen may describe an older cycle.
                self.logPredictionBreakdown(decided: decided)
            }

            // Both arms, as stock's `loop()` ends: the display run, then the stock pages' context.
            self.updateDisplayStateOnQueue()

            // Stock's predicted-low alert reads `LoopDataManager.predictedGlucose`, the display
            // run's forecast. Stock evaluates on both arms; the wrist keeps its compute-succeeded gate.
            if computeSucceeded { self.evaluatePredictedLowAlert(self.displayState.output?.predictedGlucose) }
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

    /// A labelled copy of stock `LoopDataManager.fetchData`: same parameters, same body, adapted
    /// only where the watch's sources differ:
    /// - `settingsProvider` is `WatchSettingsProvider` (the grant's snapshot, with the phone's
    ///   settings history before the grant);
    /// - the override history is this manager's `overrideHistory`, and the active override is
    ///   `scheduleOverride` while active (stock: `temporaryPresetsManager.activeOverride`);
    /// - the carb window is stock's `LoopConstants.maxCarbEntryPastTime` (−12 h), a phone-only constant;
    /// - errors are `WatchLoopError.configurationError`, not `LoopError`;
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
            throw WatchLoopError.configurationError("basalRateSchedule")
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
            throw WatchLoopError.configurationError("carbRatioSchedule")
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
            throw WatchLoopError.configurationError("maximumBolus")
        }

        guard let maxBasalRate = dosingLimits.maxBasalRate else {
            throw WatchLoopError.configurationError("maximumBasalRatePerHour")
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
            throw WatchLoopError.configurationError("insulinSensitivitySchedule")
        }

        let sensitivityWithOverrides = overrides.applySensitivity(over: sensitivity)

        guard !basal.isEmpty else {
            throw WatchLoopError.configurationError("basalRateSchedule")
        }
        let basalWithOverrides = overrides.applyBasal(over: basal)

        guard !carbRatio.isEmpty else {
            throw WatchLoopError.configurationError("carbRatioSchedule")
        }
        let carbRatioWithOverrides = overrides.applyCarbRatio(over: carbRatio)

        var target: [AbsoluteScheduleValue<ClosedRange<LoopQuantity>>]

        guard var suspendThreshold = dosingLimits.suspendThreshold else {
            throw WatchLoopError.configurationError("suspendThreshold")
        }

        // If we have an active override, and it's not a preMeal override that should be disabled,
        // or ended for other reasons (like comparing effects without preset), then override the
        // target for the entire forecast.
        if let activeOverride,
           !presumePresetEndingNow
        {
            guard let schedule = settingsProvider.settings.glucoseTargetRangeSchedule else
            {
                throw WatchLoopError.configurationError("glucoseTargetRangeSchedule")
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
            throw WatchLoopError.configurationError("glucoseTargetRangeSchedule")
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
    func loopInputRecencyError(_ input: StoredDataAlgorithmInput, at loopBaseTime: Date) -> WatchLoopError? {
        guard let latestGlucose = input.glucoseHistory.last else {
            return .missingDataError("glucose")
        }

        guard loopBaseTime.timeIntervalSince(latestGlucose.startDate) <= LoopAlgorithm.inputDataRecencyInterval else {
            return .missingDataError(String(format: "glucoseTooOld (%.0f s old)", loopBaseTime.timeIntervalSince(latestGlucose.startDate)))
        }

        guard latestGlucose.startDate.timeIntervalSince(loopBaseTime) <= LoopAlgorithm.inputDataRecencyInterval else {
            return .missingDataError(String(format: "invalidFutureGlucose (%.0f s ahead)", latestGlucose.startDate.timeIntervalSince(loopBaseTime)))
        }

        let pumpDataAge = loopBaseTime.timeIntervalSince(doseStore.lastAddedPumpData)
        guard pumpDataAge <= LoopAlgorithm.inputDataRecencyInterval else {
            return .missingDataError(String(format: "pumpDataTooOld (%.0f s since the last pump report)", pumpDataAge))
        }
        return nil
    }

    /// The body of stock `loop()` up to the enact: fetch, trim, check, run, round, decide.
    func updatePredictedGlucoseAndRecommendedDose() -> WatchLoopError? {
        dispatchPrecondition(condition: .onQueue(dataAccessQueue))

        let loopBaseTime = now()

        var input: StoredDataAlgorithmInput
        do {
            input = try runBlocking { try await self.fetchData(for: loopBaseTime) }
        } catch let error as WatchLoopError {
            return error
        } catch {
            // Anything the stores throw is a COMPUTE failure by definition — nothing has been
            // sent to the pod at this point.
            return .missingDataError(String(describing: error))
        }

        // Trim future basal
        input.doses = input.doses.trimmed(to: loopBaseTime)

        var dosingStrategy: AutomaticDosingStrategy = .automaticBolus

        if FeatureFlags.dosingStrategySelectionEnabled {
            dosingStrategy = settingsProvider.settings.automaticDosingStrategy
        }
        input.recommendationType = dosingStrategy.recommendationType

        if let error = loopInputRecencyError(input, at: loopBaseTime) {
            return error
        }

        let output = LoopAlgorithm.run(input: input)

        loopRunState = AlgorithmDisplayState(input: input, output: output)

        switch output.recommendationResult {
        case .failure(let error):
            // Clear the pending command as well as reporting: an algorithm that has just declined
            // must not leave a previous cycle's recommendation behind for the enact path to find.
            recommendedAutomaticDose = nil
            SportLog.event("dosemath", "algorithm declined: \(String(describing: error))")
            return .missingDataError(String(describing: error))

        case .success(let recommendation):
            guard var automatic = recommendation.automatic else {
                recommendedAutomaticDose = nil
                self.log.default("No dose recommended.")
                return nil
            }

            var basal = automatic.basalAdjustment
            basal.unitsPerHour = roundBasalRate(unitsPerHour: basal.unitsPerHour)
            let scheduledBasalRate = input.basal.closestPrior(to: loopBaseTime)?.value ?? 0
            let adjusted = basal.adjustForCurrentDelivery(
                at: loopBaseTime,
                neutralBasalRate: scheduledBasalRate,
                currentTempBasal: runningTempBasal(),
                continuationInterval: .minutes(11),
                neutralBasalRateMatchesPump: overrideHistory.activeOverride(at: loopBaseTime) == nil
            )

            // Stock's call: `continuationInterval` leaves a matching temp alone; `neutralBasalRateMatchesPump`
            // is false under an override. Nil means no command.
            let bolusUnits = automatic.bolusUnits.flatMap { $0 > 0 ? $0 : nil }
            automatic.bolusUnits = bolusUnits

            guard adjusted != nil || bolusUnits != nil else {
                recommendedAutomaticDose = nil
                SportLog.event("dosemath", String(format: "no command needed — pod already at %.2f U/hr", basal.unitsPerHour))
                return nil
            }
            if let adjusted {
                automatic.basalAdjustment = adjusted
            }

            recommendedAutomaticDose = (recommendation: automatic, enactTempBasal: adjusted != nil, date: loopBaseTime)
            let derivation = algorithmSummary(input: input, output: output, enacting: adjusted ?? basal)
                + (adjusted == nil ? " (temp unchanged)" : "")
                + (bolusUnits.map { String(format: " + auto-bolus %.2f U", $0) } ?? "")
            SportLog.event("dosemath", derivation)
            return nil
        }
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

    func updateDisplayStateOnQueue() {
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
