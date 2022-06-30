//
//  ManualEntryDoseViewModel.swift
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

protocol ManualDoseViewModelDelegate: AnyObject {
    
    func withLoopState(do block: @escaping (LoopState) -> Void)

    func addManuallyEnteredDose(startDate: Date, units: Double, insulinType: InsulinType?)

    func getGlucoseSamples(start: Date?, end: Date?, completion: @escaping (_ samples: Swift.Result<[StoredGlucoseSample], Error>) -> Void)

    func insulinOnBoard(at date: Date, completion: @escaping (_ result: DoseStoreResult<InsulinValue>) -> Void)
    
    func carbsOnBoard(at date: Date, effectVelocities: [GlucoseEffectVelocity]?, completion: @escaping (_ result: CarbStoreResult<CarbValue>) -> Void)
    
    func insulinActivityDuration(for type: InsulinType?) -> TimeInterval

    var mostRecentGlucoseDataDate: Date? { get }
    
    var mostRecentPumpDataDate: Date? { get }
    
    var isPumpConfigured: Bool { get }
    
    var preferredGlucoseUnit: HKUnit { get }
    
    var pumpInsulinType: InsulinType? { get }

    var settings: LoopSettings { get }
}

final class ManualEntryDoseViewModel: ObservableObject {

    var authenticate: AuthenticationChallenge = LocalAuthentication.deviceOwnerCheck

    // MARK: - State

    @Published var glucoseValues: [GlucoseValue] = [] // stored glucose values
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

    @Published var enteredBolus = HKQuantity(unit: .internationalUnit(), doubleValue: 0)
    private var isInitiatingSaveOrBolus = false

    private let log = OSLog(category: "ManualEntryDoseViewModel")
    private var cancellables: Set<AnyCancellable> = []

    let chartManager: ChartsManager = {
        let predictedGlucoseChart = PredictedGlucoseChart(predictedGlucoseBounds: FeatureFlags.predictedGlucoseChartClampEnabled ? .default : nil,
                                                          yAxisStepSizeMGDLOverride: FeatureFlags.predictedGlucoseChartClampEnabled ? 40 : nil)
        predictedGlucoseChart.glucoseDisplayRange = LoopConstants.glucoseChartDefaultDisplayRangeWide
        return ChartsManager(colors: .primary, settings: .default, charts: [predictedGlucoseChart], traitCollection: .current)
    }()
    
    // MARK: - External Insulin
    @Published var selectedInsulinType: InsulinType
    
    @Published var selectedDoseDate: Date = Date()
    
    var insulinTypePickerOptions: [InsulinType]
    
    // MARK: - Seams
    private weak var delegate: ManualDoseViewModelDelegate?
    private let now: () -> Date
    private let screenWidth: CGFloat
    private let debounceIntervalMilliseconds: Int
    private let uuidProvider: () -> String
    
    // MARK: - Initialization

    init(
        delegate: ManualDoseViewModelDelegate,
        now: @escaping () -> Date = { Date() },
        screenWidth: CGFloat = UIScreen.main.bounds.width,
        debounceIntervalMilliseconds: Int = 400,
        uuidProvider: @escaping () -> String = { UUID().uuidString },
        timeZone: TimeZone? = nil
    ) {
        self.delegate = delegate
        self.now = now
        self.screenWidth = screenWidth
        self.debounceIntervalMilliseconds = debounceIntervalMilliseconds
        self.uuidProvider = uuidProvider
        
        self.insulinTypePickerOptions = [.novolog, .humalog, .apidra, .fiasp, .lyumjev, .afrezza]
        
        self.chartDateInterval = DateInterval(start: Date(timeInterval: .hours(-1), since: now()), duration: .hours(7))

        if let pumpInsulinType = delegate.pumpInsulinType {
            selectedInsulinType = pumpInsulinType
        } else {
            selectedInsulinType = .novolog
        }

        observeLoopUpdates()
        observeEnteredBolusChanges()
        observeInsulinModelChanges()
        observeDoseDateChanges()

        update()
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
        $selectedInsulinType
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

    func saveManualDose(onSuccess completion: @escaping () -> Void) {
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

        delegate?.addManuallyEnteredDose(startDate: selectedDoseDate, units: doseVolume, insulinType: selectedInsulinType)
        completion()
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

        self.glucoseValues = storedGlucoseValues
    }

    /// - NOTE: `completion` is invoked on the main queue after predicted glucose values are updated
    private func updatePredictedGlucoseValues(from state: LoopState, completion: @escaping () -> Void = {}) {
        dispatchPrecondition(condition: .notOnQueue(.main))

        let (enteredBolus, doseDate, insulinType) = DispatchQueue.main.sync { (self.enteredBolus, self.selectedDoseDate, self.selectedInsulinType) }
        
        let enteredBolusDose = DoseEntry(type: .bolus, startDate: doseDate, value: enteredBolus.doubleValue(for: .internationalUnit()), unit: .units, insulinType: insulinType)

        let predictedGlucoseValues: [PredictedGlucoseValue]
        do {
            predictedGlucoseValues = try state.predictGlucose(
                using: .all,
                potentialBolus: enteredBolusDose,
                potentialCarbEntry: nil,
                replacingCarbEntry: nil,
                includingPendingInsulin: true,
                considerPositiveVelocityAndRC: true
            )
        } catch {
            predictedGlucoseValues = []
        }

        DispatchQueue.main.async {
            self.predictedGlucoseValues = predictedGlucoseValues
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
                case .failure:
                    self.activeInsulin = nil
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
                case .failure:
                    self.activeCarbs = nil
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
        scheduleOverride = delegate.settings.scheduleOverride

        if preMealOverride?.hasFinished() == true {
            preMealOverride = nil
        }

        if scheduleOverride?.hasFinished() == true {
            scheduleOverride = nil
        }
    }

    private func updateChartDateInterval() {
        dispatchPrecondition(condition: .onQueue(.main))

        // How far back should we show data? Use the screen size as a guide.
        let viewMarginInset: CGFloat = 14
        let availableWidth = screenWidth - chartManager.fixedHorizontalMargin - 2 * viewMarginInset

        let totalHours = floor(Double(availableWidth / LoopConstants.minimumChartWidthPerHour))
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
