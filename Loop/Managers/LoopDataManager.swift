//
//  LoopDataManager.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 3/12/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation
import HealthKit
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

    fileprivate typealias GlucoseChange = (start: GlucoseValue, end: GlucoseValue)

    let carbStore: CarbStore

    let doseStore: DoseStore

    let glucoseStore: GlucoseStore

    weak var delegate: LoopDataManagerDelegate?

    private let logger: CategoryLogger
    
    fileprivate var glucoseUpdated: Bool // flag used to decide if integral RC should be updated or not
    fileprivate var lastRetrospectiveCorrectionGlucose: GlucoseValue?
    fileprivate var initializeIntegralRetrospectiveCorrection: Bool // flag used to decide if integral RC should be initialized upon Loop relaunch or for other reasons
    var overallRetrospectiveCorrection: HKQuantity? // value used to display overall RC effect to the user

    // References to registered notification center observers
    private var notificationObservers: [Any] = []

    deinit {
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    init(
        lastLoopCompleted: Date?,
        lastTempBasal: DoseEntry?,
        basalRateSchedule: BasalRateSchedule? = UserDefaults.appGroup.basalRateSchedule,
        carbRatioSchedule: CarbRatioSchedule? = UserDefaults.appGroup.carbRatioSchedule,
        insulinModelSettings: InsulinModelSettings? = UserDefaults.appGroup.insulinModelSettings,
        insulinSensitivitySchedule: InsulinSensitivitySchedule? = UserDefaults.appGroup.insulinSensitivitySchedule,
        settings: LoopSettings = UserDefaults.appGroup.loopSettings ?? LoopSettings()
    ) {
        self.logger = DiagnosticLogger.shared.forCategory("LoopDataManager")
        self.lockedLastLoopCompleted = Locked(lastLoopCompleted)
        self.lastTempBasal = lastTempBasal
        self.settings = settings
        self.glucoseUpdated = false
        self.lastRetrospectiveCorrectionGlucose = nil
        self.initializeIntegralRetrospectiveCorrection = true
        self.overallRetrospectiveCorrection = nil

        let healthStore = HKHealthStore()
        let cacheStore = PersistenceController.controllerInAppGroupDirectory()

        carbStore = CarbStore(
            healthStore: healthStore,
            cacheStore: cacheStore,
            defaultAbsorptionTimes: (
                fast: TimeInterval(hours: 2),
                medium: TimeInterval(hours: 3),
                slow: TimeInterval(hours: 4)
            ),
            carbRatioSchedule: carbRatioSchedule,
            insulinSensitivitySchedule: insulinSensitivitySchedule
        )

        doseStore = DoseStore(
            healthStore: healthStore,
            cacheStore: cacheStore,
            insulinModel: insulinModelSettings?.model,
            basalProfile: basalRateSchedule,
            insulinSensitivitySchedule: insulinSensitivitySchedule
        )

        glucoseStore = GlucoseStore(healthStore: healthStore, cacheStore: cacheStore, cacheLength: .hours(24))

        cacheStore.delegate = self

        // Observe changes
        notificationObservers = [
            NotificationCenter.default.addObserver(
                forName: .CarbEntriesDidUpdate,
                object: carbStore,
                queue: nil
            ) { (note) -> Void in
                self.dataAccessQueue.async {
                    self.logger.info("Received notification of carb entries updating")

                    self.carbEffect = nil
                    self.carbsOnBoard = nil
                    self.notify(forChange: .carbs)
                }
            },
            NotificationCenter.default.addObserver(
                forName: .GlucoseSamplesDidChange,
                object: glucoseStore,
                queue: nil
            ) { (note) in
                self.dataAccessQueue.async {
                    self.logger.info("Received notification of glucose samples changing")

                    self.glucoseMomentumEffect = nil
                    self.retrospectiveGlucoseChange = nil

                    self.notify(forChange: .glucose)
                }
            }
        ]
    }

    /// Loop-related settings
    ///
    /// These are not thread-safe.
    var settings: LoopSettings {
        didSet {
            UserDefaults.appGroup.loopSettings = settings
            notify(forChange: .preferences)
            AnalyticsManager.shared.didChangeLoopSettings(from: oldValue, to: settings)
        }
    }

    // MARK: - Calculation state

    fileprivate let dataAccessQueue: DispatchQueue = DispatchQueue(label: "com.loudnate.Naterade.LoopDataManager.dataAccessQueue", qos: .utility)

    private var carbEffect: [GlucoseEffect]? {
        didSet {
            predictedGlucose = nil

            // Carb data may be back-dated, so re-calculate the retrospective glucose.
            retrospectivePredictedGlucose = nil
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
    private var retrospectiveGlucoseEffect: [GlucoseEffect] = [] {
        didSet {
            predictedGlucose = nil
        }
    }

    /// The change in glucose over the reflection time interval (default is 30 min)
    fileprivate var retrospectiveGlucoseChange: GlucoseChange? {
        didSet {
            retrospectivePredictedGlucose = nil
        }
    }

    fileprivate var predictedGlucose: [GlucoseValue]? {
        didSet {
            recommendedTempBasal = nil
            recommendedBolus = nil
        }
    }
    fileprivate var retrospectivePredictedGlucose: [GlucoseValue]? {
        didSet {
            retrospectiveGlucoseEffect = []
        }
    }
    fileprivate var recommendedTempBasal: (recommendation: TempBasalRecommendation, date: Date)?
    fileprivate var recommendedBolus: (recommendation: BolusRecommendation, date: Date)?

    fileprivate var carbsOnBoard: CarbValue?

    fileprivate var lastTempBasal: DoseEntry?
    fileprivate var lastRequestedBolus: (units: Double, date: Date)?

    /// The last date at which a loop completed, from prediction to dose (if dosing is enabled)
    var lastLoopCompleted: Date? {
        get {
            return lockedLastLoopCompleted.value
        }
        set {
            lockedLastLoopCompleted.value = newValue

            NotificationManager.clearLoopNotRunningNotifications()
            NotificationManager.scheduleLoopNotRunningNotifications()
            AnalyticsManager.shared.loopDidSucceed()
        }
    }
    private let lockedLastLoopCompleted: Locked<Date?>

    fileprivate var lastLoopError: Error? {
        didSet {
            if lastLoopError != nil {
                AnalyticsManager.shared.loopDidError()
            }
        }
    }

    /// A timeline of average velocity of glucose change counteracting predicted insulin effects
    fileprivate var insulinCounteractionEffects: [GlucoseEffectVelocity] = [] {
        didSet {
            carbEffect = nil
            carbsOnBoard = nil
        }
    }

    // MARK: - Background task management

    private var backgroundTask: UIBackgroundTaskIdentifier = UIBackgroundTaskInvalid

    private func startBackgroundTask() {
        endBackgroundTask()
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "PersistenceController save") {
            self.endBackgroundTask()
        }
    }

    private func endBackgroundTask() {
        if backgroundTask != UIBackgroundTaskInvalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = UIBackgroundTaskInvalid
        }
    }
}

