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

enum ManualEntryDoseViewModelError: Error {
    case notAuthenticated
}

protocol ManualDoseViewModelDelegate: AnyObject {
    var algorithmDisplayState: AlgorithmDisplayState { get async }
    var pumpInsulinType: InsulinType? { get }
    var settings: StoredSettings { get }
    var scheduleOverride: TemporaryScheduleOverride? { get }

    func addManuallyEnteredDose(startDate: Date, units: Double, insulinType: InsulinType?) async
    func insulinActivityDuration(for type: InsulinType?) -> TimeInterval
}

@MainActor
final class ManualEntryDoseViewModel: ObservableObject {
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


    // MARK: - Initialization

    init(
        delegate: ManualDoseViewModelDelegate,
        now: @escaping () -> Date = { Date() },
        debounceIntervalMilliseconds: Int = 400,
        uuidProvider: @escaping () -> String = { UUID().uuidString },
        timeZone: TimeZone? = nil
    ) {
        self.delegate = delegate
        self.now = now
        self.screenWidth = UIScreen.main.bounds.width
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
                self?.updateTriggered()
            }
            .store(in: &cancellables)
    }

    private func observeInsulinModelChanges() {
        $selectedInsulinType
            .removeDuplicates()
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateTriggered()
            }
            .store(in: &cancellables)
    }
    
    private func observeDoseDateChanges() {
        $selectedDoseDate
            .removeDuplicates()
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateTriggered()
            }
            .store(in: &cancellables)
    }

    private func updateTriggered() {
        Task { @MainActor in
            await updateFromLoopState()
        }
    }


    // MARK: - View API

    func saveManualDose() async throws {
        guard enteredBolus.doubleValue(for: .internationalUnit()) > 0 else {
            return
        }

        // Authenticate before saving anything
        let message = String(format: NSLocalizedString("Authenticate to log %@ Units", comment: "The message displayed during a device authentication prompt to log an insulin dose"), enteredBolusAmountString)

        if !(await authenticationHandler(message)) {
            throw ManualEntryDoseViewModelError.notAuthenticated
        }
        await self.continueSaving()
    }
    
    private func continueSaving() async {
        let doseVolume = enteredBolus.doubleValue(for: .internationalUnit())
        guard doseVolume > 0 else {
            return
        }

        await delegate?.addManuallyEnteredDose(startDate: selectedDoseDate, units: doseVolume, insulinType: selectedInsulinType)
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

        // Prevent any UI updates after a bolus has been initiated.
        guard !isInitiatingSaveOrBolus else { return }

        updateChartDateInterval()
        Task {
            await updateFromLoopState()
        }
    }

    private func updateFromLoopState() async {
        guard let delegate = delegate else {
            return
        }

        let state = await delegate.algorithmDisplayState

        let enteredBolusDose = DoseEntry(type: .bolus, startDate: selectedDoseDate, value: enteredBolus.doubleValue(for: .internationalUnit()), unit: .units, insulinType: selectedInsulinType)

        self.activeInsulin = state.activeInsulin?.quantity
        self.activeCarbs = state.activeCarbs?.quantity


        if let input = state.input {
            self.storedGlucoseValues = input.glucoseHistory

            do {
                predictedGlucoseValues = try input
                    .addingDose(dose: enteredBolusDose)
                    .predictGlucose()
            } catch {
                predictedGlucoseValues = []
            }
        } else {
            predictedGlucoseValues = []
        }

        updateSettings()
    }

    private func updateSettings() {
        guard let delegate else {
            return
        }

        targetGlucoseSchedule = delegate.settings.glucoseTargetRangeSchedule
        scheduleOverride = delegate.scheduleOverride

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
