//
//  BolusEntryViewModel.swift
//  Loop
//
//  Created by Michael Pangburn on 7/17/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import Combine
import HealthKit
import LocalAuthentication
import Intents
import os.log
import LoopCore
import LoopKit
import LoopKitUI
import LoopUI
import SwiftUI

protocol BolusEntryViewModelDelegate: AnyObject {
    
    func withLoopState(do block: @escaping (LoopState) -> Void)

    func addGlucoseSamples(_ samples: [NewGlucoseSample], completion: ((_ result: Swift.Result<[StoredGlucoseSample], Error>) -> Void)?)
    
    func addCarbEntry(_ carbEntry: NewCarbEntry, replacing replacingEntry: StoredCarbEntry? ,
                      completion: @escaping (_ result: Result<StoredCarbEntry>) -> Void)

    func storeManualBolusDosingDecision(_ bolusDosingDecision: BolusDosingDecision, withDate date: Date)
    
    func enactBolus(units: Double, automatic: Bool, completion: @escaping (_ error: Error?) -> Void)
    
    func getGlucoseSamples(start: Date?, end: Date?, completion: @escaping (_ samples: Swift.Result<[StoredGlucoseSample], Error>) -> Void)

    func insulinOnBoard(at date: Date, completion: @escaping (_ result: DoseStoreResult<InsulinValue>) -> Void)
    
    func carbsOnBoard(at date: Date, effectVelocities: [GlucoseEffectVelocity]?, completion: @escaping (_ result: CarbStoreResult<CarbValue>) -> Void)
    
    func insulinActivityDuration(for type: InsulinType?) -> TimeInterval

    var mostRecentGlucoseDataDate: Date? { get }
    
    var mostRecentPumpDataDate: Date? { get }
    
    var isPumpConfigured: Bool { get }
    
    var pumpInsulinType: InsulinType? { get }
    
    var settings: LoopSettings { get }

    var displayGlucoseUnitObservable: DisplayGlucoseUnitObservable { get }
}

final class BolusEntryViewModel: ObservableObject {
    enum Alert: Int {
        case recommendationChanged
        case maxBolusExceeded
        case noPumpManagerConfigured
        case noMaxBolusConfigured
        case carbEntryPersistenceFailure
        case manualGlucoseEntryOutOfAcceptableRange
        case manualGlucoseEntryPersistenceFailure
        case glucoseNoLongerStale
    }

    enum Notice: Equatable {
        case predictedGlucoseInRange
        case predictedGlucoseBelowSuspendThreshold(suspendThreshold: HKQuantity)
        case glucoseBelowTarget
        case staleGlucoseData
        case stalePumpData
    }

    var authenticate: AuthenticationChallenge = LocalAuthentication.deviceOwnerCheck

    // MARK: - State

    @Published var glucoseValues: [GlucoseValue] = [] // stored glucose values + manual glucose entry
    private var storedGlucoseValues: [GlucoseValue] = []
    @Published var predictedGlucoseValues: [GlucoseValue] = []
    @Published var chartDateInterval: DateInterval

    @Published var activeCarbs: HKQuantity?
    @Published var activeInsulin: HKQuantity?

    @Published var targetGlucoseSchedule: GlucoseRangeSchedule?
    @Published var preMealOverride: TemporaryScheduleOverride?
    private var savedPreMealOverride: TemporaryScheduleOverride?
    @Published var scheduleOverride: TemporaryScheduleOverride?
    var maximumBolus: HKQuantity?

    let originalCarbEntry: StoredCarbEntry?
    let potentialCarbEntry: NewCarbEntry?
    let selectedCarbAbsorptionTimeEmoji: String?

    @Published var isManualGlucoseEntryEnabled = false
    @Published var manualGlucoseQuantity: HKQuantity?
    private var manualGlucoseSample: NewGlucoseSample? // derived from `enteredManualGlucose`, but stored to ensure timestamp consistency

