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

        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(updateWatch(_:)), name: LoopDataManager.LoopDataUpdatedNotification, object: deviceDataManager.loopManager)

        watchSession?.delegate = self
        watchSession?.activateSession()
    }

    private var watchSession: WCSession? = {
        if WCSession.isSupported() {
            return WCSession.defaultSession()
        } else {
            return nil
        }
    }()

    @objc private func updateWatch(notification: NSNotification) {
        guard
            let rawContext = notification.userInfo?[LoopDataManager.LoopUpdateContextKey] as? LoopDataManager.LoopUpdateContext.RawValue,
            let context = LoopDataManager.LoopUpdateContext(rawValue: rawContext),
            case .TempBasal = context,
            let session = watchSession
        else {
            return
        }

        switch session.activationState {
        case .NotActivated, .Inactive:
            session.activateSession()
        case .Activated:
            createWatchContext { (context) in
                if let context = context {
                    self.sendWatchContext(context)
                }
            }
        }
    }

    private var lastComplicationContext: WatchContext?

    private let minTrendDrift: Double = 20
    private lazy var minTrendUnit = HKUnit.milligramsPerDeciliterUnit()

    private func sendWatchContext(context: WatchContext) {
        if let session = watchSession where session.paired && session.watchAppInstalled {

            let complicationShouldUpdate: Bool

            if let lastContext = lastComplicationContext,
                lastGlucose = lastContext.glucose, lastGlucoseDate = lastContext.glucoseDate,
                newGlucose = context.glucose, newGlucoseDate = context.glucoseDate
            {
                let enoughTimePassed = newGlucoseDate.timeIntervalSinceDate(lastGlucoseDate).minutes >= 30
                let enoughTrendDrift = abs(newGlucose.doubleValueForUnit(minTrendUnit) - lastGlucose.doubleValueForUnit(minTrendUnit)) >= minTrendDrift

                complicationShouldUpdate = enoughTimePassed || enoughTrendDrift
            } else {
                complicationShouldUpdate = true
            }

            if session.complicationEnabled && complicationShouldUpdate {
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

    private func createWatchContext(completionHandler: (context: WatchContext?) -> Void) {

        guard let glucoseStore = self.deviceDataManager.glucoseStore else {
            completionHandler(context: nil)
            return
        }

        let glucose = deviceDataManager.glucoseStore?.latestGlucose
        let reservoir = deviceDataManager.latestReservoirValue

        deviceDataManager.loopManager.getLoopStatus { (predictedGlucose, recommendedTempBasal, lastTempBasal, lastLoopCompleted, insulinOnBoard, error) in

            let eventualGlucose = predictedGlucose?.last

            self.deviceDataManager.loopManager.getRecommendedBolus { (units, error) in
                glucoseStore.preferredUnit { (unit, error) in
                    let context = WatchContext(glucose: glucose, eventualGlucose: eventualGlucose, glucoseUnit: unit)
                    context.reservoir = reservoir?.unitVolume

                    context.loopLastRunDate = lastLoopCompleted
                    context.recommendedBolusDose = units

                    if let trend = self.deviceDataManager.sensorInfo?.trendType {
                        context.glucoseTrend = trend
                    }

                    completionHandler(context: context)
                }
            }
        }
    }

    private func addCarbEntryFromWatchMessage(message: [String: AnyObject], completionHandler: ((units: Double?) -> Void)? = nil) {
        if let carbStore = deviceDataManager.carbStore, carbEntry = CarbEntryUserInfo(rawValue: message) {
            let newEntry = NewCarbEntry(
                quantity: HKQuantity(unit: carbStore.preferredUnit, doubleValue: carbEntry.value),
                startDate: carbEntry.startDate,
                foodType: nil,
                absorptionTime: carbEntry.absorptionTimeType.absorptionTimeFromDefaults(carbStore.defaultAbsorptionTimes)
            )

            deviceDataManager.loopManager.addCarbEntryAndRecommendBolus(newEntry) { (units, error) in
                if let error = error {
                    self.deviceDataManager.logger.addError(error, fromSource: error is CarbStore.Error ? "CarbStore" : "Bolus")
                } else {
                    AnalyticsManager.sharedManager.didAddCarbsFromWatch(carbEntry.value)
                }

                completionHandler?(units: units)
            }
        } else {
            completionHandler?(units: nil)
        }
    }

    // MARK: WCSessionDelegate

    func session(session: WCSession, didReceiveMessage message: [String : AnyObject], replyHandler: ([String: AnyObject]) -> Void) {
        switch message["name"] as? String {
        case CarbEntryUserInfo.name?:
            addCarbEntryFromWatchMessage(message) { (units) in
                replyHandler(BolusSuggestionUserInfo(recommendedBolus: units ?? 0).rawValue)
            }
        case SetBolusUserInfo.name?:
            if let bolus = SetBolusUserInfo(rawValue: message) {
                self.deviceDataManager.enactBolus(bolus.value) { (error) in
                    if error != nil {
                        NotificationManager.sendBolusFailureNotificationForAmount(bolus.value, atDate: bolus.startDate)
                    } else {
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

    func session(session: WCSession, didReceiveUserInfo userInfo: [String : AnyObject]) {
        addCarbEntryFromWatchMessage(userInfo)
    }

    func session(session: WCSession, activationDidCompleteWithState activationState: WCSessionActivationState, error: NSError?) {
        switch activationState {
        case .Activated:
            if let error = error {
                deviceDataManager.logger.addError(error, fromSource: "WCSession")
            }
        case .Inactive, .NotActivated:
            break
        }
    }

    func session(session: WCSession, didFinishUserInfoTransfer userInfoTransfer: WCSessionUserInfoTransfer, error: NSError?) {
        if let error = error {
            deviceDataManager.logger.addError(error, fromSource: "WCSession")
        }
    }

    func sessionDidBecomeInactive(session: WCSession) {
        // Nothing to do here
    }

    func sessionDidDeactivate(session: WCSession) {
        watchSession = WCSession.defaultSession()
        watchSession?.delegate = self
        watchSession?.activateSession()
    }

}
