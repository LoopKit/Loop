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
import LoopCore


final class LoopDataManager: LoopSettingsAlerterDelegate {
    enum LoopUpdateContext: Int {
        case bolus
        case carbs
        case glucose
        case preferences
        case tempBasal
    }

    static let LoopUpdateContextKey = "com.loudnate.Loop.LoopDataManager.LoopUpdateContext"

    private let carbStore: CarbStoreProtocol

    private let doseStore: DoseStoreProtocol

    let dosingDecisionStore: DosingDecisionStoreProtocol

    private let glucoseStore: GlucoseStoreProtocol

    let settingsStore: SettingsStoreProtocol

    weak var delegate: LoopDataManagerDelegate?

    private let logger = DiagnosticLog(category: "LoopDataManager")

    private let analyticsServicesManager: AnalyticsServicesManager

    let loopSettingsAlerter: LoopSettingsAlerter
    
    private let now: () -> Date

    // References to registered notification center observers
    private var notificationObservers: [Any] = []
    
    private var overrideObserver: NSKeyValueObservation? = nil

    deinit {
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    init(
        lastLoopCompleted: Date?,
        basalDeliveryState: PumpManagerStatus.BasalDeliveryState?,
        basalRateSchedule: BasalRateSchedule? = UserDefaults.appGroup?.basalRateSchedule,
        carbRatioSchedule: CarbRatioSchedule? = UserDefaults.appGroup?.carbRatioSchedule,
        insulinModelSettings: InsulinModelSettings? = UserDefaults.appGroup?.insulinModelSettings, // type of insulin delivered by the pump
        insulinSensitivitySchedule: InsulinSensitivitySchedule? = UserDefaults.appGroup?.insulinSensitivitySchedule,
        settings: LoopSettings = UserDefaults.appGroup?.loopSettings ?? LoopSettings(),
        overrideHistory: TemporaryScheduleOverrideHistory,
        lastPumpEventsReconciliation: Date?,
        analyticsServicesManager: AnalyticsServicesManager,
        localCacheDuration: TimeInterval = .days(1),
        doseStore: DoseStoreProtocol,
        glucoseStore: GlucoseStoreProtocol,
        carbStore: CarbStoreProtocol,
        dosingDecisionStore: DosingDecisionStoreProtocol,
        settingsStore: SettingsStoreProtocol,
        now: @escaping () -> Date = { Date() },
        alertPresenter: AlertPresenter? = nil,
        pumpInsulinType: InsulinType?
    ) {
        self.analyticsServicesManager = analyticsServicesManager
        self.lockedLastLoopCompleted = Locked(lastLoopCompleted)
        self.lockedBasalDeliveryState = Locked(basalDeliveryState)
        self.settings = settings
        self.overrideHistory = overrideHistory

        let absorptionTimes = LoopCoreConstants.defaultCarbAbsorptionTimes

        self.overrideHistory.relevantTimeWindow = absorptionTimes.slow * 2

        self.carbStore = carbStore
        self.doseStore = doseStore
        self.glucoseStore = glucoseStore

        self.dosingDecisionStore = dosingDecisionStore

        self.now = now

        self.settingsStore = settingsStore
        
        self.lockedPumpInsulinType = Locked(pumpInsulinType)

        retrospectiveCorrection = settings.enabledRetrospectiveCorrectionAlgorithm

        loopSettingsAlerter = LoopSettingsAlerter(alertPresenter: alertPresenter)
        loopSettingsAlerter.delegate = self

        overrideObserver = UserDefaults.appGroup?.observe(\.intentExtensionOverrideToSet, options: [.new], changeHandler: {[weak self] (defaults, change) in
            guard let name = change.newValue??.lowercased(), let appGroup = UserDefaults.appGroup else {
                return
            }

            guard let preset = self?.settings.overridePresets.first(where: {$0.name.lowercased() == name}) else {
                self?.logger.error("Override Intent: Unable to find override named '%s'", String(describing: name))
                return
            }
            
            self?.logger.default("Override Intent: setting override named '%s'", String(describing: name))
            self?.settings.scheduleOverride = preset.createOverride(enactTrigger: .remote("Siri"))
            // Remove the override from UserDefaults so we don't set it multiple times
            appGroup.intentExtensionOverrideToSet = nil
        })

        overrideHistory.delegate = self

        // Observe changes
        notificationObservers = [
            NotificationCenter.default.addObserver(
                forName: CarbStore.carbEntriesDidChange,
                object: self.carbStore,
                queue: nil
            ) { (note) -> Void in
                self.dataAccessQueue.async {
                    self.logger.default("Received notification of carb entries changing")

                    self.carbEffect = nil
                    self.carbsOnBoard = nil
                    self.recentCarbEntries = nil
                    self.notify(forChange: .carbs)
                }
            },
            NotificationCenter.default.addObserver(
                forName: GlucoseStore.glucoseSamplesDidChange,
                object: self.glucoseStore,
                queue: nil
            ) { (note) in
                self.dataAccessQueue.async {
                    self.logger.default("Received notification of glucose samples changing")

                    self.glucoseMomentumEffect = nil

                    self.notify(forChange: .glucose)
                }
            },
            NotificationCenter.default.addObserver(
                forName: nil,
                object: self.doseStore,
                queue: OperationQueue.main
            ) { (note) in
                self.dataAccessQueue.async {
                    self.logger.default("Received notification of dosing changing")

                    self.insulinEffect = nil

                    self.notify(forChange: .bolus)
                }
            }
        ]
    }

    /// Loop-related settings
    ///
    /// These are not thread-safe.

    @Published var settings: LoopSettings {
        didSet {
            guard settings != oldValue else {
                return
            }

            if settings.preMealOverride != oldValue.preMealOverride {
                // The prediction isn't actually invalid, but a target range change requires recomputing recommended doses
                predictedGlucose = nil
            }

            if settings.scheduleOverride != oldValue.scheduleOverride {
                overrideHistory.recordOverride(settings.scheduleOverride)

                // Invalidate cached effects affected by the override
                self.carbEffect = nil
                self.carbsOnBoard = nil
                self.insulinEffect = nil
            }

            UserDefaults.appGroup?.loopSettings = settings
            notify(forChange: .preferences)
            analyticsServicesManager.didChangeLoopSettings(from: oldValue, to: settings)
        }
    }

    let overrideHistory: TemporaryScheduleOverrideHistory

    // MARK: - Calculation state

    fileprivate let dataAccessQueue: DispatchQueue = DispatchQueue(label: "com.loudnate.Naterade.LoopDataManager.dataAccessQueue", qos: .utility)

    private var carbEffect: [GlucoseEffect]? {
        didSet {
            predictedGlucose = nil

            // Carb data may be back-dated, so re-calculate the retrospective glucose.
            retrospectiveGlucoseDiscrepancies = nil
        }
    }

    private var insulinEffect: [GlucoseEffect]? {
        didSet {
            insulinEffectIncludingPendingInsulin = nil
            predictedGlucose = nil
        }
    }

    private var insulinEffectIncludingPendingInsulin: [GlucoseEffect]? {
        didSet {
            predictedGlucoseIncludingPendingInsulin = nil
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

    /// When combining retrospective glucose discrepancies, extend the window slightly as a buffer.
    private let retrospectiveCorrectionGroupingIntervalMultiplier = 1.01

    private var retrospectiveGlucoseDiscrepancies: [GlucoseEffect]? {
        didSet {
            retrospectiveGlucoseDiscrepanciesSummed = retrospectiveGlucoseDiscrepancies?.combinedSums(of: LoopConstants.retrospectiveCorrectionGroupingInterval * retrospectiveCorrectionGroupingIntervalMultiplier)
        }
    }

    private var retrospectiveGlucoseDiscrepanciesSummed: [GlucoseChange]?

    fileprivate var predictedGlucose: [PredictedGlucoseValue]? {
        didSet {
            recommendedTempBasal = nil
            recommendedBolus = nil
            predictedGlucoseIncludingPendingInsulin = nil
        }
    }

    fileprivate var predictedGlucoseIncludingPendingInsulin: [PredictedGlucoseValue]?

    private var recentCarbEntries: [StoredCarbEntry]?

    fileprivate var recommendedTempBasal: (recommendation: TempBasalRecommendation, date: Date)?

    fileprivate var recommendedBolus: (recommendation: BolusRecommendation, date: Date)?

    fileprivate var carbsOnBoard: CarbValue?

    var basalDeliveryState: PumpManagerStatus.BasalDeliveryState? {
        get {
            return lockedBasalDeliveryState.value
        }
        set {
            self.logger.debug("Updating basalDeliveryState to %{public}@", String(describing: newValue))
            lockedBasalDeliveryState.value = newValue
        }
    }
    private let lockedBasalDeliveryState: Locked<PumpManagerStatus.BasalDeliveryState?>
    
    var pumpInsulinType: InsulinType? {
        get {
            return lockedPumpInsulinType.value
        }
        set {
            lockedPumpInsulinType.value = newValue
        }
    }
    private let lockedPumpInsulinType: Locked<InsulinType?>

    fileprivate var lastRequestedBolus: DoseEntry?

    /// The last date at which a loop completed, from prediction to dose (if dosing is enabled)
    var lastLoopCompleted: Date? {
        get {
            return lockedLastLoopCompleted.value
        }
        set {
            lockedLastLoopCompleted.value = newValue
        }
    }
    private let lockedLastLoopCompleted: Locked<Date?>

    fileprivate var lastLoopError: Error?

    /// A timeline of average velocity of glucose change counteracting predicted insulin effects
    fileprivate var insulinCounteractionEffects: [GlucoseEffectVelocity] = [] {
        didSet {
            carbEffect = nil
            carbsOnBoard = nil
        }
    }

    // Confined to dataAccessQueue
    private var retrospectiveCorrection: RetrospectiveCorrection

    // MARK: - Background task management

    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    private func startBackgroundTask() {
        endBackgroundTask()
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "PersistenceController save") {
            self.endBackgroundTask()
        }
    }

    private func endBackgroundTask() {
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }

    private func loopDidComplete(date: Date, duration: TimeInterval) {
        lastLoopCompleted = date
        NotificationManager.clearLoopNotRunningNotifications()
        NotificationManager.scheduleLoopNotRunningNotifications()
        analyticsServicesManager.loopDidSucceed(duration)
        storeDosingDecision(withDate: date)

        NotificationCenter.default.post(name: .LoopCompleted, object: self)
    }

    private func loopDidError(date: Date, error: Error, duration: TimeInterval) {
        logger.error("%{public}@", String(describing: error))
        lastLoopError = error
        analyticsServicesManager.loopDidError()
        storeDosingDecision(withDate: date, withError: error)
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


// MARK: Override history tracking
extension LoopDataManager: TemporaryScheduleOverrideHistoryDelegate {
    func temporaryScheduleOverrideHistoryDidUpdate(_ history: TemporaryScheduleOverrideHistory) {
        UserDefaults.appGroup?.overrideHistory = history
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
            UserDefaults.appGroup?.basalRateSchedule = newValue
            notify(forChange: .preferences)

            if let newValue = newValue, let oldValue = doseStore.basalProfile, newValue.items != oldValue.items {
                analyticsServicesManager.didChangeBasalRateSchedule()
            }
        }
    }

    /// The basal rate schedule, applying recent overrides relative to the current moment in time.
    var basalRateScheduleApplyingOverrideHistory: BasalRateSchedule? {
        return doseStore.basalProfileApplyingOverrideHistory
    }

    /// The daily schedule of carbs-to-insulin ratios
    /// This is measured in grams/Unit
    var carbRatioSchedule: CarbRatioSchedule? {
        get {
            return carbStore.carbRatioSchedule
        }
        set {
            carbStore.carbRatioSchedule = newValue
            UserDefaults.appGroup?.carbRatioSchedule = newValue

            // Invalidate cached effects based on this schedule
            carbEffect = nil
            carbsOnBoard = nil

            notify(forChange: .preferences)
        }
    }

    /// The carb ratio schedule, applying recent overrides relative to the current moment in time.
    var carbRatioScheduleApplyingOverrideHistory: CarbRatioSchedule? {
        return carbStore.carbRatioScheduleApplyingOverrideHistory
    }

    /// The length of time insulin has an effect on blood glucose
    var insulinModelSettings: InsulinModelSettings? {
        get {
            return doseStore.insulinModelSettings
        }
        set {
            doseStore.insulinModelSettings = newValue
            UserDefaults.appGroup?.insulinModelSettings = newValue

            self.dataAccessQueue.async {
                // Invalidate cached effects based on this schedule
                self.insulinEffect = nil

                self.notify(forChange: .preferences)
            }

            analyticsServicesManager.didChangeInsulinModel()
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

            UserDefaults.appGroup?.insulinSensitivitySchedule = newValue

            dataAccessQueue.async {
                // Invalidate cached effects based on this schedule
                self.carbEffect = nil
                self.carbsOnBoard = nil
                self.insulinEffect = nil

                self.notify(forChange: .preferences)
            }
        }
    }

    /// The insulin sensitivity schedule, applying recent overrides relative to the current moment in time.
    var insulinSensitivityScheduleApplyingOverrideHistory: InsulinSensitivitySchedule? {
        return carbStore.insulinSensitivityScheduleApplyingOverrideHistory
    }

    /// Sets a new time zone for a the schedule-based settings
    ///
    /// - Parameter timeZone: The time zone
    func setScheduleTimeZone(_ timeZone: TimeZone) {
        if timeZone != basalRateSchedule?.timeZone {
            analyticsServicesManager.pumpTimeZoneDidChange()
            basalRateSchedule?.timeZone = timeZone
        }

        if timeZone != carbRatioSchedule?.timeZone {
            analyticsServicesManager.pumpTimeZoneDidChange()
            carbRatioSchedule?.timeZone = timeZone
        }

        if timeZone != insulinSensitivitySchedule?.timeZone {
            analyticsServicesManager.pumpTimeZoneDidChange()
            insulinSensitivitySchedule?.timeZone = timeZone
        }

        if timeZone != settings.glucoseTargetRangeSchedule?.timeZone {
            settings.glucoseTargetRangeSchedule?.timeZone = timeZone
        }
    }
}


// MARK: - Intake
extension LoopDataManager {
    /// Adds and stores glucose samples
    ///
    /// - Parameters:
    ///   - samples: The new glucose samples to store
    ///   - completion: A closure called once upon completion
    ///   - result: The stored glucose values
    func addGlucoseSamples(
        _ samples: [NewGlucoseSample],
        completion: ((_ result: Swift.Result<[StoredGlucoseSample], Error>) -> Void)? = nil
    ) {
        glucoseStore.addGlucoseSamples(samples) { (result) in
            self.dataAccessQueue.async {
                switch result {
                case .success(let samples):
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
    func addCarbEntry(_ carbEntry: NewCarbEntry, replacing replacingEntry: StoredCarbEntry? = nil, completion: @escaping (_ result: Result<StoredCarbEntry>) -> Void) {
        let addCompletion: (CarbStoreResult<StoredCarbEntry>) -> Void = { (result) in
            self.dataAccessQueue.async {
                switch result {
                case .success(let storedCarbEntry):
                    // Remove the active pre-meal target override
                    self.settings.clearOverride(matching: .preMeal)

                    self.carbEffect = nil
                    self.carbsOnBoard = nil
                    completion(.success(storedCarbEntry))
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
    ///   - dose: The DoseEntry representing the requested bolus
    func addRequestedBolus(_ dose: DoseEntry, completion: (() -> Void)?) {
        dataAccessQueue.async {
            self.logger.debug("addRequestedBolus")
            self.lastRequestedBolus = dose
            self.notify(forChange: .bolus)

            completion?()
        }
    }

    /// Notifies the manager that the bolus is confirmed, but not fully delivered.
    ///
    /// - Parameters:
    ///   - dose: The DoseEntry representing the confirmed bolus.
    func bolusConfirmed(_ dose: DoseEntry, completion: (() -> Void)?) {
        self.dataAccessQueue.async {
            self.logger.debug("bolusConfirmed")
            self.lastRequestedBolus = nil
            self.recommendedBolus = nil
            self.recommendedTempBasal = nil
            self.insulinEffect = nil
            self.notify(forChange: .bolus)

            completion?()
        }
    }

    /// Notifies the manager that the bolus failed.
    ///
    /// - Parameters:
    ///   - dose: The DoseEntry representing the confirmed bolus.
    func bolusRequestFailed(_ error: Error, completion: (() -> Void)?) {
        self.dataAccessQueue.async {
            self.logger.debug("bolusRequestFailed")
            self.lastRequestedBolus = nil
            self.insulinEffect = nil
            self.notify(forChange: .bolus)

            completion?()
        }
    }


    /// Adds and stores new pump events
    ///
    /// - Parameters:
    ///   - events: The pump events to add
    ///   - completion: A closure called once upon completion
    ///   - lastReconciliation: The date that pump events were most recently reconciled against recorded pump history. Pump events are assumed to be reflective of delivery up until this point in time. If reservoir values are recorded after this time, they may be used to supplement event based delivery.
    ///   - error: An error explaining why the events could not be saved.
    func addPumpEvents(_ events: [NewPumpEvent], lastReconciliation: Date?, completion: @escaping (_ error: DoseStore.DoseStoreError?) -> Void) {
        doseStore.addPumpEvents(events, lastReconciliation: lastReconciliation) { (error) in
            self.dataAccessQueue.async {
                if error == nil {
                    self.insulinEffect = nil
                }
                completion(error)
            }
        }
    }
    
    /// Logs a new external bolus insulin dose in the DoseStore and HealthKit
    ///
    /// - Parameters:
    ///   - startDate: The date the dose was started at.
    ///   - value: The number of Units in the dose.
    ///   - insulinModel: The type of insulin model that should be used for the dose.
    func logOutsideInsulinDose(startDate: Date, units: Double, insulinType: InsulinType? = nil) {
        let syncIdentifier = Data(UUID().uuidString.utf8).hexadecimalString
        let dose = DoseEntry(type: .bolus, startDate: startDate, value: units, unit: .units, syncIdentifier: syncIdentifier, insulinType: insulinType)

        logOutsideInsulinDose(dose: dose) { (error) in
            if error == nil {
                self.recommendedBolus = nil
                self.recommendedTempBasal = nil
                self.insulinEffect = nil
                self.notify(forChange: .bolus)
            }
        }
    }

    /// Logs a new external bolus insulin dose in the DoseStore and HealthKit
    ///
    /// - Parameters:
    ///   - dose: The dose to be added.
    func logOutsideInsulinDose(dose: DoseEntry, completion: @escaping (_ error: Error?) -> Void) {
        let doseList = [dose]

        doseStore.logOutsideDose(doseList) { (error) in
            if let error = error {
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

    func storeDosingDecision(withDate date: Date, withError error: Error? = nil) {
        getLoopState { (_, state) in
            self.doseStore.insulinOnBoard(at: date) { result in
                var insulinOnBoardError: Error?
                var insulinOnBoard: InsulinValue?

                switch result {
                case .failure(let error):
                    insulinOnBoardError = error
                case .success(let insulinValue):
                    insulinOnBoard = insulinValue
                }

                UNUserNotificationCenter.current().getNotificationSettings() { notificationSettings in
                    self.dataAccessQueue.async {
                        let dosingDecision = StoredDosingDecision(date: date,
                                                                  insulinOnBoard: insulinOnBoard,
                                                                  carbsOnBoard: state.carbsOnBoard,
                                                                  scheduleOverride: self.settings.scheduleOverride,
                                                                  glucoseTargetRangeSchedule: self.settings.glucoseTargetRangeSchedule,
                                                                  effectiveGlucoseTargetRangeSchedule: self.settings.effectiveGlucoseTargetRangeSchedule(),
                                                                  predictedGlucose: state.predictedGlucose,
                                                                  predictedGlucoseIncludingPendingInsulin: state.predictedGlucoseIncludingPendingInsulin,
                                                                  lastReservoirValue: StoredDosingDecision.LastReservoirValue(self.doseStore.lastReservoirValue),
                                                                  recommendedTempBasal: StoredDosingDecision.TempBasalRecommendationWithDate(state.recommendedTempBasal),
                                                                  recommendedBolus: StoredDosingDecision.BolusRecommendationWithDate(state.recommendedBolus),
                                                                  pumpManagerStatus: self.delegate?.pumpManagerStatus,
                                                                  notificationSettings: NotificationSettings(notificationSettings),
                                                                  deviceSettings: UIDevice.current.deviceSettings,
                                                                  errors: [error, state.error, insulinOnBoardError].compactMap { $0 })
                        self.dosingDecisionStore.storeDosingDecision(dosingDecision) {}
                    }
                }
            }
        }
    }

    func storeBolusDosingDecision(_ bolusDosingDecision: BolusDosingDecision, withDate date: Date) {
        let dosingDecision = StoredDosingDecision(date: date,
                                                  insulinOnBoard: bolusDosingDecision.insulinOnBoard,
                                                  carbsOnBoard: bolusDosingDecision.carbsOnBoard,
                                                  scheduleOverride: bolusDosingDecision.scheduleOverride,
                                                  glucoseTargetRangeSchedule: bolusDosingDecision.glucoseTargetRangeSchedule,
                                                  effectiveGlucoseTargetRangeSchedule: bolusDosingDecision.effectiveGlucoseTargetRangeSchedule,
                                                  predictedGlucoseIncludingPendingInsulin: bolusDosingDecision.predictedGlucoseIncludingPendingInsulin,
                                                  manualGlucose: bolusDosingDecision.manualGlucose.map { SimpleGlucoseValue($0) },
                                                  originalCarbEntry: bolusDosingDecision.originalCarbEntry,
                                                  carbEntry: bolusDosingDecision.carbEntry,
                                                  recommendedBolus: bolusDosingDecision.recommendedBolus.map { StoredDosingDecision.BolusRecommendationWithDate(recommendation: $0, date: date) },
                                                  requestedBolus: bolusDosingDecision.requestedBolus)
        self.dosingDecisionStore.storeDosingDecision(dosingDecision) {}
    }

    func storeSettings() {
        guard let appGroup = UserDefaults.appGroup, let loopSettings = appGroup.loopSettings else {
            return
        }

        let settings = StoredSettings(date: now(),
                                      dosingEnabled: loopSettings.dosingEnabled,
                                      glucoseTargetRangeSchedule: loopSettings.glucoseTargetRangeSchedule,
                                      preMealTargetRange: loopSettings.preMealTargetRange,
                                      workoutTargetRange: loopSettings.legacyWorkoutTargetRange,
                                      overridePresets: loopSettings.overridePresets,
                                      scheduleOverride: loopSettings.scheduleOverride,
                                      preMealOverride: loopSettings.preMealOverride,
                                      maximumBasalRatePerHour: loopSettings.maximumBasalRatePerHour,
                                      maximumBolus: loopSettings.maximumBolus,
                                      suspendThreshold: loopSettings.suspendThreshold,
                                      deviceToken: loopSettings.deviceToken?.hexadecimalString,
                                      insulinModel: appGroup.insulinModelSettings.map { StoredInsulinModel($0) },
                                      basalRateSchedule: appGroup.basalRateSchedule,
                                      insulinSensitivitySchedule: appGroup.insulinSensitivitySchedule,
                                      carbRatioSchedule: appGroup.carbRatioSchedule,
                                      bloodGlucoseUnit: loopSettings.glucoseUnit)
        self.settingsStore.storeSettings(settings) {}
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
            self.logger.default("Loop running")
            NotificationCenter.default.post(name: .LoopRunning, object: self)

            self.lastLoopError = nil
            let startDate = self.now()

            do {
                try self.update()

                if self.delegate?.automaticDosingEnabled == true {
                    self.setRecommendedTempBasal { (error) -> Void in
                        if let error = error {
                            self.loopDidError(date: self.now(), error: error, duration: -startDate.timeIntervalSince(self.now()))
                        } else {
                            self.loopDidComplete(date: self.now(), duration: -startDate.timeIntervalSince(self.now()))
                        }
                        self.logger.default("Loop ended")
                        self.notify(forChange: .tempBasal)
                    }

                    // Delay the notification until we know the result of the temp basal
                    return
                } else {
                    self.loopDidComplete(date: self.now(), duration: -startDate.timeIntervalSince(self.now()))
                }
            } catch let error {
                self.loopDidError(date: self.now(), error: error, duration: -startDate.timeIntervalSince(self.now()))
            }

            self.logger.default("Loop ended")
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
        glucoseStore.getGlucoseSamples(start: Date(timeInterval: -LoopCoreConstants.inputDataRecencyInterval, since: now()), end: nil) { (result) in
            switch result {
            case .failure(let error):
                self.logger.error("Failure getting glucose samples: %{public}@", String(describing: error))
                latestGlucoseDate = nil
            case .success(let samples):
                latestGlucoseDate = samples.last?.startDate
            }
            updateGroup.leave()
        }
        _ = updateGroup.wait(timeout: .distantFuture)

        guard let lastGlucoseDate = latestGlucoseDate else {
            throw LoopError.missingDataError(.glucose)
        }

        let retrospectiveStart = lastGlucoseDate.addingTimeInterval(-retrospectiveCorrection.retrospectionInterval)

        let earliestEffectDate = Date(timeInterval: .hours(-24), since: now())
        let nextEffectDate = insulinCounteractionEffects.last?.endDate ?? earliestEffectDate

        if glucoseMomentumEffect == nil {
            updateGroup.enter()
            glucoseStore.getRecentMomentumEffect { (result) -> Void in
                switch result {
                case .failure(let error):
                    self.logger.error("Failure getting recent momentum effect: %{public}@", String(describing: error))
                    self.glucoseMomentumEffect = nil
                case .success(let effects):
                    self.glucoseMomentumEffect = effects
                }
                updateGroup.leave()
            }
        }

        if insulinEffect == nil {
            self.logger.debug("Recomputing insulin effects")
            updateGroup.enter()
            doseStore.getGlucoseEffects(start: nextEffectDate, end: nil, basalDosingEnd: now()) { (result) -> Void in
                switch result {
                case .failure(let error):
                    self.logger.error("%{public}@", String(describing: error))
                    self.insulinEffect = nil
                case .success(let effects):
                    self.insulinEffect = effects
                }

                updateGroup.leave()
            }
        }

        if insulinEffectIncludingPendingInsulin == nil {
            updateGroup.enter()
            doseStore.getGlucoseEffects(start: nextEffectDate, end: nil, basalDosingEnd: nil) { (result) -> Void in
                switch result {
                case .failure(let error):
                    self.logger.error("Could not fetch insulin effects: %{public}@", String(describing: error))
                    self.insulinEffectIncludingPendingInsulin = nil
                case .success(let effects):
                    self.insulinEffectIncludingPendingInsulin = effects
                }

                updateGroup.leave()
            }
        }

        _ = updateGroup.wait(timeout: .distantFuture)

        if nextEffectDate < lastGlucoseDate, let insulinEffect = insulinEffect {
            updateGroup.enter()
            self.logger.debug("Fetching counteraction effects after %{public}@", String(describing: nextEffectDate))
            glucoseStore.getCounteractionEffects(start: nextEffectDate, end: nil, to: insulinEffect) { (result) in
                switch result {
                case .failure(let error):
                    self.logger.error("Failure getting counteraction effects: %{public}@", String(describing: error))
                case .success(let velocities):
                    self.insulinCounteractionEffects.append(contentsOf: velocities)
                }
                self.insulinCounteractionEffects = self.insulinCounteractionEffects.filterDateRange(earliestEffectDate, nil)

                updateGroup.leave()
            }

            _ = updateGroup.wait(timeout: .distantFuture)
        }

        if carbEffect == nil {
            updateGroup.enter()
            carbStore.getGlucoseEffects(
                start: retrospectiveStart, end: nil,
                effectVelocities: settings.dynamicCarbAbsorptionEnabled ? insulinCounteractionEffects : nil
            ) { (result) -> Void in
                switch result {
                case .failure(let error):
                    self.logger.error("%{public}@", String(describing: error))
                    self.carbEffect = nil
                    self.recentCarbEntries = nil
                case .success(let (entries, effects)):
                    self.carbEffect = effects
                    self.recentCarbEntries = entries
                }

                updateGroup.leave()
            }
        }

        if carbsOnBoard == nil {
            updateGroup.enter()
            carbStore.carbsOnBoard(at: now(), effectVelocities: settings.dynamicCarbAbsorptionEnabled ? insulinCounteractionEffects : nil) { (result) in
                switch result {
                case .failure(let error):
                    switch error {
                    case .noData:
                        // when there is no data, carbs on board is set to 0
                        self.carbsOnBoard = CarbValue(startDate: Date(), quantity: HKQuantity(unit: .gram(), doubleValue: 0))
                    default:
                        self.carbsOnBoard = nil
                    }
                case .success(let value):
                    self.carbsOnBoard = value
                }
                updateGroup.leave()
            }
        }

        _ = updateGroup.wait(timeout: .distantFuture)

        if retrospectiveGlucoseDiscrepancies == nil {
            do {
                try updateRetrospectiveGlucoseEffect()
            } catch let error {
                logger.error("%{public}@", String(describing: error))
            }
        }

        if predictedGlucose == nil {
            do {
                try updatePredictedGlucoseAndRecommendedBasalAndBolus()
            } catch let error {
                logger.error("%{public}@", String(describing: error))

                throw error
            }
        }
    }

    private func notify(forChange context: LoopUpdateContext) {
        if case .preferences = context {
            storeSettings()
        }

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

        guard let basalRates = basalRateScheduleApplyingOverrideHistory else {
            throw LoopError.configurationError(.basalRateSchedule)
        }

        let pendingTempBasalInsulin: Double
        let date = now()

        if let basalDeliveryState = basalDeliveryState, case .tempBasal(let lastTempBasal) = basalDeliveryState, lastTempBasal.endDate > date {
            let normalBasalRate = basalRates.value(at: date)
            let remainingTime = lastTempBasal.endDate.timeIntervalSince(date)
            let remainingUnits = (lastTempBasal.unitsPerHour - normalBasalRate) * remainingTime.hours

            pendingTempBasalInsulin = max(0, remainingUnits)
        } else {
            pendingTempBasalInsulin = 0
        }

        let pendingBolusAmount: Double = lastRequestedBolus?.programmedUnits ?? 0

        // All outstanding potential insulin delivery
        return pendingTempBasalInsulin + pendingBolusAmount
    }

    /// - Throws:
    ///     - LoopError.missingDataError
    ///     - LoopError.configurationError
    ///     - LoopError.glucoseTooOld
    ///     - LoopError.pumpDataTooOld
    fileprivate func predictGlucose(
        startingAt startingGlucoseOverride: GlucoseValue? = nil,
        using inputs: PredictionInputEffect,
        historicalInsulinEffect insulinEffectOverride: [GlucoseEffect]? = nil,
        insulinCounteractionEffects insulinCounteractionEffectsOverride: [GlucoseEffectVelocity]? = nil,
        historicalCarbEffect carbEffectOverride: [GlucoseEffect]? = nil,
        potentialBolus: DoseEntry? = nil,
        potentialCarbEntry: NewCarbEntry? = nil,
        replacingCarbEntry replacedCarbEntry: StoredCarbEntry? = nil,
        includingPendingInsulin: Bool = false
    ) throws -> [PredictedGlucoseValue] {
        dispatchPrecondition(condition: .onQueue(dataAccessQueue))

        guard let insulinModelSettings = insulinModelSettings else {
            throw LoopError.configurationError(.insulinModel)
        }

        guard let glucose = startingGlucoseOverride ?? self.glucoseStore.latestGlucose else {
            throw LoopError.missingDataError(.glucose)
        }

        let pumpStatusDate = doseStore.lastAddedPumpData
        let lastGlucoseDate = glucose.startDate

        guard now().timeIntervalSince(lastGlucoseDate) <= LoopCoreConstants.inputDataRecencyInterval else {
            throw LoopError.glucoseTooOld(date: glucose.startDate)
        }

        guard now().timeIntervalSince(pumpStatusDate) <= LoopCoreConstants.inputDataRecencyInterval else {
            throw LoopError.pumpDataTooOld(date: pumpStatusDate)
        }

        var momentum: [GlucoseEffect] = []
        var retrospectiveGlucoseEffect = self.retrospectiveGlucoseEffect
        var effects: [[GlucoseEffect]] = []

        let insulinCounteractionEffects = insulinCounteractionEffectsOverride ?? self.insulinCounteractionEffects
        if inputs.contains(.carbs) {
            if let potentialCarbEntry = potentialCarbEntry {
                let retrospectiveStart = lastGlucoseDate.addingTimeInterval(-retrospectiveCorrection.retrospectionInterval)

                if potentialCarbEntry.startDate > lastGlucoseDate || recentCarbEntries?.isEmpty != false, replacedCarbEntry == nil {
                    // The potential carb effect is independent and can be summed with the existing effect
                    if let carbEffect = carbEffectOverride ?? self.carbEffect {
                        effects.append(carbEffect)
                    }

                    let potentialCarbEffect = try carbStore.glucoseEffects(
                        of: [potentialCarbEntry],
                        startingAt: retrospectiveStart,
                        endingAt: nil,
                        effectVelocities: settings.dynamicCarbAbsorptionEnabled ? insulinCounteractionEffects : nil
                    )

                    effects.append(potentialCarbEffect)
                } else {
                    var recentEntries = self.recentCarbEntries ?? []
                    if let replacedCarbEntry = replacedCarbEntry, let index = recentEntries.firstIndex(of: replacedCarbEntry) {
                        recentEntries.remove(at: index)
                    }

                    // If the entry is in the past or an entry is replaced, DCA and RC effects must be recomputed
                    var entries = recentEntries.map { NewCarbEntry(quantity: $0.quantity, startDate: $0.startDate, foodType: nil, absorptionTime: $0.absorptionTime) }
                    entries.append(potentialCarbEntry)
                    entries.sort(by: { $0.startDate > $1.startDate })

                    let potentialCarbEffect = try carbStore.glucoseEffects(
                        of: entries,
                        startingAt: retrospectiveStart,
                        endingAt: nil,
                        effectVelocities: settings.dynamicCarbAbsorptionEnabled ? insulinCounteractionEffects : nil
                    )

                    effects.append(potentialCarbEffect)

                    retrospectiveGlucoseEffect = computeRetrospectiveGlucoseEffect(startingAt: glucose, carbEffects: potentialCarbEffect)
                }
            } else if let carbEffect = carbEffectOverride ?? self.carbEffect {
                effects.append(carbEffect)
            }
        }

        if inputs.contains(.insulin) {
            let computationInsulinEffect: [GlucoseEffect]?
            if insulinEffectOverride != nil {
                computationInsulinEffect = insulinEffectOverride
            } else {
                computationInsulinEffect = includingPendingInsulin ? self.insulinEffectIncludingPendingInsulin : self.insulinEffect
            }

            if let insulinEffect = computationInsulinEffect {
                effects.append(insulinEffect)
            }

            if let potentialBolus = potentialBolus {
                guard let sensitivity = insulinSensitivityScheduleApplyingOverrideHistory else {
                    throw LoopError.configurationError(.generalSettings)
                }

                let earliestEffectDate = Date(timeInterval: .hours(-24), since: now())
                let nextEffectDate = insulinCounteractionEffects.last?.endDate ?? earliestEffectDate
                let bolusEffect = [potentialBolus]
                    .glucoseEffects(insulinModelSettings: insulinModelSettings, insulinSensitivity: sensitivity)
                    .filterDateRange(nextEffectDate, nil)
                effects.append(bolusEffect)
            }
        }

        if inputs.contains(.momentum), let momentumEffect = self.glucoseMomentumEffect {
            momentum = momentumEffect
        }

        if inputs.contains(.retrospection) {
            effects.append(retrospectiveGlucoseEffect)
        }

        var prediction = LoopMath.predictGlucose(startingAt: glucose, momentum: momentum, effects: effects)

        // Dosing requires prediction entries at least as long as the insulin model duration.
        // If our prediction is shorter than that, then extend it here.
        let finalDate = glucose.startDate.addingTimeInterval(insulinModelSettings.longestEffectDuration)
        if let last = prediction.last, last.startDate < finalDate {
            prediction.append(PredictedGlucoseValue(startDate: finalDate, quantity: last.quantity))
        }

        return prediction
    }

    fileprivate func predictGlucoseFromManualGlucose(
        _ glucose: NewGlucoseSample,
        potentialBolus: DoseEntry?,
        potentialCarbEntry: NewCarbEntry?,
        replacingCarbEntry replacedCarbEntry: StoredCarbEntry?,
        includingPendingInsulin: Bool
    ) throws -> [PredictedGlucoseValue] {
        let retrospectiveStart = glucose.date.addingTimeInterval(-retrospectiveCorrection.retrospectionInterval)
        let earliestEffectDate = Date(timeInterval: .hours(-24), since: now())
        let nextEffectDate = insulinCounteractionEffects.last?.endDate ?? earliestEffectDate

        let updateGroup = DispatchGroup()
        let effectCalculationError = Locked<Error?>(nil)

        var insulinEffect: [GlucoseEffect]?
        let basalDosingEnd = includingPendingInsulin ? nil : now()
        updateGroup.enter()
        doseStore.getGlucoseEffects(start: nextEffectDate, end: nil, basalDosingEnd: basalDosingEnd) { result in
            switch result {
            case .failure(let error):
                effectCalculationError.mutate { $0 = error }
            case .success(let effects):
                insulinEffect = effects
            }

            updateGroup.leave()
        }

        updateGroup.wait()

        if let error = effectCalculationError.value {
            throw error
        }

        var insulinCounteractionEffects = self.insulinCounteractionEffects
        if nextEffectDate < glucose.date, let insulinEffect = insulinEffect {
            updateGroup.enter()
            glucoseStore.getGlucoseSamples(start: nextEffectDate, end: nil) { result in
                switch result {
                case .failure(let error):
                    self.logger.error("Failure getting glucose samples: %{public}@", String(describing: error))
                case .success(let samples):
                    var samples = samples
                    let manualSample = StoredGlucoseSample(sample: glucose.quantitySample)
                    let insertionIndex = samples.partitioningIndex(where: { manualSample.startDate < $0.startDate })
                    samples.insert(manualSample, at: insertionIndex)
                    let velocities = self.glucoseStore.counteractionEffects(for: samples, to: insulinEffect)
                    insulinCounteractionEffects.append(contentsOf: velocities)
                }
                insulinCounteractionEffects = insulinCounteractionEffects.filterDateRange(earliestEffectDate, nil)

                updateGroup.leave()
            }

            updateGroup.wait()
        }

        var carbEffect: [GlucoseEffect]?
        updateGroup.enter()
        carbStore.getGlucoseEffects(
            start: retrospectiveStart, end: nil,
            effectVelocities: settings.dynamicCarbAbsorptionEnabled ? insulinCounteractionEffects : nil
        ) { result in
            switch result {
            case .failure(let error):
                effectCalculationError.mutate { $0 = error }
            case .success(let (_, effects)):
                carbEffect = effects
            }

            updateGroup.leave()
        }

        updateGroup.wait()

        if let error = effectCalculationError.value {
            throw error
        }

        return try predictGlucose(
            startingAt: glucose.quantitySample,
            using: [.insulin, .carbs],
            historicalInsulinEffect: insulinEffect,
            insulinCounteractionEffects: insulinCounteractionEffects,
            historicalCarbEffect: carbEffect,
            potentialBolus: potentialBolus,
            potentialCarbEntry: potentialCarbEntry,
            replacingCarbEntry: replacedCarbEntry,
            includingPendingInsulin: true
        )
    }

    fileprivate func recommendBolusForManualGlucose(_ glucose: NewGlucoseSample, consideringPotentialCarbEntry potentialCarbEntry: NewCarbEntry?, replacingCarbEntry replacedCarbEntry: StoredCarbEntry?) throws -> BolusRecommendation? {
        guard lastRequestedBolus == nil else {
            // Don't recommend changes if a bolus was just requested.
            // Sending additional pump commands is not going to be
            // successful in any case.
            return nil
        }

        let pendingInsulin = try getPendingInsulin()
        let shouldIncludePendingInsulin = pendingInsulin > 0
        let prediction = try predictGlucoseFromManualGlucose(glucose, potentialBolus: nil, potentialCarbEntry: potentialCarbEntry, replacingCarbEntry: replacedCarbEntry, includingPendingInsulin: shouldIncludePendingInsulin)
        return try recommendBolus(forPrediction: prediction, consideringPotentialCarbEntry: potentialCarbEntry)
    }

    /// - Throws: LoopError.missingDataError
    fileprivate func recommendBolus(consideringPotentialCarbEntry potentialCarbEntry: NewCarbEntry?, replacingCarbEntry replacedCarbEntry: StoredCarbEntry?) throws -> BolusRecommendation? {
        guard lastRequestedBolus == nil else {
            // Don't recommend changes if a bolus was just requested.
            // Sending additional pump commands is not going to be
            // successful in any case.
            return nil
        }

        let pendingInsulin = try getPendingInsulin()
        let shouldIncludePendingInsulin = pendingInsulin > 0
        let prediction = try predictGlucose(using: .all, potentialBolus: nil, potentialCarbEntry: potentialCarbEntry, replacingCarbEntry: replacedCarbEntry, includingPendingInsulin: shouldIncludePendingInsulin)
        return try recommendBolusValidatingDataRecency(forPrediction: prediction, consideringPotentialCarbEntry: potentialCarbEntry)
    }

    /// - Throws:
    ///     - LoopError.missingDataError
    ///     - LoopError.glucoseTooOld
    ///     - LoopError.pumpDataTooOld
    ///     - LoopError.configurationError
    fileprivate func recommendBolusValidatingDataRecency<Sample: GlucoseValue>(forPrediction predictedGlucose: [Sample],
                                                                               consideringPotentialCarbEntry potentialCarbEntry: NewCarbEntry?) throws -> BolusRecommendation? {
        guard let glucose = glucoseStore.latestGlucose else {
            throw LoopError.missingDataError(.glucose)
        }

        let pumpStatusDate = doseStore.lastAddedPumpData
        let lastGlucoseDate = glucose.startDate

        guard now().timeIntervalSince(lastGlucoseDate) <= LoopCoreConstants.inputDataRecencyInterval else {
            throw LoopError.glucoseTooOld(date: glucose.startDate)
        }

        guard now().timeIntervalSince(pumpStatusDate) <= LoopCoreConstants.inputDataRecencyInterval else {
            throw LoopError.pumpDataTooOld(date: pumpStatusDate)
        }

        guard glucoseMomentumEffect != nil else {
            throw LoopError.missingDataError(.momentumEffect)
        }

        guard carbEffect != nil else {
            throw LoopError.missingDataError(.carbEffect)
        }

        guard insulinEffect != nil else {
            throw LoopError.missingDataError(.insulinEffect)
        }

        return try recommendBolus(forPrediction: predictedGlucose, consideringPotentialCarbEntry: potentialCarbEntry)
    }
    
    /// - Throws: LoopError.configurationError
    private func recommendBolus<Sample: GlucoseValue>(forPrediction predictedGlucose: [Sample],
                                                      consideringPotentialCarbEntry potentialCarbEntry: NewCarbEntry?) throws -> BolusRecommendation? {
        guard
            let glucoseTargetRange = settings.effectiveGlucoseTargetRangeSchedule(presumingMealEntry: potentialCarbEntry != nil),
            let insulinSensitivity = insulinSensitivityScheduleApplyingOverrideHistory,
            let maxBolus = settings.maximumBolus,
            let insulinModelSettings = insulinModelSettings,
            let insulinType = pumpInsulinType
        else {
            throw LoopError.configurationError(.generalSettings)
        }

        guard lastRequestedBolus == nil
        else {
            // Don't recommend changes if a bolus was just requested.
            // Sending additional pump commands is not going to be
            // successful in any case.
            return nil
        }

        let volumeRounder = { (_ units: Double) in
            return self.delegate?.loopDataManager(self, roundBolusVolume: units) ?? units
        }
        
        let model = insulinModelSettings.model(for: insulinType)

        return predictedGlucose.recommendedBolus(
            to: glucoseTargetRange,
            suspendThreshold: settings.suspendThreshold?.quantity,
            sensitivity: insulinSensitivity,
            model: model,
            pendingInsulin: 0, // Pending insulin is already reflected in the prediction
            maxBolus: maxBolus,
            volumeRounder: volumeRounder
        )
    }

    /// Generates a correction effect based on how large the discrepancy is between the current glucose and its model predicted value.
    ///
    /// - Throws: LoopError.missingDataError
    private func updateRetrospectiveGlucoseEffect() throws {
        dispatchPrecondition(condition: .onQueue(dataAccessQueue))

        // Get carb effects, otherwise clear effect and throw error
        guard let carbEffects = self.carbEffect else {
            retrospectiveGlucoseDiscrepancies = nil
            retrospectiveGlucoseEffect = []
            throw LoopError.missingDataError(.carbEffect)
        }

        // Get most recent glucose, otherwise clear effect and throw error
        guard let glucose = self.glucoseStore.latestGlucose else {
            retrospectiveGlucoseEffect = []
            throw LoopError.missingDataError(.glucose)
        }

        // Get timeline of glucose discrepancies
        retrospectiveGlucoseDiscrepancies = insulinCounteractionEffects.subtracting(carbEffects, withUniformInterval: carbStore.delta)

        // Calculate retrospective correction
        retrospectiveGlucoseEffect = retrospectiveCorrection.computeEffect(
            startingAt: glucose,
            retrospectiveGlucoseDiscrepanciesSummed: retrospectiveGlucoseDiscrepanciesSummed,
            recencyInterval: LoopCoreConstants.inputDataRecencyInterval,
            insulinSensitivitySchedule: insulinSensitivitySchedule,
            basalRateSchedule: basalRateSchedule,
            glucoseCorrectionRangeSchedule: settings.glucoseTargetRangeSchedule,
            retrospectiveCorrectionGroupingInterval: LoopConstants.retrospectiveCorrectionGroupingInterval
        )
    }

    private func computeRetrospectiveGlucoseEffect(startingAt glucose: GlucoseValue, carbEffects: [GlucoseEffect]) -> [GlucoseEffect] {
        let retrospectiveGlucoseDiscrepancies = insulinCounteractionEffects.subtracting(carbEffects, withUniformInterval: carbStore.delta)
        let retrospectiveGlucoseDiscrepanciesSummed = retrospectiveGlucoseDiscrepancies.combinedSums(of: LoopConstants.retrospectiveCorrectionGroupingInterval * retrospectiveCorrectionGroupingIntervalMultiplier)
        return retrospectiveCorrection.computeEffect(
            startingAt: glucose,
            retrospectiveGlucoseDiscrepanciesSummed: retrospectiveGlucoseDiscrepanciesSummed,
            recencyInterval: LoopCoreConstants.inputDataRecencyInterval,
            insulinSensitivitySchedule: insulinSensitivitySchedule,
            basalRateSchedule: basalRateSchedule,
            glucoseCorrectionRangeSchedule: settings.glucoseTargetRangeSchedule,
            retrospectiveCorrectionGroupingInterval: LoopConstants.retrospectiveCorrectionGroupingInterval
        )
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

        self.logger.debug("Recomputing prediction and recommendations.")

        guard let glucose = glucoseStore.latestGlucose else {
            self.predictedGlucose = nil
            throw LoopError.missingDataError(.glucose)
        }

        let pumpStatusDate = doseStore.lastAddedPumpData

        let startDate = now()

        guard startDate.timeIntervalSince(glucose.startDate) <= LoopCoreConstants.inputDataRecencyInterval else {
            self.predictedGlucose = nil
            throw LoopError.glucoseTooOld(date: glucose.startDate)
        }

        guard startDate.timeIntervalSince(pumpStatusDate) <= LoopCoreConstants.inputDataRecencyInterval else {
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

        guard insulinEffect != nil, insulinEffectIncludingPendingInsulin != nil else {
            self.predictedGlucose = nil
            throw LoopError.missingDataError(.insulinEffect)
        }

        let predictedGlucose = try predictGlucose(using: settings.enabledEffects)
        self.predictedGlucose = predictedGlucose
        let predictedGlucoseIncludingPendingInsulin = try predictGlucose(using: settings.enabledEffects, includingPendingInsulin: true)
        self.predictedGlucoseIncludingPendingInsulin = predictedGlucoseIncludingPendingInsulin

        guard
            let maxBasal = settings.maximumBasalRatePerHour,
            let glucoseTargetRange = settings.effectiveGlucoseTargetRangeSchedule(),
            let insulinSensitivity = insulinSensitivityScheduleApplyingOverrideHistory,
            let basalRates = basalRateScheduleApplyingOverrideHistory,
            let maxBolus = settings.maximumBolus,
            let insulinModelSettings = insulinModelSettings,
            let insulinType = pumpInsulinType
        else {
            throw LoopError.configurationError(.generalSettings)
        }

        guard lastRequestedBolus == nil
        else {
            // Don't recommend changes if a bolus was just requested.
            // Sending additional pump commands is not going to be
            // successful in any case.
            self.logger.debug("Not generating recommendations because bolus request is in progress.")
            return
        }

        let rateRounder = { (_ rate: Double) in
            return self.delegate?.loopDataManager(self, roundBasalRate: rate) ?? rate
        }

        let lastTempBasal: DoseEntry?

        if case .some(.tempBasal(let dose)) = basalDeliveryState {
            lastTempBasal = dose
        } else {
            lastTempBasal = nil
        }

        let tempBasal = predictedGlucose.recommendedTempBasal(
            to: glucoseTargetRange,
            at: predictedGlucose[0].startDate,
            suspendThreshold: settings.suspendThreshold?.quantity,
            sensitivity: insulinSensitivity,
            model: insulinModelSettings.model(for: insulinType),
            basalRates: basalRates,
            maxBasalRate: maxBasal,
            lastTempBasal: lastTempBasal,
            rateRounder: rateRounder,
            isBasalRateScheduleOverrideActive: settings.scheduleOverride?.isBasalRateScheduleOverriden(at: startDate) == true
        )

        if let temp = tempBasal {
            self.logger.default("Current basal state: %{public}@", String(describing: basalDeliveryState))
            self.logger.default("Recommending temp basal: %{public}@ at %{public}@", String(describing: temp), String(describing: startDate))
            recommendedTempBasal = (recommendation: temp, date: startDate)
        } else {
            recommendedTempBasal = nil
        }

        let volumeRounder = { (_ units: Double) in
            return self.delegate?.loopDataManager(self, roundBolusVolume: units) ?? units
        }

        let pendingInsulin = try getPendingInsulin()
        let predictionDrivingBolusRecommendation = pendingInsulin > 0 ? predictedGlucoseIncludingPendingInsulin : predictedGlucose
        let recommendation = predictionDrivingBolusRecommendation.recommendedBolus(
            to: glucoseTargetRange,
            at: predictedGlucose[0].startDate,
            suspendThreshold: settings.suspendThreshold?.quantity,
            sensitivity: insulinSensitivity,
            model: insulinModelSettings.model(for: insulinType),
            pendingInsulin: 0, // Pending insulin is already reflected in the prediction
            maxBolus: maxBolus,
            volumeRounder: volumeRounder
        )
        recommendedBolus = (recommendation: recommendation, date: startDate)
        self.logger.debug("Recommending bolus: %{public}@", String(describing: recommendedBolus))
    }

    /// *This method should only be called from the `dataAccessQueue`*
    private func setRecommendedTempBasal(_ completion: @escaping (_ error: Error?) -> Void) {
        dispatchPrecondition(condition: .onQueue(dataAccessQueue))

        guard let recommendedTempBasal = self.recommendedTempBasal else {
            completion(nil)
            return
        }

        guard abs(recommendedTempBasal.date.timeIntervalSince(now())) < TimeInterval(minutes: 5) else {
            completion(LoopError.recommendationExpired(date: recommendedTempBasal.date))
            return
        }

        delegate?.loopDataManager(self, didRecommendBasalChange: recommendedTempBasal) { (result) in
            self.dataAccessQueue.async {
                switch result {
                case .success:
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

    /// The calculated timeline of predicted glucose values
    var predictedGlucose: [PredictedGlucoseValue]? { get }

    /// The calculated timeline of predicted glucose values, including the effects of pending insulin
    var predictedGlucoseIncludingPendingInsulin: [PredictedGlucoseValue]? { get }

    /// The recommended temp basal based on predicted glucose
    var recommendedTempBasal: (recommendation: TempBasalRecommendation, date: Date)? { get }

    var recommendedBolus: (recommendation: BolusRecommendation, date: Date)? { get }

    /// The difference in predicted vs actual glucose over a recent period
    var retrospectiveGlucoseDiscrepancies: [GlucoseChange]? { get }

    /// The total corrective glucose effect from retrospective correction
    var totalRetrospectiveCorrection: HKQuantity? { get }

    /// Calculates a new prediction from the current data using the specified effect inputs
    ///
    /// This method is intended for visualization purposes only, not dosing calculation. No validation of input data is done.
    ///
    /// - Parameter inputs: The effect inputs to include
    /// - Parameter potentialBolus: A bolus under consideration for which to include effects in the prediction
    /// - Parameter potentialCarbEntry: A carb entry under consideration for which to include effects in the prediction
    /// - Parameter replacedCarbEntry: An existing carb entry replaced by `potentialCarbEntry`
    /// - Parameter includingPendingInsulin: If `true`, the returned prediction will include the effects of scheduled but not yet delivered insulin
    /// - Returns: An timeline of predicted glucose values
    /// - Throws: LoopError.missingDataError if prediction cannot be computed
    func predictGlucose(using inputs: PredictionInputEffect, potentialBolus: DoseEntry?, potentialCarbEntry: NewCarbEntry?, replacingCarbEntry replacedCarbEntry: StoredCarbEntry?, includingPendingInsulin: Bool) throws -> [PredictedGlucoseValue]

    /// Calculates a new prediction from a manual glucose entry in the context of a meal entry
    ///
    /// - Parameter glucose: The unstored manual glucose entry
    /// - Parameter potentialBolus: A bolus under consideration for which to include effects in the prediction
    /// - Parameter potentialCarbEntry: A carb entry under consideration for which to include effects in the prediction
    /// - Parameter replacedCarbEntry: An existing carb entry replaced by `potentialCarbEntry`
    /// - Parameter includingPendingInsulin: If `true`, the returned prediction will include the effects of scheduled but not yet delivered insulin
    /// - Returns: A timeline of predicted glucose values
    func predictGlucoseFromManualGlucose(
        _ glucose: NewGlucoseSample,
        potentialBolus: DoseEntry?,
        potentialCarbEntry: NewCarbEntry?,
        replacingCarbEntry replacedCarbEntry: StoredCarbEntry?,
        includingPendingInsulin: Bool
    ) throws -> [PredictedGlucoseValue]

    /// Computes the recommended bolus for correcting a glucose prediction, optionally considering a potential carb entry.
    /// - Parameter potentialCarbEntry: A carb entry under consideration for which to include effects in the prediction
    /// - Parameter replacedCarbEntry: An existing carb entry replaced by `potentialCarbEntry`
    /// - Returns: A bolus recommendation, or `nil` if not applicable
    /// - Throws: LoopError.missingDataError if recommendation cannot be computed
    func recommendBolus(consideringPotentialCarbEntry potentialCarbEntry: NewCarbEntry?, replacingCarbEntry replacedCarbEntry: StoredCarbEntry?) throws -> BolusRecommendation?

    /// Computes the recommended bolus for correcting a glucose prediction derived from a manual glucose entry, optionally considering a potential carb entry.
    /// - Parameter glucose: The unstored manual glucose entry
    /// - Parameter potentialCarbEntry: A carb entry under consideration for which to include effects in the prediction
    /// - Parameter replacedCarbEntry: An existing carb entry replaced by `potentialCarbEntry`
    /// - Returns: A bolus recommendation, or `nil` if not applicable
    /// - Throws: LoopError.configurationError if recommendation cannot be computed
    func recommendBolusForManualGlucose(_ glucose: NewGlucoseSample, consideringPotentialCarbEntry potentialCarbEntry: NewCarbEntry?, replacingCarbEntry replacedCarbEntry: StoredCarbEntry?) throws -> BolusRecommendation?
}

extension LoopState {
    /// Calculates a new prediction from the current data using the specified effect inputs
    ///
    /// This method is intended for visualization purposes only, not dosing calculation. No validation of input data is done.
    ///
    /// - Parameter inputs: The effect inputs to include
    /// - Parameter includingPendingInsulin: If `true`, the returned prediction will include the effects of scheduled but not yet delivered insulin
    /// - Returns: An timeline of predicted glucose values
    /// - Throws: LoopError.missingDataError if prediction cannot be computed
    func predictGlucose(using inputs: PredictionInputEffect, includingPendingInsulin: Bool = false) throws -> [GlucoseValue] {
        try predictGlucose(using: inputs, potentialBolus: nil, potentialCarbEntry: nil, replacingCarbEntry: nil, includingPendingInsulin: includingPendingInsulin)
    }
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

        var predictedGlucose: [PredictedGlucoseValue]? {
            dispatchPrecondition(condition: .onQueue(loopDataManager.dataAccessQueue))
            return loopDataManager.predictedGlucose
        }

        var predictedGlucoseIncludingPendingInsulin: [PredictedGlucoseValue]? {
            dispatchPrecondition(condition: .onQueue(loopDataManager.dataAccessQueue))
            return loopDataManager.predictedGlucoseIncludingPendingInsulin
        }

        var recommendedTempBasal: (recommendation: TempBasalRecommendation, date: Date)? {
            dispatchPrecondition(condition: .onQueue(loopDataManager.dataAccessQueue))
            guard loopDataManager.lastRequestedBolus == nil else {
                return nil
            }
            return loopDataManager.recommendedTempBasal
        }

        var recommendedBolus: (recommendation: BolusRecommendation, date: Date)? {
            dispatchPrecondition(condition: .onQueue(loopDataManager.dataAccessQueue))
            guard loopDataManager.lastRequestedBolus == nil else {
                return nil
            }
            return loopDataManager.recommendedBolus
        }

        var retrospectiveGlucoseDiscrepancies: [GlucoseChange]? {
            dispatchPrecondition(condition: .onQueue(loopDataManager.dataAccessQueue))
            return loopDataManager.retrospectiveGlucoseDiscrepanciesSummed
        }

        var totalRetrospectiveCorrection: HKQuantity? {
            dispatchPrecondition(condition: .onQueue(loopDataManager.dataAccessQueue))
            return loopDataManager.retrospectiveCorrection.totalGlucoseCorrectionEffect
        }

        func predictGlucose(using inputs: PredictionInputEffect, potentialBolus: DoseEntry?, potentialCarbEntry: NewCarbEntry?, replacingCarbEntry replacedCarbEntry: StoredCarbEntry?, includingPendingInsulin: Bool) throws -> [PredictedGlucoseValue] {
            dispatchPrecondition(condition: .onQueue(loopDataManager.dataAccessQueue))
            return try loopDataManager.predictGlucose(using: inputs, potentialBolus: potentialBolus, potentialCarbEntry: potentialCarbEntry, replacingCarbEntry: replacedCarbEntry, includingPendingInsulin: includingPendingInsulin)
        }

        func predictGlucoseFromManualGlucose(
            _ glucose: NewGlucoseSample,
            potentialBolus: DoseEntry?,
            potentialCarbEntry: NewCarbEntry?,
            replacingCarbEntry replacedCarbEntry: StoredCarbEntry?,
            includingPendingInsulin: Bool
        ) throws -> [PredictedGlucoseValue] {
            dispatchPrecondition(condition: .onQueue(loopDataManager.dataAccessQueue))
            return try loopDataManager.predictGlucoseFromManualGlucose(glucose, potentialBolus: potentialBolus, potentialCarbEntry: potentialCarbEntry, replacingCarbEntry: replacedCarbEntry, includingPendingInsulin: includingPendingInsulin)
        }

        func recommendBolus(consideringPotentialCarbEntry potentialCarbEntry: NewCarbEntry?, replacingCarbEntry replacedCarbEntry: StoredCarbEntry?) throws -> BolusRecommendation? {
            dispatchPrecondition(condition: .onQueue(loopDataManager.dataAccessQueue))
            return try loopDataManager.recommendBolus(consideringPotentialCarbEntry: potentialCarbEntry, replacingCarbEntry: replacedCarbEntry)
        }

        func recommendBolusForManualGlucose(_ glucose: NewGlucoseSample, consideringPotentialCarbEntry potentialCarbEntry: NewCarbEntry?, replacingCarbEntry replacedCarbEntry: StoredCarbEntry?) throws -> BolusRecommendation? {
            dispatchPrecondition(condition: .onQueue(loopDataManager.dataAccessQueue))
            return try loopDataManager.recommendBolusForManualGlucose(glucose, consideringPotentialCarbEntry: potentialCarbEntry, replacingCarbEntry: replacedCarbEntry)
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
                self.logger.debug("getLoopState: update()")
                try self.update()
            } catch let error {
                updateError = error
            }

            handler(self, LoopStateView(loopDataManager: self, updateError: updateError))
        }
    }
    
    func generateSimpleBolusRecommendation(at date: Date, mealCarbs: HKQuantity?, manualGlucose: HKQuantity?) -> BolusDosingDecision? {
        
        var dosingDecision = BolusDosingDecision()
        
        var activeInsulin: Double? = nil
        let semaphore = DispatchSemaphore(value: 0)
        doseStore.insulinOnBoard(at: Date()) { (result) in
            if case .success(let iobValue) = result {
                activeInsulin = iobValue.value
                dosingDecision.insulinOnBoard = iobValue
            }
            semaphore.signal()
        }
        semaphore.wait()
        
        guard let iob = activeInsulin,
            let suspendThreshold = settings.suspendThreshold?.quantity,
            let carbRatioSchedule = carbStore.carbRatioScheduleApplyingOverrideHistory,
            let correctionRangeSchedule = settings.effectiveGlucoseTargetRangeSchedule(presumingMealEntry: mealCarbs != nil),
            let sensitivitySchedule = insulinSensitivityScheduleApplyingOverrideHistory
        else {
            // Settings incomplete; should never get here; remove when therapy settings non-optional
            return nil
        }
        
        dosingDecision.effectiveGlucoseTargetRangeSchedule = correctionRangeSchedule
        dosingDecision.glucoseTargetRangeSchedule = settings.glucoseTargetRangeSchedule
        dosingDecision.scheduleOverride = settings.scheduleOverride
        
        var notice: BolusRecommendationNotice? = nil
        if let manualGlucose = manualGlucose {
            let glucoseValue = SimpleGlucoseValue(startDate: date, quantity: manualGlucose)
            dosingDecision.manualGlucose = glucoseValue
            if manualGlucose < suspendThreshold {
                notice = .glucoseBelowSuspendThreshold(minGlucose: glucoseValue)
            } else {
                let correctionRange = correctionRangeSchedule.quantityRange(at: date)
                if manualGlucose < correctionRange.lowerBound {
                    notice = .currentGlucoseBelowTarget(glucose: glucoseValue)
                }
            }
        }
        
        let bolusAmount = SimpleBolusCalculator.recommendedInsulin(
            mealCarbs: mealCarbs,
            manualGlucose: manualGlucose,
            activeInsulin: HKQuantity.init(unit: .internationalUnit(), doubleValue: iob),
            carbRatioSchedule: carbRatioSchedule,
            correctionRangeSchedule: correctionRangeSchedule,
            sensitivitySchedule: sensitivitySchedule,
            at: date)
        
        dosingDecision.recommendedBolus = BolusRecommendation(amount: bolusAmount.doubleValue(for: .internationalUnit()), pendingInsulin: 0, notice: notice)
        
        return dosingDecision
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

            var entries: [String] = [
                "## LoopDataManager",
                "settings: \(String(reflecting: manager.settings))",

                "insulinCounteractionEffects: [",
                "* GlucoseEffectVelocity(start, end, mg/dL/min)",
                manager.insulinCounteractionEffects.reduce(into: "", { (entries, entry) in
                    entries.append("* \(entry.startDate), \(entry.endDate), \(entry.quantity.doubleValue(for: GlucoseEffectVelocity.unit))\n")
                }),
                "]",

                "insulinEffect: [",
                "* GlucoseEffect(start, mg/dL)",
                (manager.insulinEffect ?? []).reduce(into: "", { (entries, entry) in
                    entries.append("* \(entry.startDate), \(entry.quantity.doubleValue(for: .milligramsPerDeciliter))\n")
                }),
                "]",

                "carbEffect: [",
                "* GlucoseEffect(start, mg/dL)",
                (manager.carbEffect ?? []).reduce(into: "", { (entries, entry) in
                    entries.append("* \(entry.startDate), \(entry.quantity.doubleValue(for: .milligramsPerDeciliter))\n")
                }),
                "]",

                "predictedGlucose: [",
                "* PredictedGlucoseValue(start, mg/dL)",
                (state.predictedGlucoseIncludingPendingInsulin ?? []).reduce(into: "", { (entries, entry) in
                    entries.append("* \(entry.startDate), \(entry.quantity.doubleValue(for: .milligramsPerDeciliter))\n")
                }),
                "]",

                "retrospectiveGlucoseDiscrepancies: [",
                "* GlucoseEffect(start, mg/dL)",
                (state.retrospectiveGlucoseDiscrepancies ?? []).reduce(into: "", { (entries, entry) in
                    entries.append("* \(entry.startDate), \(entry.quantity.doubleValue(for: .milligramsPerDeciliter))\n")
                }),
                "]",

                "retrospectiveGlucoseDiscrepanciesSummed: [",
                "* GlucoseChange(start, end, mg/dL)",
                (manager.retrospectiveGlucoseDiscrepanciesSummed ?? []).reduce(into: "", { (entries, entry) in
                    entries.append("* \(entry.startDate), \(entry.endDate), \(entry.quantity.doubleValue(for: .milligramsPerDeciliter))\n")
                }),
                "]",

                "glucoseMomentumEffect: \(manager.glucoseMomentumEffect ?? [])",
                "retrospectiveGlucoseEffect: \(manager.retrospectiveGlucoseEffect)",
                "recommendedTempBasal: \(String(describing: state.recommendedTempBasal))",
                "recommendedBolus: \(String(describing: state.recommendedBolus))",
                "lastBolus: \(String(describing: manager.lastRequestedBolus))",
                "lastLoopCompleted: \(String(describing: manager.lastLoopCompleted))",
                "basalDeliveryState: \(String(describing: manager.basalDeliveryState))",
                "carbsOnBoard: \(String(describing: state.carbsOnBoard))",
                "error: \(String(describing: state.error))",
                "overrideInUserDefaults: \(String(describing: UserDefaults.appGroup?.intentExtensionOverrideToSet))",
                "",
                String(reflecting: self.retrospectiveCorrection),
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

                        UNUserNotificationCenter.current().generateDiagnosticReport { (report) in
                            entries.append(report)
                            entries.append("")

                            UIDevice.current.generateDiagnosticReport { (report) in
                                entries.append(report)
                                entries.append("")

                                completion(entries.joined(separator: "\n"))
                            }
                        }
                    }
                }
            }
        }
    }
}


extension Notification.Name {
    static let LoopDataUpdated = Notification.Name(rawValue: "com.loopkit.Loop.LoopDataUpdated")
    static let LoopRunning = Notification.Name(rawValue: "com.loopkit.Loop.LoopRunning")
    static let LoopCompleted = Notification.Name(rawValue: "com.loopkit.Loop.LoopCompleted")
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

    /// Asks the delegate to round a recommended basal rate to a supported rate
    ///
    /// - Parameters:
    ///   - rate: The recommended rate in U/hr
    /// - Returns: a supported rate of delivery in Units/hr. The rate returned should not be larger than the passed in rate.
    func loopDataManager(_ manager: LoopDataManager, roundBasalRate unitsPerHour: Double) -> Double

    /// Asks the delegate to round a recommended bolus volume to a supported volume
    ///
    /// - Parameters:
    ///   - units: The recommended bolus in U
    /// - Returns: a supported bolus volume in U. The volume returned should not be larger than the passed in rate.
    func loopDataManager(_ manager: LoopDataManager, roundBolusVolume units: Double) -> Double

    /// The pump manager status, if one exists.
    var pumpManagerStatus: PumpManagerStatus? { get }
    
    /// The pump manager status, if one exists.
    var automaticDosingEnabled: Bool { get }
}

private extension TemporaryScheduleOverride {
    func isBasalRateScheduleOverriden(at date: Date) -> Bool {
        guard isActive(at: date), let basalRateMultiplier = settings.basalRateMultiplier else {
            return false
        }
        return abs(basalRateMultiplier - 1.0) >= .ulpOfOne
    }
}

private extension StoredDosingDecision.LastReservoirValue {
    init?(_ reservoirValue: ReservoirValue?) {
        guard let reservoirValue = reservoirValue else {
            return nil
        }
        self.init(startDate: reservoirValue.startDate, unitVolume: reservoirValue.unitVolume)
    }
}

private extension StoredDosingDecision.TempBasalRecommendationWithDate {
    init?(_ tempBasalRecommendationDate: (recommendation: TempBasalRecommendation, date: Date)?) {
        guard let tempBasalRecommendationDate = tempBasalRecommendationDate else {
            return nil
        }
        self.init(recommendation: tempBasalRecommendationDate.recommendation, date: tempBasalRecommendationDate.date)
    }
}

private extension StoredDosingDecision.BolusRecommendationWithDate {
    init?(_ bolusRecommendationDate: (recommendation: BolusRecommendation, date: Date)?) {
        guard let bolusRecommendationDate = bolusRecommendationDate else {
            return nil
        }
        self.init(recommendation: bolusRecommendationDate.recommendation, date: bolusRecommendationDate.date)
    }
}

private extension NotificationSettings {
    init(_ notificationSettings: UNNotificationSettings) {
        self.init(authorizationStatus: NotificationSettings.AuthorizationStatus(notificationSettings.authorizationStatus),
                  soundSetting: NotificationSettings.NotificationSetting(notificationSettings.soundSetting),
                  badgeSetting: NotificationSettings.NotificationSetting(notificationSettings.badgeSetting),
                  alertSetting: NotificationSettings.NotificationSetting(notificationSettings.alertSetting),
                  notificationCenterSetting: NotificationSettings.NotificationSetting(notificationSettings.notificationCenterSetting),
                  lockScreenSetting: NotificationSettings.NotificationSetting(notificationSettings.lockScreenSetting),
                  carPlaySetting: NotificationSettings.NotificationSetting(notificationSettings.carPlaySetting),
                  alertStyle: NotificationSettings.AlertStyle(notificationSettings.alertStyle),
                  showPreviewsSetting: NotificationSettings.ShowPreviewsSetting(notificationSettings.showPreviewsSetting),
                  criticalAlertSetting: NotificationSettings.NotificationSetting(notificationSettings.criticalAlertSetting),
                  providesAppNotificationSettings: notificationSettings.providesAppNotificationSettings,
                  announcementSetting: NotificationSettings.NotificationSetting(notificationSettings.announcementSetting))
    }
}

// MARK: - Simulated Core Data

extension LoopDataManager {
    func generateSimulatedHistoricalCoreData(completion: @escaping (Error?) -> Void) {
        guard FeatureFlags.simulatedCoreDataEnabled else {
            fatalError("\(#function) should be invoked only when simulated core data is enabled")
        }

        guard let glucoseStore = glucoseStore as? GlucoseStore, let carbStore = carbStore as? CarbStore, let doseStore = doseStore as? DoseStore, let settingsStore = settingsStore as? SettingsStore, let dosingDecisionStore = dosingDecisionStore as? DosingDecisionStore else {
            fatalError("Mock stores should not be used to generate simulated core data")
        }

        settingsStore.generateSimulatedHistoricalSettingsObjects() { error in
            guard error == nil else {
                completion(error)
                return
            }
            glucoseStore.generateSimulatedHistoricalGlucoseObjects() { error in
                guard error == nil else {
                    completion(error)
                    return
                }
                carbStore.generateSimulatedHistoricalCarbObjects() { error in
                    guard error == nil else {
                        completion(error)
                        return
                    }
                    dosingDecisionStore.generateSimulatedHistoricalDosingDecisionObjects() { error in
                        guard error == nil else {
                            completion(error)
                            return
                        }
                        doseStore.generateSimulatedHistoricalPumpEvents(completion: completion)
                    }
                }
            }
        }
    }

    func purgeHistoricalCoreData(completion: @escaping (Error?) -> Void) {
        guard FeatureFlags.simulatedCoreDataEnabled else {
            fatalError("\(#function) should be invoked only when simulated core data is enabled")
        }

        guard let glucoseStore = glucoseStore as? GlucoseStore, let carbStore = carbStore as? CarbStore, let doseStore = doseStore as? DoseStore, let settingsStore = settingsStore as? SettingsStore, let dosingDecisionStore = dosingDecisionStore as? DosingDecisionStore else {
            fatalError("Mock stores should not be used to generate simulated core data")
        }

        doseStore.purgeHistoricalPumpEvents() { error in
            guard error == nil else {
                completion(error)
                return
            }
            dosingDecisionStore.purgeHistoricalDosingDecisionObjects() { error in
                guard error == nil else {
                    completion(error)
                    return
                }
                carbStore.purgeHistoricalCarbObjects() { error in
                    guard error == nil else {
                        completion(error)
                        return
                    }

                    glucoseStore.purgeHistoricalGlucoseObjects() { error in
                        guard error == nil else {
                            completion(error)
                            return
                        }
                        settingsStore.purgeHistoricalSettingsObjects(completion: completion)
                    }
                }
            }
        }
    }
}

extension LoopDataManager {
    public var therapySettings: TherapySettings {
        TherapySettings(glucoseTargetRangeSchedule: settings.glucoseTargetRangeSchedule,
                        preMealTargetRange: settings.preMealTargetRange,
                        workoutTargetRange: settings.legacyWorkoutTargetRange,
                        maximumBasalRatePerHour: settings.maximumBasalRatePerHour,
                        maximumBolus: settings.maximumBolus,
                        suspendThreshold: settings.suspendThreshold,
                        insulinSensitivitySchedule: insulinSensitivitySchedule,
                        carbRatioSchedule: carbRatioSchedule,
                        basalRateSchedule: basalRateSchedule,
                        insulinModelSettings: insulinModelSettings)
    }
}
