//
//  LoopDataManager.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 3/12/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation
import LoopKit


class LoopDataManager {
    enum Error: ErrorType {
        case MissingDataError
        case StaleDataError
    }

    unowned let deviceDataManager: DeviceDataManager

    init(deviceDataManager: DeviceDataManager) {
        self.deviceDataManager = deviceDataManager
    }

    // Observation

    // Calculation

    func getPredictedGlucose(resultsHandler: (values: [GlucoseValue], error: ErrorType?) -> Void) {
        guard let
            glucose = deviceDataManager.glucoseStore?.latestGlucose,
            pumpStatus = deviceDataManager.latestPumpStatus
            else
        {
            resultsHandler(values: [], error: Error.MissingDataError)
            return
        }

        let startDate = NSDate()
        let recencyInterval = NSTimeInterval(minutes: 15)

        guard   startDate.timeIntervalSinceDate(glucose.startDate) <= recencyInterval &&
            startDate.timeIntervalSinceDate(pumpStatus.pumpDate) <= recencyInterval
            else
        {
            resultsHandler(values: [], error: Error.StaleDataError)
            return
        }

        let dataGroup = dispatch_group_create()
        var momentum: [GlucoseEffect] = []
        var carbEffect: [GlucoseEffect] = []
        var insulinEffect: [GlucoseEffect] = []
        var lastError: ErrorType?

        if let glucoseStore = deviceDataManager.glucoseStore {
            dispatch_group_enter(dataGroup)
            glucoseStore.getRecentMomentumEffect { (effects, error) -> Void in
                if let error = error {
                    self.deviceDataManager.logger?.addError(error, fromSource: "GlucoseStore")
                    lastError = error
                }

                momentum = effects
                dispatch_group_leave(dataGroup)
            }
        }

        if let carbStore = deviceDataManager.carbStore {
            dispatch_group_enter(dataGroup)
            carbStore.getGlucoseEffects(startDate: glucose.startDate) { (effects, error) -> Void in
                if let error = error {
                    self.deviceDataManager.logger?.addError(error, fromSource: "CarbStore")
                    lastError = error
                }

                carbEffect = effects
                dispatch_group_leave(dataGroup)
            }
        }

        dispatch_group_enter(dataGroup)
        deviceDataManager.doseStore.getGlucoseEffects(startDate: glucose.startDate) { (effects, error) -> Void in
            if let error = error {
                self.deviceDataManager.logger?.addError(error, fromSource: "DoseStore")
                lastError = error
            }

            insulinEffect = effects
            dispatch_group_leave(dataGroup)
        }

        dispatch_group_notify(dataGroup, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0)) { () -> Void in
            let prediction = LoopMath.predictGlucose(glucose, momentum: momentum, effects: carbEffect, insulinEffect)

            self.deviceDataManager.logger?.addLoopStatus(
                startDate: startDate,
                endDate: NSDate(),
                glucose: glucose,
                effects: [
                    "momentum": momentum,
                    "carbs": carbEffect,
                    "insulin": insulinEffect
                ],
                error: lastError,
                prediction: prediction
            )
            
            resultsHandler(values: prediction, error: lastError)
        }
    }
}