    @Published var recommendedBolus: HKQuantity?
    @Published var enteredBolus = HKQuantity(unit: .internationalUnit(), doubleValue: 0)
    private var isInitiatingSaveOrBolus = false

    private var dosingDecision = BolusDosingDecision(for: .normalBolus)

    @Published var activeAlert: Alert?
    @Published var activeNotice: Notice?

    private let log = OSLog(category: "BolusEntryViewModel")
    private var cancellables: Set<AnyCancellable> = []

    let chartManager: ChartsManager = {
        let predictedGlucoseChart = PredictedGlucoseChart(predictedGlucoseBounds: FeatureFlags.predictedGlucoseChartClampEnabled ? .default : nil,
                                                          yAxisStepSizeMGDLOverride: FeatureFlags.predictedGlucoseChartClampEnabled ? 40 : nil)
        predictedGlucoseChart.glucoseDisplayRange = LoopConstants.glucoseChartDefaultDisplayRangeWide
        return ChartsManager(colors: .primary, settings: .default, charts: [predictedGlucoseChart], traitCollection: .current)
    }()

    // needed to detect change in display glucose unit when returning to the app
    private var cachedDisplayGlucoseUnit: HKUnit

    private var displayGlucoseUnit: HKUnit? {
        delegate?.displayGlucoseUnitObservable.displayGlucoseUnit
    }

    private let glucoseQuantityFormatter = QuantityFormatter()

    private var _manualGlucoseString = "" {
        didSet {
            guard let manualGlucoseValue = glucoseQuantityFormatter.numberFormatter.number(from: _manualGlucoseString)?.doubleValue
            else {
                manualGlucoseQuantity = nil
                return
            }

            // only update manualGlucoseQuantity if needed
            if manualGlucoseQuantity == nil ||
                _manualGlucoseString != glucoseQuantityFormatter.string(from: manualGlucoseQuantity!, for: cachedDisplayGlucoseUnit, includeUnit: false)
            {
                manualGlucoseQuantity = HKQuantity(unit: cachedDisplayGlucoseUnit, doubleValue: manualGlucoseValue)
            }
        }
    }

    var manualGlucoseString: String {
        get {
            guard let displayGlucoseUnit = displayGlucoseUnit else { return "" }
            if cachedDisplayGlucoseUnit != displayGlucoseUnit {
                cachedDisplayGlucoseUnit = displayGlucoseUnit
                glucoseQuantityFormatter.setPreferredNumberFormatter(for: displayGlucoseUnit)
                guard let manualGlucoseQuantity = manualGlucoseQuantity,
                      let manualGlucoseString = glucoseQuantityFormatter.string(from: manualGlucoseQuantity, for: displayGlucoseUnit, includeUnit: false)
                else {
                    _manualGlucoseString = ""
                    return _manualGlucoseString
                }
                self._manualGlucoseString = manualGlucoseString
            }
            return _manualGlucoseString
        }
        set {
            _manualGlucoseString = newValue
        }
    }

    // MARK: - Seams
    private weak var delegate: BolusEntryViewModelDelegate?
    private let now: () -> Date
    private let screenWidth: CGFloat
    private let debounceIntervalMilliseconds: Int
    private let uuidProvider: () -> String
    private let carbEntryDateFormatter: DateFormatter
    
    // MARK: - Initialization

