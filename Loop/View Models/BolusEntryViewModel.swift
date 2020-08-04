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


final class BolusEntryViewModel: ObservableObject {
    enum Alert: Int {
        case recommendationChanged
        case maxBolusExceeded
        case noPumpManagerConfigured
        case noMaxBolusConfigured
        case carbEntryPersistenceFailure
    }

    enum Notice {
        case predictedGlucoseBelowSuspendThreshold(suspendThreshold: HKQuantity)
        case staleGlucoseData
    }

    @Published var glucoseValues: [GlucoseValue] = []
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

    static let defaultGlucoseDisplayRange = HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 60)...HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 200)

    init(
        dataManager: DeviceDataManager,
        originalCarbEntry: StoredCarbEntry? = nil,
        potentialCarbEntry: NewCarbEntry? = nil,
        selectedCarbAbsorptionTimeEmoji: String? = nil
    ) {
        self.dataManager = dataManager
        self.originalCarbEntry = originalCarbEntry
        self.potentialCarbEntry = potentialCarbEntry
        self.selectedCarbAbsorptionTimeEmoji = selectedCarbAbsorptionTimeEmoji

        NotificationCenter.default
            .publisher(for: .LoopDataUpdated, object: dataManager.loopManager)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.update() }
            .store(in: &cancellables)

        $enteredBolus
            .removeDuplicates()
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.dataManager.loopManager.getLoopState { manager, state in
                    self?.updatePredictedGlucoseValues(from: state)
                }
            }
            .store(in: &cancellables)

        update()
    }

    var isBolusRecommended: Bool {
        guard let recommendedBolus = recommendedBolus else {
            return false
        }

        return recommendedBolus.doubleValue(for: .internationalUnit()) > 0
    }

    func saveCarbsAndDeliverBolus(onSuccess completion: @escaping () -> Void) {
        guard dataManager.pumpManager != nil else {
            activeAlert = .noPumpManagerConfigured
            return
        }

        guard let maximumBolus = maximumBolus else {
            activeAlert = .noMaxBolusConfigured
            return
        }

        guard enteredBolus < maximumBolus else {
            activeAlert = .maxBolusExceeded
            return
        }

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
                    self.activeAlert = .carbEntryPersistenceFailure
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

    private func update() {
        // Prevent any UI updates after a bolus has been initiated.
        guard !isInitiatingSaveOrBolus else { return }

        updateChartDateInterval()
        updateGlucoseValues()
        updateFromLoopState()
        updateActiveInsulin()
    }

    private func updateGlucoseValues() {
        dataManager.loopManager.glucoseStore.getCachedGlucoseSamples(start: chartDateInterval.start) { [weak self] values in
            DispatchQueue.main.async {
                self?.glucoseValues = values
            }
        }
    }

    private func updatePredictedGlucoseValues(from state: LoopState) {
        let enteredBolus = DispatchQueue.main.sync { self.enteredBolus }
        let enteredBolusDose = DoseEntry(type: .bolus, startDate: Date(), value: enteredBolus.doubleValue(for: .internationalUnit()), unit: .units)

        let predictedGlucoseValues: [GlucoseValue]
        do {
            predictedGlucoseValues = try state.predictGlucose(
                using: .all,
                potentialBolus: enteredBolusDose,
                potentialCarbEntry: potentialCarbEntry,
                replacingCarbEntry: originalCarbEntry,
                includingPendingInsulin: true
            )
        } catch {
            predictedGlucoseValues = []
        }

        DispatchQueue.main.async {
            self.predictedGlucoseValues = predictedGlucoseValues
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
            self.updateRecommendedBolusAndNotice(from: state)
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

    private func updateRecommendedBolusAndNotice(from state: LoopState) {
        let recommendedBolus: HKQuantity
        let notice: Notice?
        do {
            if let recommendation = try state.recommendBolus(
                consideringPotentialCarbEntry: self.potentialCarbEntry,
                replacingCarbEntry: self.originalCarbEntry
            ) {
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
                self.activeAlert = .recommendationChanged
            }
        }
    }

    private func updateSettings() {
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
