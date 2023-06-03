//
//  StatusTableViewController.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 9/6/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

import UIKit
import HealthKit
import SwiftUI
import Intents
import LoopCore
import LoopKit
import LoopKitUI
import LoopTestingKit
import LoopUI
import SwiftCharts
import os.log
import Combine
import WidgetKit


private extension RefreshContext {
    static let all: Set<RefreshContext> = [.status, .glucose, .insulin, .carbs, .targets]
}

final class StatusTableViewController: LoopChartsTableViewController {

    private let log = OSLog(category: "StatusTableViewController")

    lazy var quantityFormatter: QuantityFormatter = QuantityFormatter()

    var onboardingManager: OnboardingManager!

    var testingScenariosManager: TestingScenariosManager!

    var automaticDosingStatus: AutomaticDosingStatus!
    
    var alertPermissionsChecker: AlertPermissionsChecker!

    var alertMuter: AlertMuter!

    var supportManager: SupportManager!

    lazy private var cancellables = Set<AnyCancellable>()

    override func viewDidLoad() {

        super.viewDidLoad()
        
        setupToolbarItems()
        
        tableView.register(BolusProgressTableViewCell.nib(), forCellReuseIdentifier: BolusProgressTableViewCell.className)
        tableView.register(AlertPermissionsDisabledWarningCell.self, forCellReuseIdentifier: AlertPermissionsDisabledWarningCell.className)
        tableView.register(MuteAlertsWarningCell.self, forCellReuseIdentifier: MuteAlertsWarningCell.className)

        if FeatureFlags.predictedGlucoseChartClampEnabled {
            statusCharts.glucose.glucoseDisplayRange = LoopConstants.glucoseChartDefaultDisplayBoundClamped
        } else {
            statusCharts.glucose.glucoseDisplayRange = LoopConstants.glucoseChartDefaultDisplayBound
        }

        registerPumpManager()
        registerCGMManager()

        let notificationCenter = NotificationCenter.default

        notificationObservers += [
            notificationCenter.addObserver(forName: .LoopDataUpdated, object: deviceManager.loopManager, queue: nil) { [weak self] note in
                let rawContext = note.userInfo?[LoopDataManager.LoopUpdateContextKey] as! LoopDataManager.LoopUpdateContext.RawValue
                let context = LoopDataManager.LoopUpdateContext(rawValue: rawContext)
                DispatchQueue.main.async {
                    switch context {
                    case .none, .insulin?:
                        self?.refreshContext.formUnion([.status, .insulin])
                    case .preferences?:
                        self?.refreshContext.formUnion([.status, .targets])
                    case .carbs?:
                        self?.refreshContext.update(with: .carbs)
                    case .glucose?:
                        self?.refreshContext.formUnion([.glucose, .carbs])
                    case .loopFinished?:
                        self?.refreshContext.update(with: .insulin)
                    }

                    self?.hudView?.loopCompletionHUD.loopInProgress = false
                    self?.log.debug("[reloadData] from notification with context %{public}@", String(describing: context))
                    self?.reloadData(animated: true)
                }
                
                WidgetCenter.shared.reloadAllTimelines()
            },
            notificationCenter.addObserver(forName: .LoopRunning, object: deviceManager.loopManager, queue: nil) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.hudView?.loopCompletionHUD.loopInProgress = true
                }
            },
            notificationCenter.addObserver(forName: .PumpManagerChanged, object: deviceManager, queue: nil) { [weak self] (notification: Notification) in
                DispatchQueue.main.async {
                    self?.registerPumpManager()
                    self?.configurePumpManagerHUDViews()
                    self?.updateToolbarItems()
                }
            },
            notificationCenter.addObserver(forName: .CGMManagerChanged, object: deviceManager, queue: nil) { [weak self] (notification: Notification) in
                DispatchQueue.main.async {
                    self?.registerCGMManager()
                    self?.configureCGMManagerHUDViews()
                    self?.updateToolbarItems()
                }
            },
            notificationCenter.addObserver(forName: .PumpEventsAdded, object: deviceManager, queue: nil) { [weak self] (notification: Notification) in
                DispatchQueue.main.async {
                    self?.refreshContext.update(with: .insulin)
                    self?.reloadData(animated: true)
                }
            },
        ]

        automaticDosingStatus.$automaticDosingEnabled
            .receive(on: DispatchQueue.main)
            .sink { self.automaticDosingStatusChanged($0) }
            .store(in: &cancellables)

        alertMuter.$configuration
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .dropFirst()
            .sink { _ in
                self.refreshContext.update(with: .status)
                self.reloadData(animated: true)
            }
            .store(in: &cancellables)

        if let gestureRecognizer = charts.gestureRecognizer {
            tableView.addGestureRecognizer(gestureRecognizer)
        }

        tableView.estimatedRowHeight = 74

        // Estimate an initial value
        landscapeMode = UIScreen.main.bounds.size.width > UIScreen.main.bounds.size.height

        addScenarioStepGestureRecognizers()

        tableView.backgroundColor = .secondarySystemBackground
    
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()

        if !visible {
            refreshContext.formUnion(RefreshContext.all)
        }
    }

    private var appearedOnce = false

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        navigationController?.setNavigationBarHidden(true, animated: animated)
        navigationController?.setToolbarHidden(false, animated: animated)
        
        setupToolbarItems()
        updateToolbarItems()

        alertPermissionsChecker.checkNow()

        updateBolusProgress()

        onboardingManager.$isComplete
            .merge(with: onboardingManager.$isSuspended)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshContext.update(with: .status)
                self?.reloadData(animated: true)
                self?.updateToolbarItems()
            }
            .store(in: &cancellables)
    }

    override func viewDidAppear(_ animated: Bool) {

        super.viewDidAppear(animated)

        if !appearedOnce {
            appearedOnce = true
            DispatchQueue.main.async {
                self.log.debug("[reloadData] after HealthKit authorization")
                self.reloadData()
            }
        }

        onscreen = true

        deviceManager.analyticsServicesManager.didDisplayStatusScreen()

        deviceManager.checkDeliveryUncertaintyState()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        onscreen = false

        if presentedViewController == nil {
            navigationController?.setNavigationBarHidden(false, animated: animated)
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        refreshContext.update(with: .size(size))

        maybeOpenDebugMenu()

        super.viewWillTransition(to: size, with: coordinator)
    }

    // MARK: - State

    // This reflects whether the application is active 
    override var active: Bool {
        didSet {
            hudView?.loopCompletionHUD.assertTimer(active)
            updateHUDActive()
        }
    }

    // This is similar to the visible property, but is set later, on viewDidAppear, to be
    // suitable for animations that should be seen in their entirety.
    var onscreen: Bool = false {
        didSet {
            updateHUDActive()
        }
    }

    private var bolusState: PumpManagerStatus.BolusState = .noBolus {
        didSet {
            if oldValue != bolusState {
                // Bolus starting
                if case .inProgress = bolusState {
                    bolusProgressReporter = deviceManager.pumpManager?.createBolusProgressReporter(reportingOn: DispatchQueue.main)
                }
                refreshContext.update(with: .status)
                reloadData(animated: true)
            }
        }
    }

    private var bolusProgressReporter: DoseProgressReporter?

    private func updateBolusProgress() {
        if let cell = tableView.cellForRow(at: IndexPath(row: StatusRow.status.rawValue, section: Section.status.rawValue)) as? BolusProgressTableViewCell {
            cell.deliveredUnits = bolusProgressReporter?.progress.deliveredUnits
        }
    }

    private func updateHUDActive() {
        deviceManager.pumpManagerHUDProvider?.visible = active && onscreen
    }

    private func setupToolbarItems() {
        let space = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: self, action: nil)
        let carbs = UIBarButtonItem(image: UIImage(named: "carbs"), style: .plain, target: self, action: #selector(userTappedAddCarbs))
        let preMeal = createPreMealButtonItem(selected: false, isEnabled: true)
        let bolus = UIBarButtonItem(image: UIImage(named: "bolus"), style: .plain, target: self, action: #selector(presentBolusScreen))
        let workout = createWorkoutButtonItem(selected: false, isEnabled: true)
        let settings = UIBarButtonItem(image: UIImage(named: "settings"), style: .plain, target: self, action: #selector(onSettingsTapped))
        
        toolbarItems = [
            carbs,
            space,
            preMeal,
            space,
            bolus,
            space,
            workout,
            space,
            settings
        ]
    }
    
    private func updateToolbarItems() {
        let isPumpOnboarded = onboardingManager.isComplete || deviceManager.pumpManager?.isOnboarded == true

        toolbarItems![0].accessibilityLabel = NSLocalizedString("Add Meal", comment: "The label of the carb entry button")
        toolbarItems![0].isEnabled = isPumpOnboarded
        toolbarItems![0].tintColor = UIColor.carbTintColor
        toolbarItems![2].isEnabled = isPumpOnboarded && (automaticDosingStatus.automaticDosingEnabled || !FeatureFlags.simpleBolusCalculatorEnabled)
        toolbarItems![4].accessibilityLabel = NSLocalizedString("Bolus", comment: "The label of the bolus entry button")
        toolbarItems![4].isEnabled = isPumpOnboarded
        toolbarItems![4].tintColor = UIColor.insulinTintColor
        toolbarItems![6].isEnabled = isPumpOnboarded
        toolbarItems![8].accessibilityLabel = NSLocalizedString("Settings", comment: "The label of the settings button")
        toolbarItems![8].tintColor = UIColor.secondaryLabel
    }

    public var basalDeliveryState: PumpManagerStatus.BasalDeliveryState? = nil {
        didSet {
            if oldValue != basalDeliveryState {
                log.debug("New basalDeliveryState: %@", String(describing: basalDeliveryState))
                refreshContext.update(with: .status)
                reloadData(animated: true)
            }
        }
    }

    // Toggles the display mode based on the screen aspect ratio. Should not be updated outside of reloadData().
    private var landscapeMode = false

    private var lastLoopError: Error?

    private var reloading = false

    private var refreshContext = RefreshContext.all

    private var shouldShowHUD: Bool {
        return !landscapeMode
    }

    private var shouldShowStatus: Bool {
        return !landscapeMode && statusRowMode.hasRow
    }

    override func glucoseUnitDidChange() {
        log.debug("[reloadData] for HealthKit unit preference change")
        refreshContext = RefreshContext.all
    }
    
    private func registerCGMManager() {
        deviceManager.cgmManager?.removeStatusObserver(self)
        deviceManager.cgmManager?.addStatusObserver(self, queue: .main)
    }

    private func registerPumpManager() {
        basalDeliveryState = deviceManager.pumpManager?.status.basalDeliveryState
        bolusState = deviceManager.pumpManager?.status.bolusState ?? .noBolus
        deviceManager.pumpManager?.removeStatusObserver(self)
        deviceManager.pumpManager?.addStatusObserver(self, queue: .main)
    }
    
    private lazy var statusCharts = StatusChartsManager(colors: .primary, settings: .default, traitCollection: traitCollection)

    override func createChartsManager() -> ChartsManager {
        return statusCharts
    }

    private func updateChartDateRange() {
        // How far back should we show data? Use the screen size as a guide.
        let availableWidth = (refreshContext.newSize ?? tableView.bounds.size).width - charts.fixedHorizontalMargin

        let totalHours = floor(Double(availableWidth / LoopConstants.minimumChartWidthPerHour))
        let futureHours = ceil(deviceManager.doseStore.longestEffectDuration.hours)
        let historyHours = max(LoopConstants.statusChartMinimumHistoryDisplay.hours, totalHours - futureHours)

        let date = Date(timeIntervalSinceNow: -TimeInterval(hours: historyHours))
        let chartStartDate = Calendar.current.nextDate(after: date, matching: DateComponents(minute: 0), matchingPolicy: .strict, direction: .backward) ?? date
        if charts.startDate != chartStartDate {
            refreshContext.formUnion(RefreshContext.all)
        }
        charts.startDate = chartStartDate
        charts.maxEndDate = chartStartDate.addingTimeInterval(.hours(totalHours))
        charts.updateEndDate(charts.maxEndDate)
    }

    override func reloadData(animated: Bool = false) {
        dispatchPrecondition(condition: .onQueue(.main))
        // This should be kept up to date immediately
        hudView?.loopCompletionHUD.lastLoopCompleted = deviceManager.loopManager.lastLoopCompleted

        guard !reloading && !deviceManager.authorizationRequired else {
            return
        }

        updateChartDateRange()

        if case .bolusing = statusRowMode, bolusProgressReporter?.progress.isComplete == true {
            refreshContext.update(with: .status)
        }

        if visible && active {
            bolusProgressReporter?.addObserver(self)
        } else {
            bolusProgressReporter?.removeObserver(self)
        }

        guard active && visible && !refreshContext.isEmpty else {
            updateBannerRow(animated: animated)
            redrawCharts()
            return
        }

        log.debug("Reloading data with context: %@", String(describing: refreshContext))

        let currentContext = refreshContext
        var retryContext: Set<RefreshContext> = []
        refreshContext = []
        reloading = true

        let reloadGroup = DispatchGroup()
        var glucoseSamples: [StoredGlucoseSample]?
        var predictedGlucoseValues: [GlucoseValue]?
        var iobValues: [InsulinValue]?
        var doseEntries: [DoseEntry]?
        var totalDelivery: Double?
        var cobValues: [CarbValue]?
        var carbsOnBoard: HKQuantity?
        let startDate = charts.startDate
        let basalDeliveryState = self.basalDeliveryState
        let automaticDosingEnabled = automaticDosingStatus.automaticDosingEnabled

        // TODO: Don't always assume currentContext.contains(.status)
        reloadGroup.enter()
        deviceManager.loopManager.getLoopState { (manager, state) -> Void in
            predictedGlucoseValues = state.predictedGlucoseIncludingPendingInsulin ?? []

            // Retry this refresh again if predicted glucose isn't available
            if state.predictedGlucose == nil {
                retryContext.update(with: .status)
            }

            /// Update the status HUDs immediately
            let lastLoopError = state.error

            // Net basal rate HUD
            let netBasal: NetBasal?
            if let basalSchedule = manager.basalRateScheduleApplyingOverrideHistory {
                netBasal = basalDeliveryState?.getNetBasal(basalSchedule: basalSchedule, settings: manager.settings)
            } else {
                netBasal = nil
            }
            self.log.debug("Update net basal to %{public}@", String(describing: netBasal))

            DispatchQueue.main.async {
                self.lastLoopError = lastLoopError

                if let netBasal = netBasal {
                    self.hudView?.pumpStatusHUD.basalRateHUD.setNetBasalRate(netBasal.rate, percent: netBasal.percent, at: netBasal.start)
                }
            }

            if currentContext.contains(.carbs) {
                reloadGroup.enter()
                self.deviceManager.carbStore.getCarbsOnBoardValues(start: startDate, end: nil, effectVelocities: FeatureFlags.dynamicCarbAbsorptionEnabled ? state.insulinCounteractionEffects : nil) { (result) in
                    switch result {
                    case .failure(let error):
                        self.log.error("CarbStore failed to get carbs on board values: %{public}@", String(describing: error))
                        retryContext.update(with: .carbs)
                        cobValues = []
                    case .success(let values):
                        cobValues = values
                    }
                    reloadGroup.leave()
                }
            }
            // always check for cob
            carbsOnBoard = state.carbsOnBoard?.quantity

            reloadGroup.leave()
        }

        if currentContext.contains(.glucose) {
            reloadGroup.enter()
            deviceManager.glucoseStore.getGlucoseSamples(start: startDate, end: nil) { (result) -> Void in
                switch result {
                case .failure(let error):
                    self.log.error("Failure getting glucose samples: %{public}@", String(describing: error))
                    glucoseSamples = nil
                case .success(let samples):
                    glucoseSamples = samples
                }
                reloadGroup.leave()
            }
        }

        if currentContext.contains(.insulin) {
            reloadGroup.enter()
            deviceManager.doseStore.getInsulinOnBoardValues(start: startDate, end: nil, basalDosingEnd: nil) { (result) -> Void in
                switch result {
                case .failure(let error):
                    self.log.error("DoseStore failed to get insulin on board values: %{public}@", String(describing: error))
                    retryContext.update(with: .insulin)
                    iobValues = []
                case .success(let values):
                    iobValues = values
                }
                reloadGroup.leave()
            }

            reloadGroup.enter()
            deviceManager.doseStore.getNormalizedDoseEntries(start: startDate, end: nil) { (result) -> Void in
                switch result {
                case .failure(let error):
                    self.log.error("DoseStore failed to get normalized dose entries: %{public}@", String(describing: error))
                    retryContext.update(with: .insulin)
                    doseEntries = []
                case .success(let doses):
                    doseEntries = doses
                }
                reloadGroup.leave()
            }

            reloadGroup.enter()
            deviceManager.doseStore.getTotalUnitsDelivered(since: Calendar.current.startOfDay(for: Date())) { (result) in
                switch result {
                case .failure:
                    retryContext.update(with: .insulin)
                    totalDelivery = nil
                case .success(let total):
                    totalDelivery = total.value
                }

                reloadGroup.leave()
            }
        }

        updatePreMealModeAvailability(automaticDosingEnabled: automaticDosingEnabled)

        if deviceManager.loopManager.settings.preMealTargetRange == nil {
            preMealMode = nil
        } else {
            preMealMode = deviceManager.loopManager.settings.preMealTargetEnabled()
        }

        if !FeatureFlags.sensitivityOverridesEnabled, deviceManager.loopManager.settings.legacyWorkoutTargetRange == nil {
            workoutMode = nil
        } else {
            workoutMode = deviceManager.loopManager.settings.nonPreMealOverrideEnabled()
        }

        reloadGroup.notify(queue: .main) {
            /// Update the chart data

            // Glucose
            if let glucoseSamples = glucoseSamples {
                self.statusCharts.setGlucoseValues(glucoseSamples)
            }
            if (automaticDosingEnabled || !FeatureFlags.simpleBolusCalculatorEnabled), let predictedGlucoseValues = predictedGlucoseValues {
                self.statusCharts.setPredictedGlucoseValues(predictedGlucoseValues)
            } else {
                self.statusCharts.setPredictedGlucoseValues([])
            }
            if !FeatureFlags.predictedGlucoseChartClampEnabled,
                let lastPoint = self.statusCharts.glucose.predictedGlucosePoints.last?.y
            {
                self.eventualGlucoseDescription = String(describing: lastPoint)
            } else {
                // if the predicted glucose values are clamped, the eventually glucose description should not be displayed, since it may not align with what is being charted.
                self.eventualGlucoseDescription = nil
            }
            if currentContext.contains(.targets) {
                self.statusCharts.targetGlucoseSchedule = self.deviceManager.loopManager.settings.glucoseTargetRangeSchedule
                self.statusCharts.preMealOverride = self.deviceManager.loopManager.settings.preMealOverride
                self.statusCharts.scheduleOverride = self.deviceManager.loopManager.settings.scheduleOverride
            }
            if self.statusCharts.scheduleOverride?.hasFinished() == true {
                self.statusCharts.scheduleOverride = nil
            }

            let charts = self.statusCharts

            // Active Insulin
            if let iobValues = iobValues {
                charts.setIOBValues(iobValues)
            }

            // Show the larger of the value either before or after the current date
            if let maxValue = charts.iob.iobPoints.allElementsAdjacent(to: Date()).max(by: {
                return $0.y.scalar < $1.y.scalar
            }) {
                self.currentIOBDescription = String(describing: maxValue.y)
            } else {
                self.currentIOBDescription = nil
            }

            // Insulin Delivery
            if let doseEntries = doseEntries {
                charts.setDoseEntries(doseEntries)
            }
            if let totalDelivery = totalDelivery {
                self.totalDelivery = totalDelivery
            }

            // Active Carbohydrates
            if let cobValues = cobValues {
                charts.setCOBValues(cobValues)
            }
            if let index = charts.cob.cobPoints.closestIndex(priorTo: Date()) {
                self.currentCOBDescription = String(describing: charts.cob.cobPoints[index].y)
            } else if let carbsOnBoard = carbsOnBoard {
                self.currentCOBDescription = self.quantityFormatter.string(from: carbsOnBoard, for: .gram())
            } else {
                self.currentCOBDescription = nil
            }

            self.tableView.beginUpdates()
            if let hudView = self.hudView {
                // CGM Status
                if let glucose = self.deviceManager.glucoseStore.latestGlucose {
                    let unit = self.statusCharts.glucose.glucoseUnit
                    hudView.cgmStatusHUD.setGlucoseQuantity(glucose.quantity.doubleValue(for: unit),
                                                            at: glucose.startDate,
                                                            unit: unit,
                                                            staleGlucoseAge: LoopCoreConstants.inputDataRecencyInterval,
                                                            glucoseDisplay: self.deviceManager.glucoseDisplay(for: glucose),
                                                            wasUserEntered: glucose.wasUserEntered,
                                                            isDisplayOnly: glucose.isDisplayOnly)
                }
                hudView.cgmStatusHUD.presentStatusHighlight(self.deviceManager.cgmStatusHighlight)
                hudView.cgmStatusHUD.presentStatusBadge(self.deviceManager.cgmStatusBadge)
                hudView.cgmStatusHUD.lifecycleProgress = self.deviceManager.cgmLifecycleProgress

                // Pump Status
                hudView.pumpStatusHUD.presentStatusHighlight(self.deviceManager.pumpStatusHighlight)
                hudView.pumpStatusHUD.presentStatusBadge(self.deviceManager.pumpStatusBadge)
                hudView.pumpStatusHUD.lifecycleProgress = self.deviceManager.pumpLifecycleProgress
            }

            // Show/hide the table view rows
            let statusRowMode = self.determineStatusRowMode()

            self.updateBannerAndHUDandStatusRows(statusRowMode: statusRowMode, newSize: currentContext.newSize, animated: animated)

            self.redrawCharts()

            self.tableView.endUpdates()

            self.reloading = false
            let reloadNow = !self.refreshContext.isEmpty
            self.refreshContext.formUnion(retryContext)

            // Trigger a reload if new context exists.
            if reloadNow {
                self.log.debug("[reloadData] due to context change during previous reload")
                self.reloadData()
            }
        }
    }

    private enum Section: Int, CaseIterable {
        case alertWarning
        case hud
        case status
        case charts
    }

    // MARK: - Chart Section Data

    private enum ChartRow: Int, CaseIterable {
        case glucose
        case iob
        case dose
        case cob
    }

    // MARK: Glucose

    private var eventualGlucoseDescription: String?

    // MARK: IOB

    private var currentIOBDescription: String?

    // MARK: Dose

    private var totalDelivery: Double?

    // MARK: COB

    private var currentCOBDescription: String?

    // MARK: - Loop Status Section Data

    private enum StatusRow: Int, CaseIterable {
        case status = 0
    }

    private enum StatusRowMode {
        case hidden
        case scheduleOverrideEnabled(TemporaryScheduleOverride)
        case enactingBolus
        case bolusing(dose: DoseEntry)
        case cancelingBolus
        case pumpSuspended(resuming: Bool)
        case onboardingSuspended
        case recommendManualGlucoseEntry

        var hasRow: Bool {
            switch self {
            case .hidden:
                return false
            default:
                return true
            }
        }
    }

    private var statusRowMode = StatusRowMode.hidden

    private func determineStatusRowMode() -> StatusRowMode {
        let statusRowMode: StatusRowMode

        if case .initiating = bolusState {
            statusRowMode = .enactingBolus
        } else if case .canceling = bolusState {
            statusRowMode = .cancelingBolus
        } else if case .suspended = basalDeliveryState {
            statusRowMode = .pumpSuspended(resuming: false)
        } else if case .resuming = basalDeliveryState {
            statusRowMode = .pumpSuspended(resuming: true)
        } else if case .inProgress(let dose) = bolusState, dose.endDate.timeIntervalSinceNow > 0 {
            statusRowMode = .bolusing(dose: dose)
        } else if !onboardingManager.isComplete, deviceManager.pumpManager?.isOnboarded == true {
            statusRowMode = .onboardingSuspended
        } else if onboardingManager.isComplete, deviceManager.isGlucoseValueStale {
            statusRowMode = .recommendManualGlucoseEntry
        } else if let scheduleOverride = deviceManager.loopManager.settings.scheduleOverride,
            !scheduleOverride.hasFinished()
        {
            statusRowMode = .scheduleOverrideEnabled(scheduleOverride)
        } else if let premealOverride = deviceManager.loopManager.settings.preMealOverride,
            !premealOverride.hasFinished()
        {
            statusRowMode = .scheduleOverrideEnabled(premealOverride)
        } else {
            statusRowMode = .hidden
        }

        return statusRowMode
    }

    private var shouldShowBannerWarning: Bool {
        alertPermissionsChecker.showWarning || alertMuter.configuration.shouldMute
    }

    private func updateBannerRow(animated: Bool) {
        let warningWasVisible = tableView.numberOfRows(inSection: Section.alertWarning.rawValue) != 0
        if !shouldShowBannerWarning && warningWasVisible {
            tableView.deleteRows(at: [IndexPath(row: 0, section: Section.alertWarning.rawValue)], with: animated ? .top : .none)
        } else if shouldShowBannerWarning && !warningWasVisible {
            tableView.insertRows(at: [IndexPath(row: 0, section: Section.alertWarning.rawValue)], with: animated ? .top : .none)
        } else {
            tableView.reloadRows(at: [IndexPath(row: 0, section: Section.alertWarning.rawValue)], with: .none)
        }
    }

    private func updateBannerAndHUDandStatusRows(statusRowMode: StatusRowMode, newSize: CGSize?, animated: Bool) {
        let hudWasVisible = self.shouldShowHUD
        let statusWasVisible = self.shouldShowStatus

        let oldStatusRowMode = self.statusRowMode

        self.statusRowMode = statusRowMode

        if let newSize = newSize {
            landscapeMode = newSize.width > newSize.height
        }

        let hudIsVisible = self.shouldShowHUD
        let statusIsVisible = self.shouldShowStatus

        hudView?.cgmStatusHUD?.isVisible = hudIsVisible

        tableView.beginUpdates()
        
        updateBannerRow(animated: animated)

        switch (hudWasVisible, hudIsVisible) {
        case (false, true):
            tableView.insertRows(at: [IndexPath(row: 0, section: Section.hud.rawValue)], with: animated ? .top : .none)
        case (true, false):
            tableView.deleteRows(at: [IndexPath(row: 0, section: Section.hud.rawValue)], with: animated ? .top : .none)
        default:
            break
        }

        let statusIndexPath = IndexPath(row: StatusRow.status.rawValue, section: Section.status.rawValue)

        switch (statusWasVisible, statusIsVisible) {
        case (true, true):
            switch (oldStatusRowMode, self.statusRowMode) {
            case (.enactingBolus, .enactingBolus):
                break
            case (.bolusing(let oldDose), .bolusing(let newDose)):
                if oldDose != newDose {
                    tableView.reloadRows(at: [statusIndexPath], with: animated ? .fade : .none)
                }
            case (.pumpSuspended(resuming: let wasResuming), .pumpSuspended(resuming: let isResuming)):
                if isResuming != wasResuming {
                    tableView.reloadRows(at: [statusIndexPath], with: animated ? .fade : .none)
                }
            default:
                tableView.reloadRows(at: [statusIndexPath], with: animated ? .fade : .none)
            }
        case (false, true):
            tableView.insertRows(at: [statusIndexPath], with: animated ? .bottom : .none)
        case (true, false):
            tableView.deleteRows(at: [statusIndexPath], with: animated ? .top : .none)
        default:
            break
        }

        tableView.endUpdates()
    }

    private func redrawCharts() {
        tableView.beginUpdates()
        charts.prerender()
        for case let cell as ChartTableViewCell in tableView.visibleCells {
            cell.reloadChart()

            if let indexPath = tableView.indexPath(for: cell) {
                self.tableView(tableView, updateSubtitleFor: cell, at: indexPath)
            }
        }
        tableView.endUpdates()
    }

    // MARK: - Toolbar data

    private var preMealMode: Bool? = nil {
        didSet {
            guard oldValue != preMealMode else {
                return
            }
            updatePreMealModeAvailability(automaticDosingEnabled: automaticDosingStatus.automaticDosingEnabled)
        }
    }

    private func updatePreMealModeAvailability(automaticDosingEnabled: Bool) {
        let allowed = onboardingManager.isComplete &&
                (automaticDosingEnabled || !FeatureFlags.simpleBolusCalculatorEnabled)
                && deviceManager.loopManager.settings.preMealTargetRange != nil
        toolbarItems![2] = createPreMealButtonItem(selected: preMealMode ?? false && allowed, isEnabled: allowed)
    }

    private var workoutMode: Bool? = nil {
        didSet {
            guard oldValue != workoutMode else {
                return
            }

            if let workoutMode = workoutMode {
                let allowed = onboardingManager.isComplete
                toolbarItems![6] = createWorkoutButtonItem(selected: workoutMode, isEnabled: allowed)
            } else {
                toolbarItems![6].isEnabled = false
            }
        }
    }

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        return Section.allCases.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .alertWarning:
            return shouldShowBannerWarning ? 1 : 0
        case .hud:
            return shouldShowHUD ? 1 : 0
        case .charts:
            return ChartRow.allCases.count
        case .status:
            return shouldShowStatus ? StatusRow.allCases.count : 0
        }
    }

    private class AlertPermissionsDisabledWarningCell: UITableViewCell {
        override func updateConfiguration(using state: UICellConfigurationState) {
            super.updateConfiguration(using: state)

            let adjustViewForNarrowDisplay = bounds.width < 350

            var contentConfig = defaultContentConfiguration().updated(for: state)
            let titleImageAttachment = NSTextAttachment()
            titleImageAttachment.image = UIImage(systemName: "exclamationmark.triangle.fill")?.withTintColor(.white)
            let title = NSMutableAttributedString(string: NSLocalizedString(" Safety Notifications are OFF", comment: "Warning text for when Notifications or Critical Alerts Permissions is disabled"))
            let titleWithImage = NSMutableAttributedString(attachment: titleImageAttachment)
            titleWithImage.append(title)
            contentConfig.attributedText = titleWithImage
            contentConfig.textProperties.color = .white
            contentConfig.textProperties.font = .systemFont(ofSize: adjustViewForNarrowDisplay ? 16 : 18, weight: .bold)
            contentConfig.textProperties.adjustsFontSizeToFitWidth = true
            contentConfig.secondaryText = NSLocalizedString("Fix now by turning Notifications, Critical Alerts and Time Sensitive Notifications ON.", comment: "Secondary text for alerts disabled warning, which appears on the main status screen.")
            contentConfig.secondaryTextProperties.color = .white
            contentConfig.secondaryTextProperties.font = .systemFont(ofSize: adjustViewForNarrowDisplay ? 13 : 15)
            contentConfiguration = contentConfig

            var backgroundConfig = backgroundConfiguration?.updated(for: state)
            backgroundConfig?.backgroundColor = .critical
            backgroundConfiguration = backgroundConfig
            backgroundConfiguration?.backgroundInsets = NSDirectionalEdgeInsets(top: 0, leading: 10, bottom: 5, trailing: 10)
            backgroundConfiguration?.cornerRadius = 10

            let disclosureIndicator = UIImage(systemName: "chevron.right")?.withTintColor(.white)
            let imageView = UIImageView(image: disclosureIndicator)
            imageView.tintColor = .white
            accessoryView = imageView

            contentView.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 6, leading: 0, bottom: 13, trailing: 0)
        }
    }

    private class MuteAlertsWarningCell: UITableViewCell {
        var formattedAlertMuteEndTime: String = NSLocalizedString("Unknown", comment: "label for when the alert mute end time is unknown")

        override func updateConfiguration(using state: UICellConfigurationState) {
            super.updateConfiguration(using: state)

            let adjustViewForNarrowDisplay = bounds.width < 350

            var contentConfig = defaultContentConfiguration().updated(for: state)
            let title = NSMutableAttributedString(string: NSLocalizedString("All Alerts Muted", comment: "Warning text for when alerts are muted"))
            contentConfig.image = UIImage(systemName: "speaker.slash.fill")
            contentConfig.imageProperties.tintColor = .white
            contentConfig.attributedText = title
            contentConfig.textProperties.color = .white
            contentConfig.textProperties.font = .systemFont(ofSize: adjustViewForNarrowDisplay ? 16 : 18, weight: .bold)
            contentConfig.textProperties.adjustsFontSizeToFitWidth = true
            contentConfig.secondaryText = String(format: NSLocalizedString("Until %1$@", comment: "indication of when alerts will be unmuted (1: time when alerts unmute)"), formattedAlertMuteEndTime)
            contentConfig.secondaryTextProperties.color = .white
            contentConfig.secondaryTextProperties.font = .systemFont(ofSize: adjustViewForNarrowDisplay ? 13 : 15)
            contentConfiguration = contentConfig

            var backgroundConfig = backgroundConfiguration?.updated(for: state)
            backgroundConfig?.backgroundColor = .warning.withAlphaComponent(0.8)
            backgroundConfiguration = backgroundConfig
            backgroundConfiguration?.backgroundInsets = NSDirectionalEdgeInsets(top: 0, leading: 10, bottom: 5, trailing: 10)
            backgroundConfiguration?.cornerRadius = 10

            let unmuteIndicator = UIImage(systemName: "stop.circle")?.withTintColor(.white)
            let imageView = UIImageView(image: unmuteIndicator)
            imageView.tintColor = .white
            imageView.frame.size = CGSize(width: 30, height: 30)
            accessoryView = imageView

            contentView.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 6, leading: 0, bottom: 13, trailing: 0)
        }
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch Section(rawValue: indexPath.section)! {
        case .alertWarning:
            if alertPermissionsChecker.showWarning {
                let cell = tableView.dequeueReusableCell(withIdentifier: AlertPermissionsDisabledWarningCell.className, for: indexPath) as! AlertPermissionsDisabledWarningCell
                return cell
            } else {
                let cell = tableView.dequeueReusableCell(withIdentifier: MuteAlertsWarningCell.className, for: indexPath) as! MuteAlertsWarningCell
                cell.formattedAlertMuteEndTime = alertMuter.formattedEndTime
                return cell
            }
        case .hud:
            let cell = tableView.dequeueReusableCell(withIdentifier: HUDViewTableViewCell.className, for: indexPath) as! HUDViewTableViewCell
            hudView = cell.hudView

            return cell
        case .charts:
            let cell = tableView.dequeueReusableCell(withIdentifier: ChartTableViewCell.className, for: indexPath) as! ChartTableViewCell

            switch ChartRow(rawValue: indexPath.row)! {
            case .glucose:
                cell.setChartGenerator(generator: { [weak self] (frame) in
                    return self?.statusCharts.glucoseChart(withFrame: frame)?.view
                })
                cell.setTitleLabelText(label: NSLocalizedString("Glucose", comment: "The title of the glucose and prediction graph"))
                cell.doesNavigate = automaticDosingStatus.automaticDosingEnabled || !FeatureFlags.simpleBolusCalculatorEnabled
            case .iob:
                cell.setChartGenerator(generator: { [weak self] (frame) in
                    return self?.statusCharts.iobChart(withFrame: frame)?.view
                })
                cell.setTitleLabelText(label: NSLocalizedString("Active Insulin", comment: "The title of the Insulin On-Board graph"))
            case .dose:
                cell.setChartGenerator(generator: { [weak self] (frame) in
                    return self?.statusCharts.doseChart(withFrame: frame)?.view
                })
                cell.setTitleLabelText(label: NSLocalizedString("Insulin Delivery", comment: "The title of the insulin delivery graph"))
            case .cob:
                cell.setChartGenerator(generator: { [weak self] (frame) in
                    return self?.statusCharts.cobChart(withFrame: frame)?.view
                })
                cell.setTitleLabelText(label: NSLocalizedString("Active Carbohydrates", comment: "The title of the Carbs On-Board graph"))
            }

            self.tableView(tableView, updateSubtitleFor: cell, at: indexPath)

            let alpha: CGFloat = charts.gestureRecognizer?.state == .possible ? 1 : 0
            cell.setAlpha(alpha: alpha)

            cell.setSubtitleTextColor(color: UIColor.secondaryLabel)

            return cell
        case .status:

            func getTitleSubtitleCell() -> TitleSubtitleTableViewCell {
                let cell = tableView.dequeueReusableCell(withIdentifier: TitleSubtitleTableViewCell.className, for: indexPath) as! TitleSubtitleTableViewCell
                cell.selectionStyle = .none
                cell.backgroundColor = .secondarySystemBackground
                cell.titleLabel.text = nil
                cell.subtitleLabel.text = nil
                cell.accessoryView = nil
                return cell
            }

            switch StatusRow(rawValue: indexPath.row)! {
            case .status:
                switch statusRowMode {
                case .hidden:
                    let cell = getTitleSubtitleCell()
                    return cell
                case .scheduleOverrideEnabled(let override):
                    let cell = getTitleSubtitleCell()
                    switch override.context {
                    case .preMeal:
                        let symbolAttachment = NSTextAttachment()
                        symbolAttachment.image = UIImage(named: "Pre-Meal-symbol")?.withTintColor(.carbTintColor)

                        let attributedString = NSMutableAttributedString(attachment: symbolAttachment)
                        attributedString.append(NSAttributedString(string: NSLocalizedString(" Pre-meal Preset", comment: "Status row title for premeal override enabled (leading space is to separate from symbol)")))
                        cell.titleLabel.attributedText = attributedString
                    case .legacyWorkout:
                        let symbolAttachment = NSTextAttachment()
                        symbolAttachment.image = UIImage(named: "workout-symbol")?.withTintColor(.glucoseTintColor)

                        let attributedString = NSMutableAttributedString(attachment: symbolAttachment)
                        attributedString.append(NSAttributedString(string: NSLocalizedString(" Workout Preset", comment: "Status row title for workout override enabled (leading space is to separate from symbol)")))
                        cell.titleLabel.attributedText = attributedString
                    case .preset(let preset):
                        cell.titleLabel.text = String(format: NSLocalizedString("%@ %@", comment: "The format for an active custom preset. (1: preset symbol)(2: preset name)"), preset.symbol, preset.name)
                    case .custom:
                        cell.titleLabel.text = NSLocalizedString("Custom Preset", comment: "The title of the cell indicating a generic custom preset is enabled")
                    }

                    if override.isActive() {
                        switch override.duration {
                        case .finite:
                            let endTimeText = DateFormatter.localizedString(from: override.activeInterval.end, dateStyle: .none, timeStyle: .short)
                            cell.subtitleLabel.text = String(format: NSLocalizedString("until %@", comment: "The format for the description of a custom preset end date"), endTimeText)
                        case .indefinite:
                            cell.subtitleLabel.text = nil
                        }
                    } else {
                        let startTimeText = DateFormatter.localizedString(from: override.startDate, dateStyle: .none, timeStyle: .short)
                        cell.subtitleLabel.text = String(format: NSLocalizedString("starting at %@", comment: "The format for the description of a custom preset start date"), startTimeText)
                    }

                    return cell
                case .enactingBolus:
                    let cell = getTitleSubtitleCell()
                    cell.titleLabel.text = NSLocalizedString("Starting Bolus", comment: "The title of the cell indicating a bolus is being sent")

                    let indicatorView = UIActivityIndicatorView(style: .default)
                    indicatorView.startAnimating()
                    cell.accessoryView = indicatorView
                    return cell
                case .bolusing(let dose):
                    let progressCell = tableView.dequeueReusableCell(withIdentifier: BolusProgressTableViewCell.className, for: indexPath) as! BolusProgressTableViewCell
                    progressCell.selectionStyle = .none
                    progressCell.totalUnits = dose.programmedUnits
                    progressCell.tintColor = .insulinTintColor
                    progressCell.unit = HKUnit.internationalUnit()
                    progressCell.deliveredUnits = bolusProgressReporter?.progress.deliveredUnits
                    progressCell.backgroundColor = .secondarySystemBackground
                    return progressCell
                case .cancelingBolus:
                    let cell = getTitleSubtitleCell()
                    cell.titleLabel.text = NSLocalizedString("Canceling Bolus", comment: "The title of the cell indicating a bolus is being canceled")

                    let indicatorView = UIActivityIndicatorView(style: .default)
                    indicatorView.startAnimating()
                    cell.accessoryView = indicatorView
                    return cell
                case .pumpSuspended(let resuming):
                    let cell = getTitleSubtitleCell()
                    cell.titleLabel.text = NSLocalizedString("Insulin Suspended", comment: "The title of the cell indicating the pump is suspended")

                    if resuming {
                        let indicatorView = UIActivityIndicatorView(style: .default)
                        indicatorView.startAnimating()
                        cell.accessoryView = indicatorView
                    } else {
                        cell.subtitleLabel.text = NSLocalizedString("Tap to Resume", comment: "The subtitle of the cell displaying an action to resume insulin delivery")
                    }
                    cell.selectionStyle = .default
                    return cell
                case .onboardingSuspended:
                    let cell = tableView.dequeueReusableCell(withIdentifier: IconTitleSubtitleTableViewCell.className, for: indexPath) as! IconTitleSubtitleTableViewCell
                    cell.selectionStyle = .default
                    cell.backgroundColor = .secondarySystemBackground
                    cell.iconImageView.image = UIImage(systemName: "exclamationmark.circle.fill")
                    cell.iconImageView.tintColor = .warning
                    cell.iconImageView.contentMode = .scaleAspectFit
                    cell.iconImageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 28)
                    cell.titleLabel.text = NSLocalizedString("Setup Incomplete", comment: "The title of the cell indicating that onboarding is suspended")
                    cell.subtitleLabel.text = NSLocalizedString("Tap to Resume", comment: "The subtitle of the cell displaying an action to resume onboarding")
                    cell.accessoryView = nil
                    return cell
                case .recommendManualGlucoseEntry:
                    let cell = getTitleSubtitleCell()
                    cell.titleLabel.text = NSLocalizedString("No Recent Glucose", comment: "The title of the cell indicating that there is no recent glucose")
                    cell.subtitleLabel.text = NSLocalizedString("Tap to Add", comment: "The subtitle of the cell displaying an action to add a manually measurement glucose value")
                    cell.selectionStyle = .default
                    let imageView = UIImageView(image: UIImage(named: "drop.circle"))
                    imageView.tintColor = .glucoseTintColor
                    cell.accessoryView = imageView
                    return cell
                }
            }
        }
    }

    private func tableView(_ tableView: UITableView, updateSubtitleFor cell: ChartTableViewCell, at indexPath: IndexPath) {
        switch Section(rawValue: indexPath.section)! {
        case .charts:
            switch ChartRow(rawValue: indexPath.row)! {
            case .glucose:
                if let eventualGlucose = eventualGlucoseDescription {
                    cell.setSubtitleLabel(label: String(format: NSLocalizedString("Eventually %@", comment: "The subtitle format describing eventual glucose. (1: localized glucose value description)"), eventualGlucose))
                } else {
                    cell.setSubtitleLabel(label: nil)
                }
                cell.doesNavigate = automaticDosingStatus.automaticDosingEnabled || !FeatureFlags.simpleBolusCalculatorEnabled
            case .iob:
                if let currentIOB = currentIOBDescription {
                    cell.setSubtitleLabel(label: currentIOB)
                } else {
                    cell.setSubtitleLabel(label: nil)
                }
            case .dose:
                let integerFormatter = NumberFormatter()
                integerFormatter.maximumFractionDigits = 0

                if  let total = totalDelivery,
                    let totalString = integerFormatter.string(from: total) {
                    cell.setSubtitleLabel(label: String(format: NSLocalizedString("%@ U Total", comment: "The subtitle format describing total insulin. (1: localized insulin total)"), totalString))
                } else {
                    cell.setSubtitleLabel(label: nil)
                }
            case .cob:
                if let currentCOB = currentCOBDescription {
                    cell.setSubtitleLabel(label: currentCOB)
                } else {
                    cell.setSubtitleLabel(label: nil)
                }
            }
        case .hud, .status, .alertWarning:
            break
        }
    }

    // MARK: - UITableViewDelegate

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        switch Section(rawValue: indexPath.section)! {
        case .charts:
            // Compute the height of the HUD, defaulting to 70
            let hudHeight = ceil(hudView?.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).height ?? 74)
            var availableSize = max(tableView.bounds.width, tableView.bounds.height)
            availableSize -= (tableView.safeAreaInsets.top + tableView.safeAreaInsets.bottom + hudHeight)

            switch ChartRow(rawValue: indexPath.row)! {
            case .glucose:
                return max(106, 0.37 * availableSize)
            case .iob, .dose, .cob:
                return max(106, 0.21 * availableSize)
            }
        case .hud, .status, .alertWarning:
            return UITableView.automaticDimension
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        switch Section(rawValue: indexPath.section)! {
        case .alertWarning:
            if alertPermissionsChecker.showWarning {
                tableView.deselectRow(at: indexPath, animated: true)
                AlertPermissionsChecker.gotoSettings()
            } else {
                tableView.deselectRow(at: indexPath, animated: true)
                presentUnmuteAlertConfirmation()
            }
        case .hud:
            break
        case .status:
            switch StatusRow(rawValue: indexPath.row)! {
            case .status:
                tableView.deselectRow(at: indexPath, animated: true)

                switch statusRowMode {
                case .pumpSuspended(let resuming) where !resuming:
                    updateBannerAndHUDandStatusRows(statusRowMode: .pumpSuspended(resuming: true) , newSize: nil, animated: true)
                    deviceManager.pumpManager?.resumeDelivery() { (error) in
                        DispatchQueue.main.async {
                            if let error = error {
                                let alert = UIAlertController(with: error, title: NSLocalizedString("Failed to Resume Insulin Delivery", comment: "The alert title for a resume error"))
                                self.present(alert, animated: true, completion: nil)
                                if case .suspended = self.basalDeliveryState {
                                    self.updateBannerAndHUDandStatusRows(statusRowMode: .pumpSuspended(resuming: false), newSize: nil, animated: true)
                                }
                            } else {
                                self.updateBannerAndHUDandStatusRows(statusRowMode: self.determineStatusRowMode(), newSize: nil, animated: true)
                                self.refreshContext.update(with: .insulin)
                                self.log.debug("[reloadData] after manually resuming suspend")
                                self.reloadData()
                            }
                        }
                    }
                case .scheduleOverrideEnabled(let override):
                    switch override.context {
                    case .preMeal, .legacyWorkout:
                        break
                    default:
                        let vc = AddEditOverrideTableViewController(glucoseUnit: statusCharts.glucose.glucoseUnit)
                        vc.inputMode = .editOverride(override)
                        vc.delegate = self
                        show(vc, sender: tableView.cellForRow(at: indexPath))
                    }
                case .bolusing:
                    updateBannerAndHUDandStatusRows(statusRowMode: .cancelingBolus, newSize: nil, animated: true)
                    deviceManager.pumpManager?.cancelBolus() { (result) in
                        DispatchQueue.main.async {
                            switch result {
                            case .success:
                                // show user confirmation and actual delivery amount?
                                break
                            case .failure(let error):
                                self.presentErrorCancelingBolus(error)
                                if case .inProgress(let dose) = self.bolusState {
                                    self.updateBannerAndHUDandStatusRows(statusRowMode: .bolusing(dose: dose), newSize: nil, animated: true)
                                } else {
                                    self.updateBannerAndHUDandStatusRows(statusRowMode: .hidden, newSize: nil, animated: true)
                                }
                            }
                        }
                    }
                case .onboardingSuspended:
                    onboardingManager.resume()
                case .recommendManualGlucoseEntry:
                    presentBolusEntryView(enableManualGlucoseEntry: true)
                default:
                    break
                }
            }
        case .charts:
            switch ChartRow(rawValue: indexPath.row)! {
            case .glucose:
                if automaticDosingStatus.automaticDosingEnabled || !FeatureFlags.simpleBolusCalculatorEnabled {
                    performSegue(withIdentifier: PredictionTableViewController.className, sender: indexPath)
                }
            case .iob, .dose:
                performSegue(withIdentifier: InsulinDeliveryTableViewController.className, sender: indexPath)
            case .cob:
                performSegue(withIdentifier: CarbAbsorptionViewController.className, sender: indexPath)
            }
        }
    }

    private func presentUnmuteAlertConfirmation() {
        let title = NSLocalizedString("Unmute Alerts?", comment: "The alert title for unmute alert confirmation")
        let body = NSLocalizedString("Tap Unmute to resume sound for your alerts and alarms.", comment: "The alert body for unmute alert confirmation")
        let action = UIAlertAction(
            title: NSLocalizedString("Unmute", comment: "The title of the action used to unmute alerts"),
            style: .default) { _ in
                self.alertMuter.unmuteAlerts()
            }
        let alert = UIAlertController(title: title, message: body, preferredStyle: .alert)
        alert.addAction(action)
        alert.addCancelAction { _ in }
        present(alert, animated: true, completion: nil)
    }

    private func presentErrorCancelingBolus(_ error: (Error)) {
        log.error("Error Canceling Bolus: %@", error.localizedDescription)
        let title = NSLocalizedString("Error Canceling Bolus", comment: "The alert title for an error while canceling a bolus")
        let body = NSLocalizedString("Unable to stop the bolus in progress. Move your iPhone closer to the pump and try again. Check your insulin delivery history for details, and monitor your glucose closely.", comment: "The alert body for an error while canceling a bolus")
        let action = UIAlertAction(
            title: NSLocalizedString("com.loudnate.LoopKit.errorAlertActionTitle", value: "OK", comment: "The title of the action used to dismiss an error alert"), style: .default)
        let alert = UIAlertController(title: title, message: body, preferredStyle: .alert)
        alert.addAction(action)
        present(alert, animated: true, completion: nil)
    }

    // MARK: - Actions

    override func restoreUserActivityState(_ activity: NSUserActivity) {
        switch activity.activityType {
        case NSUserActivity.newCarbEntryActivityType:
            presentCarbEntryScreen(activity)
        default:
            break
        }
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        super.prepare(for: segue, sender: sender)

        var targetViewController = segue.destination

        if let navVC = targetViewController as? UINavigationController, let topViewController = navVC.topViewController {
            targetViewController = topViewController
        }

        switch targetViewController {
        case let vc as CarbAbsorptionViewController:
            vc.isOnboardingComplete = onboardingManager.isComplete
            vc.automaticDosingStatus = automaticDosingStatus
            vc.deviceManager = deviceManager
            vc.hidesBottomBarWhenPushed = true
        case let vc as InsulinDeliveryTableViewController:
            vc.deviceManager = deviceManager
            vc.hidesBottomBarWhenPushed = true
            vc.enableEntryDeletion = FeatureFlags.entryDeletionEnabled
            vc.headerValueLabelColor = .insulinTintColor
        case let vc as OverrideSelectionViewController:
            if deviceManager.loopManager.settings.futureOverrideEnabled() {
                vc.scheduledOverride = deviceManager.loopManager.settings.scheduleOverride
            }
            vc.presets = deviceManager.loopManager.settings.overridePresets
            vc.glucoseUnit = statusCharts.glucose.glucoseUnit
            vc.overrideHistory = deviceManager.loopManager.overrideHistory.getEvents()
            vc.delegate = self
        case let vc as PredictionTableViewController:
            vc.deviceManager = deviceManager
        default:
            break
        }
    }

    @IBAction func unwindFromEditing(_ segue: UIStoryboardSegue) {}

    @IBAction func unwindFromSettings(_ segue: UIStoryboardSegue) {}

    @IBAction func userTappedAddCarbs() {
        presentCarbEntryScreen(nil)
    }

    func presentCarbEntryScreen(_ activity: NSUserActivity?) {
        let navigationWrapper: UINavigationController
        if FeatureFlags.simpleBolusCalculatorEnabled && !automaticDosingStatus.automaticDosingEnabled {
            let viewModel = SimpleBolusViewModel(delegate: deviceManager, displayMealEntry: true)
            if let activity = activity {
                viewModel.restoreUserActivityState(activity)
            }
            let bolusEntryView = SimpleBolusView(viewModel: viewModel).environmentObject(deviceManager.displayGlucoseUnitObservable)
            let hostingController = DismissibleHostingController(rootView: bolusEntryView, isModalInPresentation: false)
            navigationWrapper = UINavigationController(rootViewController: hostingController)
            hostingController.navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: navigationWrapper, action: #selector(dismissWithAnimation))
        } else {
            let carbEntryViewController = UIStoryboard(name: "Main", bundle: Bundle(for: AppDelegate.self)).instantiateViewController(withIdentifier: "CarbEntryViewController") as! CarbEntryViewController

            carbEntryViewController.deviceManager = deviceManager
            carbEntryViewController.defaultAbsorptionTimes = deviceManager.carbStore.defaultAbsorptionTimes
            carbEntryViewController.preferredCarbUnit = deviceManager.carbStore.preferredUnit
            if let activity = activity {
                carbEntryViewController.restoreUserActivityState(activity)
            }
            navigationWrapper = UINavigationController(rootViewController: carbEntryViewController)
        }
        present(navigationWrapper, animated: true)
        deviceManager.analyticsServicesManager.didDisplayCarbEntryScreen()
    }

    @IBAction func presentBolusScreen() {
        presentBolusEntryView()
    }

    func presentBolusEntryView(enableManualGlucoseEntry: Bool = false) {
        let hostingController: DismissibleHostingController
        if FeatureFlags.simpleBolusCalculatorEnabled && !automaticDosingStatus.automaticDosingEnabled {
            let viewModel = SimpleBolusViewModel(delegate: deviceManager, displayMealEntry: false)
            let bolusEntryView = SimpleBolusView(viewModel: viewModel).environmentObject(deviceManager.displayGlucoseUnitObservable)
            hostingController = DismissibleHostingController(rootView: bolusEntryView, isModalInPresentation: false)
        } else {
            let viewModel = BolusEntryViewModel(delegate: deviceManager, screenWidth: UIScreen.main.bounds.width, isManualGlucoseEntryEnabled: enableManualGlucoseEntry)
            Task { @MainActor in
                await viewModel.generateRecommendationAndStartObserving()
            }
            viewModel.analyticsServicesManager = deviceManager.analyticsServicesManager
            let bolusEntryView = BolusEntryView(viewModel: viewModel).environmentObject(deviceManager.displayGlucoseUnitObservable)
            hostingController = DismissibleHostingController(rootView: bolusEntryView, isModalInPresentation: false)
        }
        let navigationWrapper = UINavigationController(rootViewController: hostingController)
        hostingController.navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: navigationWrapper, action: #selector(dismissWithAnimation))
        present(navigationWrapper, animated: true)
        deviceManager.analyticsServicesManager.didDisplayBolusScreen()
    }

    private func createPreMealButtonItem(selected: Bool, isEnabled: Bool) -> UIBarButtonItem {
        let item = UIBarButtonItem(image: UIImage.preMealImage(selected: selected), style: .plain, target: self, action: #selector(togglePreMealMode(_:)))
        item.accessibilityLabel = NSLocalizedString("Pre-Meal Targets", comment: "The label of the pre-meal mode toggle button")

        if selected {
            item.accessibilityTraits.insert(.selected)
            item.accessibilityHint = NSLocalizedString("Disables", comment: "The action hint of the workout mode toggle button when enabled")
        } else {
            item.accessibilityHint = NSLocalizedString("Enables", comment: "The action hint of the workout mode toggle button when disabled")
        }

        item.tintColor = UIColor.carbTintColor
        item.isEnabled = isEnabled

        return item
    }

    private func createWorkoutButtonItem(selected: Bool, isEnabled: Bool) -> UIBarButtonItem {
        let item = UIBarButtonItem(image: UIImage.workoutImage(selected: selected), style: .plain, target: self, action: #selector(toggleWorkoutMode(_:)))
        item.accessibilityLabel = NSLocalizedString("Workout Targets", comment: "The label of the workout mode toggle button")

        if selected {
            item.accessibilityTraits.insert(.selected)
            item.accessibilityHint = NSLocalizedString("Disables", comment: "The action hint of the workout mode toggle button when enabled")
        } else {
            item.accessibilityHint = NSLocalizedString("Enables", comment: "The action hint of the workout mode toggle button when disabled")
        }

        item.tintColor = UIColor.glucoseTintColor
        item.isEnabled = isEnabled

        return item
    }

    @IBAction func togglePreMealMode(_ sender: UIBarButtonItem) {
        if preMealMode == true {
            deviceManager.loopManager.mutateSettings { settings in
                settings.clearOverride(matching: .preMeal)
            }
        } else {
            let vc = UIAlertController(premealDurationSelectionHandler: { duration in
                let startDate = Date()

                guard self.workoutMode != true else {
                    // allow cell animation when switching between presets
                    self.deviceManager.loopManager.mutateSettings { settings in
                        settings.clearOverride()
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        self.deviceManager.loopManager.mutateSettings { settings in
                            settings.enablePreMealOverride(at: startDate, for: duration)
                        }
                    }
                    return
                }

                self.deviceManager.loopManager.mutateSettings { settings in
                    settings.enablePreMealOverride(at: startDate, for: duration)
                }
            })

            present(vc, animated: true, completion: nil)
        }
    }

    @IBAction func toggleWorkoutMode(_ sender: UIBarButtonItem) {
        if workoutMode == true {
            deviceManager.loopManager.mutateSettings { settings in
                settings.clearOverride()
            }
        } else {
            if FeatureFlags.sensitivityOverridesEnabled {
                performSegue(withIdentifier: OverrideSelectionViewController.className, sender: toolbarItems![6])
            } else {
                let vc = UIAlertController(workoutDurationSelectionHandler: { duration in
                    let startDate = Date()

                    guard self.preMealMode != true else {
                        // allow cell animation when switching between presets
                        self.deviceManager.loopManager.mutateSettings { settings in
                            settings.clearOverride(matching: .preMeal)
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            self.deviceManager.loopManager.mutateSettings { settings in
                                settings.enableLegacyWorkoutOverride(at: startDate, for: duration)
                            }
                        }
                        return
                    }

                    self.deviceManager.loopManager.mutateSettings { settings in
                        settings.enableLegacyWorkoutOverride(at: startDate, for: duration)
                    }
                })

                present(vc, animated: true, completion: nil)
            }
        }
    }

    @IBAction func onSettingsTapped(_ sender: UIBarButtonItem) {
        presentSettings()
    }

    private func presentSettings() {
        let deletePumpDataFunc: () -> PumpManagerViewModel.DeleteTestingDataFunc? = { [weak self] in
            (self?.deviceManager.pumpManager is TestingPumpManager) ? {
                [weak self] in self?.deviceManager.deleteTestingPumpData()
                } : nil
        }
        let deleteCGMDataFunc: () -> CGMManagerViewModel.DeleteTestingDataFunc? = { [weak self] in
            (self?.deviceManager.cgmManager is TestingCGMManager) ? {
                [weak self] in self?.deviceManager.deleteTestingCGMData()
                } : nil
        }
        let pumpViewModel = PumpManagerViewModel(
            image: { [weak self] in self?.deviceManager.pumpManager?.smallImage },
            name: { [weak self] in self?.deviceManager.pumpManager?.localizedTitle ?? "" },
            isSetUp: { [weak self] in self?.deviceManager.pumpManager?.isOnboarded == true },
            availableDevices: deviceManager.availablePumpManagers,
            deleteTestingDataFunc: deletePumpDataFunc,
            onTapped: { [weak self] in
                self?.onPumpTapped()
            },
            didTapAddDevice: { [weak self] in
                self?.addPumpManager(withIdentifier: $0.identifier)
        })

        let cgmViewModel = CGMManagerViewModel(
            image: {[weak self] in (self?.deviceManager.cgmManager as? DeviceManagerUI)?.smallImage },
            name: {[weak self] in self?.deviceManager.cgmManager?.localizedTitle ?? "" },
            isSetUp: {[weak self] in self?.deviceManager.cgmManager?.isOnboarded == true },
            availableDevices: deviceManager.availableCGMManagers,
            deleteTestingDataFunc: deleteCGMDataFunc,
            onTapped: { [weak self] in
                self?.onCGMTapped()
            },
            didTapAddDevice: { [weak self] in
                self?.addCGMManager(withIdentifier: $0.identifier)
        })
        let servicesViewModel = ServicesViewModel(showServices: FeatureFlags.includeServicesInSettingsEnabled,
                                                  availableServices: { [weak self] in self?.deviceManager.servicesManager.availableServices ?? [] },
                                                  activeServices: { [weak self] in self?.deviceManager.servicesManager.activeServices ?? [] },
                                                  delegate: self)
        let versionUpdateViewModel = VersionUpdateViewModel(supportManager: supportManager, guidanceColors: .default)
        let viewModel = SettingsViewModel(alertPermissionsChecker: alertPermissionsChecker,
                                          alertMuter: alertMuter,
                                          versionUpdateViewModel: versionUpdateViewModel,
                                          pumpManagerSettingsViewModel: pumpViewModel,
                                          cgmManagerSettingsViewModel: cgmViewModel,
                                          servicesViewModel: servicesViewModel,
                                          criticalEventLogExportViewModel: CriticalEventLogExportViewModel(exporterFactory: deviceManager.criticalEventLogExportManager),
                                          therapySettings: { [weak self] in self?.deviceManager.loopManager.therapySettings ?? TherapySettings() },
                                          sensitivityOverridesEnabled: FeatureFlags.sensitivityOverridesEnabled,
                                          initialDosingEnabled: deviceManager.loopManager.settings.dosingEnabled,
                                          isClosedLoopAllowed: automaticDosingStatus.$isAutomaticDosingAllowed,
                                          automaticDosingStrategy: deviceManager.loopManager.settings.automaticDosingStrategy,
                                          availableSupports: supportManager.availableSupports,
                                          isOnboardingComplete: onboardingManager.isComplete,
                                          therapySettingsViewModelDelegate: deviceManager,
                                          delegate: self)
        let hostingController = DismissibleHostingController(
            rootView: SettingsView(viewModel: viewModel, localizedAppNameAndVersion: supportManager.localizedAppNameAndVersion)
                .environmentObject(deviceManager.displayGlucoseUnitObservable)
                .environment(\.appName, Bundle.main.bundleDisplayName),
            isModalInPresentation: false)
        present(hostingController, animated: true)
    }

    private func onPumpTapped() {
        guard var settingsViewController = deviceManager.pumpManager?.settingsViewController(bluetoothProvider: deviceManager.bluetoothProvider, colorPalette: .default, allowDebugFeatures: FeatureFlags.allowDebugFeatures, allowedInsulinTypes: deviceManager.allowedInsulinTypes) else {
            // assert?
            return
        }
        settingsViewController.pumpManagerOnboardingDelegate = deviceManager
        settingsViewController.completionDelegate = self
        show(settingsViewController, sender: self)
    }

    private func onCGMTapped() {
        guard let cgmManager = deviceManager.cgmManager as? CGMManagerUI else {
            // assert?
            return
        }

        var settings = cgmManager.settingsViewController(bluetoothProvider: deviceManager.bluetoothProvider, displayGlucoseUnitObservable: deviceManager.displayGlucoseUnitObservable, colorPalette: .default, allowDebugFeatures: FeatureFlags.allowDebugFeatures)
        settings.cgmManagerOnboardingDelegate = deviceManager
        settings.completionDelegate = self
        show(settings, sender: self)
    }

    private func automaticDosingStatusChanged(_ automaticDosingEnabled: Bool) {
        updatePreMealModeAvailability(automaticDosingEnabled: automaticDosingEnabled)
        hudView?.loopCompletionHUD.loopIconClosed = automaticDosingEnabled
        hudView?.loopCompletionHUD.closedLoopDisallowedLocalizedDescription = deviceManager.closedLoopDisallowedLocalizedDescription
    }

    // MARK: - HUDs

    @IBOutlet var hudView: StatusBarHUDView? {
        didSet {
            guard let hudView = hudView, hudView != oldValue else {
                return
            }

            let statusTapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(showLoopCompletionMessage(_:)))
            hudView.loopCompletionHUD.addGestureRecognizer(statusTapGestureRecognizer)
            hudView.loopCompletionHUD.accessibilityHint = NSLocalizedString("Shows last loop error", comment: "Loop Completion HUD accessibility hint")

            let pumpStatusTapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(pumpStatusTapped(_:)))
            hudView.pumpStatusHUD.addGestureRecognizer(pumpStatusTapGestureRecognizer)

            let cgmStatusTapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(cgmStatusTapped(_:)))
            hudView.cgmStatusHUD.addGestureRecognizer(cgmStatusTapGestureRecognizer)

            configurePumpManagerHUDViews()
            configureCGMManagerHUDViews()

            // when HUD view is initialized, update loop completion HUD (e.g., icon and last loop completed)
            hudView.loopCompletionHUD.stateColors = .loopStatus
            hudView.loopCompletionHUD.loopIconClosed = automaticDosingStatus.automaticDosingEnabled
            hudView.loopCompletionHUD.lastLoopCompleted = deviceManager.loopManager.lastLoopCompleted

            hudView.cgmStatusHUD.stateColors = .cgmStatus
            hudView.cgmStatusHUD.tintColor = .label
            hudView.pumpStatusHUD.stateColors = .pumpStatus
            hudView.pumpStatusHUD.tintColor = .insulinTintColor

            refreshContext.update(with: .status)
            log.debug("[reloadData] after hudView loaded")
            reloadData()
        }
    }

    private func configurePumpManagerHUDViews() {
        if let hudView = hudView {
            hudView.removePumpManagerProvidedView()
            if let pumpManagerHUDProvider = deviceManager.pumpManagerHUDProvider {
                if let view = pumpManagerHUDProvider.createHUDView() {
                    addPumpManagerViewToHUD(view)
                }
                pumpManagerHUDProvider.visible = active && onscreen
            }
            hudView.pumpStatusHUD.presentStatusHighlight(deviceManager.pumpStatusHighlight)
            hudView.pumpStatusHUD.lifecycleProgress = deviceManager.pumpLifecycleProgress
        }
    }

    private func configureCGMManagerHUDViews() {
        if let hudView = hudView {
            hudView.cgmStatusHUD.presentStatusHighlight(deviceManager.cgmStatusHighlight)
            hudView.cgmStatusHUD.lifecycleProgress = deviceManager.cgmLifecycleProgress
        }
    }

    private func addPumpManagerViewToHUD(_ view: BaseHUDView) {
        if let hudView = hudView {
            view.stateColors = .pumpStatus
            hudView.addPumpManagerProvidedHUDView(view)
        }
    }

    @objc private func showLoopCompletionMessage(_: Any) {
        guard let loopCompletionMessage = hudView?.loopCompletionHUD.loopCompletionMessage else { return }
        presentLoopCompletionMessage(title: loopCompletionMessage.title, message: loopCompletionMessage.message)
    }

    private func presentLoopCompletionMessage(title: String, message: String) {
        let action = UIAlertAction(title: NSLocalizedString("Dismiss", comment: "The button label of the action used to dismiss an error alert"),
                                   style: .default)
        let alertController = UIAlertController(title: title,
                                                message: message,
                                                preferredStyle: .alert)
        alertController.addAction(action)
        present(alertController, animated: true)
    }

    @objc private func showLastError(_: Any) {
        let error: Error?
        // First, check whether we have a device error after the most recent completion date
        if let deviceError = deviceManager.lastError,
            deviceError.date > (hudView?.loopCompletionHUD.lastLoopCompleted ?? .distantPast)
        {
            error = deviceError.error
        } else if let lastLoopError = lastLoopError {
            error = lastLoopError
        } else {
            error = nil
        }
        if let error = error {
            let alertController = UIAlertController(with: error)
            let manualLoopAction = UIAlertAction(title: NSLocalizedString("Retry", comment: "The button text for attempting a manual loop"), style: .default, handler: { _ in
                self.deviceManager.refreshDeviceData()
            })
            alertController.addAction(manualLoopAction)
            present(alertController, animated: true)
        }
    }

    @objc private func pumpStatusTapped(_ sender: UIGestureRecognizer) {
        if let pumpStatusView = sender.view as? PumpStatusHUDView {
            executeHUDTapAction(deviceManager.didTapOnPumpStatus(pumpStatusView.pumpManagerProvidedHUD))
        }
    }

    @objc private func cgmStatusTapped( _ sender: UIGestureRecognizer) {
        executeHUDTapAction(deviceManager.didTapOnCGMStatus())
    }

    private func executeHUDTapAction(_ action: HUDTapAction?) {
        guard let action = action else {
            return
        }

        switch action {
        case .presentViewController(let vc):
            var completionNotifyingVC = vc
            completionNotifyingVC.completionDelegate = self
            present(completionNotifyingVC, animated: true, completion: nil)
        case .openAppURL(let url):
            UIApplication.shared.open(url)
        case .setupNewCGM:
            addNewCGMManager()
        case .setupNewPump:
            addNewPumpManager()
        default:
            return
        }
    }

    private func addNewPumpManager() {
        let availablePumpManagers = deviceManager.availablePumpManagers

        switch availablePumpManagers.count {
        case 1:
            if let availablePumpManager = availablePumpManagers.first {
                addPumpManager(withIdentifier: availablePumpManager.identifier)
            }
        default:
            let alert = UIAlertController(availablePumpManagers: availablePumpManagers) { [weak self] (identifier) in
                self?.addPumpManager(withIdentifier: identifier)
            }
            alert.addCancelAction { _ in }
            present(alert, animated: true, completion: nil)
        }
    }

    private func addNewCGMManager() {
        let availableCGMManagers = deviceManager.availableCGMManagers

        switch availableCGMManagers.count {
        case 1:
            if let availableCGMManager = availableCGMManagers.first {
                addCGMManager(withIdentifier: availableCGMManager.identifier)
            }
        default:
            let alert = UIAlertController(availableCGMManagers: availableCGMManagers) { [weak self] identifier in
                self?.addCGMManager(withIdentifier: identifier)
            }
            alert.addCancelAction { _ in }
            present(alert, animated: true, completion: nil)
        }
    }


    // MARK: - Debug Scenarios and Simulated Core Data

    var lastOrientation: UIDeviceOrientation?
    var rotateCount = 0
    let maxRotationsToTrigger = 6
    var rotateTimer: Timer?
    let rotateTimerTimeout = TimeInterval.seconds(2)
    private func maybeOpenDebugMenu() {
        guard FeatureFlags.allowDebugFeatures else {
            return
        }
        // Opens the debug menu if you rotate the phone 6 times (or back & forth 3 times), each rotation within 2 secs.
        if lastOrientation != UIDevice.current.orientation {
            if UIDevice.current.orientation == .portrait && rotateCount >= maxRotationsToTrigger-1 {
                presentDebugMenu()
                rotateCount = 0
                rotateTimer?.invalidate()
                rotateTimer = nil
            } else {
                rotateTimer?.invalidate()
                rotateTimer = Timer.scheduledTimer(withTimeInterval: rotateTimerTimeout, repeats: false) { [weak self] _ in
                    self?.rotateCount = 0
                    self?.rotateTimer?.invalidate()
                    self?.rotateTimer = nil
                }
                rotateCount += 1
            }
        }
        lastOrientation = UIDevice.current.orientation
    }

    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        guard FeatureFlags.allowDebugFeatures else {
            return
        }
        if motion == .motionShake {
            presentDebugMenu()
        }
    }

    private func presentDebugMenu() {
        guard FeatureFlags.allowDebugFeatures else {
            return
        }

        let actionSheet = UIAlertController(title: "Debug", message: nil, preferredStyle: .actionSheet)
        if FeatureFlags.scenariosEnabled {
            actionSheet.addAction(UIAlertAction(title: "Scenarios", style: .default) { _ in
                DispatchQueue.main.async {
                    self.presentScenarioSelector()
                }
            })
        }
        if FeatureFlags.simulatedCoreDataEnabled {
            actionSheet.addAction(UIAlertAction(title: "Simulated Core Data", style: .default) { _ in
                self.presentSimulatedCoreDataMenu()
            })
        }
        actionSheet.addAction(UIAlertAction(title: "Remove Exports Directory", style: .default) { _ in
            if let error = self.deviceManager.removeExportsDirectory() {
                self.presentError(error)
            }
        })
        if FeatureFlags.mockTherapySettingsEnabled {
            actionSheet.addAction(UIAlertAction(title: "Mock Therapy Settings", style: .default) { _ in
                let therapySettings = TherapySettings.mockTherapySettings
                self.deviceManager.loopManager.mutateSettings { settings in
                    settings.glucoseTargetRangeSchedule = therapySettings.glucoseTargetRangeSchedule
                    settings.preMealTargetRange = therapySettings.correctionRangeOverrides?.preMeal
                    settings.legacyWorkoutTargetRange = therapySettings.correctionRangeOverrides?.workout
                    settings.suspendThreshold = therapySettings.suspendThreshold
                    settings.maximumBolus = therapySettings.maximumBolus
                    settings.maximumBasalRatePerHour = therapySettings.maximumBasalRatePerHour
                    settings.insulinSensitivitySchedule = therapySettings.insulinSensitivitySchedule
                    settings.carbRatioSchedule = therapySettings.carbRatioSchedule
                    settings.basalRateSchedule = therapySettings.basalRateSchedule
                    settings.defaultRapidActingModel = therapySettings.defaultRapidActingModel
                }
            })
        }
        actionSheet.addAction(UIAlertAction(title: "Crash the App", style: .destructive) { _ in
            fatalError("Test Crash")
        })
        actionSheet.addAction(UIAlertAction(title: "Delete CGM Manager", style: .destructive) { _ in
            self.deviceManager.cgmManager?.delete() { }
        })

        actionSheet.addCancelAction()
        present(actionSheet, animated: true)
    }

    private func presentScenarioSelector() {
        guard FeatureFlags.scenariosEnabled else {
            fatalError("\(#function) should be invoked only when scenarios are enabled")
        }

        let vc = TestingScenariosTableViewController(scenariosManager: testingScenariosManager)
        present(UINavigationController(rootViewController: vc), animated: true)
    }

    private func addScenarioStepGestureRecognizers() {
        if FeatureFlags.scenariosEnabled {
            let leftSwipe = UISwipeGestureRecognizer(target: self, action: #selector(stepActiveScenarioForward))
            leftSwipe.direction = .left
            let rightSwipe = UISwipeGestureRecognizer(target: self, action: #selector(stepActiveScenarioBackward))
            rightSwipe.direction = .right

            if let toolBar = navigationController?.toolbar {
                toolBar.addGestureRecognizer(leftSwipe)
                toolBar.addGestureRecognizer(rightSwipe)
            }
        }
    }

    private func presentSimulatedCoreDataMenu() {
        guard FeatureFlags.simulatedCoreDataEnabled else {
            fatalError("\(#function) should be invoked only when simulated core data is enabled")
        }

        let actionSheet = UIAlertController(title: "Simulated Core Data", message: nil, preferredStyle: .actionSheet)
        actionSheet.addAction(UIAlertAction(title: "Generate Simulated Historical", style: .default) { _ in
            self.presentConfirmation(actionSheetMessage: "All existing Core Data older than 24 hours will be purged before generating new simulated historical Core Data. Are you sure?", actionTitle: "Generate Simulated Historical") {
                self.generateSimulatedHistoricalCoreData()
            }
        })
        actionSheet.addAction(UIAlertAction(title: "Purge Historical", style: .default) { _ in
            self.presentConfirmation(actionSheetMessage: "All existing Core Data older than 24 hours will be purged. Are you sure?", actionTitle: "Purge Historical") {
                self.purgeHistoricalCoreData()
            }
        })
        actionSheet.addCancelAction()
        present(actionSheet, animated: true)
    }

    private func generateSimulatedHistoricalCoreData() {
        guard FeatureFlags.simulatedCoreDataEnabled else {
            fatalError("\(#function) should be invoked only when simulated core data is enabled")
        }

        presentActivityIndicator(title: "Simulated Core Data", message: "Generating simulated historical...") { dismissActivityIndicator in
            self.deviceManager.purgeHistoricalCoreData() { error in
                DispatchQueue.main.async {
                    if let error = error {
                        dismissActivityIndicator()
                        self.presentError(error)
                        return
                    }

                    self.deviceManager.generateSimulatedHistoricalCoreData() { error in
                        DispatchQueue.main.async {
                            dismissActivityIndicator()
                            if let error = error {
                                self.presentError(error)
                            }
                        }
                    }
                }
            }
        }
    }

    private func purgeHistoricalCoreData() {
        guard FeatureFlags.simulatedCoreDataEnabled else {
            fatalError("\(#function) should be invoked only when simulated core data is enabled")
        }

        presentActivityIndicator(title: "Simulated Core Data", message: "Purging historical...") { dismissActivityIndicator in
            self.deviceManager.purgeHistoricalCoreData() { error in
                DispatchQueue.main.async {
                    dismissActivityIndicator()
                    if let error = error {
                        self.presentError(error)
                    }
                }
            }
        }
    }

    private func presentConfirmation(actionSheetMessage: String, actionTitle: String, handler: @escaping () -> Void) {
        let actionSheet = UIAlertController(title: nil, message: actionSheetMessage, preferredStyle: .actionSheet)
        actionSheet.addAction(UIAlertAction(title: actionTitle, style: .destructive) { _ in handler() })
        actionSheet.addCancelAction()
        present(actionSheet, animated: true)
    }

    private func presentError(_ error: Error, handler: (() -> Void)? = nil) {
        let alert = UIAlertController(title: "Error", message: "An error occurred: \(String(describing: error))", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in handler?() })
        present(alert, animated: true)
    }

    private func presentActivityIndicator(title: String, message: String, completion: @escaping (@escaping () -> Void) -> Void) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addActivityIndicator()
        present(alert, animated: true) { completion { alert.dismiss(animated: true) } }
    }

    @objc private func stepActiveScenarioForward() {
        testingScenariosManager.stepActiveScenarioForward { _ in }
    }

    @objc private func stepActiveScenarioBackward() {
        testingScenariosManager.stepActiveScenarioBackward { _ in }
    }
}

