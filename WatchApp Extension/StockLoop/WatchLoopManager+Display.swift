//
//  WatchLoopManager+Display.swift
//  WatchApp Extension
//
//  What the wrist draws, never what it doses from: `GlanceData` for the glance and its state for
//  the stock pages (`LoopDataManager.wristState`). Built on the manager's lane, after the cycle work
//  before it.
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

    /// Rebuild the glance snapshot; a burst collapses into one. Observers must not call back in.
    func refreshGlanceData() {
        if glanceRefreshPending { return }
        glanceRefreshPending = true

        onLane { [weak self] in
            guard let self else { return }
            self.glanceData = self.buildGlanceData()
            self.glanceRefreshPending = false

            NotificationCenter.default.post(name: Self.glanceDataDidUpdate, object: nil)
        }
    }

    /// Stock's net basal, against the override-applied schedule as stock's watch context uses.
    func netBasal() -> NetBasal? {
        guard let basalDeliveryState = pumpManager?.status.basalDeliveryState,
              let basalSchedule = basalRateScheduleApplyingOverrideHistory else { return nil }
        return basalDeliveryState.getNetBasal(basalSchedule: basalSchedule, maximumBasalRatePerHour: settings.maximumBasalRatePerHour)
    }

    /// Lane work.
    func buildGlanceData() -> GlanceData {
            let latest = glucoseStore.latestGlucose
            // Stock's net rate; none while the schedule runs, so the glance shows no temp.
            var tempRate: Double?
            if case .active? = pumpManager?.status.basalDeliveryState {} else { tempRate = netBasal()?.rate }
            let sources = self.lastGlucoseSourceStamps

            // The glance reads the display run, as stock's screens read `displayState`; the
            // diagnostics page reads the automatic loop's run.
            let loopOutput = loopRunState.output
            return GlanceData(
                glucose: latest?.quantity,
                glucoseDate: latest?.startDate,
                directG7At: sources.direct,
                phoneRelayAt: sources.phone,
                trend: (latest as? StoredGlucoseSample)?.trend,

                eventual: displayState.output?.predictedGlucose.last?.quantity,
                iob: displayState.activeInsulin?.value,
                dosingEventual: loopOutput?.predictedGlucose.last?.quantity,
                dosingIOB: loopOutput?.activeInsulin,
                dosingCOB: loopOutput?.activeCarbs,
                tempRate: tempRate,
                lastLoopCompleted: lastLoopCompleted,
                suspendThreshold: settings.suspendThreshold?.quantity,
                closedLoopEnabled: appliedClosedLoopEnabled,

                // ABSOLUTE rate, unlike `tempRate` above, which is net of the schedule.
                recommendedTempRate: lastRecommendation?.basalAdjustment.unitsPerHour,
                lastLoopErrorText: lastLoopError.map { String(describing: $0) },

                predictionBreakdown: lastPredictionBreakdown,

                retrospectiveCorrectionIsIntegral: integralRetrospectiveCorrectionEnabled,
                retrospectiveDiscrepancyCount: loopOutput?.effects.retrospectiveGlucoseDiscrepancies.count ?? 0,
                // Only while the override is active.
                overrideLabel: Self.overrideLabel(for: scheduleOverride),
                overrideSymbol: Self.overrideSymbol(for: scheduleOverride))
    }

    /// The glance's override line ("🏓 70% 128"), only while the override is active. A preset's emoji
    /// leads it; a preset drawn with an Apple symbol has it in `overrideSymbol` instead.
    nonisolated static func overrideLabel(for override: TemporaryScheduleOverride?) -> String? {
        guard let o = override, o.isActive() else { return nil }

        var parts: [String] = []
        if case .preset(let p) = o.context,
           let symbol = p.symbol?.textualRepresentation, !symbol.isEmpty {
            parts.append(symbol)
        }
        if let scale = o.settings.insulinNeedsScaleFactor {
            parts.append("\(Int((scale * 100).rounded()))%")
        }
        if let range = o.settings.targetRange {
            let mid = (range.lowerBound.doubleValue(for: .milligramsPerDeciliter)
                       + range.upperBound.doubleValue(for: .milligramsPerDeciliter)) / 2
            parts.append(String(format: "%.0f", mid))
        }
        return parts.joined(separator: " ")
    }

    /// The Apple symbol an active preset is drawn with ("figure.run"), which a string can't carry.
    nonisolated static func overrideSymbol(for override: TemporaryScheduleOverride?) -> String? {
        guard let o = override, o.isActive(), case .preset(let p) = o.context,
              let symbol = p.symbol, symbol.symbolType == .systemImage, !symbol.value.isEmpty else { return nil }
        return symbol.value
    }

    /// COB from the display run, as stock's `LoopDataManager.activeCarbs`.
    func glanceCarbsOnBoard(_ completion: @escaping (Double?) -> Void) {
        onLane { [weak self] in
            completion(self?.displayState.activeCarbs?.value)
        }
    }

    /// The state of the watch holding the pod, for the stock pages (`LoopDataManager.wristState`), only
    /// while a pod is held. As stock's `WatchDataManager.createWatchContext`: IOB, COB and the
    /// prediction come from the display run (`displayState`), and the recommended bolus from its own
    /// manual-bolus run, which changes nothing displayed. The screens lay it over the phone's context.
    func publishHUDContext() async {
        guard pumpManager != nil else { return }
        let ctx = WatchContext()

        // The wrist holding the pod asserts onboarding; the phone may be off.
        ctx.isOnboardingCompleted = true

        let (_, algoOutput) = displayState.asTuple
        if let predictedGlucose = algoOutput?.predictedGlucose {
            // Drop the first element in predictedGlucose because it is the current glucose
            let filteredPredictedGlucose = predictedGlucose.dropFirst()
            if filteredPredictedGlucose.count > 0 {
                ctx.predictedGlucose = WatchPredictedGlucose(values: Array(filteredPredictedGlucose))
            }
        }
        let latest = glucoseStore.latestGlucose
        ctx.glucose = latest?.quantity
        ctx.glucoseDate = latest?.startDate
        ctx.glucoseTrend = (latest as? StoredGlucoseSample)?.trend

        ctx.iob = displayState.activeInsulin?.value
        ctx.loopLastRunDate = lastLoopCompleted
        ctx.isClosedLoop = appliedClosedLoopEnabled
        // As stock's `WatchDataManager.createWatchContext`.
        if let netBasal = netBasal() {
            ctx.lastNetTempBasalDose = netBasal.rate
        }

        if let cob = displayState.activeCarbs?.value {
            ctx.cob = cob
        }

        // Fill the recommendation before installing the context: the stock flow reads nil as zero.
        let recommendationResult = await self.manualBolusRecommendation()
        // As stock's context for the watch, the watchBolus decision built with it is kept.
        self.noteContextDosingDecision(potentialCarbEntry: nil, recommendation: (try? recommendationResult.get()) ?? nil)
        switch recommendationResult {
        case .success(let recommendation):
            ctx.recommendedBolusDose = recommendation?.amount
        case .failure(let error):
            SportLog.eventOnChange("loan", key: "hud.rec", "bolus recommendation unavailable: \(error)")
        }
        // A loan that ended since this was built has cleared the state already.
        guard pumpManager != nil else { return }
        ExtensionDelegate.sharedIfAvailable()?.loopManager.wristState = ctx
    }
}
