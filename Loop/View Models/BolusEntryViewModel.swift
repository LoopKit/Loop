//
//  BolusEntryViewModel.swift
//  Loop
//
//  Created by Michael Pangburn on 7/17/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import Combine
import LocalAuthentication
import Intents
import os.log
import LoopCore
import LoopKit
import LoopKitUI
import LoopUI
import SwiftUI
import SwiftCharts
import LoopAlgorithm

protocol BolusEntryViewModelDelegate: AnyObject {

    var settings: StoredSettings { get }
    var scheduleOverride: TemporaryScheduleOverride? { get }
    var preMealOverride: TemporaryScheduleOverride? { get }
    var mostRecentGlucoseDataDate: Date? { get }
    var mostRecentPumpDataDate: Date? { get }

    func fetchData(for baseTime: Date, disablingPreMeal: Bool, ensureDosingCoverageStart: Date?) async throws -> StoredDataAlgorithmInput
    func effectiveGlucoseTargetRangeSchedule(presumingMealEntry: Bool) -> GlucoseRangeSchedule?

    func addCarbEntry(_ carbEntry: NewCarbEntry, replacing replacingEntry: StoredCarbEntry?) async throws -> StoredCarbEntry
    func saveGlucose(sample: NewGlucoseSample) async throws -> StoredGlucoseSample
    func storeManualBolusDosingDecision(_ bolusDosingDecision: BolusDosingDecision, withDate date: Date) async
    func enactBolus(units: Double, activationType: BolusActivationType) async throws

    func insulinModel(for type: InsulinType?) -> InsulinModel

    func recommendManualBolus(
        manualGlucoseSample: NewGlucoseSample?,
        potentialCarbEntry: NewCarbEntry?,
        originalCarbEntry: StoredCarbEntry?
    ) async throws -> ManualBolusRecommendation?


    func generatePrediction(input: StoredDataAlgorithmInput) throws -> [PredictedGlucoseValue]

