//
//  WatchLoopManager+Display.swift
//  WatchApp Extension
//
//  What the wrist draws, never what it doses from: `GlanceData` for the glance and a
//  WatchContext for the stock pages. Built on `dataAccessQueue`, published for main.
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

    /// Rebuild the glance mirror; a burst collapses into one. Observers must not call back in.
    func refreshGlanceData() {
        glanceMirrorLock.lock()
        if _glanceRefreshPending { glanceMirrorLock.unlock(); return }
        _glanceRefreshPending = true
        glanceMirrorLock.unlock()

        dataAccessQueue.async { [weak self] in
            guard let self = self else { return }
            let data = self.buildGlanceData()
            self.glanceMirrorLock.lock()
            self._glanceMirror = data
            self._glanceRefreshPending = false
            self.glanceMirrorLock.unlock()

            NotificationCenter.default.post(name: Self.glanceMirrorDidUpdate, object: nil)
        }
    }

    /// Stock's net basal, against the override-applied schedule as stock's watch context uses.
    func netBasal() -> NetBasal? {
        guard let basalDeliveryState = pumpManager?.status.basalDeliveryState,
              let basalSchedule = basalRateScheduleApplyingOverrideHistory else { return nil }
        return basalDeliveryState.getNetBasal(basalSchedule: basalSchedule, maximumBasalRatePerHour: settings.maximumBasalRatePerHour)
    }

    /// On `dataAccessQueue`.
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
                sensorActivatedAt: (cgmManager as? G7CGMManager)?.sensorActivatedAt,
                trend: (latest as? StoredGlucoseSample)?.trend,

                eventual: displayState.output?.predictedGlucose.last?.quantity,
                iob: displayState.activeInsulin?.value,
                dosingEventual: loopOutput?.predictedGlucose.last?.quantity,
                dosingIOB: loopOutput?.activeInsulin,
                dosingCOB: loopOutput?.activeCarbs,
                tempRate: tempRate,
                lastLoopCompleted: lastLoopCompleted,
                suspendThreshold: settings.suspendThreshold?.quantity,
                closedLoopEnabled: _closedLoopEnabled,

                // ABSOLUTE rate, unlike `tempRate` above, which is net of the schedule.
                recommendedTempRate: lastRecommendation?.basalAdjustment.unitsPerHour,
                lastLoopErrorText: lastLoopError.map { String(describing: $0) },

                predictionBreakdown: lastPredictionBreakdown,

                retrospectiveCorrectionIsIntegral: integralRetrospectiveCorrectionEnabled,
                retrospectiveDiscrepancyCount: loopOutput?.effects.retrospectiveGlucoseDiscrepancies.count ?? 0,
                // Only while the override is active.
                overrideLabel: Self.overrideLabel(for: scheduleOverride))
    }

    /// The glance's override line ("🏓 70% 128"), only while the override is active. Also used for the
    /// Sport complications when the phone holds the pod.
    static func overrideLabel(for override: TemporaryScheduleOverride?) -> String? {
        guard let o = override, o.isActive() else { return nil }

        var parts: [String] = []
        if case .preset(let p) = o.context,
           let symbol = p.symbol?.textualRepresentation, !symbol.isEmpty {
            parts.append(symbol)
        } else {
            parts.append("⏱")
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

    /// COB from the display run, as stock's `LoopDataManager.activeCarbs`.
    func glanceCarbsOnBoard(_ completion: @escaping (Double?) -> Void) {
        dataAccessQueue.async { [weak self] in
            completion(self?.displayState.activeCarbs?.value)
        }
    }

    /// Feeds the complication from the watch's own reading off-loan. `isWatchAuthored` keeps it out
    /// of the phone relay; the sync identifier is cleared so the sample is not stored twice.
    func publishOwnGlucoseContextWhenIdle() {
        guard pumpManager == nil, let latest = glucoseStore.latestGlucose else { return }
        let trend = (latest as? StoredGlucoseSample)?.trend
        let mgdl = Int(latest.quantity.doubleValue(for: .milligramsPerDeciliter).rounded())
        DispatchQueue.main.async {
            let manager = LoopDataManager.shared
            // Keep the phone's other fields.
            let ctx = manager.activeContext.flatMap { WatchContext(rawValue: $0.rawValue) } ?? WatchContext()
            ctx.isWatchAuthored = true
            ctx.glucoseSyncIdentifier = nil
            ctx.glucose = latest.quantity
            ctx.glucoseDate = latest.startDate
            ctx.glucoseTrend = trend
            manager.updateContext(ctx)
            NotificationCenter.default.post(name: LoopDataManager.didUpdateContextNotification, object: manager)
            SportLog.event("glucose", "complication fed from the watch's own reading (idle, no loan) — \(mgdl) mg/dL")
        }
    }

    /// The watch-authored context for the stock pages, only while a pod is held. As stock's
    /// `WatchDataManager.createWatchContext`: IOB, COB and the prediction come from the display
    /// run (`displayState`), and the recommended bolus from its own manual-bolus run, which
    /// changes nothing displayed.
    func publishHUDContext() {
        guard pumpManager != nil else { return }
        let ctx = WatchContext()
        ctx.isWatchAuthored = true

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
        ctx.isClosedLoop = _closedLoopEnabled
        // As stock's `WatchDataManager.createWatchContext`.
        if let netBasal = netBasal() {
            ctx.lastNetTempBasalDose = netBasal.rate
        }

        do {
            if let cob = displayState.activeCarbs?.value {
                ctx.cob = cob

                if cob > 0.05 { SportLog.event("loop", String(format: "COB %.1f g on board", cob)) }
            }

            // Fill the recommendation before installing the context: the stock flow reads nil as zero.
            let recommendationResult = self.manualBolusRecommendationOnQueue()
            // As stock's context for the watch, the watchBolus decision built with it is kept.
            self.noteContextDosingDecision(potentialCarbEntry: nil, recommendation: try? recommendationResult.get())
            switch recommendationResult {
            case .success(let recommendation):

                SportLog.event("loan", String(format: "REC bolus %.2f U — published to the stock bolus flow", recommendation.amount))
                ctx.recommendedBolusDose = recommendation.amount
            case .failure(let error):

                SportLog.event("loan", "REC bolus UNAVAILABLE — \(error) (the flow will show 'REC: – U')")
            }
            DispatchQueue.main.async {
                guard let loopDataManager = ExtensionDelegate.sharedIfAvailable()?.loopManager else { return }
                // The phone's display unit.
                ctx.displayGlucoseUnit = loopDataManager.activeContext?.displayGlucoseUnit ?? ctx.displayGlucoseUnit
                loopDataManager.updateContext(ctx)
                NotificationCenter.default.post(name: LoopDataManager.didUpdateContextNotification, object: loopDataManager)
            }
        }
    }
}
