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
import LoopKit
import LoopKitUI
import LoopUI
import SwiftUI


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
        case predictedGlucoseBelowSuspendThreshold(suspendThreshold: HKQuantity)
        case staleGlucoseData
    }

    // MARK: - State

    @Published var glucoseValues: [GlucoseValue] = [] // stored glucose values + manual glucose entry
    private var storedGlucoseValues: [GlucoseValue] = []
    @Published var predictedGlucoseValues: [GlucoseValue] = []
    @Published var glucoseUnit: HKUnit = .milligramsPerDeciliter
    @Published var chartDateInterval = DateInterval(start: Date(timeIntervalSinceNow: .hours(-1)), duration: .hours(7))

    @Published var activeCarbs: HKQuantity?
    @Published var activeInsulin: HKQuantity?

    @Published var targetGlucoseSchedule: GlucoseRangeSchedule?
    @Published var preMealOverride: TemporaryScheduleOverride?
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

    @Published var activeAlert: Alert?
    @Published var activeNotice: Notice?

    private let dataManager: DeviceDataManager
    private let log = OSLog(category: "BolusEntryViewModel")
    private var cancellables: Set<AnyCancellable> = []

    let chartManager: ChartsManager = {
        let predictedGlucoseChart = PredictedGlucoseChart()
        predictedGlucoseChart.glucoseDisplayRange = BolusEntryViewModel.defaultGlucoseDisplayRange
        return ChartsManager(colors: .default, settings: .default, charts: [predictedGlucoseChart], traitCollection: .current)
    }()
    
    // MARK: - External Insulin
    var selectedInsulinModelIndex: Int = 0
    @State var doseDate: Date = Date()
    
    var insulinModelPickerOptions: [String]
    var isLoggingDose: Bool {
        return insulinModelPickerOptions.count > 0
    }
    
    static let presetFromTitle: [String: ExponentialInsulinModelPreset] = [
        InsulinModelSettings.exponentialPreset(.humalogNovologAdult).title: .humalogNovologAdult,
        InsulinModelSettings.exponentialPreset(.humalogNovologChild).title: .humalogNovologChild,
        InsulinModelSettings.exponentialPreset(.fiasp).title: .fiasp
    ]

    // MARK: - Constants

    static let defaultGlucoseDisplayRange = HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 60)...HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 200)

    static let validManualGlucoseEntryRange = HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 10)...HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 600)

    // MARK: - Initialization

    init(
        dataManager: DeviceDataManager,
        originalCarbEntry: StoredCarbEntry? = nil,
        potentialCarbEntry: NewCarbEntry? = nil,
        selectedCarbAbsorptionTimeEmoji: String? = nil,
        supportedInsulinModels: SupportedInsulinModelSettings? = nil
    ) {
        self.dataManager = dataManager
        self.originalCarbEntry = originalCarbEntry
        self.potentialCarbEntry = potentialCarbEntry
        self.selectedCarbAbsorptionTimeEmoji = selectedCarbAbsorptionTimeEmoji
        self.insulinModelPickerOptions = []

        findInsulinModelPickerOptions(supportedInsulinModels)
        observeLoopUpdates()
        observeEnteredBolusChanges()
        observeEnteredManualGlucoseChanges()
        observeElapsedTime()

        update()
    }
    
    private func findInsulinModelPickerOptions(_ allowedModels: SupportedInsulinModelSettings?) {
        guard let allowedModels = allowedModels else {
            return
        }
        
        insulinModelPickerOptions.append(InsulinModelSettings.exponentialPreset(.humalogNovologAdult).title)
        insulinModelPickerOptions.append(InsulinModelSettings.exponentialPreset(.humalogNovologChild).title)
        
        if allowedModels.fiaspModelEnabled {
            insulinModelPickerOptions.append(InsulinModelSettings.exponentialPreset(.fiasp).title)
        }
        
        // ANNA TODO: not including Walsh for now in the UI (or potentially ever)
    }

    private func observeLoopUpdates() {
        NotificationCenter.default
            .publisher(for: .LoopDataUpdated, object: dataManager.loopManager)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.update() }
            .store(in: &cancellables)
    }

    private func observeEnteredBolusChanges() {
        $enteredBolus
            .removeDuplicates()
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.dataManager.loopManager.getLoopState { manager, state in
                    self?.updatePredictedGlucoseValues(from: state)
                }
            }
            .store(in: &cancellables)
    }

    private func observeEnteredManualGlucoseChanges() {
        $enteredManualGlucose
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { [weak self] enteredManualGlucose in
                self?.updateManualGlucoseSample()

                // Clear out any entered bolus whenever the manual entry changes
                self?.enteredBolus = HKQuantity(unit: .internationalUnit(), doubleValue: 0)

                self?.dataManager.loopManager.getLoopState { manager, state in
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
                self?.log.default("5 minutes elapsed on bolus screen; refreshing UI")

                // Update the manual glucose sample's timestamp, which should always be "now"
                self?.updateManualGlucoseSample()
                self?.update()
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

    func acceptRecommendedBolus() {
        guard isBolusRecommended else { return }
        enteredBolus = recommendedBolus!

        dataManager.loopManager.getLoopState { [weak self] manager, state in
            self?.updatePredictedGlucoseValues(from: state)
        }
    }

    func saveAndDeliver(onSuccess completion: @escaping () -> Void) {
        guard dataManager.pumpManager != nil else {
            presentAlert(.noPumpManagerConfigured)
            return
        }

        guard let maximumBolus = maximumBolus else {
            presentAlert(.noMaxBolusConfigured)
            return
        }

        guard enteredBolus < maximumBolus else {
            presentAlert(.maxBolusExceeded)
            return
        }

        if let manualGlucoseSample = manualGlucoseSample {
            guard Self.validManualGlucoseEntryRange.contains(manualGlucoseSample.quantity) else {
                presentAlert(.manualGlucoseEntryOutOfAcceptableRange)
                return
            }

            isInitiatingSaveOrBolus = true
            dataManager.loopManager.addGlucose([manualGlucoseSample]) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success:
                        self.saveCarbsAndDeliverBolus(onSuccess: completion)
                    case .failure(let error):
                        self.isInitiatingSaveOrBolus = false
                        self.presentAlert(.manualGlucoseEntryPersistenceFailure)
                        self.log.error("Failed to add manual glucose entry: %{public}@", String(describing: error))
                    }
                }
            }
        } else {
            saveCarbsAndDeliverBolus(onSuccess: completion)
        }
    }

    private func saveCarbsAndDeliverBolus(onSuccess completion: @escaping () -> Void) {
        guard let carbEntry = potentialCarbEntry else {
            authenticateAndDeliverBolus(onSuccess: completion)
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
        dataManager.loopManager.addCarbEntry(carbEntry, replacing: originalCarbEntry) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self.authenticateAndDeliverBolus(onSuccess: completion)
                case .failure(let error):
                    self.isInitiatingSaveOrBolus = false
                    self.presentAlert(.carbEntryPersistenceFailure)
                    self.log.error("Failed to add carb entry: %{public}@", String(describing: error))
                }
            }
        }
    }

    private func authenticateAndDeliverBolus(onSuccess completion: @escaping () -> Void) {
        let bolusVolume = enteredBolus.doubleValue(for: .internationalUnit())
        guard bolusVolume > 0 else {
            completion()
            return
        }

        isInitiatingSaveOrBolus = true

        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else {
            dataManager.enactBolus(units: bolusVolume)
            completion()
            return
        }

        context.evaluatePolicy(
            .deviceOwnerAuthentication,
            localizedReason: String(format: NSLocalizedString("Authenticate to Bolus %@ Units", comment: "The message displayed during a device authentication prompt for bolus specification"), enteredBolusAmountString),
            reply: { success, error in
                DispatchQueue.main.async {
                    if success {
                        self.dataManager.enactBolus(units: bolusVolume)
                        completion()
                    } else {
                        self.isInitiatingSaveOrBolus = false
                    }
                }
            }
        )
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

        let entryTimeString = DateFormatter.localizedString(from: potentialCarbEntry.startDate, dateStyle: .none, timeStyle: .short)

        if let absorptionTime = potentialCarbEntry.absorptionTime, let absorptionTimeString = absorptionTimeFormatter.string(from: absorptionTime) {
            return String(format: NSLocalizedString("%1$@ + %2$@", comment: "Format string combining carb entry time and absorption time"), entryTimeString, absorptionTimeString)
        } else {
            return entryTimeString
        }
    }

    // MARK: - Data upkeep

    private func updateManualGlucoseSample(enteredAt entryDate: Date = Date()) {
        dispatchPrecondition(condition: .onQueue(.main))

        manualGlucoseSample = enteredManualGlucose.map { quantity in
            NewGlucoseSample(
                date: entryDate,
                quantity: quantity,
                isDisplayOnly: false,
                wasUserEntered: true,
                syncIdentifier: UUID().uuidString
            )
        }
    }

    private func update() {
        dispatchPrecondition(condition: .onQueue(.main))

        // Prevent any UI updates after a bolus has been initiated.
        guard !isInitiatingSaveOrBolus else { return }

        disableManualGlucoseEntryIfNecessary()
        updateChartDateInterval()
        updateStoredGlucoseValues()
        updateFromLoopState()
        updateActiveInsulin()
    }

    private func disableManualGlucoseEntryIfNecessary() {
        dispatchPrecondition(condition: .onQueue(.main))

        if isManualGlucoseEntryEnabled,
            let latestGlucose = dataManager.loopManager.glucoseStore.latestGlucose,
            Date().timeIntervalSince(latestGlucose.startDate) <= dataManager.loopManager.settings.inputDataRecencyInterval
        {
            isManualGlucoseEntryEnabled = false
            enteredManualGlucose = nil
            manualGlucoseSample = nil
            presentAlert(.glucoseNoLongerStale)
        }
    }

    private func updateStoredGlucoseValues() {
        dataManager.loopManager.glucoseStore.getCachedGlucoseSamples(start: chartDateInterval.start) { [weak self] values in
            DispatchQueue.main.async {
                self?.storedGlucoseValues = values
                self?.updateGlucoseChartValues()
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

        let (manualGlucoseSample, enteredBolus) = DispatchQueue.main.sync { (self.manualGlucoseSample, self.enteredBolus) }
        let enteredBolusDose = DoseEntry(type: .bolus, startDate: Date(), value: enteredBolus.doubleValue(for: .internationalUnit()), unit: .units)

        let predictedGlucoseValues: [GlucoseValue]
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
            completion()
        }
    }

    private func updateActiveInsulin() {
        dataManager.loopManager.doseStore.insulinOnBoard(at: Date()) { [weak self] result in
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
        dataManager.loopManager.getLoopState { [weak self] manager, state in
            guard let self = self else { return }

            self.updatePredictedGlucoseValues(from: state)
            self.updateCarbsOnBoard(from: state)
            self.updateRecommendedBolusAndNotice(from: state, isUpdatingFromUserInput: false)
            DispatchQueue.main.async {
                self.updateSettings()
            }
        }
    }

    private func updateCarbsOnBoard(from state: LoopState) {
        dataManager.loopManager.carbStore.carbsOnBoard(at: Date(), effectVelocities: state.insulinCounteractionEffects) { result in
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

    private func updateRecommendedBolusAndNotice(from state: LoopState, isUpdatingFromUserInput: Bool) {
        dispatchPrecondition(condition: .notOnQueue(.main))

        let recommendedBolus: HKQuantity
        let notice: Notice?
        do {
            if let recommendation = try computeBolusRecommendation(from: state) {
                recommendedBolus = HKQuantity(unit: .internationalUnit(), doubleValue: recommendation.amount)

                switch recommendation.notice {
                case .glucoseBelowSuspendThreshold:
                    let suspendThreshold = dataManager.loopManager.settings.suspendThreshold
                    notice = .predictedGlucoseBelowSuspendThreshold(suspendThreshold: suspendThreshold!.quantity)
                default:
                    notice = nil
                }
            } else {
                recommendedBolus = HKQuantity(unit: .internationalUnit(), doubleValue: 0)
                notice = nil
            }
        } catch {
            recommendedBolus = HKQuantity(unit: .internationalUnit(), doubleValue: 0)

            switch error {
            case LoopError.missingDataError(.glucose), LoopError.glucoseTooOld:
                notice = .staleGlucoseData
            default:
                notice = nil
            }
        }

        DispatchQueue.main.async {
            let priorRecommendedBolus = self.recommendedBolus
            self.recommendedBolus = recommendedBolus
            self.activeNotice = notice

            if priorRecommendedBolus != recommendedBolus,
                self.enteredBolus.doubleValue(for: .internationalUnit()) > 0,
                !self.isInitiatingSaveOrBolus
            {
                self.enteredBolus = HKQuantity(unit: .internationalUnit(), doubleValue: 0)

                if !isUpdatingFromUserInput {
                    self.presentAlert(.recommendationChanged)
                }
            }
        }
    }

    private func computeBolusRecommendation(from state: LoopState) throws -> BolusRecommendation? {
        dispatchPrecondition(condition: .notOnQueue(.main))

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

        let settings = dataManager.loopManager.settings
        glucoseUnit = settings.glucoseUnit ?? dataManager.loopManager.glucoseStore.preferredUnit ?? .milligramsPerDeciliter

        targetGlucoseSchedule = settings.glucoseTargetRangeSchedule
        preMealOverride = settings.preMealOverride
        scheduleOverride = settings.scheduleOverride

        if preMealOverride?.hasFinished() == true {
            preMealOverride = nil
        }

        if scheduleOverride?.hasFinished() == true {
            scheduleOverride = nil
        }

        maximumBolus = settings.maximumBolus.map { maxBolusAmount in
            HKQuantity(unit: .internationalUnit(), doubleValue: maxBolusAmount)
        }
    }

    private func updateChartDateInterval() {
        dispatchPrecondition(condition: .onQueue(.main))

        let settings = dataManager.loopManager.settings

        // How far back should we show data? Use the screen size as a guide.
        let screenWidth = UIScreen.main.bounds.width
        let viewMarginInset: CGFloat = 14
        let availableWidth = screenWidth - chartManager.fixedHorizontalMargin - 2 * viewMarginInset

        let totalHours = floor(Double(availableWidth / settings.minimumChartWidthPerHour))
        let futureHours = ceil((dataManager.loopManager.insulinModelSettings?.model.effectDuration ?? .hours(4)).hours)
        let historyHours = max(settings.statusChartMinimumHistoryDisplay.hours, totalHours - futureHours)

        let date = Date(timeIntervalSinceNow: -TimeInterval(hours: historyHours))
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