extension UIAlertController {
    func addActivityIndicator() {
        let frame = CGRect(x: 0, y: 0, width: 40, height: 40)
        let activityIndicator = UIActivityIndicatorView(frame: frame)
        activityIndicator.style = .default
        activityIndicator.startAnimating()
        let viewController = UIViewController()
        viewController.preferredContentSize = frame.size
        viewController.view.addSubview(activityIndicator)
        setValue(viewController, forKey: "contentViewController")
    }
}

extension StatusTableViewController: CompletionDelegate {
    func completionNotifyingDidComplete(_ object: CompletionNotifying) {
        if let vc = object as? UIViewController {
            if presentedViewController === vc {
                dismiss(animated: true, completion: nil)
            } else {
                vc.dismiss(animated: true, completion: nil)
            }
        }
    }
}

extension StatusTableViewController: PumpManagerStatusObserver {
    func pumpManager(_ pumpManager: PumpManager, didUpdate status: PumpManagerStatus, oldStatus: PumpManagerStatus) {
        dispatchPrecondition(condition: .onQueue(.main))
        log.default("PumpManager:%{public}@ did update status", String(describing: type(of: pumpManager)))

        basalDeliveryState = status.basalDeliveryState
        bolusState = status.bolusState

        refreshContext.update(with: .status)
        reloadData(animated: true)
    }
}

