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
import MinimedKit


class LoopDataManager {
    static let LoopDataUpdatedNotification = "com.loudnate.Naterade.notification.LoopDataUpdated"

    enum Error: ErrorType {
        case CommunicationError
        case MissingDataError(String)
        case StaleDataError
    }

    typealias TempBasalRecommendation = (recommendedDate: NSDate, rate: Double, duration: NSTimeInterval)

    unowned let deviceDataManager: DeviceDataManager

    var dosingEnabled: Bool {
        didSet {
            NSUserDefaults.standardUserDefaults().dosingEnabled = dosingEnabled
        }
    }

    init(deviceDataManager: DeviceDataManager) {
        self.deviceDataManager = deviceDataManager

        dosingEnabled = NSUserDefaults.standardUserDefaults().dosingEnabled

        observe()
    }

    // Actions

    private func observe() {
        let center = NSNotificationCenter.defaultCenter()
        let queue = NSOperationQueue()
        queue.underlyingQueue = dataAccessQueue

        notificationObservers = [
            center.addObserverForName(DeviceDataManager.GlucoseUpdatedNotification, object: deviceDataManager, queue: queue) { (note) -> Void in
                self.glucoseMomentumEffect = nil
                self.loop()
            },
            center.addObserverForName(DeviceDataManager.PumpStatusUpdatedNotification, object: deviceDataManager, queue: queue) { (note) -> Void in
                self.insulinEffect = nil
                NSNotificationCenter.defaultCenter().postNotificationName(self.dynamicType.LoopDataUpdatedNotification, object: self)
            }
        ]

        if let carbStore = deviceDataManager.carbStore {
            notificationObservers.append(center.addObserverForName(CarbStore.CarbEntriesDidUpdateNotification, object: carbStore, queue: queue) { (note) -> Void in
                self.carbEffect = nil
                NSNotificationCenter.defaultCenter().postNotificationName(self.dynamicType.LoopDataUpdatedNotification, object: self)
            })
        }
    }

    private func loop() {
        self.update { (error) -> Void in
            self.lastLoopError = error

            if error == nil && self.dosingEnabled {
                self.enactRecommendedTempBasal { (success, error) -> Void in
                    self.lastLoopError = error

                    if let error = error {
                        self.deviceDataManager.logger?.addError(error, fromSource: "TempBasal")
                    }

                    NSNotificationCenter.defaultCenter().postNotificationName(self.dynamicType.LoopDataUpdatedNotification, object: self)
                }
            } else {
                NSNotificationCenter.defaultCenter().postNotificationName(self.dynamicType.LoopDataUpdatedNotification, object: self)
            }
        }
    }

    // References to registered notification center observers
    private var notificationObservers: [AnyObject] = []

    deinit {
        for observer in notificationObservers {
            NSNotificationCenter.defaultCenter().removeObserver(observer)
        }
    }

    private func update(completionHandler: (error: ErrorType?) -> Void) {
        let updateGroup = dispatch_group_create()
        var lastError: ErrorType?

        if glucoseMomentumEffect == nil {
            dispatch_group_enter(updateGroup)
            updateGlucoseMomentumEffect { (error) -> Void in
                if let error = error {
                    lastError = error
                }

                dispatch_group_leave(updateGroup)
            }
        }

        if carbEffect == nil {
            dispatch_group_enter(updateGroup)
            updateCarbEffect { (error) -> Void in
                if let error = error {
                    lastError = error
                }

                dispatch_group_leave(updateGroup)
            }
        }

        if insulinEffect == nil {
            dispatch_group_enter(updateGroup)
            updateInsulinEffect { (error) -> Void in
                if let error = error {
                    lastError = error
                }

                dispatch_group_leave(updateGroup)
            }
        }

        dispatch_group_notify(updateGroup, dataAccessQueue) { () -> Void in
            if self.predictedGlucose == nil {
                do {
                    try self.updatePredictedGlucoseAndRecommendedBasal()
                } catch let error {
                    lastError = error

                    self.deviceDataManager.logger?.addError(error, fromSource: "PredictGlucose")
                }
            }

            completionHandler(error: lastError)
        }
    }

