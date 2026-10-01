//
//  WatchLoopManager+Cycle.swift
//  WatchApp Extension
//
//  The cycle: stock Loop's `loop()`, running on the wrist while the watch holds the pod.
//
//  A CGM reading — or a carb entry, or the takeover itself — calls `checkPumpDataAndLoop`, which
//  refreshes the pod's data and then runs `loop()`: compute, enact if the loop is closed,
//  publish. The whole thing is a SYNCHRONOUS state machine on `dataAccessQueue`, bridged over
//  the stores' async API by `runBlocking`. Stock is async throughout; making this async too
//  would restructure the loan's ordering guarantees for no behavioural gain.
//
//  Exactly one CYCLE VERDICT line is written per cycle, whatever happens, and it reports the
//  compute stage and the enact stage separately. See `loop()`.
//

import Foundation
import HealthKit
import LoopKit
import LoopAlgorithm
import LoopCore
import G7SensorKit
import WatchConnectivity
import os.log

extension WatchLoopManager {

    /// Mirrors stock `DeviceDataManager.checkPumpDataAndLoop`, except for what happens with no
    /// pump: stock runs the cycle anyway so it can store a dosing decision, and this RETURNS.
    /// Between loans there is no pod, no decision to store and nothing to enact, so a cycle would
    /// do nothing but log a failure every five minutes for a watch that is behaving correctly.
    ///
    /// It still records that a reading arrived while a pump was being awaited — the resume path
    /// asks for that with `endAwaitingPumpManager`, so a reading that landed mid-rebuild is not
    /// lost — and it says "idle" once rather than once per reading.
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

