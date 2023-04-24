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
import SwiftCharts

protocol BolusEntryViewModelDelegate: AnyObject {
    
    func withLoopState(do block: @escaping (LoopState) -> Void)

    func saveGlucose(sample: NewGlucoseSample) async -> StoredGlucoseSample?

    func addCarbEntry(_ carbEntry: NewCarbEntry, replacing replacingEntry: StoredCarbEntry? ,
                      completion: @escaping (_ result: Result<StoredCarbEntry>) -> Void)

    func storeManualBolusDosingDecision(_ bolusDosingDecision: BolusDosingDecision, withDate date: Date)
    
    func enactBolus(units: Double, activationType: BolusActivationType, completion: @escaping (_ error: Error?) -> Void)
    
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

    func roundBolusVolume(units: Double) -> Double

    func updateRemoteRecommendation()
}

@MainActor
final class BolusEntryViewModel: ObservableObject {
    enum Alert: Int {
        case recommendationChanged
        case maxBolusExceeded
        case bolusTooSmall
        case noPumpManagerConfigured
        case noMaxBolusConfigured
        case carbEntryPersistenceFailure
        case manualGlucoseEntryOutOfAcceptableRange
        case manualGlucoseEntryPersistenceFailure
        case glucoseNoLongerStale
        case forecastInfo
    }

    enum Notice: Equatable {
        case predictedGlucoseInRange
        case predictedGlucoseBelowSuspendThreshold(suspendThreshold: HKQuantity)
        case glucoseBelowTarget
        case staleGlucoseData
        case futureGlucoseData
        case stalePumpData
    }

    var authenticationHandler: (String) async -> Bool = { message in
        return await withCheckedContinuation { continuation in
            LocalAuthentication.deviceOwnerCheck(message) { result in
                switch result {
                case .success:
                    continuation.resume(returning: true)
                case .failure:
                    continuation.resume(returning: false)
                }
            }
        }
    }

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

    @Published var recommendedBolus: HKQuantity?
    var recommendedBolusAmount: Double? {
        recommendedBolus?.doubleValue(for: .internationalUnit())
    }
    @Published var enteredBolus = HKQuantity(unit: .internationalUnit(), doubleValue: 0)
    var enteredBolusAmount: Double {
        enteredBolus.doubleValue(for: .internationalUnit())
    }
    private var userChangedBolusAmount = false
    @Published var isInitiatingSaveOrBolus = false
    @Published var enacting = false

    private var dosingDecision = BolusDosingDecision(for: .normalBolus)

    @Published var activeAlert: Alert?
    @Published var activeNotice: Notice?

    private let log = OSLog(category: "BolusEntryViewModel")
    private var cancellables: Set<AnyCancellable> = []

    let chartManager: ChartsManager = {
        let predictedGlucoseChart = PredictedGlucoseChart(predictedGlucoseBounds: FeatureFlags.predictedGlucoseChartClampEnabled ? .default : nil,
                                                          yAxisStepSizeMGDLOverride: FeatureFlags.predictedGlucoseChartClampEnabled ? 40 : nil)
        predictedGlucoseChart.glucoseDisplayRange = LoopConstants.glucoseChartDefaultDisplayRangeWide
        return ChartsManager(
            colors: ChartColorPalette.primary,
            settings: ChartSettings.default,
            charts: [predictedGlucoseChart],
            traitCollection: UITraitCollection.current)
    }()

    let glucoseQuantityFormatter = QuantityFormatter()

    @Published var isManualGlucoseEntryEnabled = false
    @Published var manualGlucoseQuantity: HKQuantity?

    var manualGlucoseSample: NewGlucoseSample?

    // MARK: - Seams
    private weak var delegate: BolusEntryViewModelDelegate?
    private let now: () -> Date
    private let screenWidth: CGFloat
    private let debounceIntervalMilliseconds: Int
    private let uuidProvider: () -> String
    private let carbEntryDateFormatter: DateFormatter

    var analyticsServicesManager: AnalyticsServicesManager?
    
    // MARK: - Initialization

    init(
        delegate: BolusEntryViewModelDelegate,
        now: @escaping () -> Date = { Date() },
        screenWidth: CGFloat,
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

        self.updateSettings()
    }

