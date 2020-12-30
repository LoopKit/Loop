//
//  LoggedDoseViewModel.swift
//  Loop
//
//  Created by Pete Schwamb on 12/29/20.
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

protocol LoggedDoseViewModelDelegate: class {
    
    func withLoopState(do block: @escaping (LoopState) -> Void)

    func addGlucoseSamples(_ samples: [NewGlucoseSample], completion: ((_ result: Swift.Result<[StoredGlucoseSample], Error>) -> Void)?)
    
    func addCarbEntry(_ carbEntry: NewCarbEntry, replacing replacingEntry: StoredCarbEntry? ,
                      completion: @escaping (_ result: Result<StoredCarbEntry>) -> Void)

    func storeBolusDosingDecision(_ bolusDosingDecision: BolusDosingDecision, withDate date: Date)
    
    func enactBolus(units: Double, at startDate: Date, completion: @escaping (_ error: Error?) -> Void)
    
    func logOutsideInsulinDose(startDate: Date, units: Double, insulinType: InsulinType?)

    func getGlucoseSamples(start: Date?, end: Date?, completion: @escaping (_ samples: Swift.Result<[StoredGlucoseSample], Error>) -> Void)

    func insulinOnBoard(at date: Date, completion: @escaping (_ result: DoseStoreResult<InsulinValue>) -> Void)
    
    func carbsOnBoard(at date: Date, effectVelocities: [GlucoseEffectVelocity]?, completion: @escaping (_ result: CarbStoreResult<CarbValue>) -> Void)
    
    func ensureCurrentPumpData(completion: @escaping () -> Void)
    
    func insulinActivityDuration(for type: InsulinType?) -> TimeInterval

    var mostRecentGlucoseDataDate: Date? { get }
    
    var mostRecentPumpDataDate: Date? { get }
    
    var isPumpConfigured: Bool { get }
    
    var preferredGlucoseUnit: HKUnit { get }
    
    var pumpInsulinType: InsulinType? { get }


    var settings: LoopSettings { get }
}