// MARK: Background task management
extension LoopDataManager: PersistenceControllerDelegate {
    func persistenceControllerWillSave(_ controller: PersistenceController) {
        startBackgroundTask()
    }

    func persistenceControllerDidSave(_ controller: PersistenceController, error: PersistenceController.PersistenceControllerError?) {
        endBackgroundTask()
    }
}

// MARK: - Preferences
extension LoopDataManager {

    /// The daily schedule of basal insulin rates
    var basalRateSchedule: BasalRateSchedule? {
        get {
            return doseStore.basalProfile
        }
        set {
            doseStore.basalProfile = newValue
            UserDefaults.appGroup.basalRateSchedule = newValue
            notify(forChange: .preferences)

            if let newValue = newValue, let oldValue = doseStore.basalProfile, newValue.items != oldValue.items {
                AnalyticsManager.shared.didChangeBasalRateSchedule()
            }
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
            UserDefaults.appGroup.carbRatioSchedule = newValue

            // Invalidate cached effects based on this schedule
            carbEffect = nil
            carbsOnBoard = nil

            notify(forChange: .preferences)
        }
    }

    /// The length of time insulin has an effect on blood glucose
    var insulinModelSettings: InsulinModelSettings? {
        get {
            guard let model = doseStore.insulinModel else {
                return nil
            }

            return InsulinModelSettings(model: model)
        }
        set {
            doseStore.insulinModel = newValue?.model
            UserDefaults.appGroup.insulinModelSettings = newValue

            self.dataAccessQueue.async {
                // Invalidate cached effects based on this schedule
                self.insulinEffect = nil

                self.notify(forChange: .preferences)
            }

            AnalyticsManager.shared.didChangeInsulinModel()
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

            UserDefaults.appGroup.insulinSensitivitySchedule = newValue

            dataAccessQueue.async {
                // Invalidate cached effects based on this schedule
                self.carbEffect = nil
                self.carbsOnBoard = nil
                self.insulinEffect = nil

                self.notify(forChange: .preferences)
            }
        }
    }

    /// Sets a new time zone for a the schedule-based settings
    ///
    /// - Parameter timeZone: The time zone
    func setScheduleTimeZone(_ timeZone: TimeZone) {
        if timeZone != basalRateSchedule?.timeZone {
            AnalyticsManager.shared.punpTimeZoneDidChange()
            basalRateSchedule?.timeZone = timeZone
        }

        if timeZone != carbRatioSchedule?.timeZone {
            AnalyticsManager.shared.punpTimeZoneDidChange()
            carbRatioSchedule?.timeZone = timeZone
        }

        if timeZone != insulinSensitivitySchedule?.timeZone {
            AnalyticsManager.shared.punpTimeZoneDidChange()
            insulinSensitivitySchedule?.timeZone = timeZone
        }

        if timeZone != settings.glucoseTargetRangeSchedule?.timeZone {
            settings.glucoseTargetRangeSchedule?.timeZone = timeZone
        }
    }

    /// All the HealthKit types to be read and shared by stores
    private var sampleTypes: Set<HKSampleType> {
        return Set([
            glucoseStore.sampleType,
            carbStore.sampleType,
            doseStore.sampleType,
        ].compactMap { $0 })
    }

    /// True if any stores require HealthKit authorization
    var authorizationRequired: Bool {
        return glucoseStore.authorizationRequired ||
               carbStore.authorizationRequired ||
               doseStore.authorizationRequired
    }

    /// True if the user has explicitly denied access to any stores' HealthKit types
    private var sharingDenied: Bool {
        return glucoseStore.sharingDenied ||
               carbStore.sharingDenied ||
               doseStore.sharingDenied
    }

    func authorize(_ completion: @escaping () -> Void) {
        // Authorize all types at once for simplicity
        carbStore.healthStore.requestAuthorization(toShare: sampleTypes, read: sampleTypes) { (success, error) in
            if success {
                // Call the individual authorization methods to trigger query creation
                self.carbStore.authorize({ _ in })
                self.doseStore.insulinDeliveryStore.authorize({ _ in })
                self.glucoseStore.authorize({ _ in })
            }

            completion()
        }
    }
}


// MARK: - Intake
extension LoopDataManager {
    /// Adds and stores glucose data
    ///
    /// - Parameters:
    ///   - samples: The new glucose samples to store
    ///   - completion: A closure called once upon completion
    ///   - result: The stored glucose values
    func addGlucose(
        _ samples: [NewGlucoseSample],
        completion: ((_ result: Result<[GlucoseValue]>) -> Void)? = nil
    ) {
        glucoseStore.addGlucose(samples) { (result) in
            self.dataAccessQueue.async {
                switch result {
                case .success(let samples):
                    self.glucoseUpdated = true // new glucose received, enable integral RC update
                    if let endDate = samples.sorted(by: { $0.startDate < $1.startDate }).first?.startDate {
                        // Prune back any counteraction effects for recomputation
                        self.insulinCounteractionEffects = self.insulinCounteractionEffects.filter { $0.endDate < endDate }
                    }

                    completion?(.success(samples))
                case .failure(let error):
                    completion?(.failure(error))
                }
            }
        }
    }