    public func generateRecommendationAndStartObserving() async {
        await update()

        // Only start observing after first update is complete
        self.observeLoopUpdates()
        self.observeElapsedTime()
        self.observeEnteredManualGlucoseChanges()
        self.observeEnteredBolusChanges()

    }

    private func observeLoopUpdates() {
        NotificationCenter.default
            .publisher(for: .LoopDataUpdated)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                Task {
                    if let rawContext = note.userInfo?[LoopDataManager.LoopUpdateContextKey] as? LoopDataManager.LoopUpdateContext.RawValue,
                       let context = LoopDataManager.LoopUpdateContext(rawValue: rawContext),
                       context == .preferences
                    {
                        self?.updateSettings()
                    }
                    await self?.update()
                }
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
            .sink { [weak self] manualGlucoseQuantity in
                guard let self = self else { return }

                // Clear out any entered bolus whenever the glucose entry changes
                self.enteredBolus = HKQuantity(unit: .internationalUnit(), doubleValue: 0)

                self.delegate?.withLoopState { [weak self] state in
                    self?.updatePredictedGlucoseValues(from: state, completion: {
                        // Ensure the manual glucose entry appears on the chart at the same time as the updated prediction
                        self?.updateGlucoseChartValues()
                    })

                    self?.updateRecommendedBolusAndNotice(from: state, isUpdatingFromUserInput: true)
                }

                if let manualGlucoseQuantity = manualGlucoseQuantity {
                    self.manualGlucoseSample = NewGlucoseSample(
                        date: self.now(),
                        quantity: manualGlucoseQuantity,
                        condition: nil,     // All manual glucose entries are assumed to have no condition.
                        trend: nil,         // All manual glucose entries are assumed to have no trend.
                        trendRate: nil,     // All manual glucose entries are assumed to have no trend rate.
                        isDisplayOnly: false,
                        wasUserEntered: true,
                        syncIdentifier: self.uuidProvider()
                    )
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
                Task {
                    await self.update()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - View API

    var isBolusRecommended: Bool {
        guard let recommendedBolusAmount = recommendedBolusAmount else {
            return false
        }

        return recommendedBolusAmount > 0
    }

    func saveCarbEntry(_ entry: NewCarbEntry, replacingEntry: StoredCarbEntry?) async -> StoredCarbEntry? {
        guard let delegate = delegate else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            delegate.addCarbEntry(entry, replacing: replacingEntry) { result in
                switch result {
                case .success(let storedCarbEntry):
                    continuation.resume(returning: storedCarbEntry)
                case .failure(let error):
                    self.log.error("Failed to add carb entry: %{public}@", String(describing: error))
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    // returns true if action succeeded
    func didPressActionButton() async -> Bool {
        enacting = true
        if await saveAndDeliver() {
            return true
        } else {
            enacting = false
            return false
        }
    }

    // returns true if no errors
    func saveAndDeliver() async -> Bool {
        guard delegate?.isPumpConfigured ?? false else {
            presentAlert(.noPumpManagerConfigured)
            return false
        }

        guard let delegate = delegate else {
            assertionFailure("Missing BolusEntryViewModelDelegate")
            return false
        }

        let amountToDeliver = delegate.roundBolusVolume(units: enteredBolusAmount)
        guard enteredBolusAmount == 0 || amountToDeliver > 0 else {
            presentAlert(.bolusTooSmall)
            return false
        }

        let amountToDeliverString = formatBolusAmount(amountToDeliver)

        let manualGlucoseSample = manualGlucoseSample
        let potentialCarbEntry = potentialCarbEntry

        guard let maximumBolus = maximumBolus else {
            presentAlert(.noMaxBolusConfigured)
            return false
        }

        guard amountToDeliver <= maximumBolus.doubleValue(for: .internationalUnit()) else {
            presentAlert(.maxBolusExceeded)
            return false
        }

        if let manualGlucoseSample = manualGlucoseSample {
            guard LoopConstants.validManualGlucoseEntryRange.contains(manualGlucoseSample.quantity) else {
                presentAlert(.manualGlucoseEntryOutOfAcceptableRange)
                return false
            }
        }

        // Authenticate the bolus before saving anything
        if amountToDeliver > 0 {
            let message = String(format: NSLocalizedString("Authenticate to Bolus %@ Units", comment: "The message displayed during a device authentication prompt for bolus specification"), amountToDeliverString)

            if !(await authenticationHandler(message)) {
                return false
            }
        }

        defer {
            delegate.updateRemoteRecommendation()
        }

        if let manualGlucoseSample = manualGlucoseSample {
            if let glucoseValue = await delegate.saveGlucose(sample: manualGlucoseSample) {
                dosingDecision.manualGlucoseSample = glucoseValue
            } else {
                presentAlert(.manualGlucoseEntryPersistenceFailure)
                return false
            }
        } else {
            self.dosingDecision.manualGlucoseSample = nil
        }

        let activationType = BolusActivationType.activationTypeFor(recommendedAmount: recommendedBolus?.doubleValue(for: .internationalUnit()), bolusAmount: amountToDeliver)

        if let carbEntry = potentialCarbEntry {
            if originalCarbEntry == nil {
                let interaction = INInteraction(intent: NewCarbEntryIntent(), response: nil)

                do {
                    try await interaction.donate()
                } catch {
                    log.error("Failed to donate intent: %{public}@", String(describing: error))
                }
            }
            if let storedCarbEntry = await saveCarbEntry(carbEntry, replacingEntry: originalCarbEntry) {
                self.dosingDecision.carbEntry = storedCarbEntry
                self.analyticsServicesManager?.didAddCarbs(source: "Phone", amount: storedCarbEntry.quantity.doubleValue(for: .gram()))
            } else {
                self.presentAlert(.carbEntryPersistenceFailure)
                return false
            }
        }

        dosingDecision.manualBolusRequested = amountToDeliver

        let now = self.now()
        delegate.storeManualBolusDosingDecision(dosingDecision, withDate: now)

        if amountToDeliver > 0 {
            savedPreMealOverride = nil
            delegate.enactBolus(units: amountToDeliver, activationType: activationType, completion: { _ in
                self.analyticsServicesManager?.didBolus(source: "Phone", units: amountToDeliver)
            })
        }
        return true
    }

    private func presentAlert(_ alert: Alert) {
        dispatchPrecondition(condition: .onQueue(.main))

        // As of iOS 13.6 / Xcode 11.6, swapping out an alert while one is active crashes SwiftUI.
        guard activeAlert == nil else {
            return
        }

        activeAlert = alert
    }

    private lazy var bolusAmountFormatter: NumberFormatter = {
        let formatter = QuantityFormatter()
        formatter.setPreferredNumberFormatter(for: .internationalUnit())
        formatter.numberFormatter.roundingMode = .down
        return formatter.numberFormatter
    }()

    private lazy var absorptionTimeFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.collapsesLargestUnit = true
        formatter.unitsStyle = .abbreviated
        formatter.allowsFractionalUnits = true
        formatter.allowedUnits = [.hour, .minute]
        return formatter
    }()

    var enteredBolusAmountString: String {
        let bolusAmount = enteredBolusAmount
        return formatBolusAmount(bolusAmount)
    }

    var maximumBolusAmountString: String? {
        guard let maxBolusAmount = maximumBolus?.doubleValue(for: .internationalUnit()) else {
            return nil
        }
        return formatBolusAmount(maxBolusAmount)
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
    func update() async {
        dispatchPrecondition(condition: .onQueue(.main))

        // Prevent any UI updates after a bolus has been initiated.
        guard !enacting else {
            return
        }

        disableManualGlucoseEntryIfNecessary()
        updateChartDateInterval()
        updateStoredGlucoseValues()
        await updatePredictionAndRecommendation()

        if let iob = await getInsulinOnBoard() {
            self.activeInsulin = HKQuantity(unit: .internationalUnit(), doubleValue: iob.value)
            self.dosingDecision.insulinOnBoard = iob
        } else {
            self.activeInsulin = nil
            self.dosingDecision.insulinOnBoard = nil
        }
    }

    private func disableManualGlucoseEntryIfNecessary() {
        dispatchPrecondition(condition: .onQueue(.main))

        if isManualGlucoseEntryEnabled, !isGlucoseDataStale {
            isManualGlucoseEntryEnabled = false
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
            if let manualGlucoseEntry = manualGlucoseSample {
                predictedGlucoseValues = try state.predictGlucoseFromManualGlucose(
                    manualGlucoseEntry,
                    potentialBolus: enteredBolusDose,
                    potentialCarbEntry: potentialCarbEntry,
                    replacingCarbEntry: originalCarbEntry,
                    includingPendingInsulin: true,
                    considerPositiveVelocityAndRC: true
                )
            } else {
                predictedGlucoseValues = try state.predictGlucose(
                    using: .all,
                    potentialBolus: enteredBolusDose,
                    potentialCarbEntry: potentialCarbEntry,
                    replacingCarbEntry: originalCarbEntry,
                    includingPendingInsulin: true,
                    considerPositiveVelocityAndRC: true
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

    private func getInsulinOnBoard() async -> InsulinValue? {
        guard let delegate = delegate else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            delegate.insulinOnBoard(at: Date()) { result in
                switch result {
                case .success(let iob):
                    continuation.resume(returning: iob)
                case .failure:
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func updatePredictionAndRecommendation() async {
        guard let delegate = delegate else {
            return
        }
        return await withCheckedContinuation { continuation in
            delegate.withLoopState { [weak self] state in
                self?.updateCarbsOnBoard(from: state)
                self?.updateRecommendedBolusAndNotice(from: state, isUpdatingFromUserInput: false)
                self?.updatePredictedGlucoseValues(from: state)
                continuation.resume()
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

        guard let delegate = delegate else {
            assertionFailure("Missing BolusEntryViewModelDelegate")
            return
        }

        let now = Date()
        var recommendation: ManualBolusRecommendation?
        let recommendedBolus: HKQuantity?
        let notice: Notice?
        do {
            recommendation = try computeBolusRecommendation(from: state)

            if let recommendation = recommendation {
                recommendedBolus = HKQuantity(unit: .internationalUnit(), doubleValue: delegate.roundBolusVolume(units: recommendation.amount))
                //recommendedBolus = HKQuantity(unit: .internationalUnit(), doubleValue: recommendation.amount)
                
                switch recommendation.notice {
                case .glucoseBelowSuspendThreshold:
                    if let suspendThreshold = delegate.settings.suspendThreshold {
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
            case LoopError.invalidFutureGlucose:
                notice = .futureGlucoseData
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
               !self.enacting,
               !isUpdatingFromUserInput
            {
                self.presentAlert(.recommendationChanged)
            }
        }
    }

    private func computeBolusRecommendation(from state: LoopState) throws -> ManualBolusRecommendation? {
        dispatchPrecondition(condition: .notOnQueue(.main))

        let manualGlucoseSample = DispatchQueue.main.sync { self.manualGlucoseSample }
        if manualGlucoseSample != nil {
            return try state.recommendBolusForManualGlucose(
                manualGlucoseSample!,
                consideringPotentialCarbEntry: potentialCarbEntry,
                replacingCarbEntry: originalCarbEntry,
                considerPositiveVelocityAndRC: FeatureFlags.usePositiveMomentumAndRCForManualBoluses
            )
        } else {
            return try state.recommendBolus(
                consideringPotentialCarbEntry: potentialCarbEntry,
                replacingCarbEntry: originalCarbEntry,
                considerPositiveVelocityAndRC: FeatureFlags.usePositiveMomentumAndRCForManualBoluses
            )
        }
    }

    func updateSettings() {
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

    func formatBolusAmount(_ bolusAmount: Double) -> String {
        bolusAmountFormatter.string(from: bolusAmount) ?? String(bolusAmount)
    }

    var recommendedBolusString: String {
        guard let amount = recommendedBolusAmount else {
            return "–"
        }
        return formatBolusAmount(amount)
    }

    func updateEnteredBolus(_ enteredBolusString: String) {
        updateEnteredBolus(bolusAmountFormatter.number(from: enteredBolusString)?.doubleValue)
    }

    func updateEnteredBolus(_ enteredBolusAmount: Double?) {
        enteredBolus = HKQuantity(unit: .internationalUnit(), doubleValue: enteredBolusAmount ?? 0)
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
