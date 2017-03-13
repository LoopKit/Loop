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
        case bolus
        case carbs
        case glucose
        case preferences
        case tempBasal
    }

    static let LoopUpdateContextKey = "com.loudnate.Loop.LoopDataManager.LoopUpdateContext"

    typealias TempBasalRecommendation = (recommendedDate: Date, rate: Double, duration: TimeInterval)

    private typealias GlucoseChange = (GlucoseValue, GlucoseValue)

    unowned let deviceDataManager: DeviceDataManager

    var dosingEnabled: Bool {
        didSet {
            UserDefaults.standard.dosingEnabled = dosingEnabled

            notify(forChange: .preferences)
        }
    }

    var retrospectiveCorrectionEnabled: Bool {
        didSet {
            UserDefaults.standard.retrospectiveCorrectionEnabled = retrospectiveCorrectionEnabled

            notify(forChange: .preferences)
        }
    }

    init(deviceDataManager: DeviceDataManager, lastLoopCompleted: Date?) {
        self.deviceDataManager = deviceDataManager
        self.lastLoopCompleted = lastLoopCompleted

        dosingEnabled = UserDefaults.standard.dosingEnabled
        retrospectiveCorrectionEnabled = UserDefaults.standard.retrospectiveCorrectionEnabled

        // Observe changes
        let center = NotificationCenter.default

        notificationObservers = [
            center.addObserver(forName: .GlucoseUpdated, object: deviceDataManager, queue: nil) { (note) -> Void in
                self.dataAccessQueue.async {
                    self.glucoseMomentumEffect = nil
                    self.glucoseChange = nil
                    self.notify(forChange: .glucose)
                }
            },
            center.addObserver(forName: .PumpStatusUpdated, object: deviceDataManager, queue: nil) { (note) -> Void in
                self.dataAccessQueue.async {
                    // Assuming insulin data is never back-dated, we don't need to remove the retrospective glucose effects
                    // TODO: What about a deletion?
                    self.insulinEffect = nil
                    self.insulinOnBoard = nil
                    self.loop()
                }
            },
            center.addObserver(forName: .CarbEntriesDidUpdate, object: nil, queue: nil) { (note) -> Void in
                self.dataAccessQueue.async {
                    self.carbEffect = nil
                    self.carbsOnBoardSeries = nil
                    self.notify(forChange: .carbs)
                }
            }
        ]
    }

    // Actions

    private func loop() {
        NotificationCenter.default.post(name: .LoopRunning, object: self)

        lastLoopError = nil

        do {
            try self.update()

            if dosingEnabled {

                setRecommendedTempBasal { (success, error) -> Void in
                    self.lastLoopError = error

                    if let error = error {
                        self.deviceDataManager.logger.addError(error, fromSource: "TempBasal")
                    } else {
                        self.lastLoopCompleted = Date()
                    }
                    self.notify(forChange: .tempBasal)
                }

                // Delay the notification until we know the result of the temp basal
                return
            } else {
                lastLoopCompleted = Date()
            }
        } catch let error {
            lastLoopError = error
        }

        notify(forChange: .tempBasal)
    }

    // References to registered notification center observers
    private var notificationObservers: [Any] = []

    deinit {
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func update() throws {
        let updateGroup = DispatchGroup()

        guard let glucoseStore = deviceDataManager.glucoseStore else {
            throw LoopError.configurationError("GlucoseStore")
        }

        // Fetch glucose effects as far back as we want to make retroactive analysis
        guard let effectStartDate = glucoseStore.latestGlucose?.startDate.addingTimeInterval(-glucoseStore.reflectionDataInterval) else {
            throw LoopError.missingDataError(details: "Glucose data not available", recovery: "Check your CGM data source")
        }

        if glucoseChange == nil {
            updateGroup.enter()
            glucoseStore.getRecentGlucoseChange { (values, error) in
                if let error = error {
                    self.deviceDataManager.logger.addError(error, fromSource: "GlucoseStore")
                }

                self.glucoseChange = values
                updateGroup.leave()
            }
        }

        if glucoseMomentumEffect == nil {
            updateGroup.enter()
            glucoseStore.getRecentMomentumEffect { (effects, error) -> Void in
                if let error = error, effects.count == 0 {
                    self.deviceDataManager.logger.addError(error, fromSource: "GlucoseStore")
                    self.glucoseMomentumEffect = nil
                } else {
                    self.glucoseMomentumEffect = effects
                }

                updateGroup.leave()
            }
        }

        if let carbStore = deviceDataManager.carbStore {
            if carbEffect == nil {
                updateGroup.enter()

                carbStore.getGlucoseEffects(startDate: effectStartDate) { (effects, error) -> Void in
                    if let error = error {
                        self.deviceDataManager.logger.addError(error, fromSource: "CarbStore")
                        self.carbEffect = nil
                    } else {
                        self.carbEffect = effects
                    }

                    updateGroup.leave()
                }
            }

            if carbsOnBoardSeries == nil {
                updateGroup.enter()
                carbStore.getCarbsOnBoardValues(startDate: effectStartDate) { (values, error) in
                    if let error = error {
                        self.deviceDataManager.logger.addError(error, fromSource: "CarbStore")
                    }

                    self.carbsOnBoardSeries = values
                    updateGroup.leave()
                }
            }
        }

        if insulinEffect == nil {
            updateGroup.enter()
            deviceDataManager.doseStore.getGlucoseEffects(startDate: effectStartDate) { (effects, error) -> Void in
                if let error = error {
                    self.deviceDataManager.logger.addError(error, fromSource: "DoseStore")
                    self.insulinEffect = nil
                } else {
                    self.insulinEffect = effects
                }

                updateGroup.leave()
            }
        }

        if insulinOnBoard == nil {
            updateGroup.enter()
            deviceDataManager.doseStore.insulinOnBoardAtDate(Date()) { (value, error) in
                if let error = error {
                    self.deviceDataManager.logger.addError(error, fromSource: "DoseStore")
                    self.insulinOnBoard = nil
                } else {
                    self.insulinOnBoard = value
                }
                updateGroup.leave()
            }
        }

        _ = updateGroup.wait(timeout: DispatchTime.distantFuture)

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
        NotificationCenter.default.post(name: .LoopDataUpdated,
            object: self,
            userInfo: [type(of: self).LoopUpdateContextKey: context.rawValue]
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
        - carbsOnBoard          Current carbs on board
        - error:                An error in the current state of the loop, or one that happened during the last attempt to loop.
     */
    func getLoopStatus(_ resultsHandler: @escaping (_ predictedGlucose: [GlucoseValue]?, _ retrospectivePredictedGlucose: [GlucoseValue]?, _ recommendedTempBasal: TempBasalRecommendation?, _ lastTempBasal: DoseEntry?, _ lastLoopCompleted: Date?, _ insulinOnBoard: InsulinValue?, _ carbsOnBoard: CarbValue?, _ error: Error?) -> Void) {
        dataAccessQueue.async {
            var error: Error?

            do {
                try self.update()
            } catch let updateError {
                error = updateError
            }

            let currentCOB = self.carbsOnBoardSeries?.closestPriorToDate(Date())

            resultsHandler(self.predictedGlucose, self.retrospectivePredictedGlucose, self.recommendedTempBasal, self.lastTempBasal, self.lastLoopCompleted, self.insulinOnBoard, currentCOB, error ?? self.lastLoopError)
        }
    }



    /**
     Computes amount of insulin from boluses that have been issued and not confirmed, and
     remaining insulin delivery from temporary basal rate adjustments above scheduled rate 
     that are still in progress.

     *This method should only be called from the `dataAccessQueue`*

     **/
    private func getPendingInsulin() throws -> Double {

        guard let basalRates = deviceDataManager.basalRateSchedule else {
            throw LoopError.configurationError("Basal Rate Schedule")
        }

        let pendingTempBasalInsulin: Double
        let date = Date()

        if let lastTempBasal = lastTempBasal, lastTempBasal.unit == .unitsPerHour && lastTempBasal.endDate > date {
            let normalBasalRate = basalRates.value(at: date)
            let remainingTime = lastTempBasal.endDate.timeIntervalSince(date)
            let remainingUnits = (lastTempBasal.value - normalBasalRate) * remainingTime / TimeInterval(hours: 1)

            pendingTempBasalInsulin = max(0, remainingUnits)
        } else {
            pendingTempBasalInsulin = 0
        }

        let pendingBolusAmount: Double = lastBolus?.units ?? 0

        // All outstanding potential insulin delivery
        return pendingTempBasalInsulin + pendingBolusAmount
    }

    func modelPredictedGlucose(using inputs: [PredictionInputEffect], resultsHandler: @escaping (_ predictedGlucose: [GlucoseValue]?, _ error: Error?) -> Void) {
        dataAccessQueue.async { 
            guard let
                glucose = self.deviceDataManager.glucoseStore?.latestGlucose
            else {
                resultsHandler(nil, LoopError.missingDataError(details: "Cannot predict glucose due to missing input data", recovery: "Check your CGM data source"))
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

            resultsHandler(prediction, nil)
        }
    }

    // Calculation

    private let dataAccessQueue: DispatchQueue = DispatchQueue(label: "com.loudnate.Naterade.LoopDataManager.dataAccessQueue", qos: .utility)

    private var carbEffect: [GlucoseEffect]? {
        didSet {
            predictedGlucose = nil

            // Carb data may be back-dated, so re-calculate the retrospective glucose.
            retrospectivePredictedGlucose = nil
        }
    }
    private var carbsOnBoardSeries: [CarbValue]?
    private var insulinEffect: [GlucoseEffect]? {
        didSet {
            if let bolusDate = lastBolus?.date, bolusDate.timeIntervalSinceNow < TimeInterval(minutes: -5) {
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
            predictedGlucoseWithoutMomentum = nil
        }
    }
    private var predictedGlucoseWithoutMomentum: [GlucoseValue]?
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
    private var lastBolus: (units: Double, date: Date)?
    private var lastLoopError: Error? {
        didSet {
            if lastLoopError != nil {
                AnalyticsManager.sharedManager.loopDidError()
            }
        }
    }
    private var lastLoopCompleted: Date? {
        didSet {
            NotificationManager.scheduleLoopNotRunningNotifications()

            AnalyticsManager.sharedManager.loopDidSucceed()
        }
    }

    var lastNetBasal: NetBasal? {
        get {
            guard
                let scheduledBasal = deviceDataManager.basalRateSchedule?.between(start: Date(), end: Date()).first
            else {
                return nil
            }

            return NetBasal(lastTempBasal: lastTempBasal,
                            maxBasal: deviceDataManager.maximumBasalRatePerHour,
                            scheduledBasal: scheduledBasal)
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
            throw LoopError.missingDataError(details: "Cannot retrospect glucose due to missing input data", recovery: nil)
        }

        guard let change = glucoseChange else {
            self.retrospectivePredictedGlucose = nil
            return  // Expected case for calibrations
        }

        // Run a retrospective prediction over the duration of the recorded glucose change, using the current carb and insulin effects
        let startDate = change.0.startDate
        let endDate = change.1.endDate.addingTimeInterval(TimeInterval(minutes: 5))
        let retrospectivePrediction = LoopMath.predictGlucose(change.0, effects:
            carbEffect.filterDateRange(startDate, endDate),
            insulinEffect.filterDateRange(startDate, endDate)
        )

        self.retrospectivePredictedGlucose = retrospectivePrediction

        guard let lastGlucose = retrospectivePrediction.last else { return }
        let glucoseUnit = HKUnit.milligramsPerDeciliterUnit()
        let velocityUnit = glucoseUnit.unitDivided(by: HKUnit.second())

        let discrepancy = change.1.quantity.doubleValue(for: glucoseUnit) - lastGlucose.quantity.doubleValue(for: glucoseUnit) // mg/dL
        let velocity = HKQuantity(unit: velocityUnit, doubleValue: discrepancy / change.1.endDate.timeIntervalSince(change.0.endDate))
        let type = HKQuantityType.quantityType(forIdentifier: HKQuantityTypeIdentifier.bloodGlucose)!
        let glucose = HKQuantitySample(type: type, quantity: change.1.quantity, start: change.1.startDate, end: change.1.endDate)

        self.retrospectiveGlucoseEffect = LoopMath.decayEffect(from: glucose, atRate: velocity, for: TimeInterval(minutes: 60))
    }

    /**
     Runs the glucose prediction on the latest effect data.
     
     *This method should only be called from the `dataAccessQueue`*
     */
    private func updatePredictedGlucoseAndRecommendedBasal() throws {
        guard let
            glucose = self.deviceDataManager.glucoseStore?.latestGlucose
            else {
                self.predictedGlucose = nil
                throw LoopError.missingDataError(details: "Glucose", recovery: "Check your CGM data source")
        }

        guard let
            pumpStatusDate = self.deviceDataManager.doseStore.lastReservoirValue?.startDate
        else {
            self.predictedGlucose = nil
            throw LoopError.missingDataError(details: "Reservoir", recovery: "Check that your pump is in range")
        }

        let startDate = Date()
        let recencyInterval = TimeInterval(minutes: 15)

        guard startDate.timeIntervalSince(glucose.startDate) <= recencyInterval
        else {
            self.predictedGlucose = nil
            throw LoopError.glucoseTooOld(date: glucose.startDate)
        }

        guard startDate.timeIntervalSince(pumpStatusDate) <= recencyInterval
        else {
            self.predictedGlucose = nil
            throw LoopError.pumpDataTooOld(date: pumpStatusDate)
        }

        guard let
            momentum = self.glucoseMomentumEffect,
            let carbEffect = self.carbEffect,
            let insulinEffect = self.insulinEffect else
        {
            self.predictedGlucose = nil
            throw LoopError.missingDataError(details: "Glucose effects", recovery: nil)
        }

        var error: Error?

        let prediction = LoopMath.predictGlucose(glucose, momentum: momentum, effects: carbEffect, insulinEffect)
        let predictionWithRetrospectiveEffect = LoopMath.predictGlucose(glucose, momentum: momentum, effects: carbEffect, insulinEffect, retrospectiveGlucoseEffect)
        let predictionWithoutMomentum = LoopMath.predictGlucose(glucose, effects: carbEffect, insulinEffect)

        let predictDiff: Double

        let unit = HKUnit.milligramsPerDeciliterUnit()
        if  let lastA = prediction.last?.quantity.doubleValue(for: unit),
            let lastB = predictionWithRetrospectiveEffect.last?.quantity.doubleValue(for: unit)
        {
            predictDiff = lastB - lastA
        } else {
            predictDiff = 0
        }

        let eventualBGWithRetrospectiveEffect: Double = predictionWithRetrospectiveEffect.last?.quantity.doubleValue(for: unit) ?? 0
        let eventualBGWithoutMomentum: Double = predictionWithoutMomentum.last?.quantity.doubleValue(for: unit) ?? 0

        defer {
            deviceDataManager.logger.addLoopStatus(
                startDate: startDate,
                endDate: Date(),
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
                eventualBGWithRetrospectiveEffect: eventualBGWithRetrospectiveEffect,
                eventualBGWithoutMomentum: eventualBGWithoutMomentum,
                recommendedTempBasal: recommendedTempBasal
            )
        }

        self.predictedGlucose = retrospectiveCorrectionEnabled ? predictionWithRetrospectiveEffect : prediction
        self.predictedGlucoseWithoutMomentum = predictionWithoutMomentum

        guard let minimumBGGuard = self.deviceDataManager.minimumBGGuard else {
            throw LoopError.configurationError("Minimum BG Guard")
        }

        guard let
            maxBasal = deviceDataManager.maximumBasalRatePerHour,
            let glucoseTargetRange = deviceDataManager.glucoseTargetRangeSchedule,
            let insulinSensitivity = deviceDataManager.insulinSensitivitySchedule,
            let basalRates = deviceDataManager.basalRateSchedule
        else {
            error = LoopError.configurationError("Check settings")
            throw error!
        }

        guard
            lastBolus == nil,  // Don't recommend changes if a bolus was just set
            let predictedGlucose = self.predictedGlucose,
            let tempBasal = DoseMath.recommendTempBasalFromPredictedGlucose(predictedGlucose,
                lastTempBasal: lastTempBasal,
                maxBasalRate: maxBasal,
                glucoseTargetRange: glucoseTargetRange,
                insulinSensitivity: insulinSensitivity,
                basalRateSchedule: basalRates,
                minimumBGGuard: minimumBGGuard
            )
        else {
            recommendedTempBasal = nil
            return
        }

        recommendedTempBasal = (recommendedDate: Date(), rate: tempBasal.rate, duration: tempBasal.duration)
    }

    func addCarbEntryAndRecommendBolus(_ carbEntry: CarbEntry, resultsHandler: @escaping (_ recommendation: BolusRecommendation?, _ error: Error?) -> Void) {
        if let carbStore = deviceDataManager.carbStore {
            carbStore.addCarbEntry(carbEntry) { (success, _, error) in
                self.dataAccessQueue.async {
                    if success {
                        self.carbEffect = nil
                        self.carbsOnBoardSeries = nil

                        do {
                            try self.update()

                            resultsHandler(try self.recommendBolus(), nil)
                        } catch let error {
                            resultsHandler(nil, error)
                        }
                    } else {
                        resultsHandler(nil, error)
                    }
                }
            }
        } else {
            resultsHandler(nil, LoopError.configurationError("Carb Store"))
        }
    }

    private func recommendBolus() throws -> BolusRecommendation {
        guard let minimumBGGuard = self.deviceDataManager.minimumBGGuard else {
            throw LoopError.configurationError("Minimum BG Guard")
        }

        guard let
            glucose = self.predictedGlucose,
            let glucoseWithoutMomentum = self.predictedGlucoseWithoutMomentum,
            let maxBolus = self.deviceDataManager.maximumBolus,
            let glucoseTargetRange = self.deviceDataManager.glucoseTargetRangeSchedule,
            let insulinSensitivity = self.deviceDataManager.insulinSensitivitySchedule,
            let basalRates = self.deviceDataManager.basalRateSchedule
        else {
            throw LoopError.configurationError("Check Settings")
        }

        let recencyInterval = TimeInterval(minutes: 15)
        
        guard let glucoseDate = glucose.first?.startDate else {
            throw LoopError.missingDataError(details: "No glucose data found", recovery: "Check your CGM source")
        }

        guard abs(glucoseDate.timeIntervalSinceNow) <= recencyInterval else {
            throw LoopError.glucoseTooOld(date: glucoseDate)
        }

        let pendingInsulin = try self.getPendingInsulin()

        let recommendationWithMomentum = DoseMath.recommendBolusFromPredictedGlucose(glucose,
            maxBolus: maxBolus,
            glucoseTargetRange: glucoseTargetRange,
            insulinSensitivity: insulinSensitivity,
            basalRateSchedule: basalRates,
            pendingInsulin: pendingInsulin,
            minimumBGGuard: minimumBGGuard
        )

        let recommendationWithoutMomentum = DoseMath.recommendBolusFromPredictedGlucose(glucoseWithoutMomentum,
            maxBolus: maxBolus,
            glucoseTargetRange: glucoseTargetRange,
            insulinSensitivity: insulinSensitivity,
            basalRateSchedule: basalRates,
            pendingInsulin: pendingInsulin,
            minimumBGGuard: minimumBGGuard
        )
        
        if (recommendationWithMomentum.amount > recommendationWithoutMomentum.amount) {
            return recommendationWithoutMomentum
        } else {
            return recommendationWithMomentum
        }
    }

    func getRecommendedBolus(_ resultsHandler: @escaping (_ units: BolusRecommendation?, _ error: Error?) -> Void) {
        dataAccessQueue.async {
            do {
                let recommendation = try self.recommendBolus()
                resultsHandler(recommendation, nil)
            } catch let error {
                resultsHandler(nil, error)
            }
        }
    }

    private func setRecommendedTempBasal(_ resultsHandler: @escaping (_ success: Bool, _ error: Error?) -> Void) {
        guard let recommendedTempBasal = self.recommendedTempBasal else {
            resultsHandler(true, nil)
            return
        }

        guard abs(recommendedTempBasal.recommendedDate.timeIntervalSinceNow) < TimeInterval(minutes: 5) else {
            resultsHandler(false, LoopError.recommendationExpired(date: recommendedTempBasal.recommendedDate))
            return
        }

        guard let device = self.deviceDataManager.rileyLinkManager.firstConnectedDevice else {
            resultsHandler(false, LoopError.connectionError)
            return
        }

        guard let ops = device.ops else {
            resultsHandler(false, LoopError.configurationError("PumpOps"))
            return
        }

        ops.setTempBasal(rate: recommendedTempBasal.rate, duration: recommendedTempBasal.duration) { (result) -> Void in
            switch result {
            case .success(let body):
                self.dataAccessQueue.async {
                    let now = Date()
                    let endDate = now.addingTimeInterval(body.timeRemaining)
                    let startDate = endDate.addingTimeInterval(-recommendedTempBasal.duration)

                    self.lastTempBasal = DoseEntry(type: .tempBasal, startDate: startDate, endDate: endDate, value: body.rate, unit: .unitsPerHour)
                    self.recommendedTempBasal = nil

                    resultsHandler(true, nil)
                }
            case .failure(let error):
                resultsHandler(false, error)
            }
        }
    }

    func enactRecommendedTempBasal(_ resultsHandler: @escaping (_ success: Bool, _ error: Error?) -> Void) {
        dataAccessQueue.async {
            self.setRecommendedTempBasal(resultsHandler)
        }
    }
    
    /**
     Informs the loop algorithm of an enacted bolus

     - parameter units: The amount of insulin
     - parameter date:  The date the bolus was set
     */
    func recordBolus(_ units: Double, at date: Date) {
        dataAccessQueue.async {
            self.lastBolus = (units: units, date: date)
            self.notify(forChange: .bolus)
        }
    }
}

extension LoopDataManager {
    /// Generates a diagnostic report about the current state
    ///
    /// This operation is performed asynchronously and the completion will be executed on an arbitrary background queue.
    ///
    /// - parameter completionHandler: A closure called once the report has been generated. The closure takes a single argument of the report string.
    func generateDiagnosticReport(_ completionHandler: @escaping (_ report:     String) -> Void) {
        getLoopStatus { (predictedGlucose, retrospectivePredictedGlucose, recommendedTempBasal, lastTempBasal, lastLoopCompleted, insulinOnBoard, carbsOnBoard, error) in
            let report = [
                "## LoopDataManager",
                "predictedGlucose: \(predictedGlucose ?? [])",
                "retrospectivePredictedGlucose: \(retrospectivePredictedGlucose ?? [])",
                "recommendedTempBasal: \(recommendedTempBasal)",
                "lastTempBasal: \(lastTempBasal)",
                "lastLoopCompleted: \(lastLoopCompleted ?? .distantPast)",
                "insulinOnBoard: \(insulinOnBoard)",
                "carbsOnBoard: \(carbsOnBoard)",
                "error: \(error)"
            ]
            completionHandler(report.joined(separator: "\n"))
        }
    }
}


extension Notification.Name {
    static let LoopDataUpdated = Notification.Name(rawValue:  "com.loudnate.Naterade.notification.LoopDataUpdated")

    static let LoopRunning = Notification.Name(rawValue: "com.loudnate.Naterade.notification.LoopRunning")
}