    init(
        delegate: BolusEntryViewModelDelegate,
        now: @escaping () -> Date = { Date() },
        screenWidth: CGFloat = UIScreen.main.bounds.width,
        debounceIntervalMilliseconds: Int = 400,
        uuidProvider: @escaping () -> String = { UUID().uuidString },
        timeZone: TimeZone? = nil,
        originalCarbEntry: StoredCarbEntry? = nil,
        potentialCarbEntry: NewCarbEntry? = nil,
        selectedCarbAbsorptionTimeEmoji: String? = nil,
        isManualGlucoseEntryEnabled: Bool = false
    ) {
        self.delegate = delegate
        self.now = now
        self.screenWidth = screenWidth
        self.debounceIntervalMilliseconds = debounceIntervalMilliseconds
        self.uuidProvider = uuidProvider
        self.carbEntryDateFormatter = DateFormatter()
        self.carbEntryDateFormatter.dateStyle = .none
        self.carbEntryDateFormatter.timeStyle = .short
        if let timeZone = timeZone {
            self.carbEntryDateFormatter.timeZone = timeZone
        }
        
        self.originalCarbEntry = originalCarbEntry
        self.potentialCarbEntry = potentialCarbEntry
        self.selectedCarbAbsorptionTimeEmoji = selectedCarbAbsorptionTimeEmoji
        
        self.isManualGlucoseEntryEnabled = isManualGlucoseEntryEnabled
        
        self.chartDateInterval = DateInterval(start: Date(timeInterval: .hours(-1), since: now()), duration: .hours(7))
        
        self.dosingDecision.originalCarbEntry = originalCarbEntry

        self.cachedDisplayGlucoseUnit = delegate.displayGlucoseUnitObservable.displayGlucoseUnit
        
        update() {
            // Only start observing after first update is complete
            self.observeLoopUpdates()
            self.observeEnteredManualGlucoseChanges()
            self.observeElapsedTime()
            self.observeEnteredBolusChanges()
        }
    }
        
