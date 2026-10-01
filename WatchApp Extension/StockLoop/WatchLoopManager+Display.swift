//
//  WatchLoopManager+Display.swift
//  WatchApp Extension
//
//  Everything the wrist DRAWS, and nothing it doses from.
//
//  Two surfaces. `GlanceData` is a lock-guarded snapshot the glance reads on main; the stock
//  `WatchContext` feeds the stock pages, the complication and the bolus flow. Both are BUILT on
//  `dataAccessQueue` and PUBLISHED for main to read. Main must never sync onto that queue to
//  fetch them: it is the same queue the loan and pump work runs on, so a repeating tile poll
//  would block the UI for the length of a bolus, a takeover or a reclaim.
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

    /// Rebuild the glance mirror off the caller's thread. Safe to call from anywhere, including
    /// main; the pending flag collapses a burst of triggers into one rebuild.
    ///
    /// The flag is cleared BEFORE the notification goes out, so it does not protect against
    /// re-entry from an observer: anything listening for `glanceMirrorDidUpdate` must rebuild its
    /// frame without calling back in here, or the two will drive each other without bound and
    /// saturate this queue during a loan.
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

    /// Blocking read, for tests and other callers that are already off main. Main reads
    /// `mirroredGlanceData` instead — see the file note.
    func glanceData() -> GlanceData {
        RuntimeStateLog.markBlockingIfMain("blocking.glanceData")
        defer { RuntimeStateLog.markBlockingIfMain("blocking.glanceData.done") }
        return dataAccessQueue.sync { self.buildGlanceData() }
    }

    /// Runs on `dataAccessQueue` — it reads the queue-owned prediction state and calls
    /// `liveInsulinOnBoard`, which asserts that.
    func buildGlanceData() -> GlanceData {
            let latest = glucoseStore.latestGlucose
            var tempRate: Double?
            // NET rate: what the pod is running minus the schedule it would otherwise run. The
            // baseline is the OVERRIDE-APPLIED schedule, because an override scales basal as well
            // as target — netting against the raw schedule renders "+0.00" while the pod runs the
            // override's multiple of the intended rate.
            if let dose = runningTempBasal() {
                let scheduled = (basalRateScheduleApplyingOverrideHistory ?? settings.basalRateSchedule)?.value(at: now()) ?? 0
                tempRate = dose.unitsPerHour - scheduled
            }
            let sources = self.lastGlucoseSourceStamps

            let liveIOB: Double? = liveInsulinOnBoard
            return GlanceData(
                glucose: latest?.quantity,
                glucoseDate: latest?.startDate,
                directG7At: sources.direct,
                phoneRelayAt: sources.phone,
                sensorActivatedAt: g7Manager?.sensorActivatedAt,
                trend: (latest as? StoredGlucoseSample)?.trend,

                eventual: predictedGlucose?.last?.quantity,
                iob: liveIOB,
                tempRate: tempRate,
                lastLoopCompleted: lastLoopCompleted,
                suspendThreshold: settings.suspendThreshold?.quantity,
                closedLoopEnabled: _closedLoopEnabled,

                // ABSOLUTE rate, unlike `tempRate` above, which is net of the schedule.
                recommendedTempRate: lastRecommendation?.basalAdjustment.unitsPerHour,
                lastLoopErrorText: lastLoopError.map { String(describing: $0) },

                predictionBreakdown: lastPredictionBreakdown,

                retrospectiveCorrectionIsIntegral: integralRetrospectiveCorrectionEnabled,
                retrospectiveDiscrepancyCount: lastAlgorithmEffects?.retrospectiveGlucoseDiscrepancies.count ?? 0,
                // A compact label for the glance: symbol, insulin-needs percentage, mid-target.
                // Only while the override is ACTIVE: one that is scheduled but has not started
                // must not be drawn as though it were already running.
                overrideLabel: {
                    guard let o = scheduleOverride, o.isActive() else { return nil }

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
                }())
    }

    /// COB as the LAST algorithm run computed it. It does not run the algorithm and it passes no
    /// effect velocities of its own; a value here is only as fresh as the cycle that produced it.
    func glanceCarbsOnBoard(_ completion: @escaping (Double?) -> Void) {
        dataAccessQueue.async { [weak self] in

            completion(self?.activeCarbs)
        }
    }

    /// Feed the stock complication from the watch's OWN reading while there is no loan, so a
    /// direct G7 reading is not invisible just because the phone is not relaying.
    ///
    /// Two fields carry the whole contract. `isWatchAuthored` keeps this context out of
    /// `phoneRelayContext`, which must only ever hold what the phone actually said — the glucose
    /// fallback reads it to decide whether the phone has anything newer. And the sync identifier
    /// is cleared so the context carries no `newGlucoseSample`: the reading is already in the
    /// store, and leaving it set would file it a second time.
    func publishOwnGlucoseContextWhenIdle() {
        guard pumpManager == nil, let latest = glucoseStore.latestGlucose else { return }
        let trend = (latest as? StoredGlucoseSample)?.trend
        let mgdl = Int(latest.quantity.doubleValue(for: .milligramsPerDeciliter).rounded())
        DispatchQueue.main.async {
            let manager = LoopDataManager.shared
            // Built from the current context and overwritten only where glucose is concerned,
            // so the complication keeps whatever else the phone last supplied.
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

    /// Publish the watch-authored `WatchContext` that the stock pages, the chart and the bolus
    /// flow read during a loan. Only while a pod is held: off-loan the phone's context is the
    /// right one, and displacing it would hide the phone's own numbers.
    func publishHUDContext() {
        guard pumpManager != nil else { return }
        let ctx = WatchContext()
        ctx.isWatchAuthored = true

        // The stock pages sit behind `loanIsLive || isOnboardingCompleted`. The phone answers the
        // second half, and during a loan it may be switched off entirely or have no CGM manager
        // of its own — so the wrist that is holding the pod asserts it here rather than blanking
        // the screens it most needs.
        ctx.isOnboardingCompleted = true

        ctx.predictedGlucose = predictedGlucose.flatMap { WatchPredictedGlucose(values: $0) }
        let latest = glucoseStore.latestGlucose
        ctx.glucose = latest?.quantity
        ctx.glucoseDate = latest?.startDate
        ctx.glucoseTrend = (latest as? StoredGlucoseSample)?.trend

        ctx.iob = liveInsulinOnBoard
        ctx.loopLastRunDate = lastLoopCompleted
        ctx.isClosedLoop = _closedLoopEnabled
        // Netted against the override-applied schedule, for the same reason as in
        // `buildGlanceData`. With no temp running the net is zero AS OF NOW, which is what the
        // stock page draws as "no adjustment".
        if let dose = runningTempBasal() {
            let scheduled = (basalRateScheduleApplyingOverrideHistory ?? settings.basalRateSchedule)?.value(at: now()) ?? 0
            ctx.lastNetTempBasalDose = dose.unitsPerHour - scheduled
            ctx.lastNetTempBasalDate = dose.startDate
        } else {
            ctx.lastNetTempBasalDose = 0
            ctx.lastNetTempBasalDate = now()
        }

        do {
            if let cob = activeCarbs {
                ctx.cob = cob

                if cob > 0.05 { SportLog.event("loop", String(format: "COB %.1f g on board", cob)) }
            }

            // Fill `recommendedBolusDose` BEFORE the context is installed. The stock bolus flow
            // reads a nil recommendation as a change TO ZERO: it ejects the user out of
            // confirmation and raises "recommendation updated", and a hold-to-confirm completing
            // in that window delivers 0 U while the flow dismisses as though it had bolused.
            //
            // Note this is a full `.manualBolus` algorithm run, and it is not pure: it
            // republishes prediction, IOB and COB. Stock's `recommendManualBolus` only returns a
            // value. See `manualBolusRecommendationOnQueue`.
            switch self.manualBolusRecommendationOnQueue() {
            case .success(let recommendation):

                SportLog.event("loan", String(format: "REC bolus %.2f U — published to the stock bolus flow", recommendation.amount))
                ctx.recommendedBolusDose = recommendation.amount
            case .failure(let error):

                SportLog.event("loan", "REC bolus UNAVAILABLE — \(error) (the flow will show 'REC: – U')")
            }
            DispatchQueue.main.async {
                guard let loopDataManager = ExtensionDelegate.sharedIfAvailable()?.loopManager else { return }
                // The unit is the user's choice and only the phone knows it, so carry forward
                // whatever the last context had rather than imposing this context's default.
                ctx.displayGlucoseUnit = loopDataManager.activeContext?.displayGlucoseUnit ?? ctx.displayGlucoseUnit
                loopDataManager.updateContext(ctx)
                NotificationCenter.default.post(name: LoopDataManager.didUpdateContextNotification, object: loopDataManager)
            }
        }
    }
}