extension StatusTableViewController: CGMManagerStatusObserver {
    func cgmManager(_ manager: CGMManager, didUpdate status: CGMManagerStatus) {
        refreshContext.update(with: .status)
        reloadData(animated: true)
    }
}

extension StatusTableViewController: DoseProgressObserver {
    func doseProgressReporterDidUpdate(_ doseProgressReporter: DoseProgressReporter) {

        updateBolusProgress()

        if doseProgressReporter.progress.isComplete {
            // Bolus ended
            self.bolusProgressReporter = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: {
                self.bolusState = .noBolus
                self.reloadData(animated: true)
            })
        }
    }
}

extension StatusTableViewController: OverrideSelectionViewControllerDelegate {
    func overrideSelectionViewController(_ vc: OverrideSelectionViewController, didUpdatePresets presets: [TemporaryScheduleOverridePreset]) {
        deviceManager.loopManager.mutateSettings { settings in
            settings.overridePresets = presets
        }
    }

    func overrideSelectionViewController(_ vc: OverrideSelectionViewController, didConfirmOverride override: TemporaryScheduleOverride) {
        deviceManager.loopManager.mutateSettings { settings in
            settings.scheduleOverride = override
        }
    }

    func overrideSelectionViewController(_ vc: OverrideSelectionViewController, didConfirmPreset preset: TemporaryScheduleOverridePreset) {
        let intent = EnableOverridePresetIntent()
        intent.overrideName = preset.name

        let interaction = INInteraction(intent: intent, response: nil)
        interaction.identifier = preset.id.uuidString
        interaction.groupIdentifier = preset.name
        interaction.donate { (error) in
            if let error = error {
                os_log(.error, "Failed to donate intent: %{public}@", String(describing: error))
            }
        }
        deviceManager.loopManager.mutateSettings { settings in
            settings.scheduleOverride = preset.createOverride(enactTrigger: .local)
        }
    }