    private func observeLoopUpdates() {
        NotificationCenter.default
            .publisher(for: .LoopDataUpdated)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.log.debug("calling update() from LoopDataUpdated notification")
                self?.update()
            }
            .store(in: &cancellables)
    }

    private func observeEnteredBolusChanges() {
        $enteredBolus
            .dropFirst()
            .removeDuplicates()
            .debounce(for: .milliseconds(debounceIntervalMilliseconds), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.delegate?.withLoopState { [weak self] state in
                    self?.updatePredictedGlucoseValues(from: state)
                }
            }
            .store(in: &cancellables)
    }

    private func observeEnteredManualGlucoseChanges() {
        $manualGlucoseQuantity
            .dropFirst()
            .debounce(for: .milliseconds(debounceIntervalMilliseconds), scheduler: RunLoop.main)
            .sink { [weak self] enteredManualGlucose in
                guard let self = self else { return }

                self.updateManualGlucoseSample(enteredAt: self.now())

                // Clear out any entered bolus whenever the glucose entry changes
                self.enteredBolus = HKQuantity(unit: .internationalUnit(), doubleValue: 0)

                self.delegate?.withLoopState { [weak self] state in
                    self?.updatePredictedGlucoseValues(from: state, completion: {
                        // Ensure the manual glucose entry appears on the chart at the same time as the updated prediction
                        self?.updateGlucoseChartValues()
                    })

                    self?.updateRecommendedBolusAndNotice(from: state, isUpdatingFromUserInput: true)
                }
            }
            .store(in: &cancellables)
    }
    
    private func observeElapsedTime() {
        // If glucose data is stale, loop status updates cannot be expected to keep presented data fresh.
        // Periodically update the UI to ensure recommendations do not go stale.
        Timer.publish(every: .minutes(5), tolerance: .seconds(15), on: .main, in: .default)
            .autoconnect()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                
                self.log.default("5 minutes elapsed on bolus screen; refreshing UI")

                // Update the manual glucose sample's timestamp, which should always be "now"
                self.updateManualGlucoseSample(enteredAt: self.now())
                self.log.debug("calling update() from observeElapsedTime")
                self.update()
            }
            .store(in: &cancellables)
    }

    // MARK: - View API

    var isBolusRecommended: Bool {
        guard let recommendedBolus = recommendedBolus else {
            return false
        }

        return recommendedBolus.doubleValue(for: .internationalUnit()) > 0
    }

    func saveAndDeliver(onSuccess completion: @escaping () -> Void) {
        guard delegate?.isPumpConfigured ?? false else {
            presentAlert(.noPumpManagerConfigured)
            return
        }

        guard let maximumBolus = maximumBolus else {
            presentAlert(.noMaxBolusConfigured)
            return
        }

        guard enteredBolus <= maximumBolus else {
            presentAlert(.maxBolusExceeded)
            return
        }

        if let manualGlucoseSample = manualGlucoseSample {
            guard LoopConstants.validManualGlucoseEntryRange.contains(manualGlucoseSample.quantity) else {
                presentAlert(.manualGlucoseEntryOutOfAcceptableRange)
                return
            }
        }

        // Authenticate the bolus before saving anything
        if enteredBolus.doubleValue(for: .internationalUnit()) > 0 {
            isInitiatingSaveOrBolus = true
            let message = String(format: NSLocalizedString("Authenticate to Bolus %@ Units", comment: "The message displayed during a device authentication prompt for bolus specification"), enteredBolusAmountString)
            authenticate(message) { [weak self] in
                switch $0 {
                case .success:
                    self?.continueSaving(onSuccess: completion)
                case .failure:
                    break
                }
            }
        } else if potentialCarbEntry != nil  { // Allow user to save carbs without bolusing
            continueSaving(onSuccess: completion)
        } else if manualGlucoseSample != nil { // Allow user to save the manual glucose sample without bolusing
            continueSaving(onSuccess: completion)
        } else {
            completion()
        }
    }
    
    private func continueSaving(onSuccess completion: @escaping () -> Void) {
        if let manualGlucoseSample = manualGlucoseSample {
            isInitiatingSaveOrBolus = true
            delegate?.addGlucoseSamples([manualGlucoseSample]) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let glucoseValues):
                        self.dosingDecision.manualGlucoseSample = glucoseValues.first
                        self.saveCarbsAndDeliverBolus(onSuccess: completion)
                    case .failure(let error):
                        self.isInitiatingSaveOrBolus = false
                        self.presentAlert(.manualGlucoseEntryPersistenceFailure)
                        self.log.error("Failed to add manual glucose entry: %{public}@", String(describing: error))
                    }
                }
            }
        } else {
            self.dosingDecision.manualGlucoseSample = nil
            saveCarbsAndDeliverBolus(onSuccess: completion)
        }
    }

    private func saveCarbsAndDeliverBolus(onSuccess completion: @escaping () -> Void) {
        guard let carbEntry = potentialCarbEntry else {
            dosingDecision.carbEntry = nil
            deliverBolus(onSuccess: completion)
            return
        }

        if originalCarbEntry == nil {
            let interaction = INInteraction(intent: NewCarbEntryIntent(), response: nil)
            interaction.donate { [weak self] (error) in
                if let error = error {
                    self?.log.error("Failed to donate intent: %{public}@", String(describing: error))
                }
            }
        }

        isInitiatingSaveOrBolus = true
        delegate?.addCarbEntry(carbEntry, replacing: originalCarbEntry) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let storedCarbEntry):
                    self.dosingDecision.carbEntry = storedCarbEntry
                    self.deliverBolus(onSuccess: completion)
                case .failure(let error):
                    self.isInitiatingSaveOrBolus = false
                    self.presentAlert(.carbEntryPersistenceFailure)
                    self.log.error("Failed to add carb entry: %{public}@", String(describing: error))
                }
            }
        }
    }

    private func deliverBolus(onSuccess completion: @escaping () -> Void) {
        let now = self.now()
        let bolusVolume = enteredBolus.doubleValue(for: .internationalUnit())

        dosingDecision.manualBolusRequested = bolusVolume
        delegate?.storeManualBolusDosingDecision(dosingDecision, withDate: now)

        guard bolusVolume > 0 else {
            completion()
            return
        }

        isInitiatingSaveOrBolus = true
        savedPreMealOverride = nil
        // TODO: should we pass along completion or not???
        delegate?.enactBolus(units: bolusVolume, automatic: false, completion: { _ in })
        completion()
    }

    private func presentAlert(_ alert: Alert) {
        dispatchPrecondition(condition: .onQueue(.main))

        // As of iOS 13.6 / Xcode 11.6, swapping out an alert while one is active crashes SwiftUI.
        guard activeAlert == nil else {
            return
        }

        activeAlert = alert
    }

    private lazy var bolusVolumeFormatter = QuantityFormatter(for: .internationalUnit())

    private lazy var absorptionTimeFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.collapsesLargestUnit = true
        formatter.unitsStyle = .abbreviated
        formatter.allowsFractionalUnits = true
        formatter.allowedUnits = [.hour, .minute]
        return formatter
    }()

    var enteredBolusAmountString: String {
        let bolusVolume = enteredBolus.doubleValue(for: .internationalUnit())
        return bolusVolumeFormatter.numberFormatter.string(from: bolusVolume) ?? String(bolusVolume)
    }

    var maximumBolusAmountString: String? {
        guard let maxBolusVolume = maximumBolus?.doubleValue(for: .internationalUnit()) else {
            return nil
        }
        return bolusVolumeFormatter.numberFormatter.string(from: maxBolusVolume) ?? String(maxBolusVolume)
    }

    var carbEntryAmountAndEmojiString: String? {
        guard
            let potentialCarbEntry = potentialCarbEntry,
            let carbAmountString = QuantityFormatter(for: .gram()).string(from: potentialCarbEntry.quantity, for: .gram())
        else {
            return nil
        }

        if let emoji = potentialCarbEntry.foodType ?? selectedCarbAbsorptionTimeEmoji {
            return String(format: NSLocalizedString("%1$@ %2$@", comment: "Format string combining carb entry quantity and absorption time emoji"), carbAmountString, emoji)
        } else {
            return carbAmountString
        }
    }

    var carbEntryDateAndAbsorptionTimeString: String? {
        guard let potentialCarbEntry = potentialCarbEntry else {
            return nil
        }

        let entryTimeString = carbEntryDateFormatter.string(from: potentialCarbEntry.startDate)

        if let absorptionTime = potentialCarbEntry.absorptionTime, let absorptionTimeString = absorptionTimeFormatter.string(from: absorptionTime) {
            return String(format: NSLocalizedString("%1$@ + %2$@", comment: "Format string combining carb entry time and absorption time"), entryTimeString, absorptionTimeString)
        } else {
            return entryTimeString
        }
    }

    // MARK: - Data upkeep

    private func updateManualGlucoseSample(enteredAt entryDate: Date) {
        dispatchPrecondition(condition: .onQueue(.main))

        manualGlucoseSample = manualGlucoseQuantity.map { quantity in
            NewGlucoseSample(
                date: entryDate,
                quantity: quantity,
                condition: nil,     // All manual glucose entries are assumed to have no condition.
                trend: nil,         // All manual glucose entries are assumed to have no trend.
                trendRate: nil,     // All manual glucose entries are assumed to have no trend rate.
                isDisplayOnly: false,
                wasUserEntered: true,
                syncIdentifier: uuidProvider()
            )
        }
    }

    private func update(_ completion: (() -> Void)? = nil) {
        dispatchPrecondition(condition: .onQueue(.main))

        // Prevent any UI updates after a bolus has been initiated.
        guard !isInitiatingSaveOrBolus else { return }

        disableManualGlucoseEntryIfNecessary()
        updateChartDateInterval()
        updateStoredGlucoseValues()
        updatePredictionAndRecommendation() {
            self.updateActiveInsulin()
            completion?()
        }
    }

    private func disableManualGlucoseEntryIfNecessary() {
        dispatchPrecondition(condition: .onQueue(.main))

        if isManualGlucoseEntryEnabled, !isGlucoseDataStale {
            isManualGlucoseEntryEnabled = false
            manualGlucoseString = ""
            manualGlucoseQuantity = nil
            manualGlucoseSample = nil
            presentAlert(.glucoseNoLongerStale)
        }
    }

    private func updateStoredGlucoseValues() {
        let historicalGlucoseStartDate = Date(timeInterval: -LoopCoreConstants.dosingDecisionHistoricalGlucoseInterval, since: now())
        let chartStartDate = chartDateInterval.start
        delegate?.getGlucoseSamples(start: min(historicalGlucoseStartDate, chartStartDate), end: nil) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .failure(let error):
                    self.log.error("Failure getting glucose samples: %{public}@", String(describing: error))
                    self.storedGlucoseValues = []
                    self.dosingDecision.historicalGlucose = []
                case .success(let samples):
                    self.storedGlucoseValues = samples.filter { $0.startDate >= chartStartDate }
                    self.dosingDecision.historicalGlucose = samples.filter { $0.startDate >= historicalGlucoseStartDate }.map { HistoricalGlucoseValue(startDate: $0.startDate, quantity: $0.quantity) }
                }
                self.updateGlucoseChartValues()
            }
        }
    }

    private func updateGlucoseChartValues() {
        dispatchPrecondition(condition: .onQueue(.main))

        var chartGlucoseValues = storedGlucoseValues
        if let manualGlucoseSample = manualGlucoseSample {
            chartGlucoseValues.append(manualGlucoseSample.quantitySample)
        }

        self.glucoseValues = chartGlucoseValues
    }

    /// - NOTE: `completion` is invoked on the main queue after predicted glucose values are updated
    private func updatePredictedGlucoseValues(from state: LoopState, completion: @escaping () -> Void = {}) {
        dispatchPrecondition(condition: .notOnQueue(.main))

        let (manualGlucoseSample, enteredBolus, insulinType) = DispatchQueue.main.sync { (self.manualGlucoseSample, self.enteredBolus, delegate?.pumpInsulinType) }
        
        let enteredBolusDose = DoseEntry(type: .bolus, startDate: Date(), value: enteredBolus.doubleValue(for: .internationalUnit()), unit: .units, insulinType: insulinType)

        let predictedGlucoseValues: [PredictedGlucoseValue]
        do {
            log.debug("predicting glucose with enteredDose: %@", enteredBolus)
            if let manualGlucoseEntry = manualGlucoseSample {
                predictedGlucoseValues = try state.predictGlucoseFromManualGlucose(
                    manualGlucoseEntry,
                    potentialBolus: enteredBolusDose,
                    potentialCarbEntry: potentialCarbEntry,
                    replacingCarbEntry: originalCarbEntry,
                    includingPendingInsulin: true
                )
            } else {
                predictedGlucoseValues = try state.predictGlucose(
                    using: .all,
                    potentialBolus: enteredBolusDose,
                    potentialCarbEntry: potentialCarbEntry,
                    replacingCarbEntry: originalCarbEntry,
                    includingPendingInsulin: true
                )
            }
        } catch {
            predictedGlucoseValues = []
        }

        DispatchQueue.main.async {
            self.predictedGlucoseValues = predictedGlucoseValues
            self.dosingDecision.predictedGlucose = predictedGlucoseValues
            completion()
        }
    }

    private func updateActiveInsulin() {
        delegate?.insulinOnBoard(at: Date()) { [weak self] result in
            guard let self = self else { return }

            DispatchQueue.main.async {
                switch result {
                case .success(let iob):
                    self.activeInsulin = HKQuantity(unit: .internationalUnit(), doubleValue: iob.value)
                    self.dosingDecision.insulinOnBoard = iob
                case .failure:
                    self.activeInsulin = nil
                    self.dosingDecision.insulinOnBoard = nil
                }
            }
        }
    }

    private func updatePredictionAndRecommendation(_ completion: @escaping () -> Void) {
        guard let delegate = delegate else {
            completion()
            return
        }
        delegate.withLoopState { [weak self] state in
            self?.updateCarbsOnBoard(from: state)
            DispatchQueue.main.async {
                self?.updateSettings()
            }
            self?.updateRecommendedBolusAndNotice(from: state, isUpdatingFromUserInput: false)
            self?.updatePredictedGlucoseValues(from: state)
            DispatchQueue.main.async {
                completion()
            }
        }
    }

    private func updateCarbsOnBoard(from state: LoopState) {
        delegate?.carbsOnBoard(at: Date(), effectVelocities: state.insulinCounteractionEffects) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let carbValue):
                    self.activeCarbs = carbValue.quantity
                    self.dosingDecision.carbsOnBoard = carbValue
                case .failure:
                    self.activeCarbs = nil
                    self.dosingDecision.carbsOnBoard = nil
                }
            }
        }
    }

    private func updateRecommendedBolusAndNotice(from state: LoopState, isUpdatingFromUserInput: Bool) {
        dispatchPrecondition(condition: .notOnQueue(.main))

        let now = Date()
        var recommendation: ManualBolusRecommendation?
        let recommendedBolus: HKQuantity?
        let notice: Notice?
        do {
            recommendation = try computeBolusRecommendation(from: state)
            if let recommendation = recommendation {
                recommendedBolus = HKQuantity(unit: .internationalUnit(), doubleValue: recommendation.amount)

                switch recommendation.notice {
                case .glucoseBelowSuspendThreshold:
                    if let suspendThreshold = delegate?.settings.suspendThreshold {
                        notice = .predictedGlucoseBelowSuspendThreshold(suspendThreshold: suspendThreshold.quantity)
                    } else {
                        notice = nil
                    }
                case .predictedGlucoseInRange:
                    notice = .predictedGlucoseInRange
                case .allGlucoseBelowTarget(minGlucose: _):
                    notice = .glucoseBelowTarget
                default:
                    notice = nil
                }
            } else {
                recommendedBolus = HKQuantity(unit: .internationalUnit(), doubleValue: 0)
                notice = nil
            }
        } catch {
            recommendedBolus = nil

            switch error {
            case LoopError.missingDataError(.glucose), LoopError.glucoseTooOld:
                notice = .staleGlucoseData
            case LoopError.pumpDataTooOld:
                notice = .stalePumpData
            default:
                notice = nil
            }
        }

        DispatchQueue.main.async {
            let priorRecommendedBolus = self.recommendedBolus
            self.recommendedBolus = recommendedBolus
            self.dosingDecision.manualBolusRecommendation = recommendation.map { ManualBolusRecommendationWithDate(recommendation: $0, date: now) }
            self.activeNotice = notice

            if priorRecommendedBolus != nil,
               priorRecommendedBolus != recommendedBolus,
               !self.isInitiatingSaveOrBolus,
               !isUpdatingFromUserInput
            {
                self.presentAlert(.recommendationChanged)
            }
        }
    }

    private func computeBolusRecommendation(from state: LoopState) throws -> ManualBolusRecommendation? {
        dispatchPrecondition(condition: .notOnQueue(.main))

        log.debug("getting bolus recommendation")

        let manualGlucoseSample = DispatchQueue.main.sync { self.manualGlucoseSample }
        if manualGlucoseSample != nil {
            return try state.recommendBolusForManualGlucose(
                manualGlucoseSample!,
                consideringPotentialCarbEntry: potentialCarbEntry,
                replacingCarbEntry: originalCarbEntry
            )
        } else {
            return try state.recommendBolus(
                consideringPotentialCarbEntry: potentialCarbEntry,
                replacingCarbEntry: originalCarbEntry
            )
        }
    }

    private func updateSettings() {
        dispatchPrecondition(condition: .onQueue(.main))
        
        guard let delegate = delegate else {
            return
        }

        targetGlucoseSchedule = delegate.settings.glucoseTargetRangeSchedule
        // Pre-meal override should be ignored if we have carbs (LOOP-1964)
        preMealOverride = potentialCarbEntry == nil ? delegate.settings.preMealOverride : nil
        scheduleOverride = delegate.settings.scheduleOverride

        if preMealOverride?.hasFinished() == true {
            preMealOverride = nil
        }

        if scheduleOverride?.hasFinished() == true {
            scheduleOverride = nil
        }

        maximumBolus = delegate.settings.maximumBolus.map { maxBolusAmount in
            HKQuantity(unit: .internationalUnit(), doubleValue: maxBolusAmount)
        }

        dosingDecision.scheduleOverride = scheduleOverride

        if scheduleOverride != nil || preMealOverride != nil {
            dosingDecision.glucoseTargetRangeSchedule = delegate.settings.effectiveGlucoseTargetRangeSchedule(presumingMealEntry: potentialCarbEntry != nil)
        } else {
            dosingDecision.glucoseTargetRangeSchedule = targetGlucoseSchedule
        }
    }

    private func updateChartDateInterval() {
        dispatchPrecondition(condition: .onQueue(.main))

        // How far back should we show data? Use the screen size as a guide.
        let viewMarginInset: CGFloat = 14
        let availableWidth = screenWidth - chartManager.fixedHorizontalMargin - 2 * viewMarginInset

        let totalHours = floor(Double(availableWidth / LoopConstants.minimumChartWidthPerHour))
        let futureHours = ceil((delegate?.insulinActivityDuration(for: delegate?.pumpInsulinType) ?? .hours(4)).hours)
        let historyHours = max(LoopConstants.statusChartMinimumHistoryDisplay.hours, totalHours - futureHours)

        let date = Date(timeInterval: -TimeInterval(hours: historyHours), since: now())
        let chartStartDate = Calendar.current.nextDate(
            after: date,
            matching: DateComponents(minute: 0),
            matchingPolicy: .strict,
            direction: .backward
        ) ?? date

        chartDateInterval = DateInterval(start: chartStartDate, duration: .hours(totalHours))
    }
}

