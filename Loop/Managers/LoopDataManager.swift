//
//  LoopDataManager.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 3/12/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation
import Combine
import HealthKit
import LoopKit
import LoopCore
import WidgetKit

protocol PresetActivationObserver: AnyObject {
    func presetActivated(context: TemporaryScheduleOverride.Context, duration: TemporaryScheduleOverride.Duration)
    func presetDeactivated(context: TemporaryScheduleOverride.Context)
}

final class LoopDataManager {
    enum LoopUpdateContext: Int {
        case insulin
        case carbs
        case glucose
        case preferences
        case loopFinished
    }

    static let LoopUpdateContextKey = "com.loudnate.Loop.LoopDataManager.LoopUpdateContext"

    private let carbStore: CarbStoreProtocol
    
    private let mealDetectionManager: MealDetectionManager

    private let doseStore: DoseStoreProtocol

    let dosingDecisionStore: DosingDecisionStoreProtocol

    private let glucoseStore: GlucoseStoreProtocol

    let latestStoredSettingsProvider: LatestStoredSettingsProvider

    weak var delegate: LoopDataManagerDelegate?

    private let logger = DiagnosticLog(category: "LoopDataManager")
    private let widgetLog = DiagnosticLog(category: "LoopWidgets")

    private let analyticsServicesManager: AnalyticsServicesManager

    private let trustedTimeOffset: () -> TimeInterval

    private let now: () -> Date

    private let automaticDosingStatus: AutomaticDosingStatus

    lazy private var cancellables = Set<AnyCancellable>()

    // References to registered notification center observers
    private var notificationObservers: [Any] = []
    
    private var overrideIntentObserver: NSKeyValueObservation? = nil

    var presetActivationObservers: [PresetActivationObserver] = []

    private var timeBasedDoseApplicationFactor: Double = 1.0

    private var insulinOnBoard: InsulinValue?