    func overrideSelectionViewController(_ vc: OverrideSelectionViewController, didCancelOverride override: TemporaryScheduleOverride) {
        deviceManager.loopManager.mutateSettings { settings in
            settings.scheduleOverride = nil
        }
    }
}

extension StatusTableViewController: AddEditOverrideTableViewControllerDelegate {
    func addEditOverrideTableViewController(_ vc: AddEditOverrideTableViewController, didSaveOverride override: TemporaryScheduleOverride) {
        deviceManager.loopManager.mutateSettings { settings in
            settings.scheduleOverride = override
        }
    }

    func addEditOverrideTableViewController(_ vc: AddEditOverrideTableViewController, didCancelOverride override: TemporaryScheduleOverride) {
        deviceManager.loopManager.mutateSettings { settings in
            settings.scheduleOverride = nil
        }
    }
}

extension StatusTableViewController {
    fileprivate func addCGMManager(withIdentifier identifier: String) {
        switch deviceManager.setupCGMManager(withIdentifier: identifier) {
        case .failure(let error):
            log.error("Failure to setup CGM manager with identifier '%{public}@': %{public}@", identifier, String(describing: error))
        case .success(let success):
            switch success {
            case .userInteractionRequired(var setupViewController):
                setupViewController.cgmManagerOnboardingDelegate = deviceManager
                setupViewController.completionDelegate = self
                show(setupViewController, sender: self)
            case .createdAndOnboarded:
                log.default("CGM manager with identifier '%{public}@' created and onboarded", identifier)
            }
        }
    }
}

