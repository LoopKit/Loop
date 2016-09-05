//
//  LoopDataManager.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 3/12/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation
import CarbKit
import HealthKit
import InsulinKit
import LoopKit
import MinimedKit
import HealthKit


final class LoopDataManager {
    enum LoopUpdateContext: Int {
        case Bolus
        case Carbs
        case Glucose
        case Preferences
        case TempBasal
    }

    static let LoopDataUpdatedNotification = "com.loudnate.Naterade.notification.LoopDataUpdated"

    static let LoopRunningNotification = "com.loudnate.Naterade.notification.LoopRunning"

    static let LoopUpdateContextKey = "com.loudnate.Loop.LoopDataManager.LoopUpdateContext"

    typealias TempBasalRecommendation = (recommendedDate: NSDate, rate: Double, duration: NSTimeInterval)

    private typealias GlucoseChange = (GlucoseValue, GlucoseValue)

    unowned let deviceDataManager: DeviceDataManager

    var dosingEnabled: Bool {
        didSet {
            NSUserDefaults.standardUserDefaults().dosingEnabled = dosingEnabled

            notify(forChange: .Preferences)
        }
    }

    var retrospectiveCorrectionEnabled: Bool {
        didSet {
            NSUserDefaults.standardUserDefaults().retrospectiveCorrectionEnabled = retrospectiveCorrectionEnabled

            notify(forChange: .Preferences)
        }
    }

    init(deviceDataManager: DeviceDataManager) {
        self.deviceDataManager = deviceDataManager

        dosingEnabled = NSUserDefaults.standardUserDefaults().dosingEnabled
        retrospectiveCorrectionEnabled = NSUserDefaults.standardUserDefaults().retrospectiveCorrectionEnabled

        // Observe changes
        let center = NSNotificationCenter.defaultCenter()

        notificationObservers = [
            center.addObserverForName(DeviceDataManager.GlucoseUpdatedNotification, object: deviceDataManager, queue: nil) { (note) -> Void in
                dispatch_async(self.dataAccessQueue) {
                    self.glucoseMomentumEffect = nil
                    self.glucoseChange = nil
                    self.notify(forChange: .Glucose)
                }
            },
            center.addObserverForName(DeviceDataManager.PumpStatusUpdatedNotification, object: deviceDataManager, queue: nil) { (note) -> Void in
                dispatch_async(self.dataAccessQueue) {
                    // Assuming insulin data is never back-dated, we don't need to remove the retrospective glucose effects
                    self.insulinEffect = nil
                    self.insulinOnBoard = nil
                    self.loop()
                }
            },
            center.addObserverForName(CarbStore.CarbEntriesDidUpdateNotification, object: nil, queue: nil) { (note) -> Void in
                dispatch_async(self.dataAccessQueue) {
                    self.carbEffect = nil
                    self.notify(forChange: .Carbs)
                }
            }
        ]
    }

    // Actions

