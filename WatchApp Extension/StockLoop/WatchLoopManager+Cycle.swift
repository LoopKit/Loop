//
//  WatchLoopManager+Cycle.swift
//  WatchApp Extension
//
//  The shared loop cycle (`LoopCycle`, as the phone runs it) on the wrist, one operation at a time
//  on the manager's lane, and the watch's part as its host and pump. One verdict line per cycle.
//

import Foundation
import HealthKit
import LoopKit
import LoopAlgorithm
import LoopCore
import WatchConnectivity
import WatchKit
import os.log

extension WatchLoopManager {

    /// Stock `DeviceDataManager.checkPumpDataAndLoop`, but returns with no pump (between loans, or
    /// before a takeover or resume finishes, there is nothing to decide).
    func checkPumpDataAndLoop() {
        guard let pumpManager = pumpManager else {
            if !loggedIdleNoPump {
                loggedIdleNoPump = true
                SportLog.event("loop", "no pod on the watch; cycles paused until the next grant")
            }
            return
        }
        loggedIdleNoPump = false

        // The only entry point that refreshes the pod before computing; its answer can come on the
        // driver's own queue.
        pumpManager.ensureCurrentPumpData { _ in
            DispatchQueue.main.async { self.loop() }
        }
    }

    /// The cycle both apps run (`LoopCycle`), on the lane, then the watch's own steps: the verdict line, the dead-man watchdog (refreshed on
    /// any error-free cycle with a pod held, open or closed), the phone's hold renewal and the display
    /// run. The cycle doses only with the watch's loop closed, and its decision is kept only while the
    /// pod is held.
    func loop() {
        onLane {
            self.log.default("Loop running")
            self.lastLoopError = nil
            self.lastRecommendation = nil
            let loopBaseTime = self.now()

            let outcome = await self.cycle.run(at: loopBaseTime)

            if let input = outcome.input, let output = outcome.output {
                self.loopRunState = AlgorithmDisplayState(input: input, output: output)
            }
            // The recommendation as it was to be enacted, and what it sends (nil: nothing of that kind).
            let decided = outcome.recommendation
            let basalAdjustment = outcome.basalAdjustment
            self.lastRecommendation = decided
            // A cycle that decided a dose failed, if at all, at the checks before sending or the send.
            let computeError = decided == nil ? outcome.error : nil
            let enactError = decided == nil ? nil : outcome.error

            if let decided, let input = outcome.input, let output = outcome.output {
                let bolus = decided.bolusUnits.flatMap { $0 > 0 ? $0 : nil }
                if basalAdjustment == nil, bolus == nil {
                    SportLog.event("dosemath", String(format: "no command needed: pod already at %.2f U/hr", decided.basalAdjustment.unitsPerHour))
                } else {
                    SportLog.event("dosemath", self.algorithmSummary(input: input, output: output)
                        + (basalAdjustment.map { String(format: ": temp %.2f U/hr for %.0f min", $0.unitsPerHour, $0.duration / 60) } ?? ": temp unchanged")
                        + (bolus.map { String(format: ", automatic bolus %.2f U", $0) } ?? ""))
                }
            }

            if let computeError {
                SportLog.event("loop", "not dosing: \(computeError.localizedDescription)")
            }

            let error = computeError ?? enactError
            self.lastLoopError = error

            // Open loop first: it still computes with no error, so later arms would report an unsent command.
            let enactVerdict: String
            if !self.appliedClosedLoopEnabled { enactVerdict = "no dose: loop open" }
            else if computeError != nil { enactVerdict = "no dose: not computed" }
            else if let enactError {
                // The pod's or the loop's refusal before sending, versus a send that failed.
                switch enactError {
                case .pumpInoperable, .pumpSuspended, .manualTempBasalRunning, .configurationError, .connectionError:
                    enactVerdict = "no dose: \(enactError.issueId)"
                default:
                    enactVerdict = "dose failed: \(enactError)"
                }
            }
            else if decided == nil { enactVerdict = "no dose decided" }
            else if basalAdjustment == nil && (decided?.bolusUnits ?? 0) <= 0 { enactVerdict = "dose unchanged" }
            else { enactVerdict = "dose sent" }

            let watchdogRefreshed = (error == nil && self.pumpManager != nil)
            if watchdogRefreshed { LoopStallWatchdog.refresh(); self.onCycleLanded?() }
            let sinceCompleted = self.lastLoopCompleted.map { Int(self.now().timeIntervalSince($0)) }

            // Compute and enact judged by the stage that failed.
            let computeSucceeded = computeError == nil

            SportLog.event("loop", String(format: "cycle %@, %@, watchdog %@, last completed %@",
                                          computeSucceeded ? "computed" : "failed",
                                          enactVerdict,
                                          watchdogRefreshed ? "refreshed" : "held",
                                          sinceCompleted.map { "\($0) s ago" } ?? "never"))

            if let error {
                self.log.error("Loop ended with error: %{public}@", String(describing: error))
            } else {
                // As stock: only after a successful enact with the loop closed; an open-loop
                // cycle never moves it.
                if self.appliedClosedLoopEnabled {
                    self.lastLoopCompleted = self.now()
                }
                self.log.default("Loop ended (duration %.1fs)", self.now().timeIntervalSince(loopBaseTime))
                // Success only, so the debug screen may describe an older cycle.
                self.updatePredictionBreakdown()
            }

            // Both arms, as stock's `loop()` ends: the display run, its forced
            // "updateRemoteRecommendation" decision, then the stock pages' context.
            await self.updateDisplayStateOnLane(forceStoreRemoteRecommendation: true)

            // Stock's predicted-low alert reads `LoopDataManager.predictedGlucose`, the display
            // run's forecast, on both arms.
            self.evaluatePredictedLowAlert(self.displayState.output?.predictedGlucose)
        }
    }