extension StatusTableViewController {
    fileprivate func addPumpManager(withIdentifier identifier: String) {
        guard let maximumBasalRate = deviceManager.loopManager.settings.maximumBasalRatePerHour,
              let maxBolus = deviceManager.loopManager.settings.maximumBolus,
              let basalSchedule = deviceManager.loopManager.settings.basalRateSchedule else
        {
            log.error("Failure to setup pump manager: incomplete settings")
            return
        }
        
        let settings = PumpManagerSetupSettings(maxBasalRateUnitsPerHour: maximumBasalRate,
                                                maxBolusUnits: maxBolus,
                                                basalSchedule: basalSchedule)
        switch deviceManager.setupPumpManagerUI(withIdentifier: identifier, initialSettings: settings) {
        case .failure(let error):
            log.error("Failure to setup pump manager with identifier '%{public}@': %{public}@", identifier, String(describing: error))
        case .success(let success):
            switch success {
            case .userInteractionRequired(var setupViewController):
                setupViewController.pumpManagerOnboardingDelegate = deviceManager
                setupViewController.completionDelegate = self
                show(setupViewController, sender: self)
            case .createdAndOnboarded:
                log.default("Pump manager with identifier '%{public}@' created and onboarded", identifier)
            }
        }
    }
}

extension StatusTableViewController: BluetoothObserver {
    func bluetoothDidUpdateState(_ state: BluetoothState) {
        refreshContext.update(with: .status)
        reloadData(animated: true)
    }
}

