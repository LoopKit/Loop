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

    /// The cycle's remote recommendation decision (stock `LoopDataManager.updateRemoteRecommendation`),
    /// from the display run. Lane work.
    func updateRemoteRecommendation(force: Bool = false) async {
        await cycle.storeRemoteRecommendation(displayState: displayState, force: force)
    }

    // MARK: - A wrist bolus

    /// The watchBolus decision the phone's `WatchDataManager.createWatchContext` builds with each
    /// recommendation it sends the watch (`BolusDosingDecision.watchBolus`, from the display run),
    /// kept five minutes so the bolus that follows can be stored with it. Lane work.
    func noteContextDosingDecision(potentialCarbEntry: NewCarbEntry?, recommendation: ManualBolusRecommendation?) {
        let now = self.now()
        let scheduleOverride = self.scheduleOverride.flatMap { $0.hasFinished() ? nil : $0 }
        // Stock `TemporaryPresetsManager.effectiveCorrectionRangeSchedule(presumingMealEntry:)`.
        let glucoseTargetRangeSchedule: GlucoseRangeSchedule?
        if let scheduleOverride, !(potentialCarbEntry != nil && scheduleOverride.context == .preMeal) {
            glucoseTargetRangeSchedule = settings.glucoseTargetRangeSchedule?.applyingOverride(scheduleOverride)
        } else {
            glucoseTargetRangeSchedule = settings.glucoseTargetRangeSchedule
        }
        let dosingDecision = BolusDosingDecision.watchBolus(displayState: displayState, recommendation: recommendation,
                                                            scheduleOverride: scheduleOverride,
                                                            glucoseTargetRangeSchedule: glucoseTargetRangeSchedule, now: now)

        // Remove any expired context dosing decisions and add new
        contextDosingDecisions = contextDosingDecisions.filter { now.timeIntervalSince($0.date) < .minutes(5) }
        contextDosingDecisions.append((date: now, potentialCarbEntry: potentialCarbEntry, decision: dosingDecision))
    }

    /// Stock `WatchDataManager.addCarbEntryAndBolusFromWatchMessage`: the decision built with the
    /// recommendation shown for this carb entry (a bare one if the user saved without waiting for
    /// one), with the carb entry as stored and the amount requested, stamped by the cycle as the
    /// phone stamps a manual bolus's, and stored before the command. Only while the pod is held:
    /// between loans the phone stores its own. Returns its id for the pod command. Watch: a context decision is used once, found by the
    /// entry as entered. Lane work.
    @discardableResult
    func storeWatchBolusDosingDecision(carbEntry: NewCarbEntry?, storedCarbEntry: StoredCarbEntry?, requested units: Double) async -> UUID {
        var dosingDecision: BolusDosingDecision
        let now = self.now()
        if let index = contextDosingDecisions.lastIndex(where: { $0.potentialCarbEntry == carbEntry && now.timeIntervalSince($0.date) < .minutes(5) }) {
            dosingDecision = contextDosingDecisions.remove(at: index).decision
        } else {
            dosingDecision = BolusDosingDecision(for: .watchBolus)  // The user saved without waiting for recommendation (no bolus)
        }

        dosingDecision.carbEntry = storedCarbEntry
        dosingDecision.manualBolusRequested = units

        if pumpManager != nil, let dosingDecisionStore,
           let stored = cycle.manualBolusDosingDecision(dosingDecision, withDate: now) {
            await dosingDecisionStore.storeDosingDecision(stored)
        }
        return dosingDecision.id
    }

    /// Carbs saved with no bolus: stock stores this as a watchBolus decision too.
    func storeWatchCarbsOnlyDosingDecision(carbEntry: NewCarbEntry, storedCarbEntry: StoredCarbEntry) {
        onLane {
            await self.storeWatchBolusDosingDecision(carbEntry: carbEntry, storedCarbEntry: storedCarbEntry, requested: 0)
        }
    }
}

// MARK: - Labelled copies of stock's phone-only helpers

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
