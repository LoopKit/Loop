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
import CarbKit
import LoopKit
import xDripG5


final class WatchDataManager: NSObject, WCSessionDelegate {

    unowned let deviceDataManager: DeviceDataManager

    init(deviceDataManager: DeviceDataManager) {
        self.deviceDataManager = deviceDataManager

        super.init()

        NotificationCenter.default.addObserver(self, selector: #selector(updateWatch(_:)), name: .LoopDataUpdated, object: deviceDataManager.loopManager)

        watchSession?.delegate = self
        watchSession?.activate()
    }

    private var watchSession: WCSession? = {
        if WCSession.isSupported() {
            return WCSession.default()
        } else {
            return nil
        }
    }()

    @objc private func updateWatch(_ notification: Notification) {
        guard
            let rawContext = notification.userInfo?[LoopDataManager.LoopUpdateContextKey] as? LoopDataManager.LoopUpdateContext.RawValue,
            let context = LoopDataManager.LoopUpdateContext(rawValue: rawContext),
            case .tempBasal = context,
            let session = watchSession
        else {
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
    private lazy var minTrendUnit = HKUnit.milligramsPerDeciliter()

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
                    deviceDataManager.logger.addError(error, fromSource: "WCSession")
                }
            }
        }
    }

    private func createWatchContext(_ completion: @escaping (_ context: WatchContext?) -> Void) {
        let loopManager = deviceDataManager.loopManager!

        let glucose = loopManager.glucoseStore.latestGlucose
        let reservoir = loopManager.doseStore.lastReservoirValue

        loopManager.glucoseStore.preferredUnit { (unit, error) in
            loopManager.getLoopState { (manager, state) in
                let eventualGlucose = state.predictedGlucose?.last
                let context = WatchContext(glucose: glucose, eventualGlucose: eventualGlucose, glucoseUnit: unit)
                context.reservoir = reservoir?.unitVolume

                context.loopLastRunDate = state.lastLoopCompleted
                context.recommendedBolusDose = try? state.recommendBolus().amount
                context.maxBolus = manager.settings.maximumBolus

                if let trend = self.deviceDataManager.sensorInfo?.trendType {
                    context.glucoseTrendRawValue = trend.rawValue
                }

                completion(context)
            }
        }
    }

    private func addCarbEntryFromWatchMessage(_ message: [String: Any], completionHandler: ((_ units: Double?) -> Void)? = nil) {
        if let carbEntry = CarbEntryUserInfo(rawValue: message) {
            let newEntry = NewCarbEntry(
                quantity: HKQuantity(unit: deviceDataManager.loopManager.carbStore.preferredUnit, doubleValue: carbEntry.value),
                startDate: carbEntry.startDate,
                foodType: nil,
                absorptionTime: carbEntry.absorptionTimeType.absorptionTimeFromDefaults(deviceDataManager.loopManager.carbStore.defaultAbsorptionTimes)
            )

            deviceDataManager.loopManager.addCarbEntryAndRecommendBolus(newEntry) { (result) in
                switch result {
                case .success(let recommendation):
                    AnalyticsManager.sharedManager.didAddCarbsFromWatch(carbEntry.value)
                    completionHandler?(recommendation?.amount)
                case .failure(let error):
                    self.deviceDataManager.logger.addError(error, fromSource: error is CarbStore.CarbStoreError ? "CarbStore" : "Bolus")
                    completionHandler?(nil)
                }
            }
        } else {
            completionHandler?(nil)
        }
    }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String: Any]) -> Void) {
        switch message["name"] as? String {
        case CarbEntryUserInfo.name?:
            addCarbEntryFromWatchMessage(message) { (units) in
                replyHandler(BolusSuggestionUserInfo(recommendedBolus: units ?? 0, maxBolus: self.deviceDataManager.loopManager.settings.maximumBolus).rawValue)
            }
        case SetBolusUserInfo.name?:
            if let bolus = SetBolusUserInfo(rawValue: message as SetBolusUserInfo.RawValue) {
                self.deviceDataManager.enactBolus(units: bolus.value, at: bolus.startDate) { (error) in
                    if error == nil {
                        AnalyticsManager.sharedManager.didSetBolusFromWatch(bolus.value)
                    }

                    replyHandler([:])
                }
            } else {
                replyHandler([:])
            }
        default:
            replyHandler([:])
        }
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any]) {
        addCarbEntryFromWatchMessage(userInfo)
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        switch activationState {
        case .activated:
            if let error = error {
                deviceDataManager.logger.addError(error, fromSource: "WCSession")
            }
        case .inactive, .notActivated:
            break
        }
    }

    func session(_ session: WCSession, didFinish userInfoTransfer: WCSessionUserInfoTransfer, error: Error?) {
        if let error = error {
            deviceDataManager.logger.addError(error, fromSource: "WCSession")
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {
        // Nothing to do here
    }

    func sessionDidDeactivate(_ session: WCSession) {
        watchSession = WCSession.default()
        watchSession?.delegate = self
        watchSession?.activate()
    }

}
