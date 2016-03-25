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
                NSNotificationCenter.defaultCenter().postNotificationName(self.dynamicType.LoopDataUpdatedNotification, object: self)
            },
            center.addObserverForName(DeviceDataManager.PumpStatusUpdatedNotification, object: deviceDataManager, queue: queue) { (note) -> Void in
                self.insulinEffect = nil
                self.loop()
            }
        ]

        notificationObservers.append(center.addObserverForName(CarbStore.CarbEntriesDidUpdateNotification, object: nil, queue: queue) { (note) -> Void in
            self.carbEffect = nil
            NSNotificationCenter.defaultCenter().postNotificationName(self.dynamicType.LoopDataUpdatedNotification, object: self)
        })
    }

    private func loop() {
        lastLoopError = nil

        do {
            try self.update()

            if dosingEnabled {
                setRecommendedTempBasal { (success, error) -> Void in
                    self.lastLoopError = error

                    if let error = error {
                        self.deviceDataManager.logger?.addError(error, fromSource: "TempBasal")
                    }

                    NSNotificationCenter.defaultCenter().postNotificationName(self.dynamicType.LoopDataUpdatedNotification, object: self)
                }

                // Delay the notification until we know the result of the temp basal
                return
            }
        } catch let error {
            lastLoopError = error
        }

        NSNotificationCenter.defaultCenter().postNotificationName(self.dynamicType.LoopDataUpdatedNotification, object: self)
    }

    // References to registered notification center observers
    private var notificationObservers: [AnyObject] = []

    deinit {
        for observer in notificationObservers {
            NSNotificationCenter.defaultCenter().removeObserver(observer)
        }
    }

    private func update() throws {
        let updateGroup = dispatch_group_create()

        if glucoseMomentumEffect == nil {
            dispatch_group_enter(updateGroup)
            updateGlucoseMomentumEffect { (effects, error) -> Void in
                if error == nil {
                    self.glucoseMomentumEffect = effects
                } else {
                    self.glucoseMomentumEffect = nil
                }
                dispatch_group_leave(updateGroup)
            }
        }

        if carbEffect == nil {
            dispatch_group_enter(updateGroup)
            updateCarbEffect { (effects, error) -> Void in
                if error == nil {
                    self.carbEffect = effects
                } else {
                    self.carbEffect = nil
                }
                dispatch_group_leave(updateGroup)
            }
        }

        if insulinEffect == nil {
            dispatch_group_enter(updateGroup)
            updateInsulinEffect { (effects, error) -> Void in
                if error == nil {
                    self.insulinEffect = effects
                } else {
                    self.insulinEffect = nil
                }
                dispatch_group_leave(updateGroup)
            }
        }

        dispatch_group_wait(updateGroup, DISPATCH_TIME_FOREVER)

        if self.predictedGlucose == nil {
            do {
                try self.updatePredictedGlucoseAndRecommendedBasal()
            } catch let error {
                self.deviceDataManager.logger?.addError(error, fromSource: "PredictGlucose")

                throw error
            }
        }
    }

    func getLoopStatus(resultsHandler: (predictedGlucose: [GlucoseValue]?, recommendedTempBasal: TempBasalRecommendation?, lastTempBasal: DoseEntry?, error: ErrorType?) -> Void) {
        dispatch_async(dataAccessQueue) {
            var error: ErrorType?

            do {
                try self.update()
            } catch let updateError {
                error = updateError
            }

            resultsHandler(predictedGlucose: self.predictedGlucose, recommendedTempBasal: self.recommendedTempBasal, lastTempBasal: self.lastTempBasal, error: error)
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

    private func updateCarbEffect(completionHandler: (effects: [GlucoseEffect]?, error: ErrorType?) -> Void) {
        let glucose = deviceDataManager.glucoseStore?.latestGlucose

        if let carbStore = deviceDataManager.carbStore {
            carbStore.getGlucoseEffects(startDate: glucose?.startDate) { (effects, error) -> Void in
                if let error = error {
                    self.deviceDataManager.logger?.addError(error, fromSource: "CarbStore")
                }

                completionHandler(effects: effects, error: error)
            }
        } else {
            completionHandler(effects: nil, error: Error.MissingDataError("CarbStore not available"))
        }
    }

    private func updateInsulinEffect(completionHandler: (effects: [GlucoseEffect]?, error: ErrorType?) -> Void) {
        let glucose = deviceDataManager.glucoseStore?.latestGlucose

        deviceDataManager.doseStore.getGlucoseEffects(startDate: glucose?.startDate) { (effects, error) -> Void in
            if let error = error {
                self.deviceDataManager.logger?.addError(error, fromSource: "DoseStore")
            }

            completionHandler(effects: effects, error: error)
        }
    }

    private func updateGlucoseMomentumEffect(completionHandler: (effects: [GlucoseEffect]?, error: ErrorType?) -> Void) {
        if let glucoseStore = deviceDataManager.glucoseStore {
            glucoseStore.getRecentMomentumEffect { (effects, error) -> Void in
                if let error = error {
                    self.deviceDataManager.logger?.addError(error, fromSource: "GlucoseStore")
                }

                completionHandler(effects: effects, error: error)
            }
        } else {
            completionHandler(effects: nil, error: Error.MissingDataError("GlucoseStore not available"))
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

    func addCarbEntryAndRecommendBolus(carbEntry: CarbEntry, resultsHandler: (units: Double?, error: ErrorType?) -> Void) {
        if let carbStore = deviceDataManager.carbStore {
            carbStore.addCarbEntry(carbEntry) { (success, _, error) in
                dispatch_async(self.dataAccessQueue) {
                    if success {
                        self.carbEffect = nil

                        do {
                            try self.update()

                            resultsHandler(units: try self.recommendBolus(), error: nil)
                        } catch let error {
                            resultsHandler(units: nil, error: error)
                        }
                    } else {
                        resultsHandler(units: nil, error: error)
                    }
                }
            }
        } else {
            resultsHandler(units: nil, error: Error.MissingDataError("CarbStore not configured"))
        }
    }

    private func recommendBolus() throws -> Double {
        guard let
            glucose = self.predictedGlucose,
            maxBolus = self.deviceDataManager.maximumBolus,
            glucoseTargetRange = self.deviceDataManager.glucoseTargetRangeSchedule,
            insulinSensitivity = self.deviceDataManager.insulinSensitivitySchedule,
            basalRates = self.deviceDataManager.basalRateSchedule
        else {
            throw Error.MissingDataError("Bolus prediction and configuration data not found")
        }

        let recencyInterval = NSTimeInterval(minutes: 15)

        guard let predictedInterval = glucose.first?.startDate.timeIntervalSinceNow where abs(predictedInterval) <= recencyInterval else {
            throw Error.StaleDataError
        }

        return DoseMath.recommendBolusFromPredictedGlucose(glucose,
            lastTempBasal: self.lastTempBasal,
            maxBolus: maxBolus,
            glucoseTargetRange: glucoseTargetRange,
            insulinSensitivity: insulinSensitivity,
            basalRateSchedule: basalRates
        )
    }

    func getRecommendedBolus(resultsHandler: (units: Double?, error: ErrorType?) -> Void) {
        dispatch_async(dataAccessQueue) {
            do {
                let units = try self.recommendBolus()
                resultsHandler(units: units, error: nil)
            } catch let error {
                resultsHandler(units: nil, error: error)
            }
        }
    }

    private func setRecommendedTempBasal(resultsHandler: (success: Bool, error: ErrorType?) -> Void) {
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

    func enactRecommendedTempBasal(resultsHandler: (success: Bool, error: ErrorType?) -> Void) {
        dispatch_async(dataAccessQueue) {
            self.setRecommendedTempBasal(resultsHandler)
        }
    }
}