    /// Adds and stores carb data, and recommends a bolus if needed
    ///
    /// - Parameters:
    ///   - carbEntry: The new carb value
    ///   - completion: A closure called once upon completion
    ///   - result: The bolus recommendation
    func addCarbEntryAndRecommendBolus(_ carbEntry: NewCarbEntry, replacing replacingEntry: StoredCarbEntry? = nil, completion: @escaping (_ result: Result<BolusRecommendation?>) -> Void) {
        let addCompletion: (CarbStoreResult<StoredCarbEntry>) -> Void = { (result) in
            self.dataAccessQueue.async {
                switch result {
                case .success:
                    // Remove the active pre-meal target override
                    self.settings.glucoseTargetRangeSchedule?.clearOverride(matching: .preMeal)

                    self.carbEffect = nil
                    self.carbsOnBoard = nil

                    do {
                        try self.update()

                        completion(.success(self.recommendedBolus?.recommendation))
                    } catch let error {
                        completion(.failure(error))
                    }
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }

        if let replacingEntry = replacingEntry {
            carbStore.replaceCarbEntry(replacingEntry, withEntry: carbEntry, completion: addCompletion)
        } else {
            carbStore.addCarbEntry(carbEntry, completion: addCompletion)
        }
    }

    /// Adds a bolus requested of the pump, but not confirmed.
    ///
    /// - Parameters:
    ///   - units: The bolus amount, in units
    ///   - date: The date the bolus was requested
    func addRequestedBolus(units: Double, at date: Date, completion: (() -> Void)?) {
        dataAccessQueue.async {
            self.lastRequestedBolus = (units: units, date: date)
            self.notify(forChange: .bolus)

            completion?()
        }
    }

    /// Adds a bolus enacted by the pump, but not fully delivered.
    ///
    /// - Parameters:
    ///   - units: The bolus amount, in units
    ///   - date: The date the bolus was enacted
    func addConfirmedBolus(units: Double, at date: Date, completion: (() -> Void)?) {
        self.doseStore.addPendingPumpEvent(.enactedBolus(units: units, at: date)) {
            self.dataAccessQueue.async {
                self.lastRequestedBolus = nil
                self.insulinEffect = nil
                self.notify(forChange: .bolus)

                completion?()
            }
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
            self.dataAccessQueue.async {
                if error == nil {
                    self.insulinEffect = nil
                    // Expire any bolus values now represented in the insulin data
                    if let bolusDate = self.lastRequestedBolus?.date, bolusDate.timeIntervalSinceNow < TimeInterval(minutes: -5) {
                        self.lastRequestedBolus = nil
                    }
                }

                completion(error)
            }
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
        doseStore.addReservoirValue(units, at: date) { (newValue, previousValue, areStoredValuesContinuous, error) in
            if let error = error {
                completion(.failure(error))
            } else if let newValue = newValue {
                self.dataAccessQueue.async {
                    self.insulinEffect = nil
                    // Expire any bolus values now represented in the insulin data
                    if areStoredValuesContinuous, let bolusDate = self.lastRequestedBolus?.date, bolusDate.timeIntervalSinceNow < TimeInterval(minutes: -5) {
                        self.lastRequestedBolus = nil
                    }

                    if let newDoseStartDate = previousValue?.startDate {
                        // Prune back any counteraction effects for recomputation, after the effect delay
                        self.insulinCounteractionEffects = self.insulinCounteractionEffects.filterDateRange(nil, newDoseStartDate.addingTimeInterval(.minutes(10)))
                    }

                    completion(.success((
                        newValue: newValue,
                        lastValue: previousValue,
                        areStoredValuesContinuous: areStoredValuesContinuous
                    )))
                }
            } else {
                assertionFailure()
            }
        }
    }

    // Actions

    func enactRecommendedTempBasal(_ completion: @escaping (_ error: Error?) -> Void) {
        dataAccessQueue.async {
            self.setRecommendedTempBasal(completion)
        }
    }

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
                    self.setRecommendedTempBasal { (error) -> Void in
                        self.lastLoopError = error

                        if let error = error {
                            self.logger.error(error)
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

    /// - Throws:
    ///     - LoopError.configurationError
    ///     - LoopError.glucoseTooOld
    ///     - LoopError.missingDataError
    ///     - LoopError.pumpDataTooOld
    fileprivate func update() throws {
        dispatchPrecondition(condition: .onQueue(dataAccessQueue))
        let updateGroup = DispatchGroup()

        // Fetch glucose effects as far back as we want to make retroactive analysis
        var latestGlucoseDate: Date?
        updateGroup.enter()
        glucoseStore.getCachedGlucoseSamples(start: Date(timeIntervalSinceNow: -settings.recencyInterval)) { (values) in
            latestGlucoseDate = values.last?.startDate
            updateGroup.leave()
        }
        _ = updateGroup.wait(timeout: .distantFuture)

        guard let lastGlucoseDate = latestGlucoseDate else {
            throw LoopError.missingDataError(.glucose)
        }
        
        // Reinitialize integral retrospective correction states based on past 60 minutes of data
        // For now, do this only once upon Loop relaunch
        if self.initializeIntegralRetrospectiveCorrection {
            self.initializeIntegralRetrospectiveCorrection = false
            let restartInterval = TimeInterval(minutes: 60)
            let retrospectiveRestartDate = lastGlucoseDate.addingTimeInterval(-restartInterval)
            
            // get insulin effects over the retrospective restart interval
            updateGroup.enter()
            doseStore.getGlucoseEffects(start: retrospectiveRestartDate.addingTimeInterval(-restartInterval)) { (result) -> Void in
                switch result {
                case .failure(let error):
                    self.logger.error(error)
                    self.insulinEffect = nil
                case .success(let effects):
                    self.insulinEffect = effects
                }
                updateGroup.leave()
            }
            
            // get carb effects over the retrospective restart interval
            updateGroup.enter()
            carbStore.getGlucoseEffects(
                start: retrospectiveRestartDate.addingTimeInterval(-restartInterval),
                effectVelocities: settings.dynamicCarbAbsorptionEnabled ? insulinCounteractionEffects : nil
            ) { (result) -> Void in
                switch result {
                case .failure(let error):
                    self.logger.error(error)
                    self.carbEffect = nil
                case .success(let effects):
                    self.carbEffect = effects
                }
                updateGroup.leave()
            }
            
            _ = updateGroup.wait(timeout: .distantFuture)
            
            var sampleGlucoseChangeEnd: Date = retrospectiveRestartDate
            while sampleGlucoseChangeEnd <= lastGlucoseDate {
                self.retrospectiveGlucoseChange = nil
                let sampleGlucoseChangeStart = sampleGlucoseChangeEnd.addingTimeInterval(-settings.retrospectiveCorrectionInterval)
                updateGroup.enter()
                self.glucoseStore.getGlucoseChange(start: sampleGlucoseChangeStart, end: sampleGlucoseChangeEnd) { (change) in
                    self.retrospectiveGlucoseChange = change
                    updateGroup.leave()
                }
                
                _ = updateGroup.wait(timeout: .distantFuture)
                
                // do updateRetrospectiveGlucoseEffect() for change during restart interval
                self.glucoseUpdated = true
                do {
                    try updateRetrospectiveGlucoseEffect()
                } catch let error {
                    logger.error(error)
                }
                self.glucoseUpdated = false
                
                sampleGlucoseChangeEnd = sampleGlucoseChangeEnd.addingTimeInterval(TimeInterval(minutes: 5))
            }
            
            self.insulinEffect = nil
            self.carbEffect = nil
            self.retrospectiveGlucoseChange = nil
        }

        let retrospectiveStart = lastGlucoseDate.addingTimeInterval(-settings.retrospectiveCorrectionInterval)

        let earliestEffectDate = Date(timeIntervalSinceNow: .hours(-24))
        let nextEffectDate = insulinCounteractionEffects.last?.endDate ?? earliestEffectDate

        if retrospectiveGlucoseChange == nil {
            updateGroup.enter()
            glucoseStore.getGlucoseChange(start: retrospectiveStart) { (change) in
                self.retrospectiveGlucoseChange = change
                updateGroup.leave()
            }
        }

        if glucoseMomentumEffect == nil {
            updateGroup.enter()
            glucoseStore.getRecentMomentumEffect { (effects) -> Void in
                self.glucoseMomentumEffect = effects
                updateGroup.leave()
            }
        }

        if insulinEffect == nil {
            updateGroup.enter()
            doseStore.getGlucoseEffects(start: min(retrospectiveStart, nextEffectDate)) { (result) -> Void in
                switch result {
                case .failure(let error):
                    self.logger.error(error)
                    self.insulinEffect = nil
                case .success(let effects):
                    self.insulinEffect = effects
                }

                updateGroup.leave()
            }
        }

        _ = updateGroup.wait(timeout: .distantFuture)

        if nextEffectDate < lastGlucoseDate, let insulinEffect = insulinEffect {
            updateGroup.enter()
            self.logger.debug("Fetching counteraction effects after \(nextEffectDate)")
            glucoseStore.getCounteractionEffects(start: nextEffectDate, to: insulinEffect) { (velocities) in
                self.insulinCounteractionEffects.append(contentsOf: velocities)
                self.insulinCounteractionEffects = self.insulinCounteractionEffects.filterDateRange(earliestEffectDate, nil)

                updateGroup.leave()
            }

            _ = updateGroup.wait(timeout: .distantFuture)
        }

        if carbEffect == nil {
            updateGroup.enter()
            carbStore.getGlucoseEffects(
                start: retrospectiveStart,
                effectVelocities: settings.dynamicCarbAbsorptionEnabled ? insulinCounteractionEffects : nil
            ) { (result) -> Void in
                switch result {
                case .failure(let error):
                    self.logger.error(error)
                    self.carbEffect = nil
                case .success(let effects):
                    self.carbEffect = effects
                }

                updateGroup.leave()
            }
        }

        if carbsOnBoard == nil {
            updateGroup.enter()
            carbStore.carbsOnBoard(at: Date(), effectVelocities: settings.dynamicCarbAbsorptionEnabled ? insulinCounteractionEffects : nil) { (result) in
                switch result {
                case .failure:
                    // Failure is expected when there is no carb data
                    self.carbsOnBoard = nil
                case .success(let value):
                    self.carbsOnBoard = value
                }
                updateGroup.leave()
            }
        }

        _ = updateGroup.wait(timeout: .distantFuture)

        if retrospectivePredictedGlucose == nil {
            do {
                try updateRetrospectiveGlucoseEffect()
            } catch let error {
                logger.error(error)
            }
        }

        if predictedGlucose == nil {
            do {
                try updatePredictedGlucoseAndRecommendedBasalAndBolus()
            } catch let error {
                logger.error(error)

                throw error
            }
        }
    }

    private func notify(forChange context: LoopUpdateContext) {
        NotificationCenter.default.post(name: .LoopDataUpdated,
            object: self,
            userInfo: [
                type(of: self).LoopUpdateContextKey: context.rawValue
            ]
        )
    }

    /// Computes amount of insulin from boluses that have been issued and not confirmed, and
    /// remaining insulin delivery from temporary basal rate adjustments above scheduled rate
    /// that are still in progress.
    ///
    /// - Returns: The amount of pending insulin, in units
    /// - Throws: LoopError.configurationError
    private func getPendingInsulin() throws -> Double {
        dispatchPrecondition(condition: .onQueue(dataAccessQueue))

        guard let basalRates = basalRateSchedule else {
            throw LoopError.configurationError(.basalRateSchedule)
        }

        let pendingTempBasalInsulin: Double
        let date = Date()

        if let lastTempBasal = lastTempBasal, lastTempBasal.endDate > date {
            let normalBasalRate = basalRates.value(at: date)
            let remainingTime = lastTempBasal.endDate.timeIntervalSince(date)
            let remainingUnits = (lastTempBasal.unitsPerHour - normalBasalRate) * remainingTime.hours

            pendingTempBasalInsulin = max(0, remainingUnits)
        } else {
            pendingTempBasalInsulin = 0
        }

        let pendingBolusAmount: Double = lastRequestedBolus?.units ?? 0

        // All outstanding potential insulin delivery
        return pendingTempBasalInsulin + pendingBolusAmount
    }

    /// - Throws: LoopError.missingDataError
    fileprivate func predictGlucose(using inputs: PredictionInputEffect) throws -> [GlucoseValue] {
        dispatchPrecondition(condition: .onQueue(dataAccessQueue))

        guard let model = insulinModelSettings?.model else {
            throw LoopError.configurationError(.insulinModel)
        }

        guard let glucose = self.glucoseStore.latestGlucose else {
            throw LoopError.missingDataError(.glucose)
        }

        var momentum: [GlucoseEffect] = []
        var effects: [[GlucoseEffect]] = []

        if inputs.contains(.carbs), let carbEffect = self.carbEffect {
            effects.append(carbEffect)
        }

        if inputs.contains(.insulin), let insulinEffect = self.insulinEffect {
            effects.append(insulinEffect)
        }

        if inputs.contains(.momentum), let momentumEffect = self.glucoseMomentumEffect {
            momentum = momentumEffect
        }

        if inputs.contains(.retrospection) {
            effects.append(self.retrospectiveGlucoseEffect)
        }

        var prediction = LoopMath.predictGlucose(startingAt: glucose, momentum: momentum, effects: effects)

        // Dosing requires prediction entries at least as long as the insulin model duration.
        // If our prediciton is shorter than that, then extend it here.
        let finalDate = glucose.startDate.addingTimeInterval(model.effectDuration)
        if let last = prediction.last, last.startDate < finalDate {
            prediction.append(PredictedGlucoseValue(startDate: finalDate, quantity: last.quantity))
        }

        return prediction
    }

    /**
     Retrospective correction math, including proportional and integral action
     */
    fileprivate struct RetrospectiveCorrection {
        
        let discrepancyGain: Double
        let persistentDiscrepancyGain: Double
        let correctionTimeConstant: Double
        let integralGain: Double
        let integralForget: Double
        let proportionalGain: Double
        
        static var effectDuration: Double = 60
        static var previousDiscrepancy: Double = 0
        static var integralDiscrepancy: Double = 0
        
        init() {
            discrepancyGain = 1.0 // high-frequency RC gain, equivalent to Loop 1.5 gain = 1
            persistentDiscrepancyGain = 5.0 // low-frequency RC gain for persistent errors, must be >= discrepancyGain
            correctionTimeConstant = 90.0 // correction filter time constant in minutes
            let sampleTime: Double = 5.0 // sample time = 5 min
            integralForget = exp( -sampleTime / correctionTimeConstant ) // must be between 0 and 1
            integralGain = ((1 - integralForget) / integralForget) *
                (persistentDiscrepancyGain - discrepancyGain)
            proportionalGain = discrepancyGain - integralGain
        }
        func updateRetrospectiveCorrection(discrepancy: Double,
                                           positiveLimit: Double,
                                           negativeLimit: Double,
                                           carbEffect: Double,
                                           carbEffectLimit: Double,
                                           glucoseUpdated: Bool) -> Double {
            if (RetrospectiveCorrection.previousDiscrepancy * discrepancy < 0 ||
                (discrepancy > 0 && carbEffect > carbEffectLimit)){
                // reset integral action when discrepancy reverses polarity or
                // if discrepancy is positive and carb effect is greater than carbEffectLimit
                RetrospectiveCorrection.effectDuration = 60.0
                RetrospectiveCorrection.previousDiscrepancy = 0.0
                RetrospectiveCorrection.integralDiscrepancy = integralGain * discrepancy
            } else {
                if glucoseUpdated {
                    // update integral action via low-pass filter y[n] = forget * y[n-1] + gain * u[n]
                    RetrospectiveCorrection.integralDiscrepancy =
                        integralForget * RetrospectiveCorrection.integralDiscrepancy +
                        integralGain * discrepancy
                    // impose safety limits on integral retrospective correction
                    RetrospectiveCorrection.integralDiscrepancy = min(max(RetrospectiveCorrection.integralDiscrepancy, negativeLimit), positiveLimit)
                    RetrospectiveCorrection.previousDiscrepancy = discrepancy
                    // extend duration of retrospective correction effect by 10 min, up to a maxium of 180 min
                    RetrospectiveCorrection.effectDuration =
                    min(RetrospectiveCorrection.effectDuration + 10, 180)
                }
            }
            let overallDiscrepancy = proportionalGain * discrepancy + RetrospectiveCorrection.integralDiscrepancy
            return(overallDiscrepancy)
        }
        func updateEffectDuration() -> Double {
            return(RetrospectiveCorrection.effectDuration)
        }
        func resetRetrospectiveCorrection() {
            RetrospectiveCorrection.effectDuration = 60.0
            RetrospectiveCorrection.previousDiscrepancy = 0.0
            RetrospectiveCorrection.integralDiscrepancy = 0.0
            return
        }
    }
    
    /**
     Runs the glucose retrospective analysis using the latest effect data.
     Updated to include integral retrospective correction.
 
     *This method should only be called from the `dataAccessQueue`*
     */
    private func updateRetrospectiveGlucoseEffect(effectDuration: TimeInterval = TimeInterval(minutes: 60)) throws {
        dispatchPrecondition(condition: .onQueue(dataAccessQueue))
        
        guard let carbEffect = self.carbEffect else {
            self.retrospectivePredictedGlucose = nil
            self.overallRetrospectiveCorrection = nil
            self.glucoseUpdated = false
            throw LoopError.missingDataError(.carbEffect)
        }

        guard let insulinEffect = self.insulinEffect else {
            self.retrospectivePredictedGlucose = nil
            self.overallRetrospectiveCorrection = nil
            self.glucoseUpdated = false
            throw LoopError.missingDataError(.insulinEffect)
        }
        
        // integral retrospective correction variables
        var dynamicEffectDuration: TimeInterval = effectDuration
        let retrospectiveCorrection = RetrospectiveCorrection()

        guard let change = retrospectiveGlucoseChange else {
            dynamicEffectDuration = effectDuration
            self.overallRetrospectiveCorrection = nil
            self.glucoseUpdated = false
            self.retrospectivePredictedGlucose = nil
            return  // Expected case for calibrations, skip retrospective correction
        }

        // Run a retrospective prediction over the duration of the recorded glucose change, using the current carb and insulin effects
        let startDate = change.start.startDate
        let endDate = change.end.endDate
        let retrospectivePrediction = LoopMath.predictGlucose(startingAt: change.start, effects:
            carbEffect.filterDateRange(startDate, endDate),
            insulinEffect.filterDateRange(startDate, endDate)
        )

        self.retrospectivePredictedGlucose = retrospectivePrediction

        guard let lastGlucose = retrospectivePrediction.last else {
            retrospectiveCorrection.resetRetrospectiveCorrection()
            self.overallRetrospectiveCorrection = nil
            self.glucoseUpdated = false
            self.retrospectivePredictedGlucose = nil
            return // missing glucose data, reset integral RC and skip retrospective correction
        }
        
        let retrospectionTimeInterval = change.end.endDate.timeIntervalSince(change.start.endDate).minutes
        if retrospectionTimeInterval < 6 {
            self.overallRetrospectiveCorrection = nil
            self.glucoseUpdated = false
            self.retrospectivePredictedGlucose = nil
            return // too few glucose values, erroneous insulin and carb effects, skip retrospective correction
        }
        
        // check if retrospective glucose correction has already been updated for this glucose change
        if( self.lastRetrospectiveCorrectionGlucose?.endDate == change.end.endDate ) {
            self.glucoseUpdated = false
        } else {
            self.lastRetrospectiveCorrectionGlucose = change.end
        }
        
        let glucoseUnit = HKUnit.milligramsPerDeciliter
        let velocityUnit = glucoseUnit.unitDivided(by: HKUnit.second())

        // get user settings relevant for calculation of integral retrospective correction safety parameters
        guard
            let glucoseTargetRange = settings.glucoseTargetRangeSchedule,
            let insulinSensitivity = insulinSensitivitySchedule,
            let basalRates = basalRateSchedule,
            let suspendThreshold = settings.suspendThreshold?.quantity,
            let carbRatio = carbRatioSchedule
            else {
                retrospectiveCorrection.resetRetrospectiveCorrection()
                self.overallRetrospectiveCorrection = nil
                self.glucoseUpdated = false
                self.retrospectivePredictedGlucose = nil
                return // could not get user settings, reset RC and skip retrospective correction
        }
        let currentBG = change.end.quantity.doubleValue(for: glucoseUnit)
        let currentSensitivity = insulinSensitivity.quantity(at: endDate).doubleValue(for: glucoseUnit)
        let currentBasalRate = basalRates.value(at: endDate)
        let currentCarbRatio = carbRatio.value(at: endDate)
        let currentMinTarget = glucoseTargetRange.minQuantity(at: endDate).doubleValue(for: glucoseUnit)
        let currentSuspendThreshold = suspendThreshold.doubleValue(for: glucoseUnit)
        
        // safety limit for + integral action: ISF * (2 hours) * (basal rate)
        let integralActionPositiveLimit = currentSensitivity * 2 * currentBasalRate
        // safety limit for - integral action: suspend threshold - target
        let integralActionNegativeLimit = min(-15,-abs(currentMinTarget - currentSuspendThreshold))
        
        // safety limit for current discrepancy
        let discrepancyLimit = integralActionPositiveLimit
        let currentDiscrepancyUnlimited = change.end.quantity.doubleValue(for: glucoseUnit) - lastGlucose.quantity.doubleValue(for: glucoseUnit) // mg/dL
        let currentDiscrepancy = min(max(currentDiscrepancyUnlimited, -discrepancyLimit), discrepancyLimit)
        
        // retrospective carb effect
        let retrospectiveCarbEffect = LoopMath.predictGlucose(startingAt: change.start, effects:
            carbEffect.filterDateRange(startDate, endDate))
        guard let lastCarbOnlyGlucose = retrospectiveCarbEffect.last else {
            retrospectiveCorrection.resetRetrospectiveCorrection()
            self.overallRetrospectiveCorrection = nil
            self.glucoseUpdated = false
            self.retrospectivePredictedGlucose = nil
            return // could not get carb effect, reset integral RC and skip retrospective correction
        }
        
        // setup an upper safety limit for carb action
        // integral RC resets to standard RC if discrepancy > 0 and carb action is greater than carbEffectLimit in mg/dL over 30 minutes
        let currentCarbEffect = -change.start.quantity.doubleValue(for: glucoseUnit) + lastCarbOnlyGlucose.quantity.doubleValue(for: glucoseUnit)
        let scaledCarbEffect = currentCarbEffect * 30.0 / retrospectionTimeInterval // current carb effect over 30 minutes
        let carbEffectLimit: Double = min( 200 * currentCarbRatio / currentSensitivity, 45 ) // [mg/dL] over 30 minutes
        // the above line may be replaced by a fixed value if so desired
        // let carbEffectLimit = 30 was used during early IRC testing, 15 was found by some to work better for kids
        // let carbEffectLimit = 0 is the most conservative setting
        
        // update overall retrospective correction
        let overallRC = retrospectiveCorrection.updateRetrospectiveCorrection(
            discrepancy: currentDiscrepancy,
            positiveLimit: integralActionPositiveLimit,
            negativeLimit: integralActionNegativeLimit,
            carbEffect: scaledCarbEffect,
            carbEffectLimit: carbEffectLimit,
            glucoseUpdated: self.glucoseUpdated
        )
        
        let effectMinutes = retrospectiveCorrection.updateEffectDuration()
        var scaledDiscrepancy = currentDiscrepancy
        if settings.integralRetrospectiveCorrectionEnabled {
            // retrospective correction including integral action
            scaledDiscrepancy = overallRC * 60.0 / effectMinutes // scaled to account for extended effect duration
            dynamicEffectDuration = TimeInterval(minutes: effectMinutes)
            self.overallRetrospectiveCorrection = HKQuantity(unit: glucoseUnit, doubleValue: overallRC)
        } else {
            // standard retrospective correction
            dynamicEffectDuration = effectDuration
            self.overallRetrospectiveCorrection = HKQuantity(unit: glucoseUnit, doubleValue: currentDiscrepancy)
        }
        
        // Determine the interval of discrepancy, requiring a minimum of the configured interval to avoid magnifying effects from short intervals
        let discrepancyTime = max(change.end.endDate.timeIntervalSince(change.start.endDate), settings.retrospectiveCorrectionInterval)
        let velocity = HKQuantity(unit: velocityUnit, doubleValue: scaledDiscrepancy / discrepancyTime)
        let type = HKQuantityType.quantityType(forIdentifier: HKQuantityTypeIdentifier.bloodGlucose)!
        let glucose = HKQuantitySample(type: type, quantity: change.end.quantity, start: change.end.startDate, end: change.end.endDate)
        
        self.retrospectiveGlucoseEffect = glucose.decayEffect(atRate: velocity, for: dynamicEffectDuration)
        
        // retrospective insulin effect (just for monitoring RC operation)
        let retrospectiveInsulinEffect = LoopMath.predictGlucose(startingAt: change.start, effects:
            insulinEffect.filterDateRange(startDate, endDate))
        guard let lastInsulinOnlyGlucose = retrospectiveInsulinEffect.last else {
            self.glucoseUpdated = false
            return
        }
        let currentInsulinEffect = -change.start.quantity.doubleValue(for: glucoseUnit) + lastInsulinOnlyGlucose.quantity.doubleValue(for: glucoseUnit)

        // retrospective average delta BG (just for monitoring RC operation)
        let currentDeltaBG = change.end.quantity.doubleValue(for: glucoseUnit) -
            change.start.quantity.doubleValue(for: glucoseUnit)// mg/dL
        
        if self.glucoseUpdated {
            // monitoring of retrospective correction in debugger or Console ("message: myLoop")
            NSLog("myLoop ******************************************")
            NSLog("myLoop ---retrospective correction ([mg/dL] bg unit)---")
            NSLog("myLoop Integral retrospective correction enabled: %d", settings.integralRetrospectiveCorrectionEnabled)
            NSLog("myLoop Current BG: %f", currentBG)
            NSLog("myLoop 30-min retrospective delta BG: %4.2f", currentDeltaBG)
            NSLog("myLoop Retrospective insulin effect: %4.2f", currentInsulinEffect)
            NSLog("myLoop Retrospectve carb effect: %4.2f", currentCarbEffect)
            NSLog("myLoop Scaled carb effect: %4.2f", scaledCarbEffect)
            NSLog("myLoop Carb effect limit: %4.2f", carbEffectLimit)
            NSLog("myLoop Current discrepancy: %4.2f", currentDiscrepancy)
            NSLog("myLoop Retrospection time interval: %4.2f", retrospectionTimeInterval)
            NSLog("myLoop Overall retrospective correction: %4.2f", overallRC)
            NSLog("myLoop Correction effect duration [min]: %4.2f", effectMinutes)
        }
        
        glucoseUpdated = false // ensure we are only updating integral RC once per BG update
    }

    /// Runs the glucose prediction on the latest effect data.
    ///
    /// - Throws:
    ///     - LoopError.configurationError
    ///     - LoopError.glucoseTooOld
    ///     - LoopError.missingDataError
    ///     - LoopError.pumpDataTooOld
    private func updatePredictedGlucoseAndRecommendedBasalAndBolus() throws {
        dispatchPrecondition(condition: .onQueue(dataAccessQueue))

        guard let glucose = glucoseStore.latestGlucose else {
            self.predictedGlucose = nil
            throw LoopError.missingDataError(.glucose)
        }

        guard let pumpStatusDate = doseStore.lastReservoirValue?.startDate else {
            self.predictedGlucose = nil
            throw LoopError.missingDataError(.reservoir)
        }

        let startDate = Date()

        guard startDate.timeIntervalSince(glucose.startDate) <= settings.recencyInterval else {
            self.predictedGlucose = nil
            throw LoopError.glucoseTooOld(date: glucose.startDate)
        }

        guard startDate.timeIntervalSince(pumpStatusDate) <= settings.recencyInterval else {
            self.predictedGlucose = nil
            throw LoopError.pumpDataTooOld(date: pumpStatusDate)
        }

        guard glucoseMomentumEffect != nil else {
            self.predictedGlucose = nil
            throw LoopError.missingDataError(.momentumEffect)
        }

        guard carbEffect != nil else {
            self.predictedGlucose = nil
            throw LoopError.missingDataError(.carbEffect)
        }

        guard insulinEffect != nil else {
            self.predictedGlucose = nil
            throw LoopError.missingDataError(.insulinEffect)
        }

        let predictedGlucose = try predictGlucose(using: settings.enabledEffects)
        self.predictedGlucose = predictedGlucose

        guard let
            maxBasal = settings.maximumBasalRatePerHour,
            let glucoseTargetRange = settings.glucoseTargetRangeSchedule,
            let insulinSensitivity = insulinSensitivitySchedule,
            let basalRates = basalRateSchedule,
            let maxBolus = settings.maximumBolus,
            let model = insulinModelSettings?.model
        else {
            throw LoopError.configurationError(.generalSettings)
        }
        
        guard lastRequestedBolus == nil
        else {
            // Don't recommend changes if a bolus was just requested.
            // Sending additional pump commands is not going to be
            // successful in any case.
            recommendedBolus = nil
            recommendedTempBasal = nil
            return
        }
        
        let tempBasal = predictedGlucose.recommendedTempBasal(
            to: glucoseTargetRange,
            suspendThreshold: settings.suspendThreshold?.quantity,
            sensitivity: insulinSensitivity,
            model: model,
            basalRates: basalRates,
            maxBasalRate: maxBasal,
            lastTempBasal: lastTempBasal
        )
        
        if let temp = tempBasal {
            recommendedTempBasal = (recommendation: temp, date: startDate)
        } else {
            recommendedTempBasal = nil
        }

        let pendingInsulin = try self.getPendingInsulin()

        let recommendation = predictedGlucose.recommendedBolus(
            to: glucoseTargetRange,
            suspendThreshold: settings.suspendThreshold?.quantity,
            sensitivity: insulinSensitivity,
            model: model,
            pendingInsulin: pendingInsulin,
            maxBolus: maxBolus
        )
        recommendedBolus = (recommendation: recommendation, date: startDate)
    }

    /// *This method should only be called from the `dataAccessQueue`*
    private func setRecommendedTempBasal(_ completion: @escaping (_ error: Error?) -> Void) {
        dispatchPrecondition(condition: .onQueue(dataAccessQueue))

        guard let recommendedTempBasal = self.recommendedTempBasal else {
            completion(nil)
            return
        }

        guard abs(recommendedTempBasal.date.timeIntervalSinceNow) < TimeInterval(minutes: 5) else {
            completion(LoopError.recommendationExpired(date: recommendedTempBasal.date))
            return
        }

        delegate?.loopDataManager(self, didRecommendBasalChange: recommendedTempBasal) { (result) in
            self.dataAccessQueue.async {
                switch result {
                case .success(let basal):
                    self.lastTempBasal = basal
                    self.recommendedTempBasal = nil

                    completion(nil)
                case .failure(let error):
                    completion(error)
                }
            }
        }
    }
}


/// Describes a view into the loop state
protocol LoopState {
    /// The last-calculated carbs on board
    var carbsOnBoard: CarbValue? { get }

    /// An error in the current state of the loop, or one that happened during the last attempt to loop.
    var error: Error? { get }

    /// A timeline of average velocity of glucose change counteracting predicted insulin effects
    var insulinCounteractionEffects: [GlucoseEffectVelocity] { get }

    /// The last set temp basal
    var lastTempBasal: DoseEntry? { get }

    /// The calculated timeline of predicted glucose values
    var predictedGlucose: [GlucoseValue]? { get }

    /// The recommended temp basal based on predicted glucose
    var recommendedTempBasal: (recommendation: TempBasalRecommendation, date: Date)? { get }

    var recommendedBolus: (recommendation: BolusRecommendation, date: Date)? { get }
    
    /// The retrospective prediction over a recent period of glucose samples
    var retrospectivePredictedGlucose: [GlucoseValue]? { get }

    /// Calculates a new prediction from the current data using the specified effect inputs
    ///
    /// This method is intended for visualization purposes only, not dosing calculation. No validation of input data is done.
    ///
    /// - Parameter inputs: The effect inputs to include
    /// - Returns: An timeline of predicted glucose values
    /// - Throws: LoopError.missingDataError if prediction cannot be computed
    func predictGlucose(using inputs: PredictionInputEffect) throws -> [GlucoseValue]
}


extension LoopDataManager {
    private struct LoopStateView: LoopState {
        private let loopDataManager: LoopDataManager
        private let updateError: Error?

        init(loopDataManager: LoopDataManager, updateError: Error?) {
            self.loopDataManager = loopDataManager
            self.updateError = updateError
        }

        var carbsOnBoard: CarbValue? {
            dispatchPrecondition(condition: .onQueue(loopDataManager.dataAccessQueue))
            return loopDataManager.carbsOnBoard
        }

        var error: Error? {
            dispatchPrecondition(condition: .onQueue(loopDataManager.dataAccessQueue))
            return updateError ?? loopDataManager.lastLoopError
        }

        var insulinCounteractionEffects: [GlucoseEffectVelocity] {
            dispatchPrecondition(condition: .onQueue(loopDataManager.dataAccessQueue))
            return loopDataManager.insulinCounteractionEffects
        }

        var lastTempBasal: DoseEntry? {
            dispatchPrecondition(condition: .onQueue(loopDataManager.dataAccessQueue))
            return loopDataManager.lastTempBasal
        }

        var predictedGlucose: [GlucoseValue]? {
            dispatchPrecondition(condition: .onQueue(loopDataManager.dataAccessQueue))
            return loopDataManager.predictedGlucose
        }

        var recommendedTempBasal: (recommendation: TempBasalRecommendation, date: Date)? {
            dispatchPrecondition(condition: .onQueue(loopDataManager.dataAccessQueue))
            return loopDataManager.recommendedTempBasal
        }
        
        var recommendedBolus: (recommendation: BolusRecommendation, date: Date)? {
            dispatchPrecondition(condition: .onQueue(loopDataManager.dataAccessQueue))
            return loopDataManager.recommendedBolus
        }

        var retrospectivePredictedGlucose: [GlucoseValue]? {
            dispatchPrecondition(condition: .onQueue(loopDataManager.dataAccessQueue))
            return loopDataManager.retrospectivePredictedGlucose
        }

        func predictGlucose(using inputs: PredictionInputEffect) throws -> [GlucoseValue] {
            return try loopDataManager.predictGlucose(using: inputs)
        }
    }

    /// Executes a closure with access to the current state of the loop.
    ///
    /// This operation is performed asynchronously and the closure will be executed on an arbitrary background queue.
    ///
    /// - Parameter handler: A closure called when the state is ready
    /// - Parameter manager: The loop manager
    /// - Parameter state: The current state of the manager. This is invalid to access outside of the closure.
    func getLoopState(_ handler: @escaping (_ manager: LoopDataManager, _ state: LoopState) -> Void) {
        dataAccessQueue.async {
            var updateError: Error?

            do {
                try self.update()
            } catch let error {
                updateError = error
            }

            handler(self, LoopStateView(loopDataManager: self, updateError: updateError))
        }
    }
}


extension LoopDataManager {
    /// Generates a diagnostic report about the current state
    ///
    /// This operation is performed asynchronously and the completion will be executed on an arbitrary background queue.
    ///
    /// - parameter completion: A closure called once the report has been generated. The closure takes a single argument of the report string.
    func generateDiagnosticReport(_ completion: @escaping (_ report: String) -> Void) {
        getLoopState { (manager, state) in

            var entries = [
                "## LoopDataManager",
                "settings: \(String(reflecting: manager.settings))",

                "insulinCounteractionEffects: [",
                "* GlucoseEffectVelocity(start, end, mg/dL/min)",
                manager.insulinCounteractionEffects.reduce(into: "", { (entries, entry) in
                    entries.append("* \(entry.startDate), \(entry.endDate), \(entry.quantity.doubleValue(for: GlucoseEffectVelocity.unit))\n")
                }),
                "]",

                "predictedGlucose: [",
                "* PredictedGlucoseValue(start, mg/dL)",
                (state.predictedGlucose ?? []).reduce(into: "", { (entries, entry) in
                    entries.append("* \(entry.startDate), \(entry.quantity.doubleValue(for: .milligramsPerDeciliter))\n")
                }),
                "]",

                "retrospectivePredictedGlucose: \(state.retrospectivePredictedGlucose ?? [])",
                "glucoseMomentumEffect: \(manager.glucoseMomentumEffect ?? [])",
                "retrospectiveGlucoseEffect: \(manager.retrospectiveGlucoseEffect)",
                "recommendedTempBasal: \(String(describing: state.recommendedTempBasal))",
                "recommendedBolus: \(String(describing: state.recommendedBolus))",
                "lastBolus: \(String(describing: manager.lastRequestedBolus))",
                "retrospectiveGlucoseChange: \(String(describing: manager.retrospectiveGlucoseChange))",
                "lastLoopCompleted: \(String(describing: manager.lastLoopCompleted))",
                "lastTempBasal: \(String(describing: state.lastTempBasal))",
                "carbsOnBoard: \(String(describing: state.carbsOnBoard))",
                "error: \(String(describing: state.error))",
                "",
                "cacheStore: \(String(reflecting: self.glucoseStore.cacheStore))",
                "",
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
    func loopDataManager(_ manager: LoopDataManager, didRecommendBasalChange basal: (recommendation: TempBasalRecommendation, date: Date), completion: @escaping (_ result: Result<DoseEntry>) -> Void) -> Void
}
