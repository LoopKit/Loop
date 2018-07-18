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
            let eventualGlucose = state.predictedGlucose?.last
            let context = WatchContext(glucose: glucose, eventualGlucose: eventualGlucose, glucoseUnit: manager.glucoseStore.preferredUnit)
            context.reservoir = reservoir?.unitVolume

            context.loopLastRunDate = manager.lastLoopCompleted
            context.recommendedBolusDose = state.recommendedBolus?.recommendation.amount
            context.maxBolus = manager.settings.maximumBolus

            context.cgm = self.deviceManager.cgm

            if let glucoseTargetRangeSchedule = manager.settings.glucoseTargetRangeSchedule {
                if let override = glucoseTargetRangeSchedule.override {
                    context.glucoseRangeScheduleOverride = GlucoseRangeScheduleOverrideUserInfo(
                        context: override.context.correspondingUserInfoContext,
                        startDate: override.start,
                        endDate: override.end
                    )
                }

                let configuredOverrideContexts = self.deviceManager.loopManager.settings.glucoseTargetRangeSchedule?.configuredOverrideContexts ?? []
                let configuredUserInfoOverrideContexts = configuredOverrideContexts.map { $0.correspondingUserInfoContext }
                context.configuredOverrideContexts = configuredUserInfoOverrideContexts
            }

            if let trend = self.deviceManager.sensorInfo?.trendType {
                context.glucoseTrendRawValue = trend.rawValue
            }

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
            if let overrideUserInfo = GlucoseRangeScheduleOverrideUserInfo(rawValue: message) {
                let overrideContext = overrideUserInfo.context.correspondingOverrideContext

                // update the recorded last active override context prior to enabling the actual override
                // to prevent the Watch context being unnecessarily sent in response to the override being enabled
                let previousActiveOverrideContext = lastActiveOverrideContext
                lastActiveOverrideContext = overrideContext
                let overrideSuccess = deviceManager.loopManager.settings.glucoseTargetRangeSchedule?.setOverride(overrideContext, from: overrideUserInfo.startDate, until: overrideUserInfo.effectiveEndDate)

                if overrideSuccess == false {
                    lastActiveOverrideContext = previousActiveOverrideContext
                }

                replyHandler([:])
            } else {
                lastActiveOverrideContext = nil
                deviceManager.loopManager.settings.glucoseTargetRangeSchedule?.clearOverride()
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