extension BolusEntryViewModel.Alert: Identifiable {
    var id: Self { self }
}

// MARK: Helpers
extension BolusEntryViewModel {
    
    var isGlucoseDataStale: Bool {
        guard let latestGlucoseDataDate = delegate?.mostRecentGlucoseDataDate else { return true }
        return now().timeIntervalSince(latestGlucoseDataDate) > LoopCoreConstants.inputDataRecencyInterval
    }
    
    var isPumpDataStale: Bool {
        guard let latestPumpDataDate = delegate?.mostRecentPumpDataDate else { return true }
        return now().timeIntervalSince(latestPumpDataDate) > LoopCoreConstants.inputDataRecencyInterval
    }

    var isManualGlucosePromptVisible: Bool {
        activeNotice == .staleGlucoseData && !isManualGlucoseEntryEnabled
    }
    
    var isNoticeVisible: Bool {
        if activeNotice == nil {
            return false
        } else if activeNotice != .staleGlucoseData {
            return true
        } else {
            return !isManualGlucoseEntryEnabled
        }
    }
    
    private var hasBolusEntryReadyToDeliver: Bool {
        enteredBolus.doubleValue(for: .internationalUnit()) != 0
    }

    private var hasDataToSave: Bool {
        manualGlucoseQuantity != nil || potentialCarbEntry != nil
    }

    enum ButtonChoice { case manualGlucoseEntry, actionButton }
    var primaryButton: ButtonChoice {
        if !isManualGlucosePromptVisible { return .actionButton }
        if hasBolusEntryReadyToDeliver { return .actionButton }
        return .manualGlucoseEntry
    }
    
    enum ActionButtonAction {
        case saveWithoutBolusing
        case saveAndDeliver
        case enterBolus
        case deliver
    }
    
    var actionButtonAction: ActionButtonAction {
        switch (hasDataToSave, hasBolusEntryReadyToDeliver) {
        case (true, true): return .saveAndDeliver
        case (true, false): return .saveWithoutBolusing
        case (false, true): return .deliver
        case (false, false): return .enterBolus
        }
    }
}