    var activeInsulin: InsulinValue? { get }
    var activeCarbs: CarbValue? { get }
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
        case forecastInfo
    }

    enum Notice: Equatable {
        case predictedGlucoseInRange
        case predictedGlucoseBelowSuspendThreshold(suspendThreshold: LoopQuantity)
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

    @Published var activeCarbs: LoopQuantity?
    @Published var activeInsulin: LoopQuantity?

    @Published var targetGlucoseSchedule: GlucoseRangeSchedule?
    @Published var preMealOverride: TemporaryScheduleOverride?
    private var savedPreMealOverride: TemporaryScheduleOverride?
    @Published var scheduleOverride: TemporaryScheduleOverride?
    var maximumBolus: LoopQuantity?

    let originalCarbEntry: StoredCarbEntry?
    let potentialCarbEntry: NewCarbEntry?
    let selectedCarbAbsorptionTimeEmoji: String?

    @Published var recommendedBolus: LoopQuantity?
    var recommendedBolusAmount: Double? {
        recommendedBolus?.doubleValue(for: .internationalUnit)
    }
    @Published var enteredBolus = LoopQuantity(unit: .internationalUnit, doubleValue: 0)
    var enteredBolusAmount: Double {
        enteredBolus.doubleValue(for: .internationalUnit)
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

    @Published var isManualGlucoseEntryEnabled = false
    @Published var manualGlucoseQuantity: LoopQuantity?

    var manualGlucoseSample: NewGlucoseSample?

    // MARK: - Seams
    private weak var delegate: BolusEntryViewModelDelegate?
    weak var deliveryDelegate: DeliveryDelegate?
    private let now: () -> Date
    private let screenWidth: CGFloat
    private let debounceIntervalMilliseconds: Int
    private let uuidProvider: () -> String
    private let carbEntryDateFormatter: DateFormatter

    var analyticsServicesManager: AnalyticsServicesManager?
    
    // MARK: - Initialization

    init(
        delegate: BolusEntryViewModelDelegate?,
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
                    if let rawContext = note.userInfo?[LoopDataManager.LoopUpdateContextKey] as? LoopUpdateContext.RawValue,
                       let context = LoopUpdateContext(rawValue: rawContext),
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
                Task {
                    await self?.updatePredictedGlucoseValues()
                }
            }
            .store(in: &cancellables)
    }

    private func observeEnteredManualGlucoseChanges() {
        $manualGlucoseQuantity
            .sink { [weak self] manualGlucoseQuantity in
                guard let self = self else { return }

                // Clear out any entered bolus whenever the glucose entry changes
                self.enteredBolus = LoopQuantity(unit: .internationalUnit, doubleValue: 0)

                Task {
                    await self.updatePredictedGlucoseValues()
                    // Ensure the manual glucose entry appears on the chart at the same time as the updated prediction
                    self.updateGlucoseChartValues()
                    await self.updateRecommendedBolusAndNotice(isUpdatingFromUserInput: true)
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
        try? await delegate?.addCarbEntry(entry, replacing: replacingEntry)
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
        guard let delegate, let deliveryDelegate else {
            assertionFailure("Missing Delegate")
            return false
        }

        guard deliveryDelegate.isPumpConfigured else {
            presentAlert(.noPumpManagerConfigured)
            return false
        }

        guard let maximumBolus = maximumBolus else {
            presentAlert(.noMaxBolusConfigured)
            return false
        }

        guard enteredBolusAmount <= maximumBolus.doubleValue(for: .internationalUnit) else {
            presentAlert(.maxBolusExceeded)
            return false
        }

        let amountToDeliver = deliveryDelegate.roundBolusVolume(units: enteredBolusAmount)

        guard enteredBolusAmount == 0 || amountToDeliver > 0 else {
            presentAlert(.bolusTooSmall)
            return false
        }

        let amountToDeliverString = formatBolusAmount(amountToDeliver)

        let manualGlucoseSample = manualGlucoseSample
        let potentialCarbEntry = potentialCarbEntry

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

        if let manualGlucoseSample {
            do {
                dosingDecision.manualGlucoseSample = try await delegate.saveGlucose(sample: manualGlucoseSample)
            } catch {
                presentAlert(.manualGlucoseEntryPersistenceFailure)
                return false
            }
        } else {
            self.dosingDecision.manualGlucoseSample = nil
        }

        let activationType = BolusActivationType.activationTypeFor(recommendedAmount: recommendedBolus?.doubleValue(for: .internationalUnit), bolusAmount: amountToDeliver)

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
                self.analyticsServicesManager?.didAddCarbs(source: "Phone", amount: storedCarbEntry.quantity.doubleValue(for: .gram), isFavoriteFood: storedCarbEntry.favoriteFoodID != nil)
            } else {
                self.presentAlert(.carbEntryPersistenceFailure)
                return false
            }
        }

        dosingDecision.manualBolusRequested = amountToDeliver

        let now = self.now()
        await delegate.storeManualBolusDosingDecision(dosingDecision, withDate: now)

        if amountToDeliver > 0 {
            savedPreMealOverride = nil
            do {
                try await delegate.enactBolus(units: amountToDeliver, activationType: activationType)
            } catch {
                log.error("Failed to store bolus: %{public}@", String(describing: error))
            }
            self.analyticsServicesManager?.didBolus(source: "Phone", units: amountToDeliver)
        }
        return true
    }

    private func presentAlert(_ alert: Alert) {
        // As of iOS 13.6 / Xcode 11.6, swapping out an alert while one is active crashes SwiftUI.
        guard activeAlert == nil else {
            return
        }

        activeAlert = alert
    }

    private lazy var bolusAmountFormatter: NumberFormatter = {
        let formatter = QuantityFormatter(for: .internationalUnit)
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
        guard let maxBolusAmount = maximumBolus?.doubleValue(for: .internationalUnit) else {
            return nil
        }
        return formatBolusAmount(maxBolusAmount)
    }

    var carbEntryAmountAndEmojiString: String? {
        guard
            let potentialCarbEntry = potentialCarbEntry,
            let carbAmountString = QuantityFormatter(for: .gram).string(from: potentialCarbEntry.quantity)
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
        // Prevent any UI updates after a bolus has been initiated.
        guard !enacting else {
            return
        }

        self.activeCarbs = delegate?.activeCarbs?.quantity
        self.activeInsulin = delegate?.activeInsulin?.quantity
        dosingDecision.insulinOnBoard = delegate?.activeInsulin

        disableManualGlucoseEntryIfNecessary()
        updateChartDateInterval()
        await updateRecommendedBolusAndNotice(isUpdatingFromUserInput: false)
        await updatePredictedGlucoseValues()
        updateGlucoseChartValues()
    }

    private func disableManualGlucoseEntryIfNecessary() {
        if isManualGlucoseEntryEnabled, !isGlucoseDataStale {
            isManualGlucoseEntryEnabled = false
            manualGlucoseQuantity = nil
            manualGlucoseSample = nil
        }
    }

    private func updateGlucoseChartValues() {

        var chartGlucoseValues = storedGlucoseValues
        if let manualGlucoseSample = manualGlucoseSample {
            chartGlucoseValues.append(LoopQuantitySample(with: manualGlucoseSample.quantitySample))
        }

        self.glucoseValues = chartGlucoseValues
    }

    /// - NOTE: `completion` is invoked on the main queue after predicted glucose values are updated
    private func updatePredictedGlucoseValues() async {
        guard let delegate else {
            return
        }

        do {
            let startDate = now()
            var input = try await delegate.fetchData(for: startDate, disablingPreMeal: potentialCarbEntry != nil, ensureDosingCoverageStart: nil)

            let insulinModel = delegate.insulinModel(for: deliveryDelegate?.pumpInsulinType)

            let enteredBolusDose = SimpleInsulinDose(
                deliveryType: .bolus,
                startDate: startDate,
                endDate: startDate,
                volume: enteredBolus.doubleValue(for: .internationalUnit),
                insulinModel: insulinModel
            )

            storedGlucoseValues = input.glucoseHistory

            // Add potential bolus, carbs, manual glucose
            input = input
                .addingDose(dose: enteredBolusDose)
                .addingGlucoseSample(sample: manualGlucoseSample?.asStoredGlucoseStample)
                .removingCarbEntry(carbEntry: originalCarbEntry)
                .addingCarbEntry(carbEntry: potentialCarbEntry?.asStoredCarbEntry)

            let prediction = try delegate.generatePrediction(input: input)
            predictedGlucoseValues = prediction
            dosingDecision.predictedGlucose = prediction
        } catch {
            predictedGlucoseValues = []
            dosingDecision.predictedGlucose = []
        }

    }

    private func updateRecommendedBolusAndNotice(isUpdatingFromUserInput: Bool) async {

        guard let delegate else {
            assertionFailure("Missing BolusEntryViewModelDelegate")
            return
        }

        var recommendation: ManualBolusRecommendation?
        let recommendedBolus: LoopQuantity?
        let notice: Notice?
        do {
            recommendation = try await computeBolusRecommendation()

            if let recommendation, deliveryDelegate != nil {
                recommendedBolus = LoopQuantity(unit: .internationalUnit, doubleValue: recommendation.amount)

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
                recommendedBolus = LoopQuantity(unit: .internationalUnit, doubleValue: 0)
                notice = nil
            }
        } catch {
            recommendedBolus = nil

            switch error {
            case LoopError.missingDataError(.glucose), LoopError.glucoseTooOld, AlgorithmError.missingGlucose, AlgorithmError.glucoseTooOld:
                notice = .staleGlucoseData
            case LoopError.invalidFutureGlucose:
                notice = .futureGlucoseData
            case LoopError.pumpDataTooOld:
                notice = .stalePumpData
            default:
                notice = nil
            }
        }

        let priorRecommendedBolus = self.recommendedBolus
        self.recommendedBolus = recommendedBolus
        self.dosingDecision.manualBolusRecommendation = recommendation.map { ManualBolusRecommendationWithDate(recommendation: $0, date: now()) }
        self.activeNotice = notice

        if priorRecommendedBolus != nil,
           priorRecommendedBolus != recommendedBolus,
           !self.enacting,
           !isUpdatingFromUserInput
        {
            self.presentAlert(.recommendationChanged)
        }
    }

    private func computeBolusRecommendation() async throws -> ManualBolusRecommendation? {
        guard let delegate else {
            return nil
        }

        return try await delegate.recommendManualBolus(
            manualGlucoseSample: manualGlucoseSample,
            potentialCarbEntry: potentialCarbEntry,
            originalCarbEntry: originalCarbEntry
        )
    }

    func updateSettings() {
        guard let delegate = delegate else {
            return
        }

        targetGlucoseSchedule = delegate.settings.glucoseTargetRangeSchedule
        // Pre-meal override should be ignored if we have carbs (LOOP-1964)
        preMealOverride = potentialCarbEntry == nil ? delegate.preMealOverride : nil
        scheduleOverride = delegate.scheduleOverride

        if preMealOverride?.hasFinished() == true {
            preMealOverride = nil
        }

        if scheduleOverride?.hasFinished() == true {
            scheduleOverride = nil
        }

        maximumBolus = delegate.settings.maximumBolus.map { maxBolusAmount in
            LoopQuantity(unit: .internationalUnit, doubleValue: maxBolusAmount)
        }

        dosingDecision.scheduleOverride = scheduleOverride

        if scheduleOverride != nil || preMealOverride != nil {
            dosingDecision.glucoseTargetRangeSchedule = delegate.effectiveGlucoseTargetRangeSchedule(presumingMealEntry: potentialCarbEntry != nil)
        } else {
            dosingDecision.glucoseTargetRangeSchedule = targetGlucoseSchedule
        }
    }

    private func updateChartDateInterval() {
        // How far back should we show data? Use the screen size as a guide.
        let viewMarginInset: CGFloat = 14
        let availableWidth = screenWidth - chartManager.fixedHorizontalMargin - 2 * viewMarginInset

        let totalHours = floor(Double(availableWidth / LoopConstants.minimumChartWidthPerHour))
        let insulinType = deliveryDelegate?.pumpInsulinType
        let insulinModel = delegate?.insulinModel(for: insulinType)
        let futureHours = ceil((insulinModel?.effectDuration ?? .hours(4)).hours)
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
        enteredBolus = LoopQuantity(unit: .internationalUnit, doubleValue: enteredBolusAmount ?? 0)
    }
}

extension BolusEntryViewModel.Alert: Identifiable {
    var id: Self { self }
}

// MARK: Helpers
extension BolusEntryViewModel {
    
    var isGlucoseDataStale: Bool {
        guard let latestGlucoseDataDate = delegate?.mostRecentGlucoseDataDate else { return true }
        return now().timeIntervalSince(latestGlucoseDataDate) > LoopAlgorithm.inputDataRecencyInterval
    }
    
    var isPumpDataStale: Bool {
        guard let latestPumpDataDate = delegate?.mostRecentPumpDataDate else { return true }
        return now().timeIntervalSince(latestPumpDataDate) > LoopAlgorithm.inputDataRecencyInterval
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
        enteredBolus.doubleValue(for: .internationalUnit) != 0
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
