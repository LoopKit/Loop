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
import RileyLinkKit


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

    init(deviceDataManager: DeviceDataManager) {
        self.deviceDataManager = deviceDataManager

        dosingEnabled = UserDefaults.standard.dosingEnabled
        retrospectiveCorrectionEnabled = UserDefaults.standard.retrospectiveCorrectionEnabled

        bolusState = Bolus(state: .prohibited, units: 0, carbs: 0, date: Date(), sent: nil, allowed: false, message: "Startup", reservoir: nil)
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
    
    private lazy var decimalFormatter: NumberFormatter = {
        let numberFormatter = NumberFormatter()
        numberFormatter.usesSignificantDigits = false
        numberFormatter.minimumIntegerDigits = 1
        numberFormatter.minimumFractionDigits = 1
        numberFormatter.maximumFractionDigits = 1
        
        return numberFormatter
    }()
    
    private var lastSuccessfulBolus : Date?

    private func update() throws {
        let updateGroup = DispatchGroup()
        // do bolus first as the rest might throw an exception.
        
        if self.bolusState.inProgress() {
            self.bolusState.allowed = false
            updateGroup.enter()
            // Fuzz time a bit to account for different time on pump and device
            var date = self.bolusState.date
            if let d = self.bolusState.sent {
                date = d
            }
            let startDate = date.addingTimeInterval(TimeInterval(minutes: -2))
            deviceDataManager.doseStore.getRecentNormalizedDoseEntries(startDate: startDate) {
                (doseEntries, error) in
                print("getRecentNormalizedDoseEntries", self.bolusState)
                if let error = error {
                    print("getRecentNormalizedDoseEntries", error)
                    self.deviceDataManager.logger.addError(error, fromSource: "insulinEffectbolusState")
                } else {
                    print("getRecentNormalizedDoseEntries", doseEntries)
                    for entry in doseEntries {
                        //                    print(entry.type, entry)
                        if entry.type == .bolus {
                            if entry.value >= self.bolusState.units {
                                self.bolusState.state = .success
                                self.lastSuccessfulBolus = entry.endDate
                                self.bolusState.message = ""
                                self.deviceDataManager.logger.addMessage("Bolus Success: \(self.bolusState) \(entry)", "LoopDataManager")
                                break
                            } else {
                                self.bolusState.state = .success
                                self.lastSuccessfulBolus = entry.endDate
                                let str = self.decimalFormatter.string(from: NSNumber(value: entry.value))!
                                self.bolusState.message = "Different amount \(str)"
                                self.deviceDataManager.logger.addMessage("Bolus Success, but wrong amount: \(self.bolusState) \(entry)", "LoopDataManager")
                                break
                            }
                        }
                    }
                }
                if self.bolusState.state != .success {

                    if let reservoir = self.deviceDataManager.doseStore.lastReservoirValue {
                        let timeForBolus = TimeInterval(minutes: (self.bolusState.units + 1))
                        let expiry = date + timeForBolus
                        
                        if let start = self.bolusState.reservoir {
                            if self.bolusState.date.timeIntervalSince(start.startDate) > TimeInterval(minutes: 15) {
                                print("bolusState.date \(self.bolusState.date), start.startDate \(start.startDate), more than 15 minutes")
                            }
                            let currentUnits = reservoir.unitVolume
                            let drop = start.unitVolume - currentUnits
                            
                            print("Bolus Progress Drop \(drop), current \(currentUnits), start \(start.unitVolume)")
                            if drop > self.bolusState.units {
                                self.bolusState.state = .success
                                self.lastSuccessfulBolus = reservoir.startDate
                                
                                self.bolusState.message = "\(self.bolusState.units) U"
                            } else {
                                let strDrop = self.decimalFormatter.string(from: NSNumber(value: drop))!
                                self.bolusState.message = "\(strDrop)/\(self.bolusState.units) U"
                            }
                        }
                        let eventDate = self.deviceDataManager.doseStore.pumpEventQueryAfterDate
                        // needs a more accurate measurement of how fast the pump is.
                        // this should take into account the real time it takes to give the bolus.
                        // TODO investigate if the event and startDate should be OR conditions.
                        //      If we don't wait for the event to be read back, the IOB might
                        //      be wrong though.  Better safe than sorry.
                        if self.bolusState.state != .success && reservoir.startDate > expiry && eventDate > expiry {
                            self.bolusState.state = .failed
                            self.bolusState.message = "\(reservoir.startDate) > \(expiry) [\(timeForBolus)]"
                            self.deviceDataManager.logger.addError("Bolus Failed: \(self.bolusState) \(timeForBolus)", fromSource: "LoopDataManager")
                        }
                    }
                }
                
                updateGroup.leave()
            }
        } else {
            // No Bolus in progress, update state.
            //
            // TODO this should use IOB, not reservoirValue as that's more accurate.
            if let reservoir = self.deviceDataManager.doseStore.lastReservoirValue {
                if reservoir.startDate.timeIntervalSinceNow < TimeInterval(minutes: -15) {
                    print("Bolus not allowed because reservoir too old")
                    self.bolusState.allowed = false
                    self.bolusState.state = .prohibited
                    self.bolusState.message = "Reservoir data too old."
                } else {
                    if self.bolusState.state ==  .prohibited {
                        self.bolusState.state = .none
                        self.bolusState.message = ""
                    }
                    self.bolusState.allowed = true
                }
            } else {
                print("Bolus not allowed because reservoir not available")
                self.bolusState.allowed = false
                self.bolusState.state = .prohibited
                self.bolusState.message = "Reservoir data not available."
            }
            
            if self.bolusState.date.timeIntervalSinceNow < TimeInterval(minutes: -30) {
                if self.bolusState.state != .none && self.bolusState.state != .recommended  {
                    self.bolusState.state = .none
                    self.bolusState.message = ""
                }
            }
            
            if self.bolusState.state == .none || self.bolusState.state == .recommended {
                if let units = self.recommendedBolus, units > 0.5 {  // 0.5 shouldn't be static
                    self.bolusState.state = .recommended
                    self.bolusState.units = units
                    self.bolusState.carbs = 0
                /*
                } else if let carbs = self.recommendedBolus?.carbRecommendation, carbs > 5 {
                    self.bolusState.state = .recommended
                    self.bolusState.units = 0
                    self.bolusState.carbs = 10 * round(carbs/10 + 1)
                */
                } else {
                    self.bolusState.state = .none
                    self.bolusState.units = 0
                }
                
            }
            
        }

        if glucoseChange == nil, let glucoseStore = deviceDataManager.glucoseStore {
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
            updateGlucoseMomentumEffect { (effects, error) in
                if error == nil {
                    self.glucoseMomentumEffect = effects
                } else {
                    self.glucoseMomentumEffect = nil
                }
                updateGroup.leave()
            }
        }

        if carbEffect == nil {
            updateGroup.enter()
            updateCarbEffect { (effects, error) in
                if error == nil {
                    self.carbEffect = effects
                } else {
                    self.carbEffect = nil
                }
                updateGroup.leave()
            }
        }

        if carbsOnBoardSeries == nil, let carbStore = deviceDataManager.carbStore {
            updateGroup.enter()
            carbStore.getCarbsOnBoardValues { (values, error) in
                if let error = error {
                    self.deviceDataManager.logger.addError(error, fromSource: "CarbStore")
                }

                self.carbsOnBoardSeries = values
                updateGroup.leave()
            }
        }

        if insulinEffect == nil {
            updateGroup.enter()
            updateInsulinEffect { (effects, error) in
                if error == nil {
                    self.insulinEffect = effects
                } else {
                    self.insulinEffect = nil
                }
                updateGroup.leave()
            }
        }

        if insulinOnBoard == nil {
            updateGroup.enter()
            deviceDataManager.doseStore.insulinOnBoardAtDate(Date()) { (value, error) in
                if let error = error {
                    self.deviceDataManager.logger.addError(error, fromSource: "DoseStore")
                }

                self.insulinOnBoard = value
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
        
        do {
            try self.recommendedBolus = self.recommendBolus()
        } catch let error {
            self.deviceDataManager.logger.addError(error, fromSource: "RecommendBolus")
            throw error
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
    func getLoopStatus(_ resultsHandler: @escaping (_ predictedGlucose: [GlucoseValue]?, _ retrospectivePredictedGlucose: [GlucoseValue]?, _ recommendedTempBasal: TempBasalRecommendation?, _ lastTempBasal: DoseEntry?, _ bolusState: Bolus?,
        _ lastLoopCompleted: Date?, _ insulinOnBoard: InsulinValue?, _ carbsOnBoard: CarbValue?, _ error: Error?) -> Void) {
        dataAccessQueue.async {
            var error: Error?

            do {
                try self.update()
            } catch let updateError {
                error = updateError
            }

            let currentCOB = self.carbsOnBoardSeries?.closestPriorToDate(Date())

            resultsHandler(self.predictedGlucose, self.retrospectivePredictedGlucose, self.recommendedTempBasal, self.lastTempBasal, self.bolusState, self.lastLoopCompleted, self.insulinOnBoard, currentCOB, error ?? self.lastLoopError)
        }
    }

    func modelPredictedGlucose(using inputs: [PredictionInputEffect], resultsHandler: @escaping (_ predictedGlucose: [GlucoseValue]?, _ error: Error?) -> Void) {
        dataAccessQueue.async { 
            guard let
                glucose = self.deviceDataManager.glucoseStore?.latestGlucose
            else {
                resultsHandler(nil, LoopError.missingDataError("Cannot predict glucose due to missing input data"))
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
            recommendedBolus = nil
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
    private var recommendedBolus: Double?

    private var lastTempBasal: DoseEntry?

    enum BolusState : String {
        case none  // none given
        case prohibited // not allowed
        case recommended // recommendation
        // command sent to pump
        case sent
        // initial states
        case pending
        case maybefailed
        // result
        case failed
        case success
        case timeout
    }
    struct Bolus {
        var state : BolusState = .none
        var units : Double = 0.0
        var carbs : Double = 0.0
        var date : Date
        var sent : Date?
        // if a new bolus is allowed
        var allowed : Bool = false
        var message : String = ""
        
        var reservoir: ReservoirValue? = nil
        
        func equal(_ other: Bolus) -> Bool {
            return state == other.state && date == other.date && units == other.units && message == other.message && allowed == other.allowed
        }
        
        func inProgress() -> Bool {
            return state == .pending || state == .maybefailed || state == .sent
        }
        
        func description() -> String {
            switch state {
            case .none: return ""
            case .prohibited: return "Prohibited"
            case .recommended: return "Recommended"
                
            case .sent: return "Pending"
            case .pending: return "Delivering"
            case .maybefailed: return "Maybe failed"
                
            case .failed: return "Failed"
            case .success: return "Successful"
            case .timeout: return "Timed out"
            }
        }
        
        func kind() -> String {
            if state == .recommended && carbs > 0 {
                return "Carbs"
            }
            return "Bolus"
        }
        
        func explanation() -> String {
            var val = ""
            switch state {
            case .none:
                val = ""
            case .prohibited:
                val = "Unsafe"
            case .recommended:
                if units > 0 {
                    val = "Recommended value, tap to enact."
                } else if carbs > 0 {
                    val = "Eat \(carbs) g fast acting carbs like juice, glucose tabs, etc."
                }
            case .sent:
                val = "Sending command to pump."
            case .pending:
                val = "(can turn phone off)."
            case .maybefailed:
                val = "Comm Error."
                
            case .failed:
                val = "Tap to retry now."
            case .success:
                val = "Success!"
            case .timeout:
                val = "Timeout - Check pump!"
                
            }
            if message != "" {
                val = "\(val) - \(message)"
            }
            return val
        }
    }
    private var bolusState: Bolus

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

    /// The oldest date that should be used for effect calculation
    private var effectStartDate: Date? {
        let startDate: Date?

        if let glucoseStore = deviceDataManager.glucoseStore {
            // Fetch glucose effects as far back as we want to make retroactive analysis
            startDate = glucoseStore.latestGlucose?.startDate.addingTimeInterval(-glucoseStore.reflectionDataInterval)
        } else {
            startDate = nil
        }

        return startDate
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

    private func updateCarbEffect(_ completionHandler: @escaping (_ effects: [GlucoseEffect]?, _ error: Error?) -> Void) {
        if let carbStore = deviceDataManager.carbStore {
            carbStore.getGlucoseEffects(startDate: effectStartDate) { (effects, error) -> Void in
                if let error = error {
                    self.deviceDataManager.logger.addError(error, fromSource: "CarbStore")
                }

                completionHandler(effects, error)
            }
        } else {
            completionHandler(nil, LoopError.missingDataError("CarbStore not available"))
        }
    }

    private func updateInsulinEffect(_ completionHandler: @escaping (_ effects: [GlucoseEffect]?, _ error: Error?) -> Void) {
        deviceDataManager.doseStore.getGlucoseEffects(startDate: effectStartDate) { (effects, error) -> Void in
            if let error = error {
                self.deviceDataManager.logger.addError(error, fromSource: "DoseStore")
            }

            completionHandler(effects, error)
        }
    }

    private func updateGlucoseMomentumEffect(_ completionHandler: @escaping (_ effects: [GlucoseEffect]?, _ error: Error?) -> Void) {
        guard let glucoseStore = deviceDataManager.glucoseStore else {
            completionHandler(nil, LoopError.missingDataError("GlucoseStore not available"))
            return
        }
        glucoseStore.getRecentMomentumEffect { (effects, error) -> Void in
            if let error = error {
                self.deviceDataManager.logger.addError(error, fromSource: "GlucoseStore")
            }

            completionHandler(effects, error)
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
            throw LoopError.missingDataError("Cannot retrospect glucose due to missing input data")
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
            glucose = self.deviceDataManager.glucoseStore?.latestGlucose,
            let pumpStatusDate = self.deviceDataManager.doseStore.lastReservoirValue?.startDate
        else {
            self.predictedGlucose = nil
            throw LoopError.missingDataError("Cannot predict glucose due to missing input data")
        }

        let startDate = Date()
        let recencyInterval = TimeInterval(minutes: 15)

        guard startDate.timeIntervalSince(glucose.startDate) <= recencyInterval &&
              startDate.timeIntervalSince(pumpStatusDate) <= recencyInterval
        else {
            self.predictedGlucose = nil
            throw LoopError.staleDataError("Glucose Date: \(glucose.startDate) or Pump status date: \(pumpStatusDate) older than \(recencyInterval.minutes) min")
        }

        guard let
            momentum = self.glucoseMomentumEffect,
            let carbEffect = self.carbEffect,
            let insulinEffect = self.insulinEffect else
        {
            self.predictedGlucose = nil
            throw LoopError.missingDataError("Cannot predict glucose due to missing effect data")
        }

        var error: Error?

        let prediction = LoopMath.predictGlucose(glucose, momentum: momentum, effects: carbEffect, insulinEffect)
        let predictionWithRetrospectiveEffect = LoopMath.predictGlucose(glucose, momentum: momentum, effects: carbEffect, insulinEffect, retrospectiveGlucoseEffect)

        let predictDiff: Double

        let unit = HKUnit.milligramsPerDeciliterUnit()
        if  let lastA = prediction.last?.quantity.doubleValue(for: unit),
            let lastB = predictionWithRetrospectiveEffect.last?.quantity.doubleValue(for: unit)
        {
            predictDiff = lastB - lastA
        } else {
            predictDiff = 0
        }

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
                recommendedTempBasal: recommendedTempBasal
            )
        }

        self.predictedGlucose = retrospectiveCorrectionEnabled ? predictionWithRetrospectiveEffect : prediction

        guard let
            maxBasal = deviceDataManager.maximumBasalRatePerHour,
            let glucoseTargetRange = deviceDataManager.glucoseTargetRangeSchedule,
            let insulinSensitivity = deviceDataManager.insulinSensitivitySchedule,
            let basalRates = deviceDataManager.basalRateSchedule
        else {
            error = LoopError.missingDataError("Loop configuration data not set")
            throw error!
        }

        guard
            !bolusState.inProgress(),  // Don't recommend changes if a bolus was just set
            let predictedGlucose = self.predictedGlucose,
            let tempBasal = DoseMath.recommendTempBasalFromPredictedGlucose(predictedGlucose,
                lastTempBasal: lastTempBasal,
                maxBasalRate: maxBasal,
                glucoseTargetRange: glucoseTargetRange,
                insulinSensitivity: insulinSensitivity,
                basalRateSchedule: basalRates
            )
        else {
            recommendedTempBasal = nil
            return
        }

        recommendedTempBasal = (recommendedDate: Date(), rate: tempBasal.rate, duration: tempBasal.duration)
    }

    func addCarbEntryAndRecommendBolus(_ carbEntry: CarbEntry, resultsHandler: @escaping (_ units: Double?, _ error: Error?) -> Void) {
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
            resultsHandler(nil, LoopError.missingDataError("CarbStore not configured"))
        }
    }

    private func recommendBolus() throws -> Double {
        guard let
            glucose = self.predictedGlucose,
            let maxBolus = self.deviceDataManager.maximumBolus,
            let glucoseTargetRange = self.deviceDataManager.glucoseTargetRangeSchedule,
            let insulinSensitivity = self.deviceDataManager.insulinSensitivitySchedule,
            let basalRates = self.deviceDataManager.basalRateSchedule
        else {
            throw LoopError.missingDataError("Bolus prediction and configuration data not found")
        }

        let recencyInterval = TimeInterval(minutes: 15)

        guard let predictedInterval = glucose.first?.startDate.timeIntervalSinceNow else {
            throw LoopError.missingDataError("No glucose data found")
        }

        guard abs(predictedInterval) <= recencyInterval else {
            throw LoopError.staleDataError("Glucose is \(predictedInterval.minutes) min old")
        }

        let pendingBolusAmount: Double = bolusState.inProgress() ? bolusState.units : 0

        return max(0, DoseMath.recommendBolusFromPredictedGlucose(glucose,
            lastTempBasal: self.lastTempBasal,
            maxBolus: maxBolus,
            glucoseTargetRange: glucoseTargetRange,
            insulinSensitivity: insulinSensitivity,
            basalRateSchedule: basalRates
        ) - pendingBolusAmount)
    }

    func getRecommendedBolus(_ resultsHandler: @escaping (_ units: Double?, _ error: Error?) -> Void) {
        dataAccessQueue.async {
            do {
                let units = try self.recommendBolus()
                resultsHandler(units, nil)
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

        guard recommendedTempBasal.recommendedDate.timeIntervalSinceNow < TimeInterval(minutes: 5) else {
            resultsHandler(false, LoopError.staleDataError("Recommended temp basal is \(recommendedTempBasal.recommendedDate.timeIntervalSinceNow.minutes) min old"))
            return
        }

        guard let device = self.deviceDataManager.rileyLinkManager.firstConnectedDevice else {
            resultsHandler(false, LoopError.connectionError)
            return
        }

        guard let ops = device.ops else {
            resultsHandler(false, LoopError.configurationError)
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
     Informs the loop algorithm of an enacted bolus, overrides previous one!
     
     - parameter units: The amount of insulin
     - parameter date:  The date the bolus was initially set
     - parameter state: initial state of this bolus (.pending or .maybefailed or .sent)
     - parameter sent date: The date the bolus was successfully submitted to the pump.
     - parameter message: potential (failure) message
     */
    private func recordBolus(_ units: Double, at date: Date, state: BolusState,
                             sent: Date? = nil, message: String? = nil, reservoir: ReservoirValue? = nil) {
        dataAccessQueue.async {
            self.bolusState = Bolus(state: state, units: units, carbs: 0.0, date: date,
                                   sent: sent, allowed: false,
                                   message: message ?? "",
                                   reservoir: reservoir)
            self.notify(forChange: .bolus)
        }
    }
    
    private let bolusQueue: DispatchQueue = DispatchQueue(label: "com.loudnate.Naterade.LoopDataManager.bolusQueue", qos: .utility)
    /// Send a bolus command and handle the result
    ///
    /// - parameter units:      The number of units to deliver
    /// - parameter completion: A closure called after the command is complete. This closure takes a single argument:
    ///     - error: An error describing why the command failed
    func enactBolus(units: Double, completion: @escaping (_ error: Error?) -> Void) {
        let start = Date()
        guard !self.bolusState.inProgress() else {
            completion(LoopError.bolusInProgressError)
            return
        }
        guard units > 0 else {
            completion(nil)
            self.recordBolus(units, at: start, state: .success, message: "Zero")
            return
        }
        
        guard let device = self.deviceDataManager.rileyLinkManager.firstConnectedDevice else {
            completion(LoopError.connectionError)
            self.recordBolus(units, at: start, state: .failed, message: "Connection Error")
            return
        }
        
        guard let ops = device.ops else {
            completion(LoopError.configurationError)
            self.recordBolus(units, at: start, state: .failed, message: "Configuration Error")
            return
        }
        
        self.recordBolus(units, at: start, state: .sent)
        bolusQueue.async {
            self.tryBolus(ops: ops, tries: 0, start: start, units: units, completion: completion)
        }
    }
    
    private func tryBolus(ops: PumpOps, tries: Int, start: Date, units: Double, completion: @escaping (_ error: Error?) -> Void) {
        
        let tries = tries + 1
        let reservoir = self.deviceDataManager.doseStore.lastReservoirValue
        
        ops.setNormalBolus(units: units) { (error) in
            if let error = error {
                // first housekeeping
                self.deviceDataManager.logger.addError(error, fromSource: "Bolus")
                
                let str = "\(error)"
                var retry = false
                //noResponse("Sent PumpMessage(carelink, powerOn, 681652, 00)")
                //unknownResponse("a9 69 9a c6 e9 725665 55 6b25", "Sent PumpMessage(carelink, powerOn, 681652, 00)")
                
                if (str.contains("noResponse(") || str.contains("unknownResponse(")) && str.contains("powerOn") {
                    retry = true
                }
                // TODO make this smarter in retrying.
                // TODO recognize "bolus in progress"
                if retry && tries <= 3 {
                    self.recordBolus(units, at: start, state: .sent,
                                     message: "Try \(tries): \(error)")
                    self.bolusQueue.asyncAfter(deadline: .now() + 5.0) {
                        self.tryBolus(ops: ops, tries: tries, start: start, units: units, completion: completion)
                    }
                } else {
                    self.recordBolus(units, at: start, state: .maybefailed,
                                     message: "After \(tries) tries: \(error)",
                        reservoir: reservoir)
                    //self.readAndProcessPumpData()
                    completion(LoopError.communicationError)
                }
            } else {
                self.recordBolus(units, at: start, state: .pending, sent: Date(), message: nil,
                                 reservoir: reservoir)
                completion(nil)
            }
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
        getLoopStatus { (predictedGlucose, retrospectivePredictedGlucose, recommendedTempBasal, lastTempBasal, bolusState, lastLoopCompleted, insulinOnBoard, carbsOnBoard, error) in
            let report = [
                "## LoopDataManager",
                "predictedGlucose: \(predictedGlucose ?? [])",
                "retrospectivePredictedGlucose: \(retrospectivePredictedGlucose ?? [])",
                "recommendedTempBasal: \(recommendedTempBasal)",
                "lastTempBasal: \(lastTempBasal)",
                "recommendedBolus: \(bolusState?.units)",
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
