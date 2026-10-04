//
//  WatchLoopManager+DosingDecisions.swift
//  WatchApp Extension
//
//  Stock's dosing decisions, kept by the watch while it holds the pod and built as stock builds
//  them: "loop" each cycle (built in `loop()`), "updateRemoteRecommendation" after the display
//  run, and "watchBolus" for a wrist bolus. They go home once, when the loan closes
//  (`PodLoanWatchController.sendLoanHistoryHome`). Labelled copies of stock's phone-only
//  helpers are at the bottom.
//

import Foundation
import LoopKit
import LoopAlgorithm
import LoopCore
import WatchKit

extension WatchLoopManager {

    /// Only while the pod is held: between loans the phone is the controller and stores its own.
    func storeDosingDecision(_ dosingDecision: StoredDosingDecision) {
        dispatchPrecondition(condition: .onQueue(dataAccessQueue))
        guard let dosingDecisionStore, pumpManager != nil else { return }
        try? runBlocking { await dosingDecisionStore.storeDosingDecision(dosingDecision) }
    }

    /// A labelled copy of stock `LoopDataManager.updateRemoteRecommendation`, from the display
    /// run. Watch: the controller status is this watch's, and there is no pump status highlight
    /// (the wrist has no pump UI layer).
    func updateRemoteRecommendation(force: Bool = false) {
        dispatchPrecondition(condition: .onQueue(dataAccessQueue))

        if lastManualBolusRecommendation == nil {
            lastManualBolusRecommendation = displayState.output?.recommendation?.manual
        }

        let recommendationChanged = lastManualBolusRecommendation != displayState.output?.recommendation?.manual

        guard force || recommendationChanged else {
            return
        }

        lastManualBolusRecommendation = displayState.output?.recommendation?.manual

        if let output = displayState.output {
            var dosingDecision = StoredDosingDecision(date: now(), reason: "updateRemoteRecommendation")
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

            dosingDecision.controllerStatus = WKInterfaceDevice.current().controllerStatus

            dosingDecision.pumpManagerStatus = pumpManager?.status
            dosingDecision.cgmManagerStatus = cgmManager?.cgmManagerStatus
            dosingDecision.lastReservoirValue = StoredDosingDecision.LastReservoirValue(doseStore.lastReservoirValue)

            storeDosingDecision(dosingDecision)
        }
    }

    // MARK: - A wrist bolus

    /// The watchBolus decision stock's `WatchDataManager.createWatchContext` builds with each
    /// recommendation it sends the watch, from the display run, kept five minutes so the bolus
    /// that follows can be stored with it.
    func noteContextDosingDecision(potentialCarbEntry: NewCarbEntry?, recommendation: ManualBolusRecommendation?) {
        dispatchPrecondition(condition: .onQueue(dataAccessQueue))

        var dosingDecision = StoredDosingDecision(reason: "watchBolus")

        dosingDecision.carbsOnBoard = displayState.activeCarbs

        if let recommendation {
            dosingDecision.manualBolusRecommendation = ManualBolusRecommendationWithDate(recommendation: recommendation, date: now())
        }

        if let glucose = glucoseStore.latestGlucose, let input = displayState.input {
            let historicalGlucoseStartDate = now().addingTimeInterval(-LoopCoreConstants.dosingDecisionHistoricalGlucoseInterval)
            let start = min(historicalGlucoseStartDate, glucose.startDate)
            let samples = input.glucoseHistory.filterDateRange(start, nil)
            dosingDecision.historicalGlucose = samples.filter { $0.startDate >= historicalGlucoseStartDate }.map { HistoricalGlucoseValue(startDate: $0.startDate, quantity: $0.quantity) }
        }

        dosingDecision.insulinOnBoard = displayState.activeInsulin
        dosingDecision.predictedGlucose = displayState.output?.predictedGlucose

        let scheduleOverride = self.scheduleOverride.flatMap { $0.hasFinished() ? nil : $0 }
        dosingDecision.scheduleOverride = scheduleOverride

        if let scheduleOverride {
            // Stock `TemporaryPresetsManager.effectiveCorrectionRangeSchedule(presumingMealEntry:)`.
            let presumingMealEntry = potentialCarbEntry != nil
            dosingDecision.glucoseTargetRangeSchedule = presumingMealEntry && scheduleOverride.context == .preMeal
                ? settings.glucoseTargetRangeSchedule
                : settings.glucoseTargetRangeSchedule?.applyingOverride(scheduleOverride)
        } else {
            dosingDecision.glucoseTargetRangeSchedule = settings.glucoseTargetRangeSchedule
        }

        // Remove any expired context dosing decisions and add new
        let now = self.now()
        contextDosingDecisions = contextDosingDecisions.filter { now.timeIntervalSince($0.date) < .minutes(5) }
        contextDosingDecisions.append((date: now, potentialCarbEntry: potentialCarbEntry, decision: dosingDecision))
    }