    private func loop() {
        NSNotificationCenter.defaultCenter().postNotificationName(self.dynamicType.LoopRunningNotification, object: self)

        lastLoopError = nil

        do {
            try self.update()

            if dosingEnabled {

                setRecommendedTempBasal { (success, error) -> Void in
                    self.lastLoopError = error

                    if let error = error {
                        self.deviceDataManager.logger.addError(error, fromSource: "TempBasal")
                    } else {
                        self.lastLoopCompleted = NSDate()
                    }
                    self.notify(forChange: .TempBasal)
                }

                // Delay the notification until we know the result of the temp basal
                return
            } else {
                lastLoopCompleted = NSDate()
            }
        } catch let error {
            lastLoopError = error
        }

        notify(forChange: .TempBasal)
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

        if glucoseChange == nil, let glucoseStore = deviceDataManager.glucoseStore {
            dispatch_group_enter(updateGroup)
            glucoseStore.getRecentGlucoseChange { (values, error) in
                if let error = error {
                    self.deviceDataManager.logger.addError(error, fromSource: "GlucoseStore")
                }

                self.glucoseChange = values
                dispatch_group_leave(updateGroup)
            }
        }

        if glucoseMomentumEffect == nil {
            dispatch_group_enter(updateGroup)
            updateGlucoseMomentumEffect { (effects, error) in
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
            updateCarbEffect { (effects, error) in
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
            updateInsulinEffect { (effects, error) in
                if error == nil {
                    self.insulinEffect = effects
                } else {
                    self.insulinEffect = nil
                }
                dispatch_group_leave(updateGroup)
            }
        }

        if insulinOnBoard == nil {
            dispatch_group_enter(updateGroup)
            deviceDataManager.doseStore.insulinOnBoardAtDate(NSDate()) { (value, error) in
                if let error = error {
                    self.deviceDataManager.logger.addError(error, fromSource: "DoseStore")
                }

                self.insulinOnBoard = value
                dispatch_group_leave(updateGroup)
            }
        }

        dispatch_group_wait(updateGroup, DISPATCH_TIME_FOREVER)

        if self.retrospectivePredictedGlucose == nil {
            do {
                try self.updateRetrospectiveGlucoseEffect()
            } catch let error {
                self.deviceDataManager.logger.addError(error, fromSource: "RetrospectiveGlucose")
            }
        }

        if self.predictedGlucose == nil {
            do {
                try self.updatePredictedGlucoseAndRecommendedBasal()
            } catch let error {
                self.deviceDataManager.logger.addError(error, fromSource: "PredictGlucose")

                throw error
            }
        }
    }

    private func notify(forChange context: LoopUpdateContext) {
        NSNotificationCenter.defaultCenter().postNotificationName(self.dynamicType.LoopDataUpdatedNotification,
            object: self,
            userInfo: [self.dynamicType.LoopUpdateContextKey: context.rawValue]
        )
    }

    /**
     Retrieves the current state of the loop, calculating
     
     This operation is performed asynchronously and the completion will be executed on an arbitrary background queue.

     - parameter resultsHandler: A closure called once the values have been retrieved. The closure takes the following arguments:
        - predictedGlucose:     The calculated timeline of predicted glucose values
        - retrospectivePredictedGlucose: The retrospective prediction over a recent period of glucose samples
        - recommendedTempBasal: The recommended temp basal based on predicted glucose
        - lastTempBasal:        The last set temp basal
        - lastLoopCompleted:    The last date at which a loop completed, from prediction to dose (if dosing is enabled)
        - insulinOnBoard        Current insulin on board
        - error:                An error in the current state of the loop, or one that happened during the last attempt to loop.
     */
    func getLoopStatus(resultsHandler: (predictedGlucose: [GlucoseValue]?, retrospectivePredictedGlucose: [GlucoseValue]?, recommendedTempBasal: TempBasalRecommendation?, lastTempBasal: DoseEntry?, lastLoopCompleted: NSDate?, insulinOnBoard: InsulinValue?, error: ErrorType?) -> Void) {
        dispatch_async(dataAccessQueue) {
            var error: ErrorType?

            do {
                try self.update()
            } catch let updateError {
                error = updateError
            }

            resultsHandler(predictedGlucose: self.predictedGlucose, retrospectivePredictedGlucose: self.retrospectivePredictedGlucose, recommendedTempBasal: self.recommendedTempBasal, lastTempBasal: self.lastTempBasal, lastLoopCompleted: self.lastLoopCompleted, insulinOnBoard: self.insulinOnBoard, error: error ?? self.lastLoopError)
        }
    }

    func modelPredictedGlucose(using inputs: [PredictionInputEffect], resultsHandler: (predictedGlucose: [GlucoseValue]?, error: ErrorType?) -> Void) {
        dispatch_async(dataAccessQueue) { 
            guard let
                glucose = self.deviceDataManager.glucoseStore?.latestGlucose
            else {
                resultsHandler(predictedGlucose: nil, error: LoopError.MissingDataError("Cannot predict glucose due to missing input data"))
                return
            }

            var momentum: [GlucoseEffect] = []
            var effects: [[GlucoseEffect]] = []

            for input in inputs {
                switch input {
                case .carbs:
                    if let carbEffect = self.carbEffect {
                        effects.append(carbEffect)
                    }
                case .insulin:
                    if let insulinEffect = self.insulinEffect {
                        effects.append(insulinEffect)
                    }
                case .momentum:
                    if let momentumEffect = self.glucoseMomentumEffect {
                        momentum = momentumEffect
                    }
                case .retrospection:
                    effects.append(self.retrospectiveGlucoseEffect)
                }
            }

            let prediction = LoopMath.predictGlucose(glucose, momentum: momentum, effects: effects)

            resultsHandler(predictedGlucose: prediction, error: nil)
        }
    }

    // Calculation

    private let dataAccessQueue: dispatch_queue_t = dispatch_queue_create("com.loudnate.Naterade.LoopDataManager.dataAccessQueue", dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_UTILITY, 0))

    private var carbEffect: [GlucoseEffect]? {
        didSet {
            predictedGlucose = nil

            // Carb data may be back-dated, so re-calculate the retrospective glucose.
            retrospectivePredictedGlucose = nil
        }
    }
    private var insulinEffect: [GlucoseEffect]? {
        didSet {
            if let bolusDate = lastBolus?.date where bolusDate.timeIntervalSinceNow < NSTimeInterval(minutes: -5) {
                lastBolus = nil
            }

            predictedGlucose = nil
        }
    }
    private var insulinOnBoard: InsulinValue?
    private var glucoseMomentumEffect: [GlucoseEffect]? {
        didSet {
            predictedGlucose = nil
        }
    }
    private var glucoseChange: GlucoseChange? {
        didSet {
            retrospectivePredictedGlucose = nil
        }
    }
    private var predictedGlucose: [GlucoseValue]? {
        didSet {
            recommendedTempBasal = nil
        }
    }
    private var retrospectivePredictedGlucose: [GlucoseValue]? {
        didSet {
            retrospectiveGlucoseEffect = []
        }
    }
    private var retrospectiveGlucoseEffect: [GlucoseEffect] = [] {
        didSet {
            predictedGlucose = nil
        }
    }
    private var recommendedTempBasal: TempBasalRecommendation?

    private var lastTempBasal: DoseEntry?
    private var lastBolus: (units: Double, date: NSDate)?
    private var lastLoopError: ErrorType? {
        didSet {
            if lastLoopError != nil {
                AnalyticsManager.sharedManager.loopDidError()
            }
        }
    }
    private var lastLoopCompleted: NSDate? {
        didSet {
            NotificationManager.scheduleLoopNotRunningNotifications()

            AnalyticsManager.sharedManager.loopDidSucceed()
        }
    }

    /// The oldest date that should be used for effect calculation
    private var effectStartDate: NSDate? {
        let startDate: NSDate?

        if let glucoseStore = deviceDataManager.glucoseStore {
            // Fetch glucose effects as far back as we want to make retroactive analysis
            startDate = glucoseStore.latestGlucose?.startDate.dateByAddingTimeInterval(-glucoseStore.reflectionDataInterval)
        } else {
            startDate = nil
        }

        return startDate
    }

    private func updateCarbEffect(completionHandler: (effects: [GlucoseEffect]?, error: ErrorType?) -> Void) {
        if let carbStore = deviceDataManager.carbStore {
            carbStore.getGlucoseEffects(startDate: effectStartDate) { (effects, error) -> Void in
                if let error = error {
                    self.deviceDataManager.logger.addError(error, fromSource: "CarbStore")
                }

                completionHandler(effects: effects, error: error)
            }
        } else {
            completionHandler(effects: nil, error: LoopError.MissingDataError("CarbStore not available"))
        }
    }

    private func updateInsulinEffect(completionHandler: (effects: [GlucoseEffect]?, error: ErrorType?) -> Void) {
        deviceDataManager.doseStore.getGlucoseEffects(startDate: effectStartDate) { (effects, error) -> Void in
            if let error = error {
                self.deviceDataManager.logger.addError(error, fromSource: "DoseStore")
            }

            completionHandler(effects: effects, error: error)
        }
    }

    private func updateGlucoseMomentumEffect(completionHandler: (effects: [GlucoseEffect]?, error: ErrorType?) -> Void) {
        guard let glucoseStore = deviceDataManager.glucoseStore else {
            completionHandler(effects: nil, error: LoopError.MissingDataError("GlucoseStore not available"))
            return
        }
        glucoseStore.getRecentMomentumEffect { (effects, error) -> Void in
            if let error = error {
                self.deviceDataManager.logger.addError(error, fromSource: "GlucoseStore")
            }

            completionHandler(effects: effects, error: error)
        }
    }

    /**
     Runs the glucose retrospective analysis using the latest effect data.
 
     *This method should only be called from the `dataAccessQueue`*
     */
    private func updateRetrospectiveGlucoseEffect() throws {
        guard
            let carbEffect = self.carbEffect,
            let insulinEffect = self.insulinEffect
        else {
            self.retrospectivePredictedGlucose = nil
            throw LoopError.MissingDataError("Cannot retrospect glucose due to missing input data")
        }

        guard let change = glucoseChange else {
            self.retrospectivePredictedGlucose = nil
            return  // Expected case for calibrations
        }

        // Run a retrospective prediction over the duration of the recorded glucose change, using the current carb and insulin effects
        let startDate = change.0.startDate
        let endDate = change.1.endDate.dateByAddingTimeInterval(NSTimeInterval(minutes: 5))
        let retrospectivePrediction = LoopMath.predictGlucose(change.0, effects:
            carbEffect.filterDateRange(startDate, endDate),
            insulinEffect.filterDateRange(startDate, endDate)
        )

        self.retrospectivePredictedGlucose = retrospectivePrediction

        guard let lastGlucose = retrospectivePrediction.last else { return }
        let glucoseUnit = HKUnit.milligramsPerDeciliterUnit()
        let velocityUnit = glucoseUnit.unitDividedByUnit(HKUnit.secondUnit())

        let discrepancy = change.1.quantity.doubleValueForUnit(glucoseUnit) - lastGlucose.quantity.doubleValueForUnit(glucoseUnit) // mg/dL
        let velocity = HKQuantity(unit: velocityUnit, doubleValue: discrepancy / change.1.endDate.timeIntervalSinceDate(change.0.endDate))
        let type = HKQuantityType.quantityTypeForIdentifier(HKQuantityTypeIdentifierBloodGlucose)!
        let glucose = HKQuantitySample(type: type, quantity: change.1.quantity, startDate: change.1.startDate, endDate: change.1.endDate)

        self.retrospectiveGlucoseEffect = LoopMath.decayEffect(from: glucose, atRate: velocity, for: NSTimeInterval(minutes: 60))
    }

    /**
     Runs the glucose prediction on the latest effect data.
     
     *This method should only be called from the `dataAccessQueue`*
     */
    private func updatePredictedGlucoseAndRecommendedBasal() throws {
        guard let
            glucose = self.deviceDataManager.glucoseStore?.latestGlucose,
            pumpStatusDate = self.deviceDataManager.doseStore.lastReservoirValue?.startDate
        else {
            self.predictedGlucose = nil
            throw LoopError.MissingDataError("Cannot predict glucose due to missing input data")
        }

        let startDate = NSDate()
        let recencyInterval = NSTimeInterval(minutes: 15)

        guard startDate.timeIntervalSinceDate(glucose.startDate) <= recencyInterval &&
              startDate.timeIntervalSinceDate(pumpStatusDate) <= recencyInterval
        else {
            self.predictedGlucose = nil
            throw LoopError.StaleDataError("Glucose Date: \(glucose.startDate) or Pump status date: \(pumpStatusDate) older than \(recencyInterval.minutes) min")
        }

        guard let
            momentum = self.glucoseMomentumEffect,
            carbEffect = self.carbEffect,
            insulinEffect = self.insulinEffect else
        {
            self.predictedGlucose = nil
            throw LoopError.MissingDataError("Cannot predict glucose due to missing effect data")
        }

        var error: ErrorType?

        let prediction = LoopMath.predictGlucose(glucose, momentum: momentum, effects: carbEffect, insulinEffect)
        let predictionWithRetrospectiveEffect = LoopMath.predictGlucose(glucose, momentum: momentum, effects: carbEffect, insulinEffect, retrospectiveGlucoseEffect)

        let predictDiff: Double

        let unit = HKUnit.milligramsPerDeciliterUnit()
        if  let lastA = prediction.last?.quantity.doubleValueForUnit(unit),
            let lastB = predictionWithRetrospectiveEffect.last?.quantity.doubleValueForUnit(unit)
        {
            predictDiff = lastB - lastA
        } else {
            predictDiff = 0
        }

        defer {
            deviceDataManager.logger.addLoopStatus(
                startDate: startDate,
                endDate: NSDate(),
                glucose: glucose,
                effects: [
                    "momentum": momentum,
                    "carbs": carbEffect,
                    "insulin": insulinEffect,
                    "retrospective_glucose": retrospectiveGlucoseEffect
                ],
                error: error,
                prediction: prediction,
                predictionWithRetrospectiveEffect: predictDiff,
                recommendedTempBasal: recommendedTempBasal
            )
        }

        self.predictedGlucose = retrospectiveCorrectionEnabled ? predictionWithRetrospectiveEffect : prediction

        guard let
            maxBasal = deviceDataManager.maximumBasalRatePerHour,
            glucoseTargetRange = deviceDataManager.glucoseTargetRangeSchedule,
            insulinSensitivity = deviceDataManager.insulinSensitivitySchedule,
            basalRates = deviceDataManager.basalRateSchedule
        else {
            error = LoopError.MissingDataError("Loop configuration data not set")
            throw error!
        }

        if let tempBasal = DoseMath.recommendTempBasalFromPredictedGlucose(predictionWithRetrospectiveEffect,
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
            resultsHandler(units: nil, error: LoopError.MissingDataError("CarbStore not configured"))
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
            throw LoopError.MissingDataError("Bolus prediction and configuration data not found")
        }

        let recencyInterval = NSTimeInterval(minutes: 15)

        guard let predictedInterval = glucose.first?.startDate.timeIntervalSinceNow else {
            throw LoopError.MissingDataError("No glucose data found")
        }

        guard abs(predictedInterval) <= recencyInterval else {
            throw LoopError.StaleDataError("Glucose is \(predictedInterval.minutes) min old")
        }

        let pendingBolusAmount: Double = lastBolus?.units ?? 0

        return max(0, DoseMath.recommendBolusFromPredictedGlucose(glucose,
            lastTempBasal: self.lastTempBasal,
            maxBolus: maxBolus,
            glucoseTargetRange: glucoseTargetRange,
            insulinSensitivity: insulinSensitivity,
            basalRateSchedule: basalRates
        ) - pendingBolusAmount)
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
            resultsHandler(success: false, error: LoopError.StaleDataError("Recommended temp basal is \(recommendedTempBasal.recommendedDate.timeIntervalSinceNow.minutes) min old"))
            return
        }

        guard let device = self.deviceDataManager.rileyLinkManager.firstConnectedDevice else {
            resultsHandler(success: false, error: LoopError.ConnectionError)
            return
        }

        guard let ops = device.ops else {
            resultsHandler(success: false, error: LoopError.ConfigurationError)
            return
        }

        ops.setTempBasal(recommendedTempBasal.rate, duration: recommendedTempBasal.duration) { (result) -> Void in
            switch result {
            case .Success(let body):
                dispatch_async(self.dataAccessQueue) {
                    let now = NSDate()
                    let endDate = now.dateByAddingTimeInterval(body.timeRemaining)
                    let startDate = endDate.dateByAddingTimeInterval(-recommendedTempBasal.duration)

                    self.lastTempBasal = DoseEntry(type: .tempBasal, startDate: startDate, endDate: endDate, value: body.rate, unit: .unitsPerHour)
                    self.recommendedTempBasal = nil

                    resultsHandler(success: true, error: nil)
                }
            case .Failure(let error):
                resultsHandler(success: false, error: error)
            }
        }
    }

    func enactRecommendedTempBasal(resultsHandler: (success: Bool, error: ErrorType?) -> Void) {
        dispatch_async(dataAccessQueue) {
            self.setRecommendedTempBasal(resultsHandler)
        }
    }

    /**
     Informs the loop algorithm of an enacted bolus

     - parameter units: The amount of insulin
     - parameter date:  The date the bolus was set
     */
    func recordBolus(units: Double, atDate date: NSDate) {
        dispatch_async(dataAccessQueue) {
            self.lastBolus = (units: units, date: date)
            self.notify(forChange: .Bolus)
        }
    }
}
