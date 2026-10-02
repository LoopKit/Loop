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

    /// Stock `LoopDataManager.loop()`, except: enact is gated on the watch's loop mode;
    /// `lastLoopCompleted` advances on any error-free cycle; the dead-man watchdog is deferred
    /// only when any owed command landed; no `StoredDosingDecision`. The verdict is always logged.
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
                case .enactFailed, .pumpManagerUnconnected: return true
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
                self.lastLoopCompleted = self.now()
                self.log.default("Loop ended (duration %.1fs)", self.now().timeIntervalSince(startDate))
                let bg = self.glucoseStore.latestGlucose.map { String(format: "%.0f", $0.quantity.doubleValue(for: .milligramsPerDeciliter)) } ?? "—"

                let rec = decided.map { r in
                    String(format: "%.2f U/h", r.basalAdjustment.unitsPerHour) + (r.bolusUnits.map { String(format: " + auto-bolus %.2f U", $0) } ?? "")
                } ?? "none"
                SportLog.event("loop", "cycle OK — BG \(bg), IOB \(self.activeInsulin.map { String(format: "%.2f", $0) } ?? "—"), temp \(rec)")
                // Success only, so the debug screen may describe an older cycle.
                self.logPredictionBreakdown(decided: decided)
            }

            // Stock runs predicted low on each completed cycle's forecast.
            if computeSucceeded { self.evaluatePredictedLowAlert(self.predictedGlucose) }

            // Both arms, as stock's `updateDisplayState()`.
            self.publishHUDContext()
        }
    }

    /// Compute and publish without enacting.
    func refreshPredictionForGlance() {
        dataAccessQueue.async {
            var error: WatchLoopError? = nil
            if error == nil {
                error = self.updatePredictedGlucoseAndRecommendedDose()
            }
            if case .missingDataError(let what)? = error {
                SportLog.event("loop", "takeover prediction refresh — not yet (missing \(what))")
            } else if error == nil {
                self.lastRecommendation = self.recommendedAutomaticDose?.recommendation
                SportLog.event("loop", "takeover prediction refresh — IOB \(self.activeInsulin.map { String(format: "%.2f U", $0) } ?? "—"), eventual + carbs refreshed (no enact)")
                self.logPredictionBreakdown(decided: self.recommendedAutomaticDose?.recommendation)
            }
            self.publishHUDContext()
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

    /// Rounds to nearest; stock rounds down, so this can be one increment higher.
    func roundedBasalRate(_ unitsPerHour: Double) -> Double {
        guard let supported = pumpManager?.supportedBasalRates, !supported.isEmpty else { return unitsPerHour }
        return supported.enumerated().min(by: {
            abs($0.element - unitsPerHour) < abs($1.element - unitsPerHour)
        })?.element ?? unitsPerHour
    }

    /// Stock `LoopDataManager.fetchData`, except: the pump-data recency gate lives here; doses
    /// are trimmed per dose (no forward credit); no preset-ending, high-needs threshold or
    /// ongoing-dose projection; missing settings throw rather than default.
    func fetchAlgorithmInput(at baseTime: Date, recommendationType: DoseRecommendationType) async throws -> StoredDataAlgorithmInput {
        // Dose history reaches back a full carb absorption PLUS a full insulin duration, as in
        // stock: dynamic carb absorption is derived from glucose the older insulin also moved.
        let dosesInputHistory = CarbMath.maximumAbsorptionTimeInterval + InsulinMath.defaultInsulinActivityDuration
        var dosesStart = baseTime.addingTimeInterval(-dosesInputHistory)

        // Difference 1: the gate is here, not in `loop()`, so nothing computes on a stale book.
        let pumpDataAge = baseTime.timeIntervalSince(doseStore.lastAddedPumpData)
        guard pumpDataAge <= LoopAlgorithm.inputDataRecencyInterval else {
            throw WatchLoopError.missingDataError(String(format: "pumpDataTooOld (%.0f s since the last pump report)", pumpDataAge))
        }

        // Difference 2: the per-dose trim, which pro-rates a bolus in flight.
        let doses: [DoseEntry] = try await doseStore.getNormalizedDoseEntries(start: dosesStart, end: baseTime)
            .compactMap { $0.trimmed(to: baseTime) }
        // Widen to cover doses that straddle the window.
        dosesStart = min(dosesStart, doses.map { $0.startDate }.min() ?? dosesStart)
        let dosesEnd = max(baseTime, doses.map { $0.endDate }.max() ?? baseTime)

        let rawBasal = try await settingsProvider.getBasalHistory(startDate: dosesStart, endDate: dosesEnd)
        guard !rawBasal.isEmpty else { throw WatchLoopError.configurationError("basalRateSchedule") }

        // Collapse same-rate entries split at midnight, as stock does.
        let basal: [AbsoluteScheduleValue<Double>] = rawBasal.reduce(into: []) { acc, entry in
            if let last = acc.last, last.value == entry.value, last.endDate == entry.startDate {
                acc[acc.count - 1] = AbsoluteScheduleValue(startDate: last.startDate, endDate: entry.endDate, value: last.value)
            } else {
                acc.append(entry)
            }
        }

        let forecastEndTime = baseTime.addingTimeInterval(InsulinMath.defaultInsulinActivityDuration).dateCeiledToTimeInterval(GlucoseMath.defaultDelta)
        // Stock's `LoopConstants.maxCarbEntryPastTime` (phone-only) less a minute for carb/ratio second skew.
        let carbsStart = baseTime.addingTimeInterval(.hours(-12) + .minutes(-1))

        let carbEntries = try await carbStore.getCarbEntries(start: carbsStart, end: forecastEndTime)
            .filter { $0.userCreatedDate ?? $0.startDate < baseTime }

        let carbRatio = try await settingsProvider.getCarbRatioHistory(startDate: carbsStart, endDate: forecastEndTime)
        guard !carbRatio.isEmpty else { throw WatchLoopError.configurationError("carbRatioSchedule") }

        // Glucose shares the carb window: retrospective correction and dynamic absorption both
        // need history as far back as the oldest carb that can still be absorbing.
        let glucose = try await glucoseStore.getGlucoseSamples(start: carbsStart, end: baseTime)

        let dosesWithModel = doses.map { $0.simpleDose(with: insulinModel(for: $0.insulinType)) }
        let recommendationInsulinModel = insulinModel(for: pumpManager?.status.insulinType)

        let neededSensitivityTimeline = LoopAlgorithm.timelineIntervalForSensitivity(
            doses: dosesWithModel,
            glucoseHistoryStart: glucose.first?.startDate ?? baseTime,
            recommendationEffectInterval: DateInterval(start: baseTime, duration: recommendationInsulinModel.effectDuration)
        )
        // Covers every carb entry: glucose (and so this timeline) can start later, e.g. after a CGM gap.
        let sensitivityStart = min(neededSensitivityTimeline.start, carbsStart)
        let sensitivity = try await settingsProvider.getInsulinSensitivityHistory(
            startDate: sensitivityStart,
            endDate: neededSensitivityTimeline.end
        )
        guard !sensitivity.isEmpty else { throw WatchLoopError.configurationError("insulinSensitivitySchedule") }

        let dosingLimits = try await settingsProvider.getDosingLimits(at: baseTime)
        guard let maxBolus = dosingLimits.maxBolus else { throw WatchLoopError.configurationError("maximumBolus") }
        guard let maxBasalRate = dosingLimits.maxBasalRate else { throw WatchLoopError.configurationError("maximumBasalRatePerHour") }
        guard let suspendThreshold = dosingLimits.suspendThreshold else { throw WatchLoopError.configurationError("suspendThreshold") }

        let overrides = overrideHistory.getOverrideHistory(startDate: sensitivityStart, endDate: forecastEndTime)

        // An override replaces the target for the whole forecast; the suspend threshold is the grant's.
        var target: [AbsoluteScheduleValue<ClosedRange<LoopQuantity>>]
        if let activeOverride = scheduleOverride, activeOverride.isActive(at: baseTime) {
            guard let schedule = settings.glucoseTargetRangeSchedule else {
                throw WatchLoopError.configurationError("glucoseTargetRangeSchedule")
            }
            let overridden = activeOverride.effectiveCorrectionRangeDuring(scheduledRange: schedule.quantityRange(at: baseTime))
            target = [AbsoluteScheduleValue(startDate: baseTime, endDate: forecastEndTime, value: overridden)]
        } else {
            target = try await settingsProvider.getTargetRangeHistory(startDate: baseTime, endDate: forecastEndTime)
        }
        guard !target.isEmpty else { throw WatchLoopError.configurationError("glucoseTargetRangeSchedule") }

        // The override scales basal, ISF and carb ratio through the history, not only the target.
        return StoredDataAlgorithmInput(
            glucoseHistory: glucose,
            doses: dosesWithModel,
            carbEntries: carbEntries,
            predictionStart: baseTime,
            basal: overrides.applyBasal(over: basal),
            sensitivity: overrides.applySensitivity(over: sensitivity),
            carbRatio: overrides.applyCarbRatio(over: carbRatio),
            target: target,
            suspendThreshold: suspendThreshold,
            maxBolus: maxBolus,
            maxBasalRate: maxBasalRate,
            useIntegralRetrospectiveCorrection: integralRetrospectiveCorrectionEnabled,
            includePositiveVelocityAndRC: true,
            carbAbsorptionModel: .piecewiseLinear,
            recommendationInsulinModel: recommendationInsulinModel,
            recommendationType: recommendationType
        )
    }

    /// The body of stock `loop()`: fetch, run, round, decide. No `invalidFutureGlucose` gate.
    func updatePredictedGlucoseAndRecommendedDose() -> WatchLoopError? {
        dispatchPrecondition(condition: .onQueue(dataAccessQueue))

        let startDate = now()

        // The phone's dosing strategy, carried in the grant.
        let recommendationType: DoseRecommendationType = settings.automaticDosingStrategy == .automaticBolus ? .automaticBolus : .tempBasal

        let input: StoredDataAlgorithmInput
        do {
            input = try runBlocking { try await self.fetchAlgorithmInput(at: startDate, recommendationType: recommendationType) }
        } catch let error as WatchLoopError {
            return error
        } catch {
            // Anything the stores or the algorithm throw is a COMPUTE failure by definition —
            // nothing has been sent to the pod at this point.
            return .missingDataError(String(describing: error))
        }

        let output = LoopAlgorithm.run(input: input)

        predictedGlucose = output.predictedGlucose
        activeInsulin = output.activeInsulin
        activeCarbs = output.activeCarbs
        lastAlgorithmEffects = output.effects

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
            // Nearest-rate rounding, not stock's floor — see `roundedBasalRate`.
            basal.unitsPerHour = roundedBasalRate(basal.unitsPerHour)
            let scheduledBasalRate = input.basal.closestPrior(to: startDate)?.value ?? 0
            let adjusted = basal.adjustForCurrentDelivery(
                at: startDate,
                neutralBasalRate: scheduledBasalRate,
                currentTempBasal: runningTempBasal(),
                continuationInterval: .minutes(11),
                neutralBasalRateMatchesPump: scheduleOverride == nil
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

            recommendedAutomaticDose = (recommendation: automatic, enactTempBasal: adjusted != nil, date: startDate)
            let derivation = algorithmSummary(input: input, output: output, enacting: adjusted ?? basal)
                + (adjusted == nil ? " (temp unchanged)" : "")
                + (bolusUnits.map { String(format: " + auto-bolus %.2f U", $0) } ?? "")
            SportLog.event("dosemath", derivation)
            return nil
        }
    }

    /// Republish without a cycle; `publishHUDContext` still runs a manual-bolus pass.
    func updateDisplayState() {
        dataAccessQueue.async {
            self.publishHUDContext()
            self.refreshGlanceData()
        }
    }
}
