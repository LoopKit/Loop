//
//  LoopDataManager.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 3/12/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation
import CarbKit
import GlucoseKit
import HealthKit
import InsulinKit
import LoopKit


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

    private typealias GlucoseChange = (start: GlucoseValue, end: GlucoseValue)

    let carbStore: CarbStore!

    let doseStore: DoseStore

    let glucoseStore: GlucoseStore! = GlucoseStore()

    unowned let delegate: LoopDataManagerDelegate

    private let logger = DiagnosticLogger()

    init(
        delegate: LoopDataManagerDelegate,
        lastLoopCompleted: Date?,
        pumpID: String?,
        basalRateSchedule: BasalRateSchedule? = UserDefaults.standard.basalRateSchedule,
        carbRatioSchedule: CarbRatioSchedule? = UserDefaults.standard.carbRatioSchedule,
        insulinActionDuration: TimeInterval? = UserDefaults.standard.insulinActionDuration,
        insulinSensitivitySchedule: InsulinSensitivitySchedule? = UserDefaults.standard.insulinSensitivitySchedule,
        settings: LoopSettings = UserDefaults.standard.loopSettings ?? LoopSettings()
    ) {
        self.delegate = delegate
        self.lastLoopCompleted = lastLoopCompleted
        self.settings = settings

        carbStore = CarbStore(
            defaultAbsorptionTimes: (
                fast: TimeInterval(hours: 2),
                medium: TimeInterval(hours: 3),
                slow: TimeInterval(hours: 4)
            ),
            carbRatioSchedule: carbRatioSchedule,
            insulinSensitivitySchedule: insulinSensitivitySchedule
        )

        doseStore = DoseStore(
            pumpID: pumpID,
            insulinActionDuration: insulinActionDuration,
            basalProfile: basalRateSchedule,
            insulinSensitivitySchedule: insulinSensitivitySchedule
        )

        // Observe changes
        carbUpdateObserver = NotificationCenter.default.addObserver(
            forName: .CarbEntriesDidUpdate,
            object: nil,
            queue: nil
        ) { (note) -> Void in
            self.dataAccessQueue.async {
                self.carbEffect = nil
                self.carbsOnBoardSeries = nil
                self.notify(forChange: .carbs)
            }
        }
    }

    // MARK: - Preferences

    /// Loop-related settings
    ///
    /// These are not thread-safe.
    var settings: LoopSettings {
        didSet {
            UserDefaults.standard.loopSettings = settings
            notify(forChange: .preferences)
            AnalyticsManager.sharedManager.didChangeLoopSettings(from: oldValue, to: settings)
        }
    }

    /// The daily schedule of basal insulin rates
    var basalRateSchedule: BasalRateSchedule? {
        get {
            return doseStore.basalProfile
        }
        set {
            doseStore.basalProfile = newValue
            UserDefaults.standard.basalRateSchedule = newValue
            notify(forChange: .preferences)
        }
    }

    /// The daily schedule of carbs-to-insulin ratios
    /// This is measured in grams/Unit
    var carbRatioSchedule: CarbRatioSchedule? {
        get {
            return carbStore.carbRatioSchedule
        }
        set {
            carbStore.carbRatioSchedule = newValue
            UserDefaults.standard.carbRatioSchedule = newValue
            notify(forChange: .preferences)
        }
    }

    /// Enable workout glucose targets until the given date
    ///
    /// TODO: When schedule settings are migrated to structs, this can be simplified
    ///
    /// - Parameter endDate: The date the workout targets should end
    /// - Returns: True if the override was set
    @discardableResult
    func enableWorkoutMode(until endDate: Date) -> Bool {
        guard let glucoseTargetRangeSchedule = settings.glucoseTargetRangeSchedule else {
            return false
        }

        _ = glucoseTargetRangeSchedule.setWorkoutOverride(until: endDate)

        notify(forChange: .preferences)

        return true
    }

    /// Disable any active workout glucose targets
    func disableWorkoutMode() {
        settings.glucoseTargetRangeSchedule?.clearOverride()

        notify(forChange: .preferences)
    }

    /// The length of time insulin has an effect on blood glucose
    var insulinActionDuration: TimeInterval? {
        get {
            return doseStore.insulinActionDuration
        }
        set {
            let oldValue = doseStore.insulinActionDuration
            doseStore.insulinActionDuration = newValue

            UserDefaults.standard.insulinActionDuration = newValue

            if oldValue != newValue {
                AnalyticsManager.sharedManager.didChangeInsulinActionDuration()
            }
        }
    }

    /// The daily schedule of insulin sensitivity (also known as ISF)
    /// This is measured in <blood glucose>/Unit
    var insulinSensitivitySchedule: InsulinSensitivitySchedule? {
        get {
            return carbStore.insulinSensitivitySchedule
        }
        set {
            carbStore.insulinSensitivitySchedule = newValue
            doseStore.insulinSensitivitySchedule = newValue

            UserDefaults.standard.insulinSensitivitySchedule = newValue

            notify(forChange: .preferences)
        }
    }

    /// Sets a new time zone for a the schedule-based settings
    ///
    /// - Parameter timeZone: The time zone
    func setScheduleTimeZone(_ timeZone: TimeZone) {
        // Recreate each schedule to force a change notification
        // TODO: When schedule settings are migrated to structs, this can be simplified
        if let basalRateSchedule = basalRateSchedule {
            self.basalRateSchedule = BasalRateSchedule(dailyItems: basalRateSchedule.items, timeZone: timeZone)
        }

        if let carbRatioSchedule = carbRatioSchedule {
            self.carbRatioSchedule = CarbRatioSchedule(unit: carbRatioSchedule.unit, dailyItems: carbRatioSchedule.items, timeZone: timeZone)
        }

        if let insulinSensitivitySchedule = insulinSensitivitySchedule {
            self.insulinSensitivitySchedule = InsulinSensitivitySchedule(unit: insulinSensitivitySchedule.unit, dailyItems: insulinSensitivitySchedule.items, timeZone: timeZone)
        }

        if let glucoseTargetRangeSchedule = settings.glucoseTargetRangeSchedule {
            settings.glucoseTargetRangeSchedule = GlucoseRangeSchedule(unit: glucoseTargetRangeSchedule.unit, dailyItems: glucoseTargetRangeSchedule.items, workoutRange: glucoseTargetRangeSchedule.workoutRange, timeZone: timeZone)
        }
    }

    // MARK: - Intake

    /// Adds and stores glucose data
    ///
    /// - Parameters:
    ///   - values: The new glucose values to store
    ///   - device: The device that captured the data
    ///   - completion: A closure called once upon completion
    ///   - result: The stored glucose values
    func addGlucose(
        _ values: [(quantity: HKQuantity, date: Date, isDisplayOnly: Bool)],
        from device: HKDevice?,
        completion: ((_ result: Result<[GlucoseValue]>) -> Void)? = nil
    ) {
        glucoseStore.addGlucoseValues(values, device: device) { (success, values, error) in
            if success {
                self.dataAccessQueue.async {
                    self.glucoseMomentumEffect = nil
                    self.glucoseChange = nil
                    self.notify(forChange: .glucose)
                }
            }

            if let error = error {
                completion?(.failure(error))
            } else {
                completion?(.success(values ?? []))
            }
        }
    }

    /// Adds and stores carb data, and recommends a bolus if needed
    ///
    /// - Parameters:
    ///   - carbEntry: The new carb value
    ///   - completion: A closure called once upon completion
    ///   - result: The bolus recommendation
    func addCarbEntryAndRecommendBolus(_ carbEntry: CarbEntry, completion: @escaping (_ result: Result<BolusRecommendation?>) -> Void) {
        carbStore.addCarbEntry(carbEntry) { (success, _, error) in
            self.dataAccessQueue.async {
                if success {
                    self.carbEffect = nil
                    self.carbsOnBoardSeries = nil

                    defer {
                        self.notify(forChange: .carbs)
                    }

                    do {
                        try self.update()

                        completion(.success(try self.recommendBolus()))
                    } catch let error {
                        completion(.failure(error))
                    }
                } else if let error = error {
                    completion(.failure(error))
                } else {
                    completion(.success(nil))
                }
            }
        }
    }

    /// Adds a bolus enacted by the pump, but not fully delivered.
    ///
    /// - Parameters:
    ///   - units: The bolus amount, in units
    ///   - date: The date the bolus was enacted
    func addExpectedBolus(_ units: Double, at date: Date) {
        dataAccessQueue.async {
            self.lastBolus = (units: units, date: date)
            self.notify(forChange: .bolus)
        }
    }

    /// Adds and stores new pump events
    ///
    /// - Parameters:
    ///   - events: The pump events to add
    ///   - completion: A closure called once upon completion
    ///   - error: An error explaining why the events could not be saved.
    func addPumpEvents(_ events: [NewPumpEvent], completion: @escaping (_ error: DoseStore.DoseStoreError?) -> Void) {
        doseStore.addPumpEvents(events) { (error) in
            if error != nil {
                self.insulinEffect = nil
                self.insulinOnBoard = nil
            }

            completion(error)
        }
    }

    /// Adds and stores a pump reservoir volume
    ///
    /// - Parameters:
    ///   - units: The reservoir volume, in units
    ///   - date: The date of the volume reading
    ///   - completion: A closure called once upon completion
    ///   - result: The current state of the reservoir values:
    ///       - newValue: The new stored value
    ///       - lastValue: The previous new stored value
    ///       - areStoredValuesContinuous: Whether the current recent state of the stored reservoir data is considered continuous and reliable for deriving insulin effects after addition of this new value.
    func addReservoirValue(_ units: Double, at date: Date, completion: @escaping (_ result: Result<(newValue: ReservoirValue, lastValue: ReservoirValue?, areStoredValuesContinuous: Bool)>) -> Void) {
        doseStore.addReservoirValue(units, atDate: date) { (newValue, previousValue, areStoredValuesContinuous, error) in
            if let error = error {
                completion(.failure(error))
            } else if let newValue = newValue {
                self.insulinEffect = nil
                self.insulinOnBoard = nil

                completion(.success((
                    newValue: newValue,
                    lastValue: previousValue,
                    areStoredValuesContinuous: areStoredValuesContinuous
                )))
            } else {
                assertionFailure()
            }
        }
    }

    // Actions

    /// Runs the "loop"
    ///
    /// Executes an analysis of the current data, and recommends an adjustment to the current
    /// temporary basal rate.
    func loop() {
        self.dataAccessQueue.async {
            NotificationCenter.default.post(name: .LoopRunning, object: self)

            self.lastLoopError = nil

            do {
                try self.update()

                if self.settings.dosingEnabled {
                    self.setRecommendedTempBasal { (success, error) -> Void in
                        self.lastLoopError = error

                        if let error = error {
                            self.logger.addError(error, fromSource: "TempBasal")
                        } else {
                            self.lastLoopCompleted = Date()
                        }
                        self.notify(forChange: .tempBasal)
                    }

                    // Delay the notification until we know the result of the temp basal
                    return
                } else {
                    self.lastLoopCompleted = Date()
                }
            } catch let error {
                self.lastLoopError = error
            }

            self.notify(forChange: .tempBasal)
        }
    }

    // References to registered notification center observers
    private var carbUpdateObserver: Any?

    deinit {
        if let observer = carbUpdateObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func update() throws {
        let updateGroup = DispatchGroup()

        // Fetch glucose effects as far back as we want to make retroactive analysis
        guard let effectStartDate = glucoseStore.latestGlucose?.startDate.addingTimeInterval(-glucoseStore.reflectionDataInterval) else {
            throw LoopError.missingDataError(details: "Glucose data not available", recovery: "Check your CGM data source")
        }

        if glucoseChange == nil {
            updateGroup.enter()
            glucoseStore.getRecentGlucoseChange { (values, error) in
                if let error = error {
                    self.logger.addError(error, fromSource: "GlucoseStore")
                }

                self.glucoseChange = values
                updateGroup.leave()
            }
        }

        if glucoseMomentumEffect == nil {
            updateGroup.enter()
            glucoseStore.getRecentMomentumEffect { (effects, error) -> Void in
                if let error = error, effects.count == 0 {
                    self.logger.addError(error, fromSource: "GlucoseStore")
                    self.glucoseMomentumEffect = nil
                } else {
                    self.glucoseMomentumEffect = effects
                }

                updateGroup.leave()
            }
        }

        if carbEffect == nil {
            updateGroup.enter()

            carbStore.getGlucoseEffects(startDate: effectStartDate) { (effects, error) -> Void in
                if let error = error {
                    self.logger.addError(error, fromSource: "CarbStore")
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
                    self.logger.addError(error, fromSource: "CarbStore")
                }

                self.carbsOnBoardSeries = values
                updateGroup.leave()
            }
        }

        if insulinEffect == nil {
            updateGroup.enter()
            doseStore.getGlucoseEffects(start: effectStartDate) { (result) -> Void in
                switch result {
                case .failure(let error):
                    self.logger.addError(error, fromSource: "DoseStore")
                    self.insulinEffect = nil
                case .success(let effects):
                    self.insulinEffect = effects
                }

                updateGroup.leave()
            }
        }

        if insulinOnBoard == nil {
            updateGroup.enter()
            doseStore.insulinOnBoard(at: Date()) { (result) in
                switch result {
                case .failure(let error):
                    self.logger.addError(error, fromSource: "DoseStore")
                    self.insulinOnBoard = nil
                case .success(let value):
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
                self.logger.addError(error, fromSource: "RetrospectiveGlucose")
            }
        }

        if self.predictedGlucose == nil {
            do {
                try self.updatePredictedGlucoseAndRecommendedBasal()
            } catch let error {
                self.logger.addError(error, fromSource: "PredictGlucose")

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
        guard let basalRates = basalRateSchedule else {
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
            guard let glucose = self.glucoseStore.latestGlucose else {
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
        let startDate = change.start.startDate
        let endDate = change.end.endDate.addingTimeInterval(TimeInterval(minutes: 5))
        let retrospectivePrediction = LoopMath.predictGlucose(change.start, effects:
            carbEffect.filterDateRange(startDate, endDate),
            insulinEffect.filterDateRange(startDate, endDate)
        )

        self.retrospectivePredictedGlucose = retrospectivePrediction

        guard let lastGlucose = retrospectivePrediction.last else { return }
        let glucoseUnit = HKUnit.milligramsPerDeciliterUnit()
        let velocityUnit = glucoseUnit.unitDivided(by: HKUnit.second())

        let discrepancy = change.end.quantity.doubleValue(for: glucoseUnit) - lastGlucose.quantity.doubleValue(for: glucoseUnit) // mg/dL
        let velocity = HKQuantity(unit: velocityUnit, doubleValue: discrepancy / change.end.endDate.timeIntervalSince(change.0.endDate))
        let type = HKQuantityType.quantityType(forIdentifier: HKQuantityTypeIdentifier.bloodGlucose)!
        let glucose = HKQuantitySample(type: type, quantity: change.end.quantity, start: change.end.startDate, end: change.end.endDate)

        self.retrospectiveGlucoseEffect = LoopMath.decayEffect(from: glucose, atRate: velocity, for: TimeInterval(minutes: 60))
    }

    /**
     Runs the glucose prediction on the latest effect data.
     
     *This method should only be called from the `dataAccessQueue`*
     */
    private func updatePredictedGlucoseAndRecommendedBasal() throws {
        guard let glucose = glucoseStore.latestGlucose else {
            self.predictedGlucose = nil
            throw LoopError.missingDataError(details: "Glucose", recovery: "Check your CGM data source")
        }

        guard let pumpStatusDate = doseStore.lastReservoirValue?.startDate else {
            self.predictedGlucose = nil
            throw LoopError.missingDataError(details: "Reservoir", recovery: "Check that your pump is in range")
        }

        let startDate = Date()
        let recencyInterval = TimeInterval(minutes: 15)

        guard startDate.timeIntervalSince(glucose.startDate) <= recencyInterval else {
            self.predictedGlucose = nil
            throw LoopError.glucoseTooOld(date: glucose.startDate)
        }

        guard startDate.timeIntervalSince(pumpStatusDate) <= recencyInterval else {
            self.predictedGlucose = nil
            throw LoopError.pumpDataTooOld(date: pumpStatusDate)
        }

        guard let
            momentum = self.glucoseMomentumEffect,
            let carbEffect = self.carbEffect,
            let insulinEffect = self.insulinEffect
        else {
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
            logger.addLoopStatus(
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

        self.predictedGlucose = settings.retrospectiveCorrectionEnabled ? predictionWithRetrospectiveEffect : prediction
        self.predictedGlucoseWithoutMomentum = predictionWithoutMomentum

        guard let minimumBGGuard = settings.minimumBGGuard else {
            throw LoopError.configurationError("Minimum BG Guard")
        }

        guard let
            maxBasal = settings.maximumBasalRatePerHour,
            let glucoseTargetRange = settings.glucoseTargetRangeSchedule,
            let insulinSensitivity = insulinSensitivitySchedule,
            let basalRates = basalRateSchedule
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

    private func recommendBolus() throws -> BolusRecommendation {
        guard let minimumBGGuard = settings.minimumBGGuard else {
            throw LoopError.configurationError("Minimum BG Guard")
        }

        guard let
            glucose = predictedGlucose,
            let glucoseWithoutMomentum = predictedGlucoseWithoutMomentum,
            let maxBolus = settings.maximumBolus,
            let glucoseTargetRange = settings.glucoseTargetRangeSchedule,
            let insulinSensitivity = insulinSensitivitySchedule,
            let basalRates = basalRateSchedule
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
        
        if recommendationWithMomentum.amount > recommendationWithoutMomentum.amount {
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

        delegate.loopDataManager(self, didRecommendBasalChange: recommendedTempBasal) { (result) in
            self.dataAccessQueue.async {
                switch result {
                case .success(let basal):
                    self.lastTempBasal = basal
                    self.recommendedTempBasal = nil

                    resultsHandler(true, nil)
                case .failure(let error):
                    resultsHandler(false, error)
                }
            }
        }
    }

    func enactRecommendedTempBasal(_ resultsHandler: @escaping (_ success: Bool, _ error: Error?) -> Void) {
        dataAccessQueue.async {
            self.setRecommendedTempBasal(resultsHandler)
        }
    }
}

extension LoopDataManager {
    /// Generates a diagnostic report about the current state
    ///
    /// This operation is performed asynchronously and the completion will be executed on an arbitrary background queue.
    ///
    /// - parameter completion: A closure called once the report has been generated. The closure takes a single argument of the report string.
    func generateDiagnosticReport(_ completion: @escaping (_ report:     String) -> Void) {
        getLoopStatus { (predictedGlucose, retrospectivePredictedGlucose, recommendedTempBasal, lastTempBasal, lastLoopCompleted, insulinOnBoard, carbsOnBoard, error) in
            var entries = [
                "## LoopDataManager",
                "settings: \(String(reflecting: self.settings))",
                "predictedGlucose: \(predictedGlucose ?? [])",
                "retrospectivePredictedGlucose: \(retrospectivePredictedGlucose ?? [])",
                "recommendedTempBasal: \(String(describing: recommendedTempBasal))",
                "lastTempBasal: \(String(describing: lastTempBasal))",
                "lastLoopCompleted: \(lastLoopCompleted ?? .distantPast)",
                "insulinOnBoard: \(String(describing: insulinOnBoard))",
                "carbsOnBoard: \(String(describing: carbsOnBoard))",
                "error: \(String(describing: error))"
            ]

            self.glucoseStore.generateDiagnosticReport { (report) in
                entries.append(report)
                entries.append("")

                self.carbStore.generateDiagnosticReport { (report) in
                    entries.append(report)
                    entries.append("")

                    self.doseStore.generateDiagnosticReport { (report) in
                        entries.append(report)
                        entries.append("")

                        completion(entries.joined(separator: "\n"))
                    }
                }
            }
        }
    }
}


extension Notification.Name {
    static let LoopDataUpdated = Notification.Name(rawValue:  "com.loudnate.Naterade.notification.LoopDataUpdated")

    static let LoopRunning = Notification.Name(rawValue: "com.loudnate.Naterade.notification.LoopRunning")
}


protocol LoopDataManagerDelegate: class {

    /// Informs the delegate that an immediate basal change is recommended
    ///
    /// - Parameters:
    ///   - manager: The manager
    ///   - basal: The new recommended basal
    ///   - completion: A closure called once on completion
    ///   - result: The enacted basal
    func loopDataManager(_ manager: LoopDataManager, didRecommendBasalChange basal: LoopDataManager.TempBasalRecommendation, completion: @escaping (_ result: Result<DoseEntry>) -> Void) -> Void
}