// MARK: - SettingsViewModel delegation
extension StatusTableViewController: SettingsViewModelDelegate {
    var closedLoopDescriptiveText: String? {
        return deviceManager.closedLoopDisallowedLocalizedDescription
    }

    func dosingEnabledChanged(_ value: Bool) {
        deviceManager.loopManager.mutateSettings { settings in
            settings.dosingEnabled = value
        }
    }
    
    func dosingStrategyChanged(_ strategy: AutomaticDosingStrategy) {
        self.deviceManager.loopManager.mutateSettings { settings in
            settings.automaticDosingStrategy = strategy
        }
    }

    func didTapIssueReport() {
        // TODO: this dismiss here is temporary, until we know exactly where
        // we want this screen to belong in the navigation flow
        dismiss(animated: true) {
            let vc = CommandResponseViewController.generateDiagnosticReport(deviceManager: self.deviceManager)
            vc.title = NSLocalizedString("Issue Report", comment: "The view controller title for the issue report screen")
            self.show(vc, sender: nil)
        }
    }
}

// MARK: - Services delegation

extension StatusTableViewController: ServicesViewModelDelegate {
    func addService(withIdentifier identifier: String) {
        switch deviceManager.servicesManager.setupService(withIdentifier: identifier) {
        case .failure(let error):
            log.default("Failure to setup service with identifier '%{public}@': %{public}@", identifier, String(describing: error))
        case .success(let success):
            switch success {
            case .userInteractionRequired(var setupViewController):
                setupViewController.serviceOnboardingDelegate = deviceManager.servicesManager
                setupViewController.completionDelegate = self
                show(setupViewController, sender: self)
            case .createdAndOnboarded:
                log.default("Service with identifier '%{public}@' created and onboarded", identifier)
            }
        }
    }

    func gotoService(withIdentifier identifier: String) {
        guard let serviceUI = deviceManager.servicesManager.activeServices.first(where: { $0.serviceIdentifier == identifier }) as? ServiceUI else {
            return
        }
        showServiceSettings(serviceUI)
    }

    fileprivate func showServiceSettings(_ serviceUI: ServiceUI) {
        var settingsViewController = serviceUI.settingsViewController(colorPalette: .default)
        settingsViewController.serviceOnboardingDelegate = deviceManager.servicesManager
        settingsViewController.completionDelegate = self
        show(settingsViewController, sender: self)
    }
}
