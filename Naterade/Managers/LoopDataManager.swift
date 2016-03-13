//
//  LoopDataManager.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 3/12/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation
import CarbKit
import InsulinKit
import LoopKit


class LoopDataManager {
    static let LoopDataUpdatedNotification = "com.loudnate.Naterade.notification.LoopDataUpdated"

    enum Error: ErrorType {
        case CommunicationError
        case MissingDataError
        case StaleDataError
    }

    typealias TempBasalRecommendation = (recommendedDate: NSDate, rate: Double, duration: NSTimeInterval)

    unowned let deviceDataManager: DeviceDataManager

    init(deviceDataManager: DeviceDataManager) {
        self.deviceDataManager = deviceDataManager

        observe()
    }

    // Actions

    private func observe() {
        let center = NSNotificationCenter.defaultCenter()

        notificationObservers = [
            center.addObserverForName(DeviceDataManager.GlucoseUpdatedNotification, object: deviceDataManager, queue: nil) { (note) -> Void in
                self.updateGlucoseMomentumEffect(self.observationUpdateHandler)
            },
            center.addObserverForName(DeviceDataManager.PumpStatusUpdatedNotification, object: deviceDataManager, queue: nil) { (note) -> Void in
                self.updateInsulinEffect(self.observationUpdateHandler)
            }
        ]

        if let carbStore = deviceDataManager.carbStore {
            notificationObservers.append(center.addObserverForName(CarbStore.CarbEntriesDidUpdateNotification, object: carbStore, queue: nil) { (note) -> Void in

                self.updateCarbEffect(self.observationUpdateHandler)
            })
        }
    }

    private func observationUpdateHandler(error: ErrorType?) {
        if let error = error {
            self.lastLoopError = error
        } else {
            do {
                try self.updatePredictedGlucoseAndRecommendedBasal()
            } catch let error {
                self.lastLoopError = error
            }

            NSNotificationCenter.defaultCenter().postNotificationName(self.dynamicType.LoopDataUpdatedNotification, object: self)
        }
    }

    // References to registered notification center observers
    private var notificationObservers: [AnyObject] = []

    deinit {
        for observer in notificationObservers {
            NSNotificationCenter.defaultCenter().removeObserver(observer)
        }
    }

    func update(completionHandler: (error: ErrorType?) -> Void) {
        let updateGroup = dispatch_group_create()
        var lastError: ErrorType?

        dispatch_group_enter(updateGroup)
        updateGlucoseMomentumEffect { (error) -> Void in
            if let error = error {
                lastError = error
            }

            dispatch_group_leave(updateGroup)
        }

        dispatch_group_enter(updateGroup)
        updateCarbEffect { (error) -> Void in
            if let error = error {
                lastError = error
            }

            dispatch_group_leave(updateGroup)
        }

        dispatch_group_enter(updateGroup)
        updateInsulinEffect { (error) -> Void in
            if let error = error {
                lastError = error
            }

            dispatch_group_leave(updateGroup)
        }

        dispatch_group_notify(updateGroup, dataAccessQueue) { () -> Void in
            do {
                try self.updatePredictedGlucoseAndRecommendedBasal()
            } catch let error {
                lastError = error
            }

            completionHandler(error: lastError)
        }
    }

    func getLoopStatus(resultsHandler: (predictedGlucose: [GlucoseValue]?, recommendedTempBasal: TempBasalRecommendation?, lastTempBasal: DoseEntry?, error: ErrorType?) -> Void) {
        dispatch_async(dataAccessQueue) {
            resultsHandler(predictedGlucose: self.predictedGlucose, recommendedTempBasal: self.recommendedTempBasal, lastTempBasal: self.lastTempBasal, error: self.lastLoopError)
        }
    }

    // Calculation