    deinit {
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    init(
        lastLoopCompleted: Date?,
        basalDeliveryState: PumpManagerStatus.BasalDeliveryState?,
        settings: LoopSettings,
        overrideHistory: TemporaryScheduleOverrideHistory,
        analyticsServicesManager: AnalyticsServicesManager,
        localCacheDuration: TimeInterval = .days(1),
        doseStore: DoseStoreProtocol,
        glucoseStore: GlucoseStoreProtocol,
        carbStore: CarbStoreProtocol,
        dosingDecisionStore: DosingDecisionStoreProtocol,
        latestStoredSettingsProvider: LatestStoredSettingsProvider,
        now: @escaping () -> Date = { Date() },
        pumpInsulinType: InsulinType?,
        automaticDosingStatus: AutomaticDosingStatus,
        trustedTimeOffset: @escaping () -> TimeInterval
    ) {
        self.analyticsServicesManager = analyticsServicesManager
        self.lockedLastLoopCompleted = Locked(lastLoopCompleted)
        self.lockedBasalDeliveryState = Locked(basalDeliveryState)
        self.lockedSettings = Locked(settings)
        self.dosingEnabled = settings.dosingEnabled

        self.overrideHistory = overrideHistory

        let absorptionTimes = LoopCoreConstants.defaultCarbAbsorptionTimes

        self.overrideHistory.relevantTimeWindow = absorptionTimes.slow * 2

        self.carbStore = carbStore
        self.doseStore = doseStore
        self.glucoseStore = glucoseStore

        self.dosingDecisionStore = dosingDecisionStore

        self.now = now

        self.latestStoredSettingsProvider = latestStoredSettingsProvider
        self.mealDetectionManager = MealDetectionManager(
            carbRatioScheduleApplyingOverrideHistory: carbStore.carbRatioScheduleApplyingOverrideHistory,
            insulinSensitivityScheduleApplyingOverrideHistory: carbStore.insulinSensitivityScheduleApplyingOverrideHistory,
            maximumBolus: settings.maximumBolus
        )
        
        self.lockedPumpInsulinType = Locked(pumpInsulinType)

        self.automaticDosingStatus = automaticDosingStatus

        self.trustedTimeOffset = trustedTimeOffset

        retrospectiveCorrection = settings.enabledRetrospectiveCorrectionAlgorithm

        overrideIntentObserver = UserDefaults.appGroup?.observe(\.intentExtensionOverrideToSet, options: [.new], changeHandler: {[weak self] (defaults, change) in
            guard let name = change.newValue??.lowercased(), let appGroup = UserDefaults.appGroup else {
                return
            }

            guard let preset = self?.settings.overridePresets.first(where: {$0.name.lowercased() == name}) else {
                self?.logger.error("Override Intent: Unable to find override named '%s'", String(describing: name))
                return
            }
            
            self?.logger.default("Override Intent: setting override named '%s'", String(describing: name))
            self?.mutateSettings { settings in
                if let oldPreset = settings.scheduleOverride {
                    if let observers = self?.presetActivationObservers {
                        for observer in observers {
                            observer.presetDeactivated(context: oldPreset.context)
                        }
                    }
                }
                settings.scheduleOverride = preset.createOverride(enactTrigger: .remote("Siri"))
                if let observers = self?.presetActivationObservers {
                    for observer in observers {
                        observer.presetActivated(context: .preset(preset), duration: preset.duration)
                    }
                }
            }
            // Remove the override from UserDefaults so we don't set it multiple times
            appGroup.intentExtensionOverrideToSet = nil
        })

        // Required for device settings in stored dosing decisions
        UIDevice.current.isBatteryMonitoringEnabled = true

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
                    self.remoteRecommendationNeedsUpdating = true
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
                    self.remoteRecommendationNeedsUpdating = true

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
                    self.remoteRecommendationNeedsUpdating = true

                    self.notify(forChange: .insulin)
                }
            }
        ]

        // Turn off preMeal when going into closed loop off mode
        // Cancel any active temp basal when going into closed loop off mode
        // The dispatch is necessary in case this is coming from a didSet already on the settings struct.
        self.automaticDosingStatus.$automaticDosingEnabled
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { if !$0 {
                self.mutateSettings { settings in
                    settings.clearOverride(matching: .preMeal)
                }
                self.cancelActiveTempBasal(for: .automaticDosingDisabled)
            } }
            .store(in: &cancellables)
    }

    /// Loop-related settings

    private var lockedSettings: Locked<LoopSettings>

    var settings: LoopSettings {
        lockedSettings.value
    }

    func mutateSettings(_ changes: (_ settings: inout LoopSettings) -> Void) {
        var oldValue: LoopSettings!
        let newValue = lockedSettings.mutate { settings in
            oldValue = settings
            changes(&settings)
        }

        guard oldValue != newValue else {
            return
        }

        var invalidateCachedEffects = false

        dosingEnabled = newValue.dosingEnabled

        if newValue.preMealOverride != oldValue.preMealOverride {
            // The prediction isn't actually invalid, but a target range change requires recomputing recommended doses
            predictedGlucose = nil
        }

        if newValue.scheduleOverride != oldValue.scheduleOverride {
            overrideHistory.recordOverride(settings.scheduleOverride)

            if let oldPreset = oldValue.scheduleOverride {
                for observer in self.presetActivationObservers {
                    observer.presetDeactivated(context: oldPreset.context)
                }

            }
            if let newPreset = newValue.scheduleOverride {
                for observer in self.presetActivationObservers {
                    observer.presetActivated(context: newPreset.context, duration: newPreset.duration)
                }
            }

            // Invalidate cached effects affected by the override
            invalidateCachedEffects = true
            
            // Update the affected schedules
            mealDetectionManager.carbRatioScheduleApplyingOverrideHistory = carbRatioScheduleApplyingOverrideHistory
            mealDetectionManager.insulinSensitivityScheduleApplyingOverrideHistory = insulinSensitivityScheduleApplyingOverrideHistory
        }

        if newValue.insulinSensitivitySchedule != oldValue.insulinSensitivitySchedule {
            carbStore.insulinSensitivitySchedule = newValue.insulinSensitivitySchedule
            doseStore.insulinSensitivitySchedule = newValue.insulinSensitivitySchedule
            mealDetectionManager.insulinSensitivityScheduleApplyingOverrideHistory = insulinSensitivityScheduleApplyingOverrideHistory
            invalidateCachedEffects = true
            analyticsServicesManager.didChangeInsulinSensitivitySchedule()
        }

        if newValue.basalRateSchedule != oldValue.basalRateSchedule {
            doseStore.basalProfile = newValue.basalRateSchedule

            if let newValue = newValue.basalRateSchedule, let oldValue = oldValue.basalRateSchedule, newValue.items != oldValue.items {
                analyticsServicesManager.didChangeBasalRateSchedule()
            }
        }

        if newValue.carbRatioSchedule != oldValue.carbRatioSchedule {
            carbStore.carbRatioSchedule = newValue.carbRatioSchedule
            mealDetectionManager.carbRatioScheduleApplyingOverrideHistory = carbRatioScheduleApplyingOverrideHistory
            invalidateCachedEffects = true
            analyticsServicesManager.didChangeCarbRatioSchedule()
        }

        if newValue.defaultRapidActingModel != oldValue.defaultRapidActingModel {
            if FeatureFlags.adultChildInsulinModelSelectionEnabled {
                doseStore.insulinModelProvider = PresetInsulinModelProvider(defaultRapidActingModel: newValue.defaultRapidActingModel)
            } else {
                doseStore.insulinModelProvider = PresetInsulinModelProvider(defaultRapidActingModel: nil)
            }
            invalidateCachedEffects = true
            analyticsServicesManager.didChangeInsulinModel()
        }

        if newValue.maximumBolus != oldValue.maximumBolus {
            mealDetectionManager.maximumBolus = newValue.maximumBolus
        }

        if invalidateCachedEffects {
            dataAccessQueue.async {
                // Invalidate cached effects based on this schedule
                self.carbEffect = nil
                self.carbsOnBoard = nil
                self.insulinEffect = nil
            }
        }

        notify(forChange: .preferences)
        analyticsServicesManager.didChangeLoopSettings(from: oldValue, to: newValue)
    }

    @Published private(set) var dosingEnabled: Bool

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
            recommendedAutomaticDose = nil
            predictedGlucoseIncludingPendingInsulin = nil
        }
    }

    fileprivate var predictedGlucoseIncludingPendingInsulin: [PredictedGlucoseValue]?

    private var recentCarbEntries: [StoredCarbEntry]?

    fileprivate var recommendedAutomaticDose: (recommendation: AutomaticDoseRecommendation, date: Date)?

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

    fileprivate var lastLoopError: LoopError?

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

    private func loopDidComplete(date: Date, dosingDecision: StoredDosingDecision, duration: TimeInterval) {
        logger.default("Loop completed successfully.")
        lastLoopCompleted = date
        analyticsServicesManager.loopDidSucceed(duration)
        dosingDecisionStore.storeDosingDecision(dosingDecision) {}

        NotificationCenter.default.post(name: .LoopCompleted, object: self)
    }

    private func loopDidError(date: Date, error: LoopError, dosingDecision: StoredDosingDecision, duration: TimeInterval) {
        logger.error("Loop did error: %{public}@", String(describing: error))
        lastLoopError = error
        analyticsServicesManager.loopDidError(error: error)
        var dosingDecisionWithError = dosingDecision
        dosingDecisionWithError.appendError(error)
        dosingDecisionStore.storeDosingDecision(dosingDecisionWithError) {}
    }

    // This is primarily for remote clients displaying a bolus recommendation and forecast
    // Should be called after any significant change to forecast input data.


    var remoteRecommendationNeedsUpdating: Bool = false

    func updateRemoteRecommendation() {
        dataAccessQueue.async {
            if self.remoteRecommendationNeedsUpdating {
                var (dosingDecision, updateError) = self.update(for: .updateRemoteRecommendation)

                if let error = updateError {
                    self.logger.error("Error updating manual bolus recommendation: %{public}@", String(describing: error))
                } else {
                    do {
                        if let predictedGlucoseIncludingPendingInsulin = self.predictedGlucoseIncludingPendingInsulin,
                           let manualBolusRecommendation = try self.recommendManualBolus(forPrediction: predictedGlucoseIncludingPendingInsulin, consideringPotentialCarbEntry: nil)
                        {
                            dosingDecision.manualBolusRecommendation = ManualBolusRecommendationWithDate(recommendation: manualBolusRecommendation, date: Date())
                            self.logger.debug("Manual bolus rec = %{public}@", String(describing: dosingDecision.manualBolusRecommendation))
                            self.dosingDecisionStore.storeDosingDecision(dosingDecision) {}
                        }
                    } catch {
                        self.logger.error("Error updating manual bolus recommendation: %{public}@", String(describing: error))
                    }
                }
                self.remoteRecommendationNeedsUpdating = false
            }
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

    /// The basal rate schedule, applying recent overrides relative to the current moment in time.
    var basalRateScheduleApplyingOverrideHistory: BasalRateSchedule? {
        return doseStore.basalProfileApplyingOverrideHistory
    }

    /// The carb ratio schedule, applying recent overrides relative to the current moment in time.
    var carbRatioScheduleApplyingOverrideHistory: CarbRatioSchedule? {
        return carbStore.carbRatioScheduleApplyingOverrideHistory
    }

    /// The insulin sensitivity schedule, applying recent overrides relative to the current moment in time.
    var insulinSensitivityScheduleApplyingOverrideHistory: InsulinSensitivitySchedule? {
        return carbStore.insulinSensitivityScheduleApplyingOverrideHistory
    }

    /// Sets a new time zone for a the schedule-based settings
    ///
    /// - Parameter timeZone: The time zone
    func setScheduleTimeZone(_ timeZone: TimeZone) {
        self.mutateSettings { settings in
            settings.basalRateSchedule?.timeZone = timeZone
            settings.carbRatioSchedule?.timeZone = timeZone
            settings.insulinSensitivitySchedule?.timeZone = timeZone
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
    
    /// Take actions to address how insulin is delivered when the CGM data is unreliable
    ///
    /// An active high temp basal (greater than the basal schedule) is cancelled when the CGM data is unreliable.
    func receivedUnreliableCGMReading() {
        guard case .tempBasal(let tempBasal) = basalDeliveryState,
              let scheduledBasalRate = settings.basalRateSchedule?.value(at: now()),
              tempBasal.unitsPerHour > scheduledBasalRate else
        {
            return
        }
              
        // Cancel active high temp basal
        cancelActiveTempBasal(for: .unreliableCGMData)
    }

    private enum CancelActiveTempBasalReason: String {
        case automaticDosingDisabled
        case unreliableCGMData
        case maximumBasalRateChanged
    }
    
    /// Cancel the active temp basal if it was automatically issued
    private func cancelActiveTempBasal(for reason: CancelActiveTempBasalReason) {
        guard case .tempBasal(let dose) = basalDeliveryState, (dose.automatic ?? true) else { return }

        dataAccessQueue.async {
            self.cancelActiveTempBasal(for: reason, completion: nil)
        }
    }
    
    private func cancelActiveTempBasal(for reason: CancelActiveTempBasalReason, completion: ((Error?) -> Void)?) {
        dispatchPrecondition(condition: .onQueue(dataAccessQueue))

        let recommendation = AutomaticDoseRecommendation(basalAdjustment: .cancel)
        recommendedAutomaticDose = (recommendation: recommendation, date: now())

        var dosingDecision = StoredDosingDecision(reason: reason.rawValue)
        dosingDecision.settings = StoredDosingDecision.Settings(latestStoredSettingsProvider.latestSettings)
        dosingDecision.controllerStatus = UIDevice.current.controllerStatus
        dosingDecision.automaticDoseRecommendation = recommendation

        let error = enactRecommendedAutomaticDose()

        dosingDecision.pumpManagerStatus = delegate?.pumpManagerStatus
        dosingDecision.cgmManagerStatus = delegate?.cgmManagerStatus
        dosingDecision.lastReservoirValue = StoredDosingDecision.LastReservoirValue(doseStore.lastReservoirValue)

        if let error = error {
            dosingDecision.appendError(error)
        }
        self.dosingDecisionStore.storeDosingDecision(dosingDecision) {}

        // Didn't actually run a loop, but this is similar to a loop() in that the automatic dosing
        // was updated.
        self.notify(forChange: .loopFinished)
        completion?(error)
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
                    self.mutateSettings { settings in
                        settings.clearOverride(matching: .preMeal)
                    }

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

    func deleteCarbEntry(_ oldEntry: StoredCarbEntry, completion: @escaping (_ result: CarbStoreResult<Bool>) -> Void) {
        carbStore.deleteCarbEntry(oldEntry) { result in
            completion(result)
        }
    }


    /// Adds a bolus requested of the pump, but not confirmed.
    ///
    /// - Parameters:
    ///   - dose: The DoseEntry representing the requested bolus
    ///   - completion: A closure that is called after state has been updated
    func addRequestedBolus(_ dose: DoseEntry, completion: (() -> Void)?) {
        dataAccessQueue.async {
            self.logger.debug("addRequestedBolus")
            self.lastRequestedBolus = dose
            self.notify(forChange: .insulin)

            completion?()
        }
    }

    /// Notifies the manager that the bolus is confirmed, but not fully delivered.
    ///
    /// - Parameters:
    ///   - completion: A closure that is called after state has been updated
    func bolusConfirmed(completion: (() -> Void)?) {
        self.dataAccessQueue.async {
            self.logger.debug("bolusConfirmed")
            self.lastRequestedBolus = nil
            self.recommendedAutomaticDose = nil
            self.insulinEffect = nil
            self.notify(forChange: .insulin)

            completion?()
        }
    }

    /// Notifies the manager that the bolus failed.
    ///
    /// - Parameters:
    ///   - error: An error describing why the bolus request failed
    ///   - completion: A closure that is called after state has been updated
    func bolusRequestFailed(_ error: Error, completion: (() -> Void)?) {
        self.dataAccessQueue.async {
            self.logger.debug("bolusRequestFailed")
            self.lastRequestedBolus = nil
            self.insulinEffect = nil
            self.notify(forChange: .insulin)

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
            completion(error)
            
            self.dataAccessQueue.async {
                if error == nil {
                    self.insulinEffect = nil
                }
            }
        }
    }
    
    /// Logs a new external bolus insulin dose in the DoseStore and HealthKit
    ///
    /// - Parameters:
    ///   - startDate: The date the dose was started at.
    ///   - value: The number of Units in the dose.
    ///   - insulinModel: The type of insulin model that should be used for the dose.
    func addManuallyEnteredDose(startDate: Date, units: Double, insulinType: InsulinType? = nil) {
        let syncIdentifier = Data(UUID().uuidString.utf8).hexadecimalString
        let dose = DoseEntry(type: .bolus, startDate: startDate, value: units, unit: .units, syncIdentifier: syncIdentifier, insulinType: insulinType, manuallyEntered: true)

        doseStore.addDoses([dose], from: nil) { (error) in
            if error == nil {
                self.recommendedAutomaticDose = nil
                self.insulinEffect = nil
                self.notify(forChange: .insulin)
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

    func storeManualBolusDosingDecision(_ bolusDosingDecision: BolusDosingDecision, withDate date: Date) {
        let dosingDecision = StoredDosingDecision(date: date,
                                                  reason: bolusDosingDecision.reason.rawValue,
                                                  settings: StoredDosingDecision.Settings(latestStoredSettingsProvider.latestSettings),
                                                  scheduleOverride: bolusDosingDecision.scheduleOverride,
                                                  controllerStatus: UIDevice.current.controllerStatus,
                                                  pumpManagerStatus: delegate?.pumpManagerStatus,
                                                  cgmManagerStatus: delegate?.cgmManagerStatus,
                                                  lastReservoirValue: StoredDosingDecision.LastReservoirValue(doseStore.lastReservoirValue),
                                                  historicalGlucose: bolusDosingDecision.historicalGlucose,
                                                  originalCarbEntry: bolusDosingDecision.originalCarbEntry,
                                                  carbEntry: bolusDosingDecision.carbEntry,
                                                  manualGlucoseSample: bolusDosingDecision.manualGlucoseSample,
                                                  carbsOnBoard: bolusDosingDecision.carbsOnBoard,
                                                  insulinOnBoard: bolusDosingDecision.insulinOnBoard,
                                                  glucoseTargetRangeSchedule: bolusDosingDecision.glucoseTargetRangeSchedule,
                                                  predictedGlucose: bolusDosingDecision.predictedGlucose,
                                                  manualBolusRecommendation: bolusDosingDecision.manualBolusRecommendation,
                                                  manualBolusRequested: bolusDosingDecision.manualBolusRequested)
        dosingDecisionStore.storeDosingDecision(dosingDecision) {}
    }

    // Actions

    /// Runs the "loop"
    ///
    /// Executes an analysis of the current data, and recommends an adjustment to the current
    /// temporary basal rate.
    func loop() {
        
        dataAccessQueue.async {

            // If time was changed to future time, and a loop completed, then time was fixed, lastLoopCompleted will prevent looping
            // until the future loop time passes. Fix that here.
            if let lastLoopCompleted = self.lastLoopCompleted, Date() < lastLoopCompleted, self.trustedTimeOffset() == 0 {
                self.logger.error("Detected future lastLoopCompleted. Restoring.")
                self.lastLoopCompleted = Date()
            }

            // Partial application factor assumes 5 minute intervals. If our looping intervals are shorter, then this will be adjusted
            self.timeBasedDoseApplicationFactor = 1.0
            if let lastLoopCompleted = self.lastLoopCompleted {
                let timeSinceLastLoop = max(0, Date().timeIntervalSince(lastLoopCompleted))
                self.timeBasedDoseApplicationFactor = min(1, timeSinceLastLoop/TimeInterval.minutes(5))
                self.logger.default("Looping with timeBasedDoseApplicationFactor = %{public}@", String(describing: self.timeBasedDoseApplicationFactor))
            }

            self.logger.default("Loop running")
            NotificationCenter.default.post(name: .LoopRunning, object: self)

            self.lastLoopError = nil
            let startDate = self.now()

            var (dosingDecision, error) = self.update(for: .loop)

            if error == nil, self.automaticDosingStatus.automaticDosingEnabled == true {
                error = self.enactRecommendedAutomaticDose()
            } else {
                self.logger.default("Not adjusting dosing during open loop.")
            }

            self.finishLoop(startDate: startDate, dosingDecision: dosingDecision, error: error)
        }
    }

    private func finishLoop(startDate: Date, dosingDecision: StoredDosingDecision, error: LoopError? = nil) {
        let date = now()
        let duration = date.timeIntervalSince(startDate)

        if let error = error {
            loopDidError(date: date, error: error, dosingDecision: dosingDecision, duration: duration)
        } else {
            loopDidComplete(date: date, dosingDecision: dosingDecision, duration: duration)
        }

        logger.default("Loop ended")
        notify(forChange: .loopFinished)

        if FeatureFlags.missedMealNotifications {
            let carbEffectStart = now().addingTimeInterval(-MissedMealSettings.maxRecency)
            carbStore.getGlucoseEffects(start: carbEffectStart, end: now(), effectVelocities: insulinCounteractionEffects) {[weak self] result in
                guard
                    let self = self,
                    case .success((_, let carbEffects)) = result
                else {
                    if case .failure(let error) = result {
                        self?.logger.error("Failed to fetch glucose effects to check for missed meal: %{public}@", String(describing: error))
                    }
                    return
                }
                
                self.mealDetectionManager.generateMissedMealNotificationIfNeeded(
                    insulinCounteractionEffects: self.insulinCounteractionEffects,
                    carbEffects: carbEffects,
                    pendingAutobolusUnits: self.recommendedAutomaticDose?.recommendation.bolusUnits,
                    bolusDurationEstimator: { [unowned self] bolusAmount in
                        return self.delegate?.loopDataManager(self, estimateBolusDuration: bolusAmount)
                    }
                )
            }
        }

        // 5 second delay to allow stores to cache data before it is read by widget
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            self.widgetLog.default("Refreshing widget. Reason: Loop completed")
            WidgetCenter.shared.reloadAllTimelines()
        }

        updateRemoteRecommendation()
    }

    fileprivate enum UpdateReason: String {
        case loop
        case getLoopState
        case updateRemoteRecommendation
    }

    fileprivate func update(for reason: UpdateReason) -> (StoredDosingDecision, LoopError?) {
        dispatchPrecondition(condition: .onQueue(dataAccessQueue))

        var dosingDecision = StoredDosingDecision(reason: reason.rawValue)
        let latestSettings = latestStoredSettingsProvider.latestSettings
        dosingDecision.settings = StoredDosingDecision.Settings(latestSettings)
        dosingDecision.scheduleOverride = latestSettings.scheduleOverride
        dosingDecision.controllerStatus = UIDevice.current.controllerStatus
        dosingDecision.pumpManagerStatus = delegate?.pumpManagerStatus
        if let pumpStatusHighlight = delegate?.pumpStatusHighlight {
            dosingDecision.pumpStatusHighlight = StoredDosingDecision.StoredDeviceHighlight(
                localizedMessage: pumpStatusHighlight.localizedMessage,
                imageName: pumpStatusHighlight.imageName,
                state: pumpStatusHighlight.state)
        }
        dosingDecision.cgmManagerStatus = delegate?.cgmManagerStatus
        dosingDecision.lastReservoirValue = StoredDosingDecision.LastReservoirValue(doseStore.lastReservoirValue)

        let warnings = Locked<[LoopWarning]>([])

        let updateGroup = DispatchGroup()

        let historicalGlucoseStartDate = Date(timeInterval: -LoopCoreConstants.dosingDecisionHistoricalGlucoseInterval, since: now())
        let inputDataRecencyStartDate = Date(timeInterval: -LoopCoreConstants.inputDataRecencyInterval, since: now())

        // Fetch glucose effects as far back as we want to make retroactive analysis and historical glucose for dosing decision
        var historicalGlucose: [HistoricalGlucoseValue]?
        var latestGlucoseDate: Date?
        updateGroup.enter()
        glucoseStore.getGlucoseSamples(start: min(historicalGlucoseStartDate, inputDataRecencyStartDate), end: nil) { (result) in
            switch result {
            case .failure(let error):
                self.logger.error("Failure getting glucose samples: %{public}@", String(describing: error))
                latestGlucoseDate = nil
                warnings.append(.fetchDataWarning(.glucoseSamples(error: error)))
            case .success(let samples):
                historicalGlucose = samples.filter { $0.startDate >= historicalGlucoseStartDate }.map { HistoricalGlucoseValue(startDate: $0.startDate, quantity: $0.quantity) }
                latestGlucoseDate = samples.last?.startDate
            }
            updateGroup.leave()
        }
        _ = updateGroup.wait(timeout: .distantFuture)

        guard let lastGlucoseDate = latestGlucoseDate else {
            dosingDecision.appendWarnings(warnings.value)
            dosingDecision.appendError(.missingDataError(.glucose))
            return (dosingDecision, .missingDataError(.glucose))
        }

        let retrospectiveStart = lastGlucoseDate.addingTimeInterval(-retrospectiveCorrection.retrospectionInterval)

        let earliestEffectDate = Date(timeInterval: .hours(-24), since: now())
        let nextCounteractionEffectDate = insulinCounteractionEffects.last?.endDate ?? earliestEffectDate
        let insulinEffectStartDate = nextCounteractionEffectDate.addingTimeInterval(.minutes(-5))

        if glucoseMomentumEffect == nil {
            updateGroup.enter()
            glucoseStore.getRecentMomentumEffect { (result) -> Void in
                switch result {
                case .failure(let error):
                    self.logger.error("Failure getting recent momentum effect: %{public}@", String(describing: error))
                    self.glucoseMomentumEffect = nil
                    warnings.append(.fetchDataWarning(.glucoseMomentumEffect(error: error)))
                case .success(let effects):
                    self.glucoseMomentumEffect = effects
                }
                updateGroup.leave()
            }
        }

        if insulinEffect == nil {
            self.logger.debug("Recomputing insulin effects")
            updateGroup.enter()
            doseStore.getGlucoseEffects(start: insulinEffectStartDate, end: nil, basalDosingEnd: now()) { (result) -> Void in
                switch result {
                case .failure(let error):
                    self.logger.error("%{public}@", String(describing: error))
                    self.insulinEffect = nil
                    warnings.append(.fetchDataWarning(.insulinEffect(error: error)))
                case .success(let effects):
                    self.insulinEffect = effects
                }

                updateGroup.leave()
            }
        }

        if insulinEffectIncludingPendingInsulin == nil {
            updateGroup.enter()
            doseStore.getGlucoseEffects(start: insulinEffectStartDate, end: nil, basalDosingEnd: nil) { (result) -> Void in
                switch result {
                case .failure(let error):
                    self.logger.error("Could not fetch insulin effects: %{public}@", String(describing: error))
                    self.insulinEffectIncludingPendingInsulin = nil
                    warnings.append(.fetchDataWarning(.insulinEffectIncludingPendingInsulin(error: error)))
                case .success(let effects):
                    self.insulinEffectIncludingPendingInsulin = effects
                }

                updateGroup.leave()
            }
        }

        _ = updateGroup.wait(timeout: .distantFuture)

        if nextCounteractionEffectDate < lastGlucoseDate, let insulinEffect = insulinEffect {
            updateGroup.enter()
            self.logger.debug("Fetching counteraction effects after %{public}@", String(describing: nextCounteractionEffectDate))
            glucoseStore.getCounteractionEffects(start: nextCounteractionEffectDate, end: nil, to: insulinEffect) { (result) in
                switch result {
                case .failure(let error):
                    self.logger.error("Failure getting counteraction effects: %{public}@", String(describing: error))
                    warnings.append(.fetchDataWarning(.insulinCounteractionEffect(error: error)))
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
                effectVelocities: FeatureFlags.dynamicCarbAbsorptionEnabled ? insulinCounteractionEffects : nil
            ) { (result) -> Void in
                switch result {
                case .failure(let error):
                    self.logger.error("%{public}@", String(describing: error))
                    self.carbEffect = nil
                    self.recentCarbEntries = nil
                    warnings.append(.fetchDataWarning(.carbEffect(error: error)))
                case .success(let (entries, effects)):
                    self.carbEffect = effects
                    self.recentCarbEntries = entries
                }

                updateGroup.leave()
            }
        }

        if carbsOnBoard == nil {
            updateGroup.enter()
            carbStore.carbsOnBoard(at: now(), effectVelocities: FeatureFlags.dynamicCarbAbsorptionEnabled ? insulinCounteractionEffects : nil) { (result) in
                switch result {
                case .failure(let error):
                    switch error {
                    case .noData:
                        // when there is no data, carbs on board is set to 0
                        self.carbsOnBoard = CarbValue(startDate: Date(), quantity: HKQuantity(unit: .gram(), doubleValue: 0))
                    default:
                        self.carbsOnBoard = nil
                        warnings.append(.fetchDataWarning(.carbsOnBoard(error: error)))
                    }
                case .success(let value):
                    self.carbsOnBoard = value
                }
                updateGroup.leave()
            }
        }
        updateGroup.enter()
        doseStore.insulinOnBoard(at: now()) { result in
            switch result {
            case .failure(let error):
                warnings.append(.fetchDataWarning(.insulinOnBoard(error: error)))
            case .success(let insulinValue):
                self.insulinOnBoard = insulinValue
            }
            updateGroup.leave()
        }

        _ = updateGroup.wait(timeout: .distantFuture)

        if retrospectiveGlucoseDiscrepancies == nil {
            do {
                try updateRetrospectiveGlucoseEffect()
            } catch let error {
                logger.error("%{public}@", String(describing: error))
                warnings.append(.fetchDataWarning(.retrospectiveGlucoseEffect(error: error)))
            }
        }

        dosingDecision.appendWarnings(warnings.value)

        dosingDecision.date = now()
        dosingDecision.historicalGlucose = historicalGlucose
        dosingDecision.carbsOnBoard = carbsOnBoard
        dosingDecision.insulinOnBoard = self.insulinOnBoard
        dosingDecision.glucoseTargetRangeSchedule = settings.effectiveGlucoseTargetRangeSchedule()

        // These will be updated by updatePredictedGlucoseAndRecommendedDose, if possible
        dosingDecision.predictedGlucose = predictedGlucose
        dosingDecision.automaticDoseRecommendation = recommendedAutomaticDose?.recommendation

        // If the glucose prediction hasn't changed, then nothing has changed, so just use pre-existing recommendations
        guard predictedGlucose == nil else {

            // If we still have a bolus in progress, then warn (unlikely, but possible if device comms fail)
            if lastRequestedBolus != nil, dosingDecision.automaticDoseRecommendation == nil, dosingDecision.manualBolusRecommendation == nil {
                dosingDecision.appendWarning(.bolusInProgress)
            }

            return (dosingDecision, nil)
        }

        return updatePredictedGlucoseAndRecommendedDose(with: dosingDecision)
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
    ///     - LoopError.invalidFutureGlucose
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
        includingPendingInsulin: Bool = false,
        includingPositiveVelocityAndRC: Bool = true
    ) throws -> [PredictedGlucoseValue] {
        dispatchPrecondition(condition: .onQueue(dataAccessQueue))

        guard let glucose = startingGlucoseOverride ?? self.glucoseStore.latestGlucose else {
            throw LoopError.missingDataError(.glucose)
        }

        let pumpStatusDate = doseStore.lastAddedPumpData
        let lastGlucoseDate = glucose.startDate

        guard now().timeIntervalSince(lastGlucoseDate) <= LoopCoreConstants.inputDataRecencyInterval else {
            throw LoopError.glucoseTooOld(date: glucose.startDate)
        }

        guard lastGlucoseDate.timeIntervalSince(now()) <= LoopCoreConstants.futureGlucoseDataInterval else {
            throw LoopError.invalidFutureGlucose(date: lastGlucoseDate)
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
                        effectVelocities: FeatureFlags.dynamicCarbAbsorptionEnabled ? insulinCounteractionEffects : nil
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
                        effectVelocities: FeatureFlags.dynamicCarbAbsorptionEnabled ? insulinCounteractionEffects : nil
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
                    throw LoopError.configurationError(.insulinSensitivitySchedule)
                }

                let earliestEffectDate = Date(timeInterval: .hours(-24), since: now())
                let nextEffectDate = insulinCounteractionEffects.last?.endDate ?? earliestEffectDate
                let bolusEffect = [potentialBolus]
                    .glucoseEffects(insulinModelProvider: doseStore.insulinModelProvider, longestEffectDuration: doseStore.longestEffectDuration, insulinSensitivity: sensitivity)
                    .filterDateRange(nextEffectDate, nil)
                effects.append(bolusEffect)
            }
        }

        if inputs.contains(.momentum), let momentumEffect = self.glucoseMomentumEffect {
            if !includingPositiveVelocityAndRC, let netMomentum = momentumEffect.netEffect(), netMomentum.quantity.doubleValue(for: .milligramsPerDeciliter) > 0 {
                momentum = []
            } else {
                momentum = momentumEffect
            }
        }

        if inputs.contains(.retrospection) {
            if !includingPositiveVelocityAndRC, let netRC = retrospectiveGlucoseEffect.netEffect(), netRC.quantity.doubleValue(for: .milligramsPerDeciliter) > 0 {
                // positive RC is turned off
            } else {
                effects.append(retrospectiveGlucoseEffect)
            }
        }

        var prediction = LoopMath.predictGlucose(startingAt: glucose, momentum: momentum, effects: effects)

        // Dosing requires prediction entries at least as long as the insulin model duration.
        // If our prediction is shorter than that, then extend it here.
        let finalDate = glucose.startDate.addingTimeInterval(doseStore.longestEffectDuration)
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
        includingPendingInsulin: Bool,
        considerPositiveVelocityAndRC: Bool
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
            effectVelocities: FeatureFlags.dynamicCarbAbsorptionEnabled ? insulinCounteractionEffects : nil
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
            includingPendingInsulin: true,
            includingPositiveVelocityAndRC: considerPositiveVelocityAndRC
        )
    }

    fileprivate func recommendBolusForManualGlucose(_ glucose: NewGlucoseSample, consideringPotentialCarbEntry potentialCarbEntry: NewCarbEntry?, replacingCarbEntry replacedCarbEntry: StoredCarbEntry?, considerPositiveVelocityAndRC: Bool) throws -> ManualBolusRecommendation? {
        guard lastRequestedBolus == nil else {
            // Don't recommend changes if a bolus was just requested.
            // Sending additional pump commands is not going to be
            // successful in any case.
            return nil
        }

        let pendingInsulin = try getPendingInsulin()
        let shouldIncludePendingInsulin = pendingInsulin > 0
        let prediction = try predictGlucoseFromManualGlucose(glucose, potentialBolus: nil, potentialCarbEntry: potentialCarbEntry, replacingCarbEntry: replacedCarbEntry, includingPendingInsulin: shouldIncludePendingInsulin, considerPositiveVelocityAndRC: considerPositiveVelocityAndRC)
        return try recommendManualBolus(forPrediction: prediction, consideringPotentialCarbEntry: potentialCarbEntry)
    }

    /// - Throws: LoopError.missingDataError
    fileprivate func recommendBolus(consideringPotentialCarbEntry potentialCarbEntry: NewCarbEntry?, replacingCarbEntry replacedCarbEntry: StoredCarbEntry?, considerPositiveVelocityAndRC: Bool) throws -> ManualBolusRecommendation? {
        guard lastRequestedBolus == nil else {
            // Don't recommend changes if a bolus was just requested.
            // Sending additional pump commands is not going to be
            // successful in any case.
            return nil
        }

        let pendingInsulin = try getPendingInsulin()
        let shouldIncludePendingInsulin = pendingInsulin > 0
        let prediction = try predictGlucose(using: .all, potentialBolus: nil, potentialCarbEntry: potentialCarbEntry, replacingCarbEntry: replacedCarbEntry, includingPendingInsulin: shouldIncludePendingInsulin, includingPositiveVelocityAndRC: considerPositiveVelocityAndRC)
        return try recommendBolusValidatingDataRecency(forPrediction: prediction, consideringPotentialCarbEntry: potentialCarbEntry)
    }

    /// - Throws:
    ///     - LoopError.missingDataError
    ///     - LoopError.glucoseTooOld
    ///     - LoopError.invalidFutureGlucose
    ///     - LoopError.pumpDataTooOld
    ///     - LoopError.configurationError
    fileprivate func recommendBolusValidatingDataRecency<Sample: GlucoseValue>(forPrediction predictedGlucose: [Sample],
                                                                               consideringPotentialCarbEntry potentialCarbEntry: NewCarbEntry?) throws -> ManualBolusRecommendation? {
        guard let glucose = glucoseStore.latestGlucose else {
            throw LoopError.missingDataError(.glucose)
        }

        let pumpStatusDate = doseStore.lastAddedPumpData
        let lastGlucoseDate = glucose.startDate

        guard now().timeIntervalSince(lastGlucoseDate) <= LoopCoreConstants.inputDataRecencyInterval else {
            throw LoopError.glucoseTooOld(date: glucose.startDate)
        }

        guard lastGlucoseDate.timeIntervalSince(now()) <= LoopCoreConstants.inputDataRecencyInterval else {
            throw LoopError.invalidFutureGlucose(date: lastGlucoseDate)
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

        return try recommendManualBolus(forPrediction: predictedGlucose, consideringPotentialCarbEntry: potentialCarbEntry)
    }
    
    /// - Throws: LoopError.configurationError
    private func recommendManualBolus<Sample: GlucoseValue>(forPrediction predictedGlucose: [Sample],
                                                      consideringPotentialCarbEntry potentialCarbEntry: NewCarbEntry?) throws -> ManualBolusRecommendation? {
        guard let glucoseTargetRange = settings.effectiveGlucoseTargetRangeSchedule(presumingMealEntry: potentialCarbEntry != nil) else {
            throw LoopError.configurationError(.glucoseTargetRangeSchedule)
        }
        guard let insulinSensitivity = insulinSensitivityScheduleApplyingOverrideHistory else {
            throw LoopError.configurationError(.insulinSensitivitySchedule)
        }
        guard let maxBolus = settings.maximumBolus else {
            throw LoopError.configurationError(.maximumBolus)
        }

        guard lastRequestedBolus == nil
        else {
            // Don't recommend changes if a bolus was just requested.
            // Sending additional pump commands is not going to be
            // successful in any case.
            return nil
        }

        let volumeRounder = { (_ units: Double) in
            return self.delegate?.roundBolusVolume(units: units) ?? units
        }
        
        let model = doseStore.insulinModelProvider.model(for: pumpInsulinType)

        return predictedGlucose.recommendedManualBolus(
            to: glucoseTargetRange,
            at: now(),
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
            insulinSensitivitySchedule: settings.insulinSensitivitySchedule,
            basalRateSchedule: settings.basalRateSchedule,
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
            insulinSensitivitySchedule: settings.insulinSensitivitySchedule,
            basalRateSchedule: settings.basalRateSchedule,
            glucoseCorrectionRangeSchedule: settings.glucoseTargetRangeSchedule,
            retrospectiveCorrectionGroupingInterval: LoopConstants.retrospectiveCorrectionGroupingInterval
        )
    }

    /// Runs the glucose prediction on the latest effect data.
    ///
    /// - Throws:
    ///     - LoopError.configurationError
    ///     - LoopError.glucoseTooOld
    ///     - LoopError.invalidFutureGlucose
    ///     - LoopError.missingDataError
    ///     - LoopError.pumpDataTooOld
    private func updatePredictedGlucoseAndRecommendedDose(with dosingDecision: StoredDosingDecision) -> (StoredDosingDecision, LoopError?) {
        dispatchPrecondition(condition: .onQueue(dataAccessQueue))

        var dosingDecision = dosingDecision

        self.logger.debug("Recomputing prediction and recommendations.")

        let startDate = now()

        guard let glucose = glucoseStore.latestGlucose else {
            logger.error("Latest glucose missing")
            dosingDecision.appendError(.missingDataError(.glucose))
            return (dosingDecision, .missingDataError(.glucose))
        }

        var errors = [LoopError]()

        if startDate.timeIntervalSince(glucose.startDate) > LoopCoreConstants.inputDataRecencyInterval {
            errors.append(.glucoseTooOld(date: glucose.startDate))
        }

        if glucose.startDate.timeIntervalSince(startDate) > LoopCoreConstants.inputDataRecencyInterval {
            errors.append(.invalidFutureGlucose(date: glucose.startDate))
        }

        let pumpStatusDate = doseStore.lastAddedPumpData

        if startDate.timeIntervalSince(pumpStatusDate) > LoopCoreConstants.inputDataRecencyInterval {
            errors.append(.pumpDataTooOld(date: pumpStatusDate))
        }

        let glucoseTargetRange = settings.effectiveGlucoseTargetRangeSchedule()
        if glucoseTargetRange == nil {
            errors.append(.configurationError(.glucoseTargetRangeSchedule))
        }

        let basalRateSchedule = basalRateScheduleApplyingOverrideHistory
        if basalRateSchedule == nil {
            errors.append(.configurationError(.basalRateSchedule))
        }

        let insulinSensitivity = insulinSensitivityScheduleApplyingOverrideHistory
        if insulinSensitivity == nil {
            errors.append(.configurationError(.insulinSensitivitySchedule))
        }

        if carbRatioScheduleApplyingOverrideHistory == nil {
            errors.append(.configurationError(.carbRatioSchedule))
        }

        let maxBasal = settings.maximumBasalRatePerHour
        if maxBasal == nil {
            errors.append(.configurationError(.maximumBasalRatePerHour))
        }

        let maxBolus = settings.maximumBolus
        if maxBolus == nil {
            errors.append(.configurationError(.maximumBolus))
        }

        if glucoseMomentumEffect == nil {
            errors.append(.missingDataError(.momentumEffect))
        }

        if carbEffect == nil {
            errors.append(.missingDataError(.carbEffect))
        }

        if insulinEffect == nil {
            errors.append(.missingDataError(.insulinEffect))
        }

        if insulinEffectIncludingPendingInsulin == nil {
            errors.append(.missingDataError(.insulinEffectIncludingPendingInsulin))
        }

        if self.insulinOnBoard == nil {
            errors.append(.missingDataError(.activeInsulin))
        }

        dosingDecision.appendErrors(errors)
        if let error = errors.first {
            logger.error("%{public}@", String(describing: error))
            return (dosingDecision, error)
        }

        var loopError: LoopError?
        do {
            let predictedGlucose = try predictGlucose(using: settings.enabledEffects)
            self.predictedGlucose = predictedGlucose
            let predictedGlucoseIncludingPendingInsulin = try predictGlucose(using: settings.enabledEffects, includingPendingInsulin: true)
            self.predictedGlucoseIncludingPendingInsulin = predictedGlucoseIncludingPendingInsulin

            dosingDecision.predictedGlucose = predictedGlucose

            guard lastRequestedBolus == nil
            else {
                // Don't recommend changes if a bolus was just requested.
                // Sending additional pump commands is not going to be
                // successful in any case.
                self.logger.debug("Not generating recommendations because bolus request is in progress.")
                dosingDecision.appendWarning(.bolusInProgress)
                return (dosingDecision, nil)
            }

            let rateRounder = { (_ rate: Double) in
                return self.delegate?.roundBasalRate(unitsPerHour: rate) ?? rate
            }

            let lastTempBasal: DoseEntry?

            if case .some(.tempBasal(let dose)) = basalDeliveryState {
                lastTempBasal = dose
            } else {
                lastTempBasal = nil
            }

            let dosingRecommendation: AutomaticDoseRecommendation?

            // automaticDosingIOBLimit calculated from the user entered maxBolus
            let automaticDosingIOBLimit = maxBolus! * 2.0
            let iobHeadroom = automaticDosingIOBLimit - self.insulinOnBoard!.value

            switch settings.automaticDosingStrategy {
            case .automaticBolus:
                let volumeRounder = { (_ units: Double) in
                    return self.delegate?.roundBolusVolume(units: units) ?? units
                }

                let maxAutomaticBolus = min(iobHeadroom, maxBolus! * LoopConstants.bolusPartialApplicationFactor)

                dosingRecommendation = predictedGlucose.recommendedAutomaticDose(
                    to: glucoseTargetRange!,
                    at: predictedGlucose[0].startDate,
                    suspendThreshold: settings.suspendThreshold?.quantity,
                    sensitivity: insulinSensitivity!,
                    model: doseStore.insulinModelProvider.model(for: pumpInsulinType),
                    basalRates: basalRateSchedule!,
                    maxAutomaticBolus: maxAutomaticBolus,
                    partialApplicationFactor: LoopConstants.bolusPartialApplicationFactor * self.timeBasedDoseApplicationFactor,
                    lastTempBasal: lastTempBasal,
                    volumeRounder: volumeRounder,
                    rateRounder: rateRounder,
                    isBasalRateScheduleOverrideActive: settings.scheduleOverride?.isBasalRateScheduleOverriden(at: startDate) == true
                )
            case .tempBasalOnly:

                let temp = predictedGlucose.recommendedTempBasal(
                    to: glucoseTargetRange!,
                    at: predictedGlucose[0].startDate,
                    suspendThreshold: settings.suspendThreshold?.quantity,
                    sensitivity: insulinSensitivity!,
                    model: doseStore.insulinModelProvider.model(for: pumpInsulinType),
                    basalRates: basalRateSchedule!,
                    maxBasalRate: maxBasal!,
                    additionalActiveInsulinClamp: iobHeadroom,
                    lastTempBasal: lastTempBasal,
                    rateRounder: rateRounder,
                    isBasalRateScheduleOverrideActive: settings.scheduleOverride?.isBasalRateScheduleOverriden(at: startDate) == true
                )
                dosingRecommendation = AutomaticDoseRecommendation(basalAdjustment: temp)
            }

            if let dosingRecommendation = dosingRecommendation {
                self.logger.default("Recommending dose: %{public}@ at %{public}@", String(describing: dosingRecommendation), String(describing: startDate))
                recommendedAutomaticDose = (recommendation: dosingRecommendation, date: startDate)
            } else {
                self.logger.default("No dose recommended.")
                recommendedAutomaticDose = nil
            }
            dosingDecision.automaticDoseRecommendation = recommendedAutomaticDose?.recommendation
        } catch let error {
            loopError = error as? LoopError ?? .unknownError(error)
            if let loopError = loopError {
                logger.error("Error attempting to predict glucose: %{public}@", String(describing: loopError))
                dosingDecision.appendError(loopError)
            }
        }

        return (dosingDecision, loopError)
    }

    /// *This method should only be called from the `dataAccessQueue`*
    private func enactRecommendedAutomaticDose() -> LoopError? {
        dispatchPrecondition(condition: .onQueue(dataAccessQueue))

        guard let recommendedDose = self.recommendedAutomaticDose else {
            return nil
        }

        guard abs(recommendedDose.date.timeIntervalSince(now())) < TimeInterval(minutes: 5) else {
            return LoopError.recommendationExpired(date: recommendedDose.date)
        }
        
        if case .suspended = basalDeliveryState {
            return LoopError.pumpSuspended
        }

        let updateGroup = DispatchGroup()
        updateGroup.enter()
        var delegateError: LoopError?

        delegate?.loopDataManager(self, didRecommend: recommendedDose) { (error) in
            delegateError = error
            updateGroup.leave()
        }
        updateGroup.wait()

        if delegateError == nil {
            self.recommendedAutomaticDose = nil
        }
        
        return delegateError
    }
    
    /// Ensures that the current temp basal is at or below the proposed max temp basal, and if not, cancel it before proceeding.
    /// Calls the completion with `nil` if successful, or an `error` if canceling the active temp basal fails.
    func maxTempBasalSavePreflight(unitsPerHour: Double?, completion: @escaping (_ error: Error?) -> Void) {
        guard let unitsPerHour = unitsPerHour else {
            completion(nil)
            return 
        }
        dataAccessQueue.async {
            switch self.basalDeliveryState {
            case .some(.tempBasal(let dose)):
                if dose.unitsPerHour > unitsPerHour {
                    // Temp basal is higher than proposed rate, so should cancel
                    self.cancelActiveTempBasal(for: .maximumBasalRateChanged, completion: completion)
                } else {
                    completion(nil)
                }
            default:
                completion(nil)
            }
        }
    }
}

/// Describes a view into the loop state
protocol LoopState {
    /// The last-calculated carbs on board
    var carbsOnBoard: CarbValue? { get }
    
    /// The last-calculated insulin on board
    var insulinOnBoard: InsulinValue? { get }

    /// An error in the current state of the loop, or one that happened during the last attempt to loop.
    var error: LoopError? { get }

    /// A timeline of average velocity of glucose change counteracting predicted insulin effects
    var insulinCounteractionEffects: [GlucoseEffectVelocity] { get }

    /// The calculated timeline of predicted glucose values
    var predictedGlucose: [PredictedGlucoseValue]? { get }

    /// The calculated timeline of predicted glucose values, including the effects of pending insulin
    var predictedGlucoseIncludingPendingInsulin: [PredictedGlucoseValue]? { get }

    /// The recommended temp basal based on predicted glucose
    var recommendedAutomaticDose: (recommendation: AutomaticDoseRecommendation, date: Date)? { get }

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
    /// - Parameter considerPositiveVelocityAndRC: Positive velocity and positive retrospective correction will not be used if this is false.
    /// - Returns: An timeline of predicted glucose values
    /// - Throws: LoopError.missingDataError if prediction cannot be computed
    func predictGlucose(using inputs: PredictionInputEffect, potentialBolus: DoseEntry?, potentialCarbEntry: NewCarbEntry?, replacingCarbEntry replacedCarbEntry: StoredCarbEntry?, includingPendingInsulin: Bool, considerPositiveVelocityAndRC: Bool) throws -> [PredictedGlucoseValue]

    /// Calculates a new prediction from a manual glucose entry in the context of a meal entry
    ///
    /// - Parameter glucose: The unstored manual glucose entry
    /// - Parameter potentialBolus: A bolus under consideration for which to include effects in the prediction
    /// - Parameter potentialCarbEntry: A carb entry under consideration for which to include effects in the prediction
    /// - Parameter replacedCarbEntry: An existing carb entry replaced by `potentialCarbEntry`
    /// - Parameter includingPendingInsulin: If `true`, the returned prediction will include the effects of scheduled but not yet delivered insulin
    /// - Parameter considerPositiveVelocityAndRC: Positive velocity and positive retrospective correction will not be used if this is false.
    /// - Returns: A timeline of predicted glucose values
    func predictGlucoseFromManualGlucose(
        _ glucose: NewGlucoseSample,
        potentialBolus: DoseEntry?,
        potentialCarbEntry: NewCarbEntry?,
        replacingCarbEntry replacedCarbEntry: StoredCarbEntry?,
        includingPendingInsulin: Bool,
        considerPositiveVelocityAndRC: Bool
    ) throws -> [PredictedGlucoseValue]

    /// Computes the recommended bolus for correcting a glucose prediction, optionally considering a potential carb entry.
    /// - Parameter potentialCarbEntry: A carb entry under consideration for which to include effects in the prediction
    /// - Parameter replacedCarbEntry: An existing carb entry replaced by `potentialCarbEntry`
    /// - Parameter considerPositiveVelocityAndRC: Positive velocity and positive retrospective correction will not be used if this is false.
    /// - Returns: A bolus recommendation, or `nil` if not applicable
    /// - Throws: LoopError.missingDataError if recommendation cannot be computed
    func recommendBolus(consideringPotentialCarbEntry potentialCarbEntry: NewCarbEntry?, replacingCarbEntry replacedCarbEntry: StoredCarbEntry?, considerPositiveVelocityAndRC: Bool) throws -> ManualBolusRecommendation?

    /// Computes the recommended bolus for correcting a glucose prediction derived from a manual glucose entry, optionally considering a potential carb entry.
    /// - Parameter glucose: The unstored manual glucose entry
    /// - Parameter potentialCarbEntry: A carb entry under consideration for which to include effects in the prediction
    /// - Parameter replacedCarbEntry: An existing carb entry replaced by `potentialCarbEntry`
    /// - Parameter considerPositiveVelocityAndRC: Positive velocity and positive retrospective correction will not be used if this is false.
    /// - Returns: A bolus recommendation, or `nil` if not applicable
    /// - Throws: LoopError.configurationError if recommendation cannot be computed
    func recommendBolusForManualGlucose(_ glucose: NewGlucoseSample, consideringPotentialCarbEntry potentialCarbEntry: NewCarbEntry?, replacingCarbEntry replacedCarbEntry: StoredCarbEntry?, considerPositiveVelocityAndRC: Bool) throws -> ManualBolusRecommendation?
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
        try predictGlucose(using: inputs, potentialBolus: nil, potentialCarbEntry: nil, replacingCarbEntry: nil, includingPendingInsulin: includingPendingInsulin, considerPositiveVelocityAndRC: true)
    }
}


extension LoopDataManager {
    private struct LoopStateView: LoopState {

        private let loopDataManager: LoopDataManager
        private let updateError: LoopError?

        init(loopDataManager: LoopDataManager, updateError: LoopError?) {
            self.loopDataManager = loopDataManager
            self.updateError = updateError
        }

        var carbsOnBoard: CarbValue? {
            dispatchPrecondition(condition: .onQueue(loopDataManager.dataAccessQueue))
            return loopDataManager.carbsOnBoard
        }
        
        var insulinOnBoard: InsulinValue? {
            dispatchPrecondition(condition: .onQueue(loopDataManager.dataAccessQueue))
            return loopDataManager.insulinOnBoard
        }

        var error: LoopError? {
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

        var recommendedAutomaticDose: (recommendation: AutomaticDoseRecommendation, date: Date)? {
            dispatchPrecondition(condition: .onQueue(loopDataManager.dataAccessQueue))
            guard loopDataManager.lastRequestedBolus == nil else {
                return nil
            }
            return loopDataManager.recommendedAutomaticDose
        }

        var retrospectiveGlucoseDiscrepancies: [GlucoseChange]? {
            dispatchPrecondition(condition: .onQueue(loopDataManager.dataAccessQueue))
            return loopDataManager.retrospectiveGlucoseDiscrepanciesSummed
        }

        var totalRetrospectiveCorrection: HKQuantity? {
            dispatchPrecondition(condition: .onQueue(loopDataManager.dataAccessQueue))
            return loopDataManager.retrospectiveCorrection.totalGlucoseCorrectionEffect
        }

        func predictGlucose(using inputs: PredictionInputEffect, potentialBolus: DoseEntry?, potentialCarbEntry: NewCarbEntry?, replacingCarbEntry replacedCarbEntry: StoredCarbEntry?, includingPendingInsulin: Bool, considerPositiveVelocityAndRC: Bool) throws -> [PredictedGlucoseValue] {
            dispatchPrecondition(condition: .onQueue(loopDataManager.dataAccessQueue))
            return try loopDataManager.predictGlucose(using: inputs, potentialBolus: potentialBolus, potentialCarbEntry: potentialCarbEntry, replacingCarbEntry: replacedCarbEntry, includingPendingInsulin: includingPendingInsulin, includingPositiveVelocityAndRC: considerPositiveVelocityAndRC)
        }

        func predictGlucoseFromManualGlucose(
            _ glucose: NewGlucoseSample,
            potentialBolus: DoseEntry?,
            potentialCarbEntry: NewCarbEntry?,
            replacingCarbEntry replacedCarbEntry: StoredCarbEntry?,
            includingPendingInsulin: Bool,
            considerPositiveVelocityAndRC: Bool
        ) throws -> [PredictedGlucoseValue] {
            dispatchPrecondition(condition: .onQueue(loopDataManager.dataAccessQueue))
            return try loopDataManager.predictGlucoseFromManualGlucose(glucose, potentialBolus: potentialBolus, potentialCarbEntry: potentialCarbEntry, replacingCarbEntry: replacedCarbEntry, includingPendingInsulin: includingPendingInsulin, considerPositiveVelocityAndRC: considerPositiveVelocityAndRC)
        }

        func recommendBolus(consideringPotentialCarbEntry potentialCarbEntry: NewCarbEntry?, replacingCarbEntry replacedCarbEntry: StoredCarbEntry?, considerPositiveVelocityAndRC: Bool) throws -> ManualBolusRecommendation? {
            dispatchPrecondition(condition: .onQueue(loopDataManager.dataAccessQueue))
            return try loopDataManager.recommendBolus(consideringPotentialCarbEntry: potentialCarbEntry, replacingCarbEntry: replacedCarbEntry, considerPositiveVelocityAndRC: considerPositiveVelocityAndRC)
        }

        func recommendBolusForManualGlucose(_ glucose: NewGlucoseSample, consideringPotentialCarbEntry potentialCarbEntry: NewCarbEntry?, replacingCarbEntry replacedCarbEntry: StoredCarbEntry?, considerPositiveVelocityAndRC: Bool) throws -> ManualBolusRecommendation? {
            dispatchPrecondition(condition: .onQueue(loopDataManager.dataAccessQueue))
            return try loopDataManager.recommendBolusForManualGlucose(glucose, consideringPotentialCarbEntry: potentialCarbEntry, replacingCarbEntry: replacedCarbEntry, considerPositiveVelocityAndRC: considerPositiveVelocityAndRC)
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
            let (_, updateError) = self.update(for: .getLoopState)

            handler(self, LoopStateView(loopDataManager: self, updateError: updateError))
        }
    }
    
    func generateSimpleBolusRecommendation(at date: Date, mealCarbs: HKQuantity?, manualGlucose: HKQuantity?) -> BolusDosingDecision? {
        
        var dosingDecision = BolusDosingDecision(for: .simpleBolus)
        
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
        
        if let scheduleOverride = settings.scheduleOverride, !scheduleOverride.hasFinished() {
            dosingDecision.scheduleOverride = settings.scheduleOverride
        }

        dosingDecision.glucoseTargetRangeSchedule = correctionRangeSchedule
        
        var notice: BolusRecommendationNotice? = nil
        if let manualGlucose = manualGlucose {
            let glucoseValue = SimpleGlucoseValue(startDate: date, quantity: manualGlucose)
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
        
        dosingDecision.manualBolusRecommendation = ManualBolusRecommendationWithDate(recommendation: ManualBolusRecommendation(amount: bolusAmount.doubleValue(for: .internationalUnit()), pendingInsulin: 0, notice: notice),
                                                                                     date: Date())
        
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
                "recommendedAutomaticDose: \(String(describing: state.recommendedAutomaticDose))",
                "lastBolus: \(String(describing: manager.lastRequestedBolus))",
                "lastLoopCompleted: \(String(describing: manager.lastLoopCompleted))",
                "basalDeliveryState: \(String(describing: manager.basalDeliveryState))",
                "carbsOnBoard: \(String(describing: state.carbsOnBoard))",
                "insulinOnBoard: \(String(describing: manager.insulinOnBoard))",
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
                        
                        self.mealDetectionManager.generateDiagnosticReport { report in
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
}


extension Notification.Name {
    static let LoopDataUpdated = Notification.Name(rawValue: "com.loopkit.Loop.LoopDataUpdated")
    static let LoopRunning = Notification.Name(rawValue: "com.loopkit.Loop.LoopRunning")
    static let LoopCompleted = Notification.Name(rawValue: "com.loopkit.Loop.LoopCompleted")
}

protocol LoopDataManagerDelegate: AnyObject {

    /// Informs the delegate that an immediate basal change is recommended
    ///
    /// - Parameters:
    ///   - manager: The manager
    ///   - basal: The new recommended basal
    ///   - completion: A closure called once on completion. Will be passed a non-null error if acting on the recommendation fails.
    ///   - result: The enacted basal
    func loopDataManager(_ manager: LoopDataManager, didRecommend automaticDose: (recommendation: AutomaticDoseRecommendation, date: Date), completion: @escaping (LoopError?) -> Void) -> Void

    /// Asks the delegate to round a recommended basal rate to a supported rate
    ///
    /// - Parameters:
    ///   - rate: The recommended rate in U/hr
    /// - Returns: a supported rate of delivery in Units/hr. The rate returned should not be larger than the passed in rate.
    func roundBasalRate(unitsPerHour: Double) -> Double
    
    /// Asks the delegate to estimate the duration to deliver the bolus.
    ///
    /// - Parameters:
    ///   - bolusUnits: size of the bolus in U
    /// - Returns: the estimated time it will take to deliver bolus
    func loopDataManager(_ manager: LoopDataManager, estimateBolusDuration bolusUnits: Double) -> TimeInterval?
    
    /// Asks the delegate to round a recommended bolus volume to a supported volume
    ///
    /// - Parameters:
    ///   - units: The recommended bolus in U
    /// - Returns: a supported bolus volume in U. The volume returned should be the nearest deliverable volume.
    func roundBolusVolume(units: Double) -> Double

    /// The pump manager status, if one exists.
    var pumpManagerStatus: PumpManagerStatus? { get }

    /// The pump status highlight, if one exists.
    var pumpStatusHighlight: DeviceStatusHighlight? { get }

    /// The cgm manager status, if one exists.
    var cgmManagerStatus: CGMManagerStatus? { get }
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

extension ManualBolusRecommendationWithDate {
    init?(_ bolusRecommendationDate: (recommendation: ManualBolusRecommendation, date: Date)?) {
        guard let bolusRecommendationDate = bolusRecommendationDate else {
            return nil
        }
        self.init(recommendation: bolusRecommendationDate.recommendation, date: bolusRecommendationDate.date)
    }
}

private extension StoredDosingDecision.Settings {
    init?(_ settings: StoredSettings?) {
        guard let settings = settings else {
            return nil
        }
        self.init(syncIdentifier: settings.syncIdentifier)
    }
}

// MARK: - Simulated Core Data

extension LoopDataManager {
    func generateSimulatedHistoricalCoreData(completion: @escaping (Error?) -> Void) {
        guard FeatureFlags.simulatedCoreDataEnabled else {
            fatalError("\(#function) should be invoked only when simulated core data is enabled")
        }

        guard let glucoseStore = glucoseStore as? GlucoseStore, let carbStore = carbStore as? CarbStore, let doseStore = doseStore as? DoseStore, let dosingDecisionStore = dosingDecisionStore as? DosingDecisionStore else {
            fatalError("Mock stores should not be used to generate simulated core data")
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

    func purgeHistoricalCoreData(completion: @escaping (Error?) -> Void) {
        guard FeatureFlags.simulatedCoreDataEnabled else {
            fatalError("\(#function) should be invoked only when simulated core data is enabled")
        }

        guard let glucoseStore = glucoseStore as? GlucoseStore, let carbStore = carbStore as? CarbStore, let doseStore = doseStore as? DoseStore, let dosingDecisionStore = dosingDecisionStore as? DosingDecisionStore else {
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
                    glucoseStore.purgeHistoricalGlucoseObjects(completion: completion)
                }
            }
        }
    }
}

extension LoopDataManager {
    public var therapySettings: TherapySettings {
        get {
            let settings = settings
            return TherapySettings(glucoseTargetRangeSchedule: settings.glucoseTargetRangeSchedule,
                            correctionRangeOverrides: CorrectionRangeOverrides(preMeal: settings.preMealTargetRange, workout: settings.legacyWorkoutTargetRange),
                            overridePresets: settings.overridePresets,
                            maximumBasalRatePerHour: settings.maximumBasalRatePerHour,
                            maximumBolus: settings.maximumBolus,
                            suspendThreshold: settings.suspendThreshold,
                            insulinSensitivitySchedule: settings.insulinSensitivitySchedule,
                            carbRatioSchedule: settings.carbRatioSchedule,
                            basalRateSchedule: settings.basalRateSchedule,
                            defaultRapidActingModel: settings.defaultRapidActingModel)
        }
        
        set {
            mutateSettings { settings in
                settings.defaultRapidActingModel = newValue.defaultRapidActingModel
                settings.insulinSensitivitySchedule = newValue.insulinSensitivitySchedule
                settings.carbRatioSchedule = newValue.carbRatioSchedule
                settings.basalRateSchedule = newValue.basalRateSchedule
                settings.glucoseTargetRangeSchedule = newValue.glucoseTargetRangeSchedule
                settings.preMealTargetRange = newValue.correctionRangeOverrides?.preMeal
                settings.legacyWorkoutTargetRange = newValue.correctionRangeOverrides?.workout
                settings.suspendThreshold = newValue.suspendThreshold
                settings.maximumBolus = newValue.maximumBolus
                settings.maximumBasalRatePerHour = newValue.maximumBasalRatePerHour
                settings.overridePresets = newValue.overridePresets ?? []
            }
        }
    }
}