    /// Stock `WatchDataManager.addCarbEntryAndBolusFromWatchMessage` then
    /// `LoopDataManager.storeManualBolusDosingDecision`: the decision built with the
    /// recommendation shown for this carb entry (a bare one if the user saved without waiting for
    /// one), with the carb entry as stored and the amount requested. Returns its id for the pod
    /// command. Watch: a context decision is used once, found by the entry as entered.
    @discardableResult
    func storeWatchBolusDosingDecision(carbEntry: NewCarbEntry?, storedCarbEntry: StoredCarbEntry?, requested units: Double) -> UUID {
        dispatchPrecondition(condition: .onQueue(dataAccessQueue))

        var dosingDecision: StoredDosingDecision
        let now = self.now()
        if let index = contextDosingDecisions.lastIndex(where: { $0.potentialCarbEntry == carbEntry && now.timeIntervalSince($0.date) < .minutes(5) }) {
            dosingDecision = contextDosingDecisions.remove(at: index).decision
        } else {
            dosingDecision = StoredDosingDecision(reason: "watchBolus")  // The user saved without waiting for recommendation (no bolus)
        }

        dosingDecision.carbEntry = storedCarbEntry
        dosingDecision.manualBolusRequested = units

        dosingDecision.date = now
        dosingDecision.settings = StoredDosingDecision.Settings(settingsProvider.settings)
        dosingDecision.controllerStatus = WKInterfaceDevice.current().controllerStatus
        dosingDecision.pumpManagerStatus = pumpManager?.status
        dosingDecision.cgmManagerStatus = cgmManager?.cgmManagerStatus
        dosingDecision.lastReservoirValue = StoredDosingDecision.LastReservoirValue(doseStore.lastReservoirValue)

        storeDosingDecision(dosingDecision)
        return dosingDecision.id
    }

    /// Carbs saved with no bolus: stock stores this as a watchBolus decision too.
    func storeWatchCarbsOnlyDosingDecision(carbEntry: NewCarbEntry, storedCarbEntry: StoredCarbEntry) {
        dataAccessQueue.async {
            self.storeWatchBolusDosingDecision(carbEntry: carbEntry, storedCarbEntry: storedCarbEntry, requested: 0)
        }
    }
}

// MARK: - Labelled copies of stock's phone-only helpers

/// A labelled copy of stock's extension (`Loop/Managers/LoopDataManager.swift`, private there).
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

/// Labelled copies of stock's extensions (`Loop/Managers/LoopDataManager.swift`).
extension StoredDosingDecision.Settings {
    init?(_ settings: StoredSettings?) {
        guard let settings = settings else {
            return nil
        }
        self.init(syncIdentifier: settings.syncIdentifier)
    }
}

extension StoredDosingDecision.LastReservoirValue {
    init?(_ reservoirValue: ReservoirValue?) {
        guard let reservoirValue = reservoirValue else {
            return nil
        }
        self.init(startDate: reservoirValue.startDate, unitVolume: reservoirValue.unitVolume)
    }
}

/// A labelled copy of stock's `UIDevice.controllerStatus` (`Loop/Extensions/UIDevice+Loop.swift`).
extension WKInterfaceDevice {
    var controllerStatus: StoredDosingDecision.ControllerStatus {
        return StoredDosingDecision.ControllerStatus(batteryState: isBatteryMonitoringEnabled ? batteryState.batteryState : nil,
                                                     batteryLevel: isBatteryMonitoringEnabled && batteryLevel != -1.0 ? batteryLevel : nil)   // -1.0 indicates unknown
    }
}

extension WKInterfaceDeviceBatteryState {
    var batteryState: StoredDosingDecision.ControllerStatus.BatteryState {
        switch self {
        case .unknown:
            return .unknown
        case .unplugged:
            return .unplugged
        case .charging:
            return .charging
        case .full:
            return .full
        @unknown default:
            return .unknown
        }
    }
}