    private let dataAccessQueue: dispatch_queue_t = dispatch_queue_create("com.loudnate.Naterade.LoopDataManager.dataAccessQueue", dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_UTILITY, 0))

    private var carbEffect: [GlucoseEffect]?
    private var insulinEffect: [GlucoseEffect]?
    private var glucoseMomentumEffect: [GlucoseEffect]?
    private var predictedGlucose: [GlucoseValue]? {
        didSet {
            recommendedTempBasal = nil
        }
    }
    private var recommendedTempBasal: TempBasalRecommendation?
    private var lastTempBasal: DoseEntry?
    private var lastLoopError: ErrorType?

    private func updateCarbEffect(completionHandler: (error: ErrorType?) -> Void) {
        let glucose = deviceDataManager.glucoseStore?.latestGlucose

        if let carbStore = deviceDataManager.carbStore {
            carbStore.getGlucoseEffects(startDate: glucose?.startDate) { (effects, error) -> Void in
                dispatch_async(self.dataAccessQueue) {
                    if let error = error {
                        self.deviceDataManager.logger?.addError(error, fromSource: "CarbStore")
                        self.carbEffect = nil
                    } else {
                        self.carbEffect = effects
                    }
                    completionHandler(error: error)
                }
            }
        } else {
            completionHandler(error: Error.MissingDataError)
        }
    }

    private func updateInsulinEffect(completionHandler: (error: ErrorType?) -> Void) {
        let glucose = deviceDataManager.glucoseStore?.latestGlucose

        deviceDataManager.doseStore.getGlucoseEffects(startDate: glucose?.startDate) { (effects, error) -> Void in
            dispatch_async(self.dataAccessQueue) {
                if let error = error {
                    self.deviceDataManager.logger?.addError(error, fromSource: "DoseStore")
                    self.insulinEffect = nil
                } else {
                    self.insulinEffect = effects
                }

                completionHandler(error: error)
            }
        }
    }

    private func updateGlucoseMomentumEffect(completionHandler: (error: ErrorType?) -> Void) {
        if let glucoseStore = deviceDataManager.glucoseStore {
            glucoseStore.getRecentMomentumEffect { (effects, error) -> Void in
                dispatch_async(self.dataAccessQueue) {
                    if let error = error {
                        self.deviceDataManager.logger?.addError(error, fromSource: "GlucoseStore")
                        self.glucoseMomentumEffect = nil
                    } else {
                        self.glucoseMomentumEffect = effects
                    }

                    completionHandler(error: error)
                }
            }
        } else {
            completionHandler(error: Error.MissingDataError)
        }
    }

    /**
     Runs the glucose prediction on the latest effect data.
     
     *This method should only be called from the `dataAccessQueue`*
     */
    private func updatePredictedGlucoseAndRecommendedBasal() throws {
        guard let
            glucose = self.deviceDataManager.glucoseStore?.latestGlucose,
            pumpStatus = self.deviceDataManager.latestPumpStatus
            else
        {
            self.predictedGlucose = nil
            throw Error.MissingDataError
        }

        let startDate = NSDate()
        let recencyInterval = NSTimeInterval(minutes: 15)

        guard   startDate.timeIntervalSinceDate(glucose.startDate) <= recencyInterval &&
            startDate.timeIntervalSinceDate(pumpStatus.pumpDate) <= recencyInterval
            else
        {
            self.predictedGlucose = nil
            throw Error.StaleDataError
        }

        guard let
            momentum = self.glucoseMomentumEffect,
            carbEffect = self.carbEffect,
            insulinEffect = self.insulinEffect else
        {
            self.predictedGlucose = nil
            throw Error.MissingDataError
        }

        var error: ErrorType?

        defer {
            self.deviceDataManager.logger?.addLoopStatus(
                startDate: startDate,
                endDate: NSDate(),
                glucose: glucose,
                effects: [
                    "momentum": momentum,
                    "carbs": carbEffect,
                    "insulin": insulinEffect
                ],
                error: error,
                prediction: prediction,
                recommendedTempBasal: recommendedTempBasal
            )
        }

        let prediction = LoopMath.predictGlucose(glucose, momentum: momentum, effects: carbEffect, insulinEffect)

        self.predictedGlucose = prediction

        guard let
            maxBasal = deviceDataManager.maximumBasalRatePerHour,
            glucoseTargetRange = deviceDataManager.glucoseTargetRangeSchedule,
            insulinSensitivity = deviceDataManager.insulinSensitivitySchedule,
            basalRates = deviceDataManager.basalRateSchedule
        else {
            error = Error.MissingDataError
            throw error!
        }

        if let tempBasal = DoseMath.recommendTempBasalFromPredictedGlucose(prediction,
            lastTempBasal: lastTempBasal,
            maxBasalRate: maxBasal,
            glucoseTargetRange: glucoseTargetRange,
            insulinSensitivity: insulinSensitivity,
            basalRateSchedule: basalRates,
            allowPredictiveTempBelowRange: true
        ) {
            recommendedTempBasal = (recommendedDate: NSDate(), rate: tempBasal.rate, duration: tempBasal.duration)
        } else {
            recommendedTempBasal = nil
        }
    }

    func getRecommendedBolus(resultsHandler: (units: Double?, error: ErrorType?) -> Void) {
        dispatch_async(dataAccessQueue) {
            guard let
                glucose = self.predictedGlucose,
                maxBolus = self.deviceDataManager.maximumBolus,
                glucoseTargetRange = self.deviceDataManager.glucoseTargetRangeSchedule,
                insulinSensitivity = self.deviceDataManager.insulinSensitivitySchedule,
                basalRates = self.deviceDataManager.basalRateSchedule
            else {
                resultsHandler(units: nil, error: Error.MissingDataError)
                return
            }

            let recencyInterval = NSTimeInterval(minutes: 15)

            guard let predictedInterval = glucose.first?.startDate.timeIntervalSinceNow where abs(predictedInterval) <= recencyInterval else {
                resultsHandler(units: nil, error: Error.StaleDataError)
                return
            }

            let units = DoseMath.recommendBolusFromPredictedGlucose(glucose,
                lastTempBasal: self.lastTempBasal,
                maxBolus: maxBolus,
                glucoseTargetRange: glucoseTargetRange,
                insulinSensitivity: insulinSensitivity,
                basalRateSchedule: basalRates
            )

            resultsHandler(units: units, error: nil)
        }
    }
}