        // The ONLY entry point that refreshes the pod before computing. `loop()` is also called
        // directly — after a carb entry, after a manual bolus is accepted, at takeover — and
        // those paths judge the recency gate against whatever the last pod report left behind.
        pumpManager.ensureCurrentPumpData { _ in self.loop() }
    }

    /// One cycle. Mirrors stock `LoopDataManager.loop()`, with four deliberate differences.
    ///
    /// 1. The enact gate is the WATCH's `_closedLoopEnabled`. Stock gates on
    ///    `settingsProvider.dosingEnabled`, which is the phone's flag; once the pod is lent, the
    ///    watch is sovereign over its own loop mode and the therapy settings frozen into the
    ///    grant are the only limits it answers to.
    /// 2. `lastLoopCompleted` advances on ANY error-free cycle, including an open-loop one, where
    ///    stock advances it only on a cycle that actually dosed. On the wrist it means "a cycle
    ///    completed", which is what the freshness ring is asking.
    /// 3. The dead-man watchdog is re-deferred on a NARROWER condition than that: the cycle must
    ///    have computed AND, if it owed the pod a command, landed it. A run of failed enacts must
    ///    hold the alarm, not keep pushing it away.
    /// 4. No `StoredDosingDecision`: there is no decision store on the wrist, and the loan
    ///    journal is what carries the record home.
    ///
    /// The verdict line is written UNCONDITIONALLY. A cycle that logs nothing is
    /// indistinguishable from a cycle that never ran, and that ambiguity is what let a quarter of
    /// an hour of a disconnected pod read as a quiet, healthy night.
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

            // Open loop is tested FIRST and that ordering is load-bearing: with the loop open a
            // recommendation is still computed and `error` stays nil, so any later arm would
            // report a command that was never sent. The rest name a reason apiece — "no-change"
            // (the pod is already at the right rate) and "nothing-decided" (the algorithm
            // declined) look alike from outside and mean opposite things.
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

            // COMPUTE and ENACT are judged separately: a pod that refused the command still
            // produced a good prediction, and reporting that as a compute failure hides which
            // half is broken. This is why an enact failure must never be typed as
            // `.missingDataError` — it would be counted here as a failed compute and described
            // in the line above as a missing prediction, and the refusal itself would vanish.
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

                let rec = decided.map { String(format: "%.2f U/h", $0.basalAdjustment.unitsPerHour) } ?? "none"
                SportLog.event("loop", "cycle OK — BG \(bg), IOB \(self.activeInsulin.map { String(format: "%.2f", $0) } ?? "—"), temp \(rec)")
                // Only on success, so `lastPredictionBreakdown` — and the debug screen that draws
                // it — can be describing an older cycle while newer ones are failing. The verdict
                // line above is the one that is always current.
                self.logPredictionBreakdown(decided: decided)
            }

            // On BOTH arms, matching stock's `updateDisplayState()` after the do/catch: a failed
            // cycle still has to move the display, or the wrist shows the last good numbers as
            // though they were current.
            self.publishHUDContext()
        }
    }

    /// Compute and publish WITHOUT enacting — the only path that does. Takeover runs a full
    /// `loop()` instead, because a full cycle reuses every gate and mints a journal event; this
    /// remains the seam for driving a compute in isolation.
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

    /// Run async store work from the synchronous cycle. Safe ONLY because it never runs on main:
    /// it blocks the calling thread on a semaphore until the Task signals. Every caller is on
    /// `dataAccessQueue`; call it from main and the app deadlocks.
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

    /// Rounds to the NEAREST supported rate. Stock rounds DOWN — `DeviceDataManager`'s
    /// `roundBasalRate` calls the pump manager, and OmnipodKit's implementation takes the last
    /// supported rate at or below the value. So an algorithm output of 1.03 U/h becomes 1.05 here
    /// and 1.00 on the phone: a divergence of at most one increment, in the direction of more
    /// insulin. An unforced difference from stock, not a deliberate dosing choice.
    func roundedBasalRate(_ unitsPerHour: Double) -> Double {
        guard let supported = pumpManager?.supportedBasalRates, !supported.isEmpty else { return unitsPerHour }
        return supported.enumerated().min(by: {
            abs($0.element - unitsPerHour) < abs($1.element - unitsPerHour)
        })?.element ?? unitsPerHour
    }

    /// Mirrors stock `LoopDataManager.fetchData` — same queries, same order — and every
    /// difference from it is listed here.
    ///
    /// 1. The PUMP-DATA RECENCY GATE lives here rather than in `loop()`, so it also refuses the
    ///    manual-bolus recommendation and the display run. An empty book and "no insulin on
    ///    board" are the same number, and a book the pod has not written to must not license a
    ///    dose of any kind.
    /// 2. Doses are trimmed PER DOSE with LoopKit's `DoseEntry.trimmed`, which pro-rates
    ///    anything — including a bolus still being delivered. Stock trims in `loop()` with the
    ///    `[SimpleInsulinDose]` extension, which leaves boluses whole. The effect is no forward
    ///    credit for insulin the pod has not delivered yet: a temp keeps its rate and loses its
    ///    remaining window, a bolus in flight counts only for the fraction already given.
    /// 3. The carb and glucose window is 10 hours back (`CarbMath.maximumAbsorptionTimeInterval`)
    ///    where stock reaches 12 hours 1 minute.
    /// 4. The ISF and override windows start at `neededSensitivityTimeline.start`. Stock widens
    ///    both to `min(that, carbsStart)`, because `CarbMath` traps when a carb entry starts
    ///    before the sensitivity timeline — reachable whenever the dose and glucose history are
    ///    more recent than the carb window, i.e. after a CGM gap. That widening is not
    ///    reproduced here.
    /// 5. Absent from this copy: `presumePresetEndingNow` and pre-meal handling, the
    ///    `veryHighInsulinNeeds` suspend-threshold raise, and `ensureDosingCoverageStart` /
    ///    `projectOngoingDoses` — so the display run cannot project an ongoing suspend.
    /// 6. The recommendation's insulin model comes from the pod's insulin type and falls back to
    ///    the settings default; stock falls back to novolog.
    ///
    /// MISSING SETTINGS DENY DOSING. Every configuration element throws `configurationError`
    /// rather than substituting a default — a wrist that invents a basal rate is worse than a
    /// wrist that refuses.
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
        // Widen the window to whatever came back: a dose can begin before the query start and
        // still be included, and its basal must be covered. Same on the far end for one that ends
        // after `baseTime`.
        dosesStart = min(dosesStart, doses.map { $0.startDate }.min() ?? dosesStart)
        let dosesEnd = max(baseTime, doses.map { $0.endDate }.max() ?? baseTime)

        let rawBasal = try await settingsProvider.getBasalHistory(startDate: dosesStart, endDate: dosesEnd)
        guard !rawBasal.isEmpty else { throw WatchLoopError.configurationError("basalRateSchedule") }

        // Collapse contiguous same-rate entries, as stock does: the history projects the daily
        // schedule onto absolute time and splits at every local midnight even when the rate does
        // not change, and the IOB integrator does not rejoin the sub-doses across the boundary.
        let basal: [AbsoluteScheduleValue<Double>] = rawBasal.reduce(into: []) { acc, entry in
            if let last = acc.last, last.value == entry.value, last.endDate == entry.startDate {
                acc[acc.count - 1] = AbsoluteScheduleValue(startDate: last.startDate, endDate: entry.endDate, value: last.value)
            } else {
                acc.append(entry)
            }
        }

        let forecastEndTime = baseTime.addingTimeInterval(InsulinMath.defaultInsulinActivityDuration).dateCeiledToTimeInterval(GlucoseMath.defaultDelta)
        let carbsStart = baseTime.addingTimeInterval(CarbMath.maximumAbsorptionTimeInterval * -1)

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
        // Difference 4: stock starts this at `min(neededSensitivityTimeline.start, carbsStart)`.
        let sensitivity = try await settingsProvider.getInsulinSensitivityHistory(
            startDate: neededSensitivityTimeline.start,
            endDate: neededSensitivityTimeline.end
        )
        guard !sensitivity.isEmpty else { throw WatchLoopError.configurationError("insulinSensitivitySchedule") }

        let dosingLimits = try await settingsProvider.getDosingLimits(at: baseTime)
        guard let maxBolus = dosingLimits.maxBolus else { throw WatchLoopError.configurationError("maximumBolus") }
        guard let maxBasalRate = dosingLimits.maxBasalRate else { throw WatchLoopError.configurationError("maximumBasalRatePerHour") }
        guard let suspendThreshold = dosingLimits.suspendThreshold else { throw WatchLoopError.configurationError("suspendThreshold") }

        // Same window as the sensitivity query, and stock widens this one too — see difference 4.
        let overrides = overrideHistory.getOverrideHistory(startDate: neededSensitivityTimeline.start, endDate: forecastEndTime)

        // An active override replaces the target for the WHOLE forecast, as stock does. Stock
        // also raises the suspend threshold for a `veryHighInsulinNeeds` override; that is not
        // reproduced, so the threshold here is always the grant's.
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

        // The override reaches dosing through the HISTORY, and it scales the TIMELINES — basal,
        // sensitivity and carb ratio — not only the target. Moving the target alone would leave
        // every "neutral" temp reading as a high temp in override terms.
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

    /// Mirrors the body of stock `LoopDataManager.loop()`: fetch, run, round, decide whether a
    /// command is needed. Differences are noted at each site below, plus one that is not visible
    /// here — stock's `invalidFutureGlucose` gate has no equivalent. The missing-glucose and
    /// too-old-glucose gates are inside `LoopAlgorithm.run` and do apply.
    func updatePredictedGlucoseAndRecommendedDose() -> WatchLoopError? {
        dispatchPrecondition(condition: .onQueue(dataAccessQueue))

        let startDate = now()

        // TEMP BASAL ONLY, and an `automaticBolus` setting is refused OUT LOUD rather than
        // quietly reinterpreted. Stock defaults to `.automaticBolus`; on the wrist every bolus is
        // human-confirmed, so a setting asking for automatic ones stops dosing instead of being
        // silently downgraded to something the user did not choose.
        guard settings.automaticDosingStrategy == .tempBasalOnly else {
            return .configurationError("automaticDosingStrategy: automaticBolus is not supported on the watch (temps only)")
        }

        let input: StoredDataAlgorithmInput
        do {
            input = try runBlocking { try await self.fetchAlgorithmInput(at: startDate, recommendationType: .tempBasal) }
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

            // Argument for argument stock's call, and both of the interesting arguments earn
            // their place. `continuationInterval` leaves a MATCHING temp alone while it still has
            // more than eleven minutes to run, so an unchanged rate is re-commanded only as its
            // window runs down — that is where the radio saving comes from.
            // `neutralBasalRateMatchesPump` asks whether the neutral rate we just computed is the
            // one the POD is programmed with. Under an override it is not: ours is scaled and the
            // pod's schedule is not, so a "neutral" recommendation must still be sent as a temp
            // instead of being satisfied by letting the pod's own schedule run.
            //
            // A nil result means no command is needed at all, and then none is sent.
            guard let adjusted else {
                recommendedAutomaticDose = nil
                SportLog.event("dosemath", String(format: "no command needed — pod already at %.2f U/hr", basal.unitsPerHour))
                return nil
            }
            automatic.basalAdjustment = adjusted

            recommendedAutomaticDose = (recommendation: automatic, date: startDate)
            let derivation = algorithmSummary(input: input, output: output, enacting: adjusted)
            SportLog.event("dosemath", derivation)
            return nil
        }
    }

    /// Republish both display surfaces without running a cycle. Note that it is not free:
    /// `publishHUDContext` runs a `.manualBolus` pass to fill the recommended bolus, so the
    /// prediction, IOB and COB it publishes are recomputed rather than replayed.
    func updateDisplayState() {
        dataAccessQueue.async {
            self.publishHUDContext()
            self.refreshGlanceData()
        }
    }
}
