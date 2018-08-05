//
//  WatchDataManager.swift
//  Loop
//
//  Created by Nathan Racklyeft on 5/29/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import HealthKit
import UIKit
import WatchConnectivity
import LoopKit

final class WatchDataManager: NSObject, WCSessionDelegate {

    unowned let deviceManager: DeviceDataManager

    init(deviceManager: DeviceDataManager) {
        self.deviceManager = deviceManager

        super.init()

        NotificationCenter.default.addObserver(self, selector: #selector(updateWatch(_:)), name: .LoopDataUpdated, object: deviceManager.loopManager)

        watchSession?.delegate = self
        watchSession?.activate()
    }

    private var watchSession: WCSession? = {
        if WCSession.isSupported() {
            return WCSession.default
        } else {
            return nil
        }
    }()

    private var lastActiveOverrideContext: GlucoseRangeSchedule.Override.Context?
    private var lastConfiguredOverrideContexts: [GlucoseRangeSchedule.Override.Context] = []

    @objc private func updateWatch(_ notification: Notification) {
        guard
            let rawUpdateContext = notification.userInfo?[LoopDataManager.LoopUpdateContextKey] as? LoopDataManager.LoopUpdateContext.RawValue,
            let updateContext = LoopDataManager.LoopUpdateContext(rawValue: rawUpdateContext),
            let session = watchSession
        else {
            return
        }

        switch updateContext {
        case .glucose:
            break
        case .tempBasal:
            break
        case .preferences:
            let activeOverrideContext = deviceManager.loopManager.settings.glucoseTargetRangeSchedule?.activeOverrideContext
            let configuredOverrideContexts = deviceManager.loopManager.settings.glucoseTargetRangeSchedule?.configuredOverrideContexts ?? []
            defer {
                lastActiveOverrideContext = activeOverrideContext
                lastConfiguredOverrideContexts = configuredOverrideContexts
            }

            guard activeOverrideContext != lastActiveOverrideContext || configuredOverrideContexts != lastConfiguredOverrideContexts else {
                return
            }
        default:
            return
        }

        switch session.activationState {
        case .notActivated, .inactive:
            session.activate()
        case .activated:
            createWatchContext { (context) in
                if let context = context {
                    self.sendWatchContext(context)
                }
            }
        }
    }

    private var lastComplicationContext: WatchContext?

    private let minTrendDrift: Double = 20
    private lazy var minTrendUnit = HKUnit.milligramsPerDeciliter

    private func sendWatchContext(_ context: WatchContext) {
        if let session = watchSession, session.isPaired && session.isWatchAppInstalled {
            let complicationShouldUpdate: Bool

            if let lastContext = lastComplicationContext,
                let lastGlucose = lastContext.glucose, let lastGlucoseDate = lastContext.glucoseDate,
                let newGlucose = context.glucose, let newGlucoseDate = context.glucoseDate
            {
                let enoughTimePassed = newGlucoseDate.timeIntervalSince(lastGlucoseDate).minutes >= 30
                let enoughTrendDrift = abs(newGlucose.doubleValue(for: minTrendUnit) - lastGlucose.doubleValue(for: minTrendUnit)) >= minTrendDrift

                complicationShouldUpdate = enoughTimePassed || enoughTrendDrift
            } else {
                complicationShouldUpdate = true
            }

            if session.isComplicationEnabled && complicationShouldUpdate {
                session.transferCurrentComplicationUserInfo(context.rawValue)
                lastComplicationContext = context
            } else {
                do {
                    try session.updateApplicationContext(context.rawValue)
                } catch let error {
                    deviceManager.logger.addError(error, fromSource: "WCSession")
                }
            }
        }
    }

    private func createWatchContext(_ completion: @escaping (_ context: WatchContext?) -> Void) {
        let loopManager = deviceManager.loopManager!

        let glucose = loopManager.glucoseStore.latestGlucose
        let reservoir = loopManager.doseStore.lastReservoirValue

        loopManager.getLoopState { (manager, state) in
            let updateGroup = DispatchGroup()

            let startDate = Date().addingTimeInterval(TimeInterval(minutes: -180))
            let endDate = Date().addingTimeInterval(TimeInterval(minutes: 180))

            let context = WatchContext(glucose: glucose, eventualGlucose: state.predictedGlucose?.last, glucoseUnit: manager.glucoseStore.preferredUnit)
            context.reservoir = reservoir?.unitVolume
            context.loopLastRunDate = manager.lastLoopCompleted
            context.recommendedBolusDose = state.recommendedBolus?.recommendation.amount
            context.maxBolus = manager.settings.maximumBolus
            context.COB = state.carbsOnBoard?.quantity.doubleValue(for: HKUnit.gram())
            context.glucoseTrendRawValue = self.deviceManager.sensorInfo?.trendType?.rawValue

            context.cgm = self.deviceManager.cgm

            if let glucoseTargetRangeSchedule = manager.settings.glucoseTargetRangeSchedule {
                if let override = glucoseTargetRangeSchedule.override {
                    context.glucoseRangeScheduleOverride = GlucoseRangeScheduleOverrideUserInfo(
                        context: override.context.correspondingUserInfoContext,
                        startDate: override.start,
                        endDate: override.end
                    )

                    let endDate = override.end ?? .distantFuture
                    if endDate > Date() {
                        context.temporaryOverride = WatchDatedRange(
                            startDate: override.start,
                            endDate: endDate,
                            minValue: override.value.minValue,
                            maxValue: override.value.maxValue
                        )
                    }
                }

                let configuredOverrideContexts = self.deviceManager.loopManager.settings.glucoseTargetRangeSchedule?.configuredOverrideContexts ?? []
                let configuredUserInfoOverrideContexts = configuredOverrideContexts.map { $0.correspondingUserInfoContext }
                context.configuredOverrideContexts = configuredUserInfoOverrideContexts

                context.targetRanges = glucoseTargetRangeSchedule.between(start: startDate, end: endDate).map {
                    return WatchDatedRange(
                        startDate: $0.startDate,
                        endDate: $0.endDate,
                        minValue: $0.value.minValue,
                        maxValue: $0.value.maxValue
                    )
                }
            }

            updateGroup.enter()
            manager.doseStore.insulinOnBoard(at: Date()) { (result) in
                switch result {
                case .success(let iobValue):
                    context.IOB = iobValue.value
                case .failure:
                    context.IOB = nil
                }
                updateGroup.leave()
            }

            // Only set this value in the Watch context if there is a temp basal running that hasn't ended yet
            let date = state.lastTempBasal?.startDate ?? Date()
            if let scheduledBasal = manager.basalRateSchedule?.between(start: date, end: date).first,
                let lastTempBasal = state.lastTempBasal,
                lastTempBasal.endDate > Date() {
                context.lastNetTempBasalDose =  lastTempBasal.unitsPerHour - scheduledBasal.value
            }

            // Drop the first element in predictedGlucose because it is the current glucose
            if let predictedGlucose = state.predictedGlucose?.dropFirst(), predictedGlucose.count > 0 {
                context.predictedGlucose = WatchPredictedGlucose(values: Array(predictedGlucose))
            }

            if let trend = self.deviceManager.sensorInfo?.trendType {
                context.glucoseTrendRawValue = trend.rawValue
            }

            _ = updateGroup.wait(timeout: .distantFuture)
            completion(context)
        }
    }

    private func addCarbEntryFromWatchMessage(_ message: [String: Any], completionHandler: ((_ units: Double?) -> Void)? = nil) {
        if let carbEntry = CarbEntryUserInfo(rawValue: message) {
            let newEntry = NewCarbEntry(
                quantity: HKQuantity(unit: deviceManager.loopManager.carbStore.preferredUnit, doubleValue: carbEntry.value),
                startDate: carbEntry.startDate,
                foodType: nil,
                absorptionTime: carbEntry.absorptionTimeType.absorptionTimeFromDefaults(deviceManager.loopManager.carbStore.defaultAbsorptionTimes)
            )

            deviceManager.loopManager.addCarbEntryAndRecommendBolus(newEntry) { (result) in
                switch result {
                case .success(let recommendation):
                    AnalyticsManager.shared.didAddCarbsFromWatch(carbEntry.value)
                    completionHandler?(recommendation?.amount)
                case .failure(let error):
                    self.deviceManager.logger.addError(error, fromSource: error is CarbStore.CarbStoreError ? "CarbStore" : "Bolus")
                    completionHandler?(nil)
                }
            }
        } else {
            completionHandler?(nil)
        }
    }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        switch message["name"] as? String {
        case CarbEntryUserInfo.name?:
            addCarbEntryFromWatchMessage(message) { (units) in
                replyHandler(BolusSuggestionUserInfo(recommendedBolus: units ?? 0, maxBolus: self.deviceManager.loopManager.settings.maximumBolus).rawValue)
            }
        case SetBolusUserInfo.name?:
            if let bolus = SetBolusUserInfo(rawValue: message as SetBolusUserInfo.RawValue) {
                self.deviceManager.enactBolus(units: bolus.value, at: bolus.startDate) { (error) in
                    if error == nil {
                        AnalyticsManager.shared.didSetBolusFromWatch(bolus.value)
                    }
                }
            }

            replyHandler([:])
        case GlucoseRangeScheduleOverrideUserInfo.name?:
            // Successful changes will trigger a preferences change which will update the watch with the new overrides
            if let overrideUserInfo = GlucoseRangeScheduleOverrideUserInfo(rawValue: message) {
                _ = deviceManager.loopManager.settings.glucoseTargetRangeSchedule?.setOverride(overrideUserInfo.context.correspondingOverrideContext, from: overrideUserInfo.startDate, until: overrideUserInfo.effectiveEndDate)
            } else {
                deviceManager.loopManager.settings.glucoseTargetRangeSchedule?.clearOverride()
            }
            replyHandler([:])
        case GlucoseBackfillRequestUserInfo.name?:
            if let userInfo = GlucoseBackfillRequestUserInfo(rawValue: message),
                let manager = deviceManager.loopManager {
                manager.glucoseStore.getCachedGlucoseSamples(start: userInfo.startDate) { (values) in
                    replyHandler(WatchHistoricalGlucose(with: values).rawValue)
                }
            } else {
                replyHandler([:])
            }
        default:
            replyHandler([:])
        }
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        addCarbEntryFromWatchMessage(userInfo)
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        switch activationState {
        case .activated:
            if let error = error {
                deviceManager.logger.addError(error, fromSource: "WCSession")
            }
        case .inactive, .notActivated:
            break
        }
    }

    func session(_ session: WCSession, didFinish userInfoTransfer: WCSessionUserInfoTransfer, error: Error?) {
        if let error = error {
            deviceManager.logger.addError(error, fromSource: "WCSession")
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {
        // Nothing to do here
    }

    func sessionDidDeactivate(_ session: WCSession) {
        watchSession = WCSession.default
        watchSession?.delegate = self
        watchSession?.activate()
    }
}

fileprivate extension GlucoseRangeSchedule.Override.Context {
    var correspondingUserInfoContext: GlucoseRangeScheduleOverrideUserInfo.Context {
        switch self {
        case .preMeal:
            return .preMeal
        case .workout:
            return .workout
        }
    }
}

fileprivate extension GlucoseRangeScheduleOverrideUserInfo.Context {
    var correspondingOverrideContext: GlucoseRangeSchedule.Override.Context {
        switch self {
        case .preMeal:
            return .preMeal
        case .workout:
            return .workout
        }
    }
}