    func getLoopStatus(resultsHandler: (predictedGlucose: [GlucoseValue]?, recommendedTempBasal: TempBasalRecommendation?, lastTempBasal: DoseEntry?, error: ErrorType?) -> Void) {
        dispatch_async(dataAccessQueue) {
            self.update { (error) -> Void in
                resultsHandler(predictedGlucose: self.predictedGlucose, recommendedTempBasal: self.recommendedTempBasal, lastTempBasal: self.lastTempBasal, error: error)
            }
        }
    }

    // Calculation

    private let dataAccessQueue: dispatch_queue_t = dispatch_queue_create("com.loudnate.Naterade.LoopDataManager.dataAccessQueue", dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_UTILITY, 0))

    private var carbEffect: [GlucoseEffect]? {
        didSet {
            predictedGlucose = nil
        }
    }
    private var insulinEffect: [GlucoseEffect]? {
        didSet {
            predictedGlucose = nil
        }
    }
    private var glucoseMomentumEffect: [GlucoseEffect]? {
        didSet {
            predictedGlucose = nil
        }
    }
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
            completionHandler(error: Error.MissingDataError("CarbStore not available"))
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
            completionHandler(error: Error.MissingDataError("GlucoseStore not available"))
        }
    }

    /**
     Runs the glucose prediction on the latest effect data.
     
     *This method should only be called from the `dataAccessQueue`*
     */
    private func updatePredictedGlucoseAndRecommendedBasal() throws {
        guard let
            glucose = self.deviceDataManager.glucoseStore?.latestGlucose,
            pumpStatusDate = self.deviceDataManager.latestPumpStatus?.pumpDateComponents.date
            else
        {
            self.predictedGlucose = nil
            throw Error.MissingDataError("Cannot predict glucose due to missing input data")
        }

        let startDate = NSDate()
        let recencyInterval = NSTimeInterval(minutes: 15)

        guard   startDate.timeIntervalSinceDate(glucose.startDate) <= recencyInterval &&
            startDate.timeIntervalSinceDate(pumpStatusDate) <= recencyInterval
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
            throw Error.MissingDataError("Cannot predict glucose due to missing effect data")
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
            error = Error.MissingDataError("Loop configuration data not set")
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
                resultsHandler(units: nil, error: Error.MissingDataError("Bolus prediction and configuration data not found"))
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

    func enactRecommendedTempBasal(resultsHandler: (success: Bool, error: ErrorType?) -> Void) {
        dispatch_async(dataAccessQueue) {
            guard let recommendedTempBasal = self.recommendedTempBasal else {
                resultsHandler(success: true, error: nil)
                return
            }

            guard recommendedTempBasal.recommendedDate.timeIntervalSinceNow < NSTimeInterval(minutes: 5) else {
                resultsHandler(success: false, error: Error.StaleDataError)
                return
            }

            guard let device = self.deviceDataManager.rileyLinkManager?.firstConnectedDevice else {
                resultsHandler(success: false, error: Error.CommunicationError)
                return
            }

            device.sendTempBasalDose(recommendedTempBasal.rate, duration: recommendedTempBasal.duration) { (success, message, error) -> Void in
                if success, let body = message?.messageBody as? ReadTempBasalCarelinkMessageBody where body.rateType == .Absolute {
                    dispatch_async(self.dataAccessQueue) {
                        let now = NSDate()
                        let endDate = now.dateByAddingTimeInterval(body.timeRemaining)
                        let startDate = endDate.dateByAddingTimeInterval(-recommendedTempBasal.duration)

                        self.lastTempBasal = DoseEntry(startDate: startDate, endDate: endDate, value: body.rate, unit: DoseUnit.UnitsPerHour)
                        self.recommendedTempBasal = nil

                        resultsHandler(success: success, error: error)
                    }
                } else {
                    resultsHandler(success: success, error: error)
                }
            }
        }
    }
}