    /// The cycle's fetch, as stock's `LoopDataManager.fetchData`, with the watch's sources (`LoopCycleHost`).
    func fetchData(
        for baseTime: Date? = nil,
        presumePresetEndingNow: Bool = false,
        ensureDosingCoverageStart: Date? = nil,
        projectOngoingDoses: Bool = false
    ) async throws -> StoredDataAlgorithmInput {
        try await cycle.fetchData(for: baseTime, presumePresetEndingNow: presumePresetEndingNow,
                                  ensureDosingCoverageStart: ensureDosingCoverageStart, projectOngoingDoses: projectOngoingDoses)
    }

    /// As stock's `LoopDataManager`: automatic bolus, unless strategy selection is enabled.
    var currentDosingStrategy: AutomaticDosingStrategy {
        FeatureFlags.dosingStrategySelectionEnabled ? settingsProvider.settings.automaticDosingStrategy : .automaticBolus
    }

    /// Stock `LoopDataManager.algorithmExperiments(for:guardAndRunway:)`, from the grant's experiments.
    func algorithmExperiments(for dosingStrategy: AutomaticDosingStrategy, guardAndRunway: GuardAndRunwayOutput? = nil) -> [AlgorithmExperiment] {
        AlgorithmExperiment.records(enabled: enabledAlgorithmExperiments, dosingStrategy: dosingStrategy,
                                    volatilityBaseline: guardAndRunwayEnabled ? volatilityBaseline : nil, guardAndRunway: guardAndRunway)
    }

    /// The grant's experiment flags as LoopAlgorithm's experiments, with the phone's volatility baseline.
    var enabledAlgorithmExperiments: Set<ExperimentOption> {
        var experiments: Set<ExperimentOption> = []
        if integralRetrospectiveCorrectionEnabled {
            experiments.insert(.integralRetrospectiveCorrection)
        }
        if glucoseBasedApplicationFactorEnabled {
            experiments.insert(.glucoseBasedApplicationFactor)
        }
        if guardAndRunwayEnabled {
            experiments.insert(.guardAndRunway)
        }
        return experiments
    }

    /// Stock `LoopDataManager.updateDisplayState`: the display run, fed with doses back a day,
    /// ongoing doses projected (no trim) and `.manualBolus`, stored as `displayState`. Then the
    /// stock pages' context and the glance are republished from it. As in stock, no recency
    /// check gates this run.
    func updateDisplayState(_ completion: ((AlgorithmDisplayState) -> Void)? = nil) {
        onLane {
            await self.updateDisplayStateOnLane()
            completion?(self.displayState)
        }
    }

    /// Stock's other triggers for the display run: a change in the carb, glucose or dose store, an
    /// override set or cleared, and the loop mode. No debounce, as stock. Only while a pod is held:
    /// between loans the display run is not refreshed, as before. The run writes to none of the
    /// stores observed (only to the dosing decision store), so it cannot retrigger itself.
    func updateDisplayStateForChange() {
        onLane {
            guard self.pumpManager != nil else { return }
            await self.updateDisplayStateOnLane()
        }
    }

    /// Lane work.
    func updateDisplayStateOnLane(forceStoreRemoteRecommendation: Bool = false) async {
        displayState = await cycle.displayState()

        await publishHUDContext()
        refreshGlanceData()

        await updateRemoteRecommendation(force: forceStoreRemoteRecommendation)
    }
}

/// The watch hosts the loop cycle while it holds the pod: the grant's settings, overrides and
/// experiments, and the watch's own loop mode.
extension WatchLoopManager: LoopCycleHost {
    var deliveryDelegate: DeliveryDelegate? { self }

    var activeOverride: TemporaryScheduleOverride? {
        scheduleOverride.flatMap { $0.isActive(at: now()) ? $0 : nil }
    }

    /// The phone's baseline, from the grant.
    func currentVolatilityBaseline(at date: Date) async -> Double? {
        guardAndRunwayEnabled ? volatilityBaseline : nil
    }

    var carbAbsorptionModel: CarbAbsorptionModel { .piecewiseLinear }

    /// Between loans the phone is the controller and stores its own decisions.
    var holdsPump: Bool {
        pumpManager != nil
    }

    /// The watch's own loop mode, not the phone's `dosingEnabled`.
    var isClosedLoop: Bool {
        appliedClosedLoopEnabled
    }

    var controllerStatus: StoredDosingDecision.ControllerStatus {
        WKInterfaceDevice.current().controllerStatus
    }
}