final class LoggedDoseViewModel: ObservableObject {
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
        case predictedGlucoseBelowSuspendThreshold(suspendThreshold: HKQuantity)
        case staleGlucoseData
        case stalePumpData
    }

    var authenticate: AuthenticationChallenge = LocalAuthentication.deviceOwnerCheck

    // MARK: - State

    @Published var glucoseValues: [GlucoseValue] = [] // stored glucose values + manual glucose entry
    private var storedGlucoseValues: [GlucoseValue] = []
    @Published var predictedGlucoseValues: [GlucoseValue] = []
    @Published var glucoseUnit: HKUnit = .milligramsPerDeciliter
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
    @Published var enteredManualGlucose: HKQuantity?
    private var manualGlucoseSample: NewGlucoseSample? // derived from `enteredManualGlucose`, but stored to ensure timestamp consistency

    @Published var recommendedBolus: HKQuantity?
    @Published var enteredBolus = HKQuantity(unit: .internationalUnit(), doubleValue: 0)
    private var isInitiatingSaveOrBolus = false

    private var dosingDecision = BolusDosingDecision()

    @Published var activeAlert: Alert?
    @Published var activeNotice: Notice?

    private let log = OSLog(category: "BolusEntryViewModel")
    private var cancellables: Set<AnyCancellable> = []

    @Published var isRefreshingPump: Bool = false
    
    let chartManager: ChartsManager = {
        let predictedGlucoseChart = PredictedGlucoseChart(predictedGlucoseBounds: FeatureFlags.predictedGlucoseChartClampEnabled ? .default : nil,
                                                          yAxisStepSizeMGDLOverride: FeatureFlags.predictedGlucoseChartClampEnabled ? 40 : nil)
        predictedGlucoseChart.glucoseDisplayRange = LoopConstants.glucoseChartDefaultDisplayRangeWide
        return ChartsManager(colors: .primary, settings: .default, charts: [predictedGlucoseChart], traitCollection: .current)
    }()
    
    // MARK: - External Insulin
    @Published var selectedInsulinTypeIndex: Int = 0
    
    var selectedInsulinType: InsulinType? {
        return insulinTypePickerOptions[selectedInsulinTypeIndex]
    }
    @Published var selectedDoseDate: Date = Date()
    
    var insulinTypePickerOptions: [InsulinType]
    
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
        isManualGlucoseEntryEnabled: Bool = false,
        supportedInsulinModels: SupportedInsulinModelSettings? = nil
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
        
        self.insulinTypePickerOptions = [.aspart, .lispro, .glulisine]
        if let allowedModels = supportedInsulinModels, allowedModels.fiaspModelEnabled {
            insulinTypePickerOptions.append(.fiasp)
        }
        
        self.isManualGlucoseEntryEnabled = isManualGlucoseEntryEnabled
        
        self.chartDateInterval = DateInterval(start: Date(timeInterval: .hours(-1), since: now()), duration: .hours(7))
        
        self.dosingDecision.originalCarbEntry = originalCarbEntry

        selectedInsulinTypeIndex = startingPickerIndex
        
        observeLoopUpdates()
        observeEnteredBolusChanges()
        observeInsulinModelChanges()
        observeDoseDateChanges()

        update()
    }
        
    var startingPickerIndex: Int {
        if let pumpInsulinType = delegate?.pumpInsulinType {
            if let indexToStartOn = insulinTypePickerOptions.firstIndex(of: pumpInsulinType) {
                return indexToStartOn
            }
        }
        
        return 0
    }

    private func observeLoopUpdates() {
        NotificationCenter.default
            .publisher(for: .LoopDataUpdated)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.update() }
            .store(in: &cancellables)
    }

    private func observeEnteredBolusChanges() {
        $enteredBolus
            .removeDuplicates()
            .debounce(for: .milliseconds(debounceIntervalMilliseconds), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.delegate?.withLoopState { [weak self] state in
                    self?.updatePredictedGlucoseValues(from: state)
                }
            }
            .store(in: &cancellables)
    }

    private func observeInsulinModelChanges() {
        $selectedInsulinTypeIndex
            .removeDuplicates()
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.delegate?.withLoopState { [weak self] state in
                    self?.updatePredictedGlucoseValues(from: state)
                }
            }
            .store(in: &cancellables)
    }
    
    private func observeDoseDateChanges() {
        $selectedDoseDate
            .removeDuplicates()
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.delegate?.withLoopState { [weak self] state in
                    self?.updatePredictedGlucoseValues(from: state)
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - View API

    func logDose(onSuccess completion: @escaping () -> Void) {
        // Authenticate before saving anything
        if enteredBolus.doubleValue(for: .internationalUnit()) > 0 {
            let message = String(format: NSLocalizedString("Authenticate to log %@ Units", comment: "The message displayed during a device authentication prompt to log an insulin dose"), enteredBolusAmountString)
            authenticate(message) {
                switch $0 {
                case .success:
                    self.continueSaving(onSuccess: completion)
                case .failure:
                    break
                }
            }
        } else {
            completion()
        }
    }
    
    private func continueSaving(onSuccess completion: @escaping () -> Void) {
        let doseVolume = enteredBolus.doubleValue(for: .internationalUnit())
        guard doseVolume > 0 else {
            completion()
            return
        }

        delegate?.logOutsideInsulinDose(startDate: selectedDoseDate, units: doseVolume, insulinType: selectedInsulinType)
        completion()
    }

    private func deliverBolus(onSuccess completion: @escaping () -> Void) {
        let now = self.now()
        let bolusVolume = enteredBolus.doubleValue(for: .internationalUnit())

        dosingDecision.requestedBolus = bolusVolume
        delegate?.storeBolusDosingDecision(dosingDecision, withDate: now)

        guard bolusVolume > 0 else {
            completion()
            return
        }

        isInitiatingSaveOrBolus = true
        savedPreMealOverride = nil
        // TODO: should we pass along completion or not???
        delegate?.enactBolus(units: bolusVolume, at: now, completion: { _ in })
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

    private func update() {
        dispatchPrecondition(condition: .onQueue(.main))

        // Prevent any UI updates after a bolus has been initiated.
        guard !isInitiatingSaveOrBolus else { return }

        updateChartDateInterval()
        updateStoredGlucoseValues()
        updateFromLoopState()
        updateActiveInsulin()
    }

    private func updateStoredGlucoseValues() {
        delegate?.getGlucoseSamples(start: chartDateInterval.start, end: nil) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .failure(let error):
                    self.log.error("Failure getting glucose samples: %{public}@", String(describing: error))
                    self.storedGlucoseValues = []
                case .success(let samples):
                    self.storedGlucoseValues = samples
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

        let (manualGlucoseSample, enteredBolus, doseDate, insulinType) = DispatchQueue.main.sync { (self.manualGlucoseSample, self.enteredBolus, self.selectedDoseDate, self.selectedInsulinType) }
        
        let enteredBolusDose = DoseEntry(type: .bolus, startDate: doseDate, value: enteredBolus.doubleValue(for: .internationalUnit()), unit: .units, insulinType: insulinType)

        let predictedGlucoseValues: [PredictedGlucoseValue]
        do {
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
            self.dosingDecision.predictedGlucoseIncludingPendingInsulin = predictedGlucoseValues
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

    private func updateFromLoopState() {
        delegate?.withLoopState { [weak self] state in
            self?.updatePredictedGlucoseValues(from: state)
            self?.updateCarbsOnBoard(from: state)
            DispatchQueue.main.async {
                self?.updateSettings()
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
    

    private func updateSettings() {
        dispatchPrecondition(condition: .onQueue(.main))
        
        guard let delegate = delegate else {
            return
        }

        glucoseUnit = delegate.preferredGlucoseUnit

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

        dosingDecision.scheduleOverride = preMealOverride ?? scheduleOverride
        dosingDecision.glucoseTargetRangeSchedule = targetGlucoseSchedule
        if scheduleOverride != nil || preMealOverride != nil {
            dosingDecision.effectiveGlucoseTargetRangeSchedule = delegate.settings.effectiveGlucoseTargetRangeSchedule(presumingMealEntry: potentialCarbEntry != nil)
        } else {
            dosingDecision.effectiveGlucoseTargetRangeSchedule = nil
        }
    }

    private func updateChartDateInterval() {
        dispatchPrecondition(condition: .onQueue(.main))

        // How far back should we show data? Use the screen size as a guide.
        let viewMarginInset: CGFloat = 14
        let availableWidth = screenWidth - chartManager.fixedHorizontalMargin - 2 * viewMarginInset

        let totalHours = floor(Double(availableWidth / LoopConstants.minimumChartWidthPerHour))
        let selectedInsulinType = insulinTypePickerOptions[selectedInsulinTypeIndex]
        let futureHours = ceil((delegate?.insulinActivityDuration(for: selectedInsulinType) ?? .hours(4)).hours)
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
