//
//  StatusTableViewController.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 9/6/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

import UIKit
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
import LoopAlgorithm

private extension RefreshContext {
    static let all: Set<RefreshContext> = [.status, .glucose, .insulin, .carbs, .targets]
}

@MainActor
final class StatusTableViewController: LoopChartsTableViewController {

    private let log = OSLog(category: "StatusTableViewController")

    lazy var carbFormatter: QuantityFormatter = QuantityFormatter(for: .gram)
    
    lazy var insulinFormatter: QuantityFormatter = {
        let formatter = QuantityFormatter(for: .internationalUnit)
        formatter.numberFormatter.maximumFractionDigits = 3
        return formatter
    }()

    var onboardingManager: OnboardingManager!

    var testingScenariosManager: TestingScenariosManager!

    var alertPermissionsChecker: AlertPermissionsChecker!

    var settingsManager: SettingsManager!

    var temporaryPresetsManager: TemporaryPresetsManager!

    var loopManager: LoopDataManager!

    var alertMuter: AlertMuter!

    var supportManager: SupportManager!

    var diagnosticReportGenerator: DiagnosticReportGenerator!

    var analyticsServicesManager: AnalyticsServicesManager?

    var servicesManager: ServicesManager!

    var simulatedData: SimulatedData!

    var carbStore: CarbStore!

    var doseStore: DoseStore!

    var criticalEventLogExportManager: CriticalEventLogExportManager!
    
    var statusTableViewModel: StatusTableViewModel!
    
    lazy private var cancellables = Set<AnyCancellable>()
    
    var statusBarBackgroundView: UIView?

    override func viewDidLoad() {

        super.viewDidLoad()
      
        statusTableViewModel.settingsViewModel.delegate = self
        statusTableViewModel.settingsViewModel.servicesViewModel.delegate = self
        statusTableViewModel.settingsViewModel.pumpManagerSettingsViewModel.didTap = { [weak self] in
            self?.onPumpTapped()
        }
        statusTableViewModel.settingsViewModel.pumpManagerSettingsViewModel.didTapAdd = { [weak self] in
            self?.addPumpManager(withIdentifier: $0.identifier)
        }
        statusTableViewModel.settingsViewModel.cgmManagerSettingsViewModel.didTap = { [weak self] in
            self?.onCGMTapped()
        }
        statusTableViewModel.settingsViewModel.cgmManagerSettingsViewModel.didTapAdd = { [weak self] in
            self?.addCGMManager(withIdentifier: $0.identifier)
        }

        tableView.register(BolusProgressTableViewCell.nib(), forCellReuseIdentifier: BolusProgressTableViewCell.className)
        tableView.register(InsulinSuspendedTableViewCell.nib(), forCellReuseIdentifier: InsulinSuspendedTableViewCell.className)
        tableView.register(RecentGlucoseTableViewCell.nib(), forCellReuseIdentifier: RecentGlucoseTableViewCell.className)

        if FeatureFlags.predictedGlucoseChartClampEnabled {
            statusCharts.glucose.glucoseDisplayRange = LoopConstants.glucoseChartDefaultDisplayBoundClamped
        } else {
            statusCharts.glucose.glucoseDisplayRange = LoopConstants.glucoseChartDefaultDisplayBound
        }

        registerPumpManager()
        registerCGMManager()

        let notificationCenter = NotificationCenter.default

        notificationObservers += [
            notificationCenter.addObserver(forName: .LoopDataUpdated, object: nil, queue: nil) { note in
                let rawContext = note.userInfo?[LoopDataManager.LoopUpdateContextKey] as! LoopUpdateContext.RawValue
                let context = LoopUpdateContext(rawValue: rawContext)
                Task { @MainActor [weak self] in
                    switch context {
                    case .none, .insulin?:
                        self?.refreshContext.formUnion([.status, .insulin])
                    case .preferences?:
                        self?.refreshContext.formUnion([.status, .targets])
                    case .carbs?:
                        self?.refreshContext.update(with: .carbs)
                    case .glucose?:
                        self?.refreshContext.formUnion([.glucose, .carbs])
                    case .forecast?:
                        self?.refreshContext.update(with: .glucose)
                    }

                    self?.hudView?.loopCompletionHUD.loopInProgress = false
                    await self?.reloadData(animated: true)
                }

                WidgetCenter.shared.reloadAllTimelines()
            },
            notificationCenter.addObserver(forName: .LoopRunning, object: nil, queue: nil) { _ in
                Task { @MainActor [weak self] in
                    self?.hudView?.loopCompletionHUD.loopInProgress = true
                }
            },
            notificationCenter.addObserver(forName: .LoopCycleCompleted, object: nil, queue: nil) { _ in
                Task { @MainActor [weak self] in
                    self?.hudView?.loopCompletionHUD.loopInProgress = false
                }
            },
            notificationCenter.addObserver(forName: .PumpManagerChanged, object: deviceManager, queue: nil) { (notification: Notification) in
                Task { @MainActor [weak self] in
                    self?.registerPumpManager()
                    self?.configurePumpManagerHUDViews()
                    await self?.reloadData()
                }
            },
            notificationCenter.addObserver(forName: .CGMManagerChanged, object: deviceManager, queue: nil) { (notification: Notification) in
                Task { @MainActor [weak self] in
                    self?.registerCGMManager()
                    self?.configureCGMManagerHUDViews()
                    await self?.reloadData()
                }
            },
            notificationCenter.addObserver(forName: .PumpEventsAdded, object: deviceManager, queue: nil) { (notification: Notification) in
                Task { @MainActor [weak self] in
                    self?.refreshContext.update(with: .insulin)
                    await self?.reloadData(animated: true)
                }
            },
        ]

        withObservationTracking(of: self.settingsManager.dosingEnabled) { [weak self] enabled in
            self?.automaticDosingStatusChanged(enabled)
        }

        alertMuter.$configuration
            .removeDuplicates()
            .dropFirst()
            .sink { _ in
                Task { @MainActor in
                    self.refreshContext.update(with: .status)
                    await self.reloadData(animated: true)
                }
            }
            .store(in: &cancellables)
        
        loopManager.$lastLoopCompleted
            .receive(on: DispatchQueue.main)
            .sink { [weak self] lastLoopCompleted in
                self?.hudView?.loopCompletionHUD.lastLoopCompleted = lastLoopCompleted
            }
            .store(in: &cancellables)
        
        loopManager.$publishedMostRecentGlucoseDataDate
            .receive(on: DispatchQueue.main)
            .sink { [weak self] mostRecentGlucoseDataDate in
                self?.hudView?.loopCompletionHUD.mostRecentGlucoseDataDate = mostRecentGlucoseDataDate
            }
            .store(in: &cancellables)
        
        loopManager.$publishedMostRecentPumpDataDate
            .receive(on: DispatchQueue.main)
            .sink { [weak self] mostRecentPumpDataDate in
                self?.hudView?.loopCompletionHUD.mostRecentPumpDataDate = mostRecentPumpDataDate
            }
            .store(in: &cancellables)

        if let gestureRecognizer = charts.gestureRecognizer {
            tableView.addGestureRecognizer(gestureRecognizer)
        }

        tableView.estimatedRowHeight = 74

        // Estimate an initial value
        landscapeMode = UIScreen.main.bounds.size.width > UIScreen.main.bounds.size.height

        addScenarioStepGestureRecognizers()

        setupPresetsStatusBar()
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
        navigationController?.setToolbarHidden(true, animated: animated)
        
        alertPermissionsChecker.checkNow()

        updateBolusProgress()

        onboardingManager.$isComplete
            .merge(with: onboardingManager.$isSuspended)
            .sink { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    self.statusTableViewModel.settingsViewModel.isOnboardingComplete = self.onboardingManager.isComplete
                    self.refreshContext.update(with: .status)
                    await self.reloadData(animated: true)
                }
            }
            .store(in: &cancellables)
    }

    override func viewDidAppear(_ animated: Bool) {

        super.viewDidAppear(animated)

        if !appearedOnce {
            appearedOnce = true
            Task { @MainActor in
                self.log.debug("[reloadData] after HealthKit authorization")
                await self.reloadData()
            }
        }

        onscreen = true

        analyticsServicesManager?.didDisplayStatusScreen()

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
            loopManager.startGlucoseValueStalenessTimerIfNeeded()
        }
    }
    
    private var bolusState: PumpManagerStatus.BolusState = .noBolus {
        didSet {
            if oldValue != bolusState {
                switch bolusState {
                case .inProgress(let doseNew):
                    switch oldValue {
                    case .inProgress(let doseOld):
                        guard doseNew.syncIdentifier != doseOld.syncIdentifier,
                              doseNew.automatic != true
                        else { break }
                        // Different manual bolus is being delivered
                        bolusProgressReporter = deviceManager.pumpManager?.createBolusProgressReporter(reportingOn: DispatchQueue.main)
                    case .canceling:
                        break
                    default:
                        // Bolus starting
                        guard doseNew.automatic != true else { break }
                        bolusProgressReporter = deviceManager.pumpManager?.createBolusProgressReporter(reportingOn: DispatchQueue.main)
                    }
                default:
                    break
                }
            }
        }
    }
    
    private func setupPresetsStatusBar() {
        let backgroundContainerView = UIView()
        backgroundContainerView.backgroundColor = .systemBackground
        let statusBarBackgroundView = UIView(frame: CGRect(x: 0, y: 0, width: view.bounds.width, height: 0))
        self.statusBarBackgroundView = statusBarBackgroundView
        backgroundContainerView.addSubview(statusBarBackgroundView)
        tableView.backgroundView = backgroundContainerView
        
        updateStatusBar()
    }

    private var bolusProgressReporter: DoseProgressReporter?

    private func updateBolusProgress() {
        if let cell = tableView.cellForRow(at: IndexPath(row: StatusRow.status.rawValue, section: Section.status.rawValue)) as? BolusProgressTableViewCell {
            if case let .bolusing(_, total) = cell.configuration {
                cell.configuration = .bolusing(delivered: bolusProgressReporter?.progress.deliveredUnits, ofTotalVolume: total)
            }
        }
    }

    private func updateHUDActive() {
        deviceManager.pumpManagerHUDProvider?.visible = active && onscreen
    }

    public var basalDeliveryState: PumpManagerStatus.BasalDeliveryState? = nil {
        didSet {
            if oldValue != basalDeliveryState {
                Task { @MainActor in
                    log.debug("New basalDeliveryState: %@", String(describing: basalDeliveryState))
                    refreshContext.update(with: .status)
                    await reloadData(animated: true)
                }
            }
        }
    }

    // Toggles the display mode based on the screen aspect ratio. Should not be updated outside of reloadData().
    private var landscapeMode = false {
        didSet {
            setupPresetsStatusBar()
        }
    }

    private var lastLoopError: Error?

    private var reloading = false

    private var refreshContext = RefreshContext.all

    private var shouldShowPresets: Bool {
        presetsRowMode.hasRow
    }
    
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
    
    private var deviceIssue: Bool {
        // includes when devices are in signal loss, even though that is recoverable
        deviceManager.cgmManager == nil || deviceManager.cgmManager?.isInoperable == true || deviceManager.cgmManager?.inSignalLoss == true || deviceManager.pumpManager == nil || deviceManager.pumpManager?.isInoperable == true || deviceManager.pumpManager?.inSignalLoss == true || deviceManager.hasBluetoothIssue
    }

    private func updateChartDateRange() {
        // How far back should we show data? Use the screen size as a guide.
        let availableWidth = (refreshContext.newSize ?? tableView.bounds.size).width - charts.fixedHorizontalMargin

        let totalHours = floor(Double(availableWidth / LoopConstants.minimumChartWidthPerHour))
        let futureHours = ceil(doseStore.longestEffectDuration.hours)
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
    
    override func reloadData(animated: Bool = false) async {
        dispatchPrecondition(condition: .onQueue(.main))

        guard view.window != nil else {
            return
        }
        
        // This should be kept up to date immediately
        hudView?.loopCompletionHUD.lastLoopCompleted = loopManager.lastLoopCompleted
        hudView?.loopCompletionHUD.deviceIssue = deviceIssue
        hudView?.loopCompletionHUD.mostRecentGlucoseDataDate = loopManager.mostRecentGlucoseDataDate
        hudView?.loopCompletionHUD.mostRecentPumpDataDate = loopManager.mostRecentPumpDataDate

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
        refreshContext = []
        reloading = true

        var glucoseSamples: [StoredGlucoseSample]?
        var predictedGlucoseValues: [GlucoseValue]?
        var iobValues: [InsulinValue]?
        var doseEntries: [DoseEntry]?
        var totalDelivery: Double?
        var cobValues: [CarbValue]?
        var carbsOnBoard: LoopQuantity?
        let startDate = charts.startDate
        let basalDeliveryState = self.basalDeliveryState
        let automaticDosingEnabled = settingsManager.dosingEnabled

        let state = await loopManager.algorithmDisplayState
        predictedGlucoseValues = state.output?.predictedGlucose ?? []

        /// Update the status HUDs immediately
        let lastLoopError: Error?
        if let output = state.output, case .failure(let error) = output.recommendationResult {
            lastLoopError = error
        } else {
            lastLoopError = nil
        }

        self.lastLoopError = lastLoopError

        if let automatedTreatmentState = loopManager.automatedTreatmentState {
            self.hudView?.pumpStatusHUD.basalRateHUD.setAutomatedTreatmentState(automatedTreatmentState)
        }

        if currentContext.contains(.carbs) {
            cobValues = await loopManager.dynamicCarbsOnBoard(from: startDate)
        }

        // always check for cob
        carbsOnBoard = loopManager.activeCarbs?.quantity

        if currentContext.contains(.glucose) {
            do {
                glucoseSamples = try await loopManager.glucoseStore.getGlucoseSamples(start: startDate, end: nil)
            } catch {
                self.log.error("Failure getting glucose samples: %{public}@", String(describing: error))
                glucoseSamples = nil
            }
        }

        if currentContext.contains(.insulin) {
            doseEntries = try? await loopManager.doseStore.getNormalizedDoseEntries(start: startDate, end: nil)
            iobValues = loopManager.iobValues.filterDateRange(startDate, nil)
            totalDelivery = await loopManager.totalDeliveredToday()?.value
        }

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
            let valueAttributedString = NSMutableAttributedString(string: String(describing: lastPoint.copy), attributes: [.font: UIFont.systemFont(ofSize: 22, weight: .semibold), .foregroundColor: ChartColorPalette.primary.glucoseTint])
            let spacer = NSAttributedString(string: "\u{00a0}")
            let unitAttributedString =  NSAttributedString(string: String(describing: lastPoint).replacingOccurrences(of: String(describing: lastPoint.copy), with: "").trimmingCharacters(in: .whitespacesAndNewlines), attributes: [.font: UIFont.systemFont(ofSize: 15, weight: .regular), .foregroundColor: ChartColorPalette.primary.glucoseTint])
            
            valueAttributedString.append(spacer)
            valueAttributedString.append(unitAttributedString)
            
            self.eventualGlucoseDescription = valueAttributedString
        } else {
            // if the predicted glucose values are clamped, the eventually glucose description should not be displayed, since it may not align with what is being charted.
            self.eventualGlucoseDescription = nil
        }
        if currentContext.contains(.targets) {
            self.statusCharts.targetGlucoseSchedule = settingsManager.settings.glucoseTargetRangeSchedule
            self.statusCharts.preMealOverride = temporaryPresetsManager.preMealOverride
            self.statusCharts.scheduleOverride = temporaryPresetsManager.scheduleOverride
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
        if let activeInsulin = loopManager.activeInsulin, let valueString = insulinFormatter.string(from: activeInsulin.quantity, includeUnit: false) {
            let valueAttributedString = NSMutableAttributedString(string: valueString, attributes: [.font: UIFont.systemFont(ofSize: 22, weight: .semibold), .foregroundColor: ChartColorPalette.primary.insulinTint])
            let spacer = NSAttributedString(string: "\u{00a0}")
            let unitAttributedString = NSMutableAttributedString(string: insulinFormatter.localizedUnitStringWithPlurality(forQuantity: activeInsulin.quantity, avoidLineBreaking: true), attributes: [.font: UIFont.systemFont(ofSize: 15, weight: .regular), .foregroundColor: ChartColorPalette.primary.insulinTint])
            
            valueAttributedString.append(spacer)
            valueAttributedString.append(unitAttributedString)
            
            self.currentIOBDescription = valueAttributedString
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
            let valueAttributedString = NSMutableAttributedString(string: String(describing: charts.cob.cobPoints[index].y.copy), attributes: [.font: UIFont.systemFont(ofSize: 22, weight: .semibold), .foregroundColor: ChartColorPalette.primary.carbTint])
            let spacer = NSAttributedString(string: "\u{00a0}")
            let unitAttributedString =  NSAttributedString(string: String(describing: charts.cob.cobPoints[index].y).replacingOccurrences(of: String(describing: charts.cob.cobPoints[index].y.copy), with: "").trimmingCharacters(in: .whitespacesAndNewlines), attributes: [.font: UIFont.systemFont(ofSize: 15, weight: .regular), .foregroundColor: ChartColorPalette.primary.carbTint])
            
            valueAttributedString.append(spacer)
            valueAttributedString.append(unitAttributedString)
            
            self.currentCOBDescription = valueAttributedString
        } else if let carbsOnBoard = carbsOnBoard, let valueString = carbFormatter.string(from: carbsOnBoard, includeUnit: false) {
            let valueAttributedString = NSMutableAttributedString(string: valueString, attributes: [.font: UIFont.systemFont(ofSize: 22, weight: .semibold), .foregroundColor: ChartColorPalette.primary.carbTint])
            let spacer = NSAttributedString(string: "\u{00a0}")
            let unitAttributedString = NSAttributedString(string: carbFormatter.localizedUnitStringWithPlurality(forQuantity: carbsOnBoard, avoidLineBreaking: true), attributes: [.font: UIFont.systemFont(ofSize: 15, weight: .regular), .foregroundColor: ChartColorPalette.primary.carbTint])
            
            valueAttributedString.append(spacer)
            valueAttributedString.append(unitAttributedString)
            
            self.currentCOBDescription = valueAttributedString
        } else {
            self.currentCOBDescription = nil
        }

        if let hudView = self.hudView {
            // CGM Status
            if let glucose = self.loopManager.latestGlucose {
                let unit = self.statusCharts.glucose.glucoseUnit
                hudView.cgmStatusHUD.setGlucoseQuantity(glucose.quantity.doubleValue(for: unit),
                                                        at: glucose.startDate,
                                                        unit: unit,
                                                        glucoseDisplay: self.deviceManager.glucoseDisplay(for: glucose),
                                                        wasUserEntered: glucose.wasUserEntered,
                                                        isDisplayOnly: glucose.isDisplayOnly,
                                                        isGlucoseValueStale: self.deviceManager.isGlucoseValueStale)
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

        updateBannerAndHUDandStatusRows(statusRowMode: statusRowMode, newSize: currentContext.newSize, animated: animated)
        tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: ActionTabBarMetrics.tableContentInset, right: 0)
        
        redrawCharts()

        reloading = false
        let reloadNow = !self.refreshContext.isEmpty

        // Trigger a reload if new context exists.
        if reloadNow {
            log.debug("[reloadData] due to context change during previous reload")
            await reloadData()
        }
    }

    private enum Section: Int, CaseIterable {
        case presets
        case alertWarning
        case hud
        case status
        case charts
    }

    // MARK: - Chart Section Data

    private enum ChartRow: Int, CaseIterable {
        case glucose
        case iob
        case cob
    }

    // MARK: Glucose

    private var eventualGlucoseDescription: NSAttributedString?

    // MARK: IOB

    private var currentIOBDescription: NSAttributedString?

    // MARK: Dose

    private var totalDelivery: Double?

    // MARK: COB

    private var currentCOBDescription: NSAttributedString?

    // MARK: - Loop Status Section Data
    
    private enum PresetsRow: Int, CaseIterable {
        case presets = 0
    }

    private enum PresetsRowMode {
        case hidden
        case scheduleOverrideEnabled(TemporaryScheduleOverride)
        
        var hasRow: Bool {
            switch self {
            case .hidden:
                return false
            default:
                return true
            }
        }
    }
    
    private enum StatusRow: Int, CaseIterable {
        case status = 0
    }

    private enum StatusRowMode {
        case hidden
        case enactingBolus
        case bolusing(dose: DoseEntry)
        case cancelingBolus
        case canceledBolus(dose: DoseEntry)
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

    private var presetsRowMode = PresetsRowMode.hidden
    private var statusRowMode = StatusRowMode.hidden

    private var canceledDose: DoseEntry? = nil
    
    private func determinePresetsRowMode() -> PresetsRowMode {
        if let preset = temporaryPresetsManager.scheduleOverride ?? temporaryPresetsManager.preMealOverride, !preset.hasFinished() {
            return .scheduleOverrideEnabled(preset)
        } else {
            return .hidden
        }
    }
    
    private func determineStatusRowMode() -> StatusRowMode {
        let statusRowMode: StatusRowMode

        if case .canceling = bolusState {
            statusRowMode = .cancelingBolus
        } else if let canceledDose {
            statusRowMode = .canceledBolus(dose: canceledDose)
        } else if case .suspended = basalDeliveryState {
            statusRowMode = .pumpSuspended(resuming: false)
        } else if case .resuming = basalDeliveryState {
            statusRowMode = .pumpSuspended(resuming: true)
        } else if case .inProgress(let dose) = bolusState, bolusProgressReporter?.progress.isComplete == false {
            // the isComplete check should be tested on DIY
            statusRowMode = .bolusing(dose: dose)
        } else if !onboardingManager.isComplete, deviceManager.pumpManager?.isOnboarded == true {
            statusRowMode = .onboardingSuspended
        } else if onboardingManager.isComplete, deviceManager.isGlucoseValueStale {
            statusRowMode = .recommendManualGlucoseEntry
        } else {
            statusRowMode = .hidden
        }

        return statusRowMode
    }

    private var shouldShowBannerWarning: Bool {
        alertPermissionsChecker.showWarning || alertMuter.configuration.shouldMute
    }
    
    override func viewDidLayoutSubviews() {
        updateStatusBar()
    }

    private func updateBannerRow(animated: Bool) {
        let warningWasVisible = tableView.numberOfRows(inSection: Section.alertWarning.rawValue) != 0
        if !shouldShowBannerWarning && warningWasVisible {
            tableView.deleteRows(at: [IndexPath(row: 0, section: Section.alertWarning.rawValue)], with: animated ? .fade : .none)
        } else if shouldShowBannerWarning && !warningWasVisible {
            tableView.insertRows(at: [IndexPath(row: 0, section: Section.alertWarning.rawValue)], with: animated ? .top : .none)
        } else {
            tableView.reloadRows(at: [IndexPath(row: 0, section: Section.alertWarning.rawValue)], with: .none)
        }
    }
    
    private func updateStatusBar() {
        statusBarBackgroundView?.backgroundColor = landscapeMode ? .systemBackground : (shouldShowPresets ? .presets : .secondarySystemBackground)
        statusBarBackgroundView?.frame.size.height = abs(tableView.contentOffset.y) + (shouldShowPresets ? tableView(tableView, cellForRowAt: IndexPath(row: 0, section: 0)).contentView.frame.height + 8 : 0)
    }

    private func updateBannerAndHUDandStatusRows(statusRowMode: StatusRowMode, newSize: CGSize?, animated: Bool) {
        let presetsWasVisible = self.shouldShowPresets
        let hudWasVisible = self.shouldShowHUD
        let statusWasVisible = self.shouldShowStatus

        let oldStatusRowMode = self.statusRowMode

        self.presetsRowMode = determinePresetsRowMode()
        self.statusRowMode = statusRowMode

        if let newSize = newSize {
            landscapeMode = newSize.width > newSize.height
        }

        let presetsIsVisible = self.shouldShowPresets
        let hudIsVisible = self.shouldShowHUD
        let statusIsVisible = self.shouldShowStatus
        
        hudView?.cgmStatusHUD?.isVisible = hudIsVisible
        hudView?.cgmStatusHUD.isGlucoseValueStale = deviceManager.isGlucoseValueStale

        tableView.beginUpdates()
        
        updateBannerRow(animated: animated)
        
        switch (presetsWasVisible, presetsIsVisible) {
        case (false, true):
            tableView.insertRows(at: [IndexPath(row: 0, section: Section.presets.rawValue)], with: animated ? .top : .none)
        case (true, false):
            tableView.deleteRows(at: [IndexPath(row: 0, section: Section.presets.rawValue)], with: animated ? .fade : .none)
        default:
            tableView.reloadRows(at: [IndexPath(row: 0, section: Section.presets.rawValue)], with: animated ? .automatic : .none)
        }
        
        switch (hudWasVisible, hudIsVisible) {
        case (false, true):
            tableView.insertRows(at: [IndexPath(row: 0, section: Section.hud.rawValue)], with: animated ? .top : .none)
        case (true, false):
            tableView.deleteRows(at: [IndexPath(row: 0, section: Section.hud.rawValue)], with: animated ? .fade : .none)
        default:
            break
        }

        let statusIndexPath = IndexPath(row: StatusRow.status.rawValue, section: Section.status.rawValue)

        switch (statusWasVisible, statusIsVisible) {
        case (true, true):
            switch (oldStatusRowMode, self.statusRowMode) {
            case (.pumpSuspended(resuming: let wasResuming), .pumpSuspended(resuming: let isResuming)):
                if isResuming != wasResuming {
                    tableView.reloadRows(at: [statusIndexPath], with: animated ? .fade : .none)
                }
            case (.enactingBolus, .enactingBolus):
                break
            case (.bolusing(let oldDose), .bolusing(let newDose)):
                if oldDose.syncIdentifier != newDose.syncIdentifier {
                    tableView.reloadRows(at: [statusIndexPath], with: animated ? .fade : .none)
                }
            case (.cancelingBolus, .bolusing):
                // this occurs when a cancel command fails
                tableView.reloadRows(at: [statusIndexPath], with: animated ? .fade : .none)
            case (.canceledBolus(let oldDose), .canceledBolus(let newDose)):
                if oldDose != newDose {
                    tableView.reloadRows(at: [statusIndexPath], with: animated ? .fade : .none)
                }
            // these updates cause flickering and/or confusion.
            case (.cancelingBolus, .cancelingBolus):
                break
            case (.canceledBolus(_), .cancelingBolus):
                break
            case (.canceledBolus(_), .bolusing(_)):
                break
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
                if Section(rawValue: indexPath.section)! == .charts && ChartRow(rawValue: indexPath.row)! == .iob {
                    cell.setFooterView(content: iobFooterViewContent)
                }
            }
        }
        tableView.endUpdates()
    }

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        return Section.allCases.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .presets:
            return shouldShowPresets ? PresetsRow.allCases.count : 0
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
    
    private class GradientView: UIView {
        override static var layerClass: AnyClass { CAGradientLayer.self }
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch Section(rawValue: indexPath.section)! {
        case .presets:
            let cell = UITableViewCell()
            
            switch presetsRowMode {
            case .hidden:
                break
            case .scheduleOverrideEnabled(let override):
                cell.contentConfiguration = UIHostingConfiguration  {
                    ActivePresetBanner(override: override)
                }
                .margins(.all, 0)
                
                cell.backgroundColor = .presets
                cell.selectionStyle = .none
            }
            
            return cell
        case .alertWarning:
            let cell = UITableViewCell()
            let alert = AlertPermissionsChecker.UnsafeNotificationPermissionAlert(permissions: alertPermissionsChecker.notificationCenterSettings)
    
            cell.contentConfiguration = UIHostingConfiguration  {
                if alertPermissionsChecker.showWarning {
                    if let alert {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(Image(systemName: "exclamationmark.triangle.fill")) + Text(" ") + Text(alert.bannerTitle)
                                    .font(.headline.bold())
                                
                                Text(alert.bannerBody)
                                    .font(.subheadline)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            
                            Spacer()
                            
                            Text(Image(systemName: "chevron.right"))
                                .font(.headline)
                        }
                        .foregroundStyle(Color.white)
                        .padding(8)
                        .background(Color.critical.cornerRadius(10))
                        .padding([.top, .horizontal], 8)
                    }
                } else {
                    HStack {
                        Text(Image(systemName: "speaker.slash.fill")).font(.title) + Text(" ")
                        
                        VStack(alignment: .leading) {
                            Text(NSLocalizedString("All App Sounds Muted", comment: "Warning text for when alerts are muted"))
                                .font(.headline.bold())
                            
                            Text(String(format: NSLocalizedString("Until %1$@", comment: "indication of when alerts will be unmuted (1: time when alerts unmute)"), alertMuter.formattedEndTime))
                                .font(.subheadline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        
                        Spacer()
                        
                        Text(Image(systemName: "stop.circle"))
                            .font(.title)
                    }
                    .foregroundStyle(Color.white)
                    .padding(8)
                    .background(Color.critical.cornerRadius(10))
                    .padding([.top, .horizontal], 8)
                }
            }
            .margins(.all, 0)
            
            cell.backgroundColor = .secondarySystemBackground
            
            return cell
        case .hud:
            let cell = tableView.dequeueReusableCell(withIdentifier: HUDViewTableViewCell.className, for: indexPath) as! HUDViewTableViewCell
            hudView = cell.hudView
            cell.hudView.loopCompletionHUD.loopStatusColors = .loopStatus

            return cell
        case .charts:
            let cell = tableView.dequeueReusableCell(withIdentifier: ChartTableViewCell.className, for: indexPath) as! ChartTableViewCell

            switch ChartRow(rawValue: indexPath.row)! {
            case .glucose:
                cell.setChartGenerator(generator: { [weak self] (frame) in
                    return self?.statusCharts.glucoseChart(withFrame: frame)?.view
                })
                cell.setTitleLabelText(label: NSLocalizedString("Glucose", comment: "The title of the glucose and prediction graph"))
                cell.setTitleTextColor(color: ChartColorPalette.primary.glucoseTint)
                cell.doesNavigate = settingsManager.dosingEnabled || !FeatureFlags.simpleBolusCalculatorEnabled
            case .iob:
                cell.setSupplementalChartGenerator(generator: { [weak self] (frame) in
                    return self?.statusCharts.doseChart(withFrame: frame)?.view
                })
                
                cell.setChartGenerator(generator: { [weak self] (frame) in
                    return self?.statusCharts.iobChart(withFrame: frame, highlightLabelOffsetY: cell.supplementalChartContentView?.bounds.height ?? 0)?.view
                })
                cell.setTitleLabelText(label: NSLocalizedString("Active Insulin", comment: "The title of the Insulin On-Board graph"))
                cell.setTitleTextColor(color: ChartColorPalette.primary.insulinTint)
                cell.setFooterView(content: iobFooterViewContent)
            case .cob:
                cell.setChartGenerator(generator: { [weak self] (frame) in
                    return self?.statusCharts.cobChart(withFrame: frame)?.view
                })
                cell.setTitleLabelText(label: NSLocalizedString("Active Carbohydrates", comment: "The title of the Carbs On-Board graph"))
                cell.setTitleTextColor(color: ChartColorPalette.primary.carbTint)
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
                cell.titleLabel.textColor = .label
                cell.titleLabel.font = .systemFont(ofSize: 15, weight: .bold)
                cell.subtitleLabel.text = nil
                cell.subtitleLabel.textColor = .secondaryLabel
                cell.subtitleLabel.font = .systemFont(ofSize: 15, weight: .bold)
                cell.accessoryView = nil
                return cell
            }

            switch StatusRow(rawValue: indexPath.row)! {
            case .status:
                switch statusRowMode {
                case .hidden:
                    let cell = getTitleSubtitleCell()
                    return cell
                case .enactingBolus:
                    let progressCell = tableView.dequeueReusableCell(withIdentifier: BolusProgressTableViewCell.className, for: indexPath) as! BolusProgressTableViewCell
                    progressCell.selectionStyle = .none
                    progressCell.configuration = .starting
                    return progressCell
                case .bolusing(let dose):
                    let progressCell = tableView.dequeueReusableCell(withIdentifier: BolusProgressTableViewCell.className, for: indexPath) as! BolusProgressTableViewCell
                    progressCell.selectionStyle = .none
                    progressCell.configuration = .bolusing(delivered: bolusProgressReporter?.progress.deliveredUnits, ofTotalVolume: dose.programmedUnits)
                    progressCell.tintColor = .insulinTintColor
                    return progressCell
                case .cancelingBolus:
                    let progressCell = tableView.dequeueReusableCell(withIdentifier: BolusProgressTableViewCell.className, for: indexPath) as! BolusProgressTableViewCell
                    progressCell.selectionStyle = .none
                    progressCell.configuration = .canceling
                    progressCell.activityIndicator.startAnimating()
                    return progressCell
                case .canceledBolus(let dose):
                    let progressCell = tableView.dequeueReusableCell(withIdentifier: BolusProgressTableViewCell.className, for: indexPath) as! BolusProgressTableViewCell
                    progressCell.selectionStyle = .none
                    progressCell.configuration = .canceled(delivered: dose.deliveredUnits ?? 0, ofTotalVolume: dose.programmedUnits)
                    return progressCell
                case .pumpSuspended(let resuming):
                    let cell = tableView.dequeueReusableCell(withIdentifier: InsulinSuspendedTableViewCell.className, for: indexPath) as! InsulinSuspendedTableViewCell
                    cell.selectionStyle = .default
                    if resuming {
                        cell.activityIndicator.startAnimating()
                        cell.activityIndicator.isHidden = false
                    } else {
                        cell.tapToResumeLabel.text = NSLocalizedString("Tap to Resume", comment: "The subtitle of the cell displaying an action to resume insulin delivery")
                        cell.tapToResumeLabel.accessibilityIdentifier = "text_InsulinTapToResume"
                        cell.activityIndicator.stopAnimating()
                        cell.activityIndicator.isHidden = true
                    }
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
                    cell.titleLabel.textColor = .label
                    cell.titleLabel.font = .systemFont(ofSize: 15, weight: .bold)
                    cell.subtitleLabel.text = NSLocalizedString("Tap to Resume", comment: "The subtitle of the cell displaying an action to resume onboarding")
                    cell.subtitleLabel.textColor = .secondaryLabel
                    cell.subtitleLabel.font = .systemFont(ofSize: 15, weight: .bold)
                    cell.accessoryView = nil
                    return cell
                case .recommendManualGlucoseEntry:
                    let cell = tableView.dequeueReusableCell(withIdentifier: RecentGlucoseTableViewCell.className, for: indexPath) as! RecentGlucoseTableViewCell
                    cell.selectionStyle = .default
                    return cell
                }
            }
        }
    }
    
    private var iobFooterText: Text? {
        if let lastManualDose = loopManager.lastManualBolus,
           let formattedBolusValue = insulinFormatter.string(from: LoopQuantity(unit: .internationalUnit, doubleValue: lastManualDose.amount)) {

            let hoursDifference = Date().timeIntervalSince(lastManualDose.startDate) / 3600

            // Build a single Text view
            let footerText: Text
            let lastBolusLabel = Text("Last Bolus: ")
            let lastBolusValue = Text("\(formattedBolusValue) ").fontWeight(.semibold)
            let icon = Text(Image(systemName: "hourglass.bottomhalf.filled")).foregroundStyle(.secondary)
            let exactTime = Text("at \(lastManualDose.startDate.formatted(date: .omitted, time: .shortened))").foregroundStyle(.secondary)
            let roundedTime = Text(" \(Int(hoursDifference.rounded())) hours ago").foregroundStyle(.secondary)

            switch hoursDifference {
            case ..<6:
                footerText = lastBolusLabel + lastBolusValue + exactTime
            case 6..<12:
                footerText = lastBolusLabel + lastBolusValue.foregroundStyle(.secondary) + icon + roundedTime
            default:
                footerText = lastBolusLabel + icon + roundedTime
            }

            return footerText
        } else {
            return nil
        }
    }

    @ViewBuilder
    private func iobFooterViewContent() -> some View {
        if let iobFooterText = iobFooterText {
            iobFooterText
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 36)
                .padding(.vertical)
                .accessibilityIdentifier("text_ActiveInsulinFooter")
        }
    }

    private func tableView(_ tableView: UITableView, updateSubtitleFor cell: ChartTableViewCell, at indexPath: IndexPath) {
        switch Section(rawValue: indexPath.section)! {
        case .charts:
            switch ChartRow(rawValue: indexPath.row)! {
            case .glucose:
                if let eventualGlucose = eventualGlucoseDescription {
                    let subtitle = NSMutableAttributedString(string: NSLocalizedString("Eventually", comment: ""), attributes: [.font: UIFont.systemFont(ofSize: 15, weight: .regular)])
                    let spacer = NSAttributedString(string: "\u{00a0}")
                    
                    subtitle.append(spacer)
                    subtitle.append(eventualGlucose)
                    
                    cell.setSubtitleLabel(label: subtitle)
                    cell.setTitleLabelAccessibilityIdentifier("Glucose")
                } else {
                    cell.setSubtitleLabel(label: nil)
                    cell.setTitleLabelAccessibilityIdentifier("Glucose")
                }
                cell.doesNavigate = settingsManager.dosingEnabled || !FeatureFlags.simpleBolusCalculatorEnabled
            case .iob:
                if let currentIOB = currentIOBDescription {
                    cell.setSubtitleLabel(label: currentIOB)
                    cell.setTitleLabelAccessibilityIdentifier("ActiveInsulin_\(currentIOB.string)")
                } else {
                    cell.setSubtitleLabel(label: nil)
                }
            case .cob:
                if let currentCOB = currentCOBDescription {
                    cell.setSubtitleLabel(label: currentCOB)
                    cell.setTitleLabelAccessibilityIdentifier("ActiveCarbs_\(currentCOB.string)")
                } else {
                    cell.setSubtitleLabel(label: nil)
                }
            }
        case .presets, .hud, .status, .alertWarning:
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
            availableSize -= (tableView.safeAreaInsets.top + tableView.safeAreaInsets.bottom + tableView.contentInset.bottom + hudHeight)

            switch ChartRow(rawValue: indexPath.row)! {
            case .glucose:
                return max(106, 0.30 * availableSize)
            case .iob:
                return max(106, 0.45 * availableSize)
            case .cob:
                return max(106, 0.25 * availableSize)
            }
        case .alertWarning:
            return UITableView.automaticDimension
        case .presets, .hud, .status:
            return UITableView.automaticDimension
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        switch Section(rawValue: indexPath.section)! {
        case .presets:
            statusTableViewModel.pendingPreset = temporaryPresetsManager.activePreset
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
                        Task { @MainActor in
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
                                await self.reloadData()
                            }
                        }
                    }
                case .bolusing(var dose):
                    bolusState = .canceling
                    updateBannerAndHUDandStatusRows(statusRowMode: .cancelingBolus, newSize: nil, animated: true)
                    Task {
                        try? await Task.sleep(nanoseconds: NSEC_PER_SEC)
                        dose.deliveredUnits = bolusProgressReporter?.progress.deliveredUnits
                        self.canceledDose = dose
                        deviceManager.pumpManager?.cancelBolus() { (result) in
                            DispatchQueue.main.async {
                                switch result {
                                case .success(let canceledDose):
                                    let doseToReport = canceledDose ?? dose
                                    self.canceledDose = doseToReport
                                    self.updateBannerAndHUDandStatusRows(statusRowMode: .canceledBolus(dose: doseToReport), newSize: nil, animated: true)
                                    self.bolusState = .noBolus
                                    Task {
                                        try? await Task.sleep(nanoseconds: NSEC_PER_SEC * 10)
                                        self.canceledDose = nil
                                        self.updateBannerAndHUDandStatusRows(statusRowMode: self.determineStatusRowMode(), newSize: nil, animated: true)
                                    }
                                case .failure(let error):
                                    self.canceledDose = nil
                                    self.presentErrorCancelingBolus(error)
                                    if case .noBolus = self.bolusState {
                                        self.updateBannerAndHUDandStatusRows(statusRowMode: .hidden, newSize: nil, animated: true)
                                    } else {
                                        self.updateBannerAndHUDandStatusRows(statusRowMode: .bolusing(dose: dose), newSize: nil, animated: true)
                                    }
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
                if settingsManager.dosingEnabled || !FeatureFlags.simpleBolusCalculatorEnabled {
                    performSegue(withIdentifier: PredictionTableViewController.className, sender: indexPath)
                }
            case .iob:
                let showLegacy = false
                
                if !showLegacy, let pumpManager = deviceManager.pumpManager {
                    let hostingController = UIHostingController(
                        rootView: InsulinDeliveryLog(
                            viewModel: InsulinDeliveryLogViewModel(
                                loopDataManager: loopManager,
                                pumpManager: pumpManager
                            ),
                            onTapGesture: { [weak navigationController] doseEntry in
                                Task {
                                    var dosingDecision: StoredDosingDecision?
                                    if let decisionId = doseEntry.decisionId {
                                        dosingDecision = try await self.loopManager.dosingDecisionStore.findDosingDecisionsById(decisionId)
                                    }
                                    
                                    let viewController = CommandResponseViewController(command: { (completionHandler) -> String in
                                        var description = [String]()
                                        
                                        let timeFormatter: DateFormatter = {
                                            let formatter = DateFormatter()
                                            
                                            formatter.dateStyle = .none
                                            formatter.timeStyle = .short
                                            
                                            return formatter
                                        }()
                                        
                                        description.append(timeFormatter.string(from: doseEntry.startDate))
                                        
                                        description.append(String(describing: doseEntry))
                                        
                                        if let dosingDecision {
                                            description.append(String(describing: dosingDecision))
                                        }
                                        
                                        return description.joined(separator: "\n\n")
                                    })
                                    
                                    navigationController?.pushViewController(viewController, animated: true)
                                }
                            },
                            onEnterManualDose: { [weak self] in
                                self?.presentManualDoseEntry()
                            }
                        )
                        .navigationTitle(Text("Insulin"))
                        .environment(\.colorPalette, .default)
                        .environment(\.loopStatusColorPalette, .loopStatus)
                    )
                    
                    hostingController.hidesBottomBarWhenPushed = true
                    
                    navigationController?.pushViewController(
                        hostingController,
                        animated: true
                    )
                } else {
                    performSegue(withIdentifier: InsulinDeliveryTableViewController.className, sender: indexPath)
                }
            case .cob:
                performSegue(withIdentifier: CarbAbsorptionViewController.className, sender: indexPath)
            }
        }
    }

    private func presentManualDoseEntry() {
        let viewModel = ManualEntryDoseViewModel(delegate: loopManager)
        let manualEntryDoseView = ManualEntryDoseView(viewModel: viewModel)
        let hostingController = DismissibleHostingController(rootView: manualEntryDoseView, isModalInPresentation: false)
        let navigationWrapper = UINavigationController(rootViewController: hostingController)
        hostingController.navigationItem.leftBarButtonItem = UIBarButtonItem(title: NSLocalizedString("Cancel", comment: ""), style: .plain, target: navigationWrapper, action: #selector(dismissWithAnimation))
        present(navigationWrapper, animated: true)
    }

    private func presentUnmuteAlertConfirmation() {
        let title = NSLocalizedString("Unmute All App Sounds?", comment: "The alert title for unmute all app sounds confirmation")
        let body = NSLocalizedString("All app sounds, including sounds for all critical alerts, are currently muted.\n\nTap Unmute to resume app sounds for your alerts.", comment: "The alert body for unmute alert confirmation")
        let action = UIAlertAction(
            title: NSLocalizedString("Unmute", comment: "The title of the action used to unmute app sounds"),
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
            vc.automaticDosingEnabled = settingsManager.dosingEnabled
            vc.deviceManager = deviceManager
            vc.loopDataManager = loopManager
            vc.analyticsServicesManager = analyticsServicesManager
            vc.carbStore = carbStore
            vc.hidesBottomBarWhenPushed = true
        case let vc as InsulinDeliveryTableViewController:
            vc.loopDataManager = loopManager
            vc.doseStore = doseStore
            vc.hidesBottomBarWhenPushed = true
            vc.enableEntryDeletion = FeatureFlags.entryDeletionEnabled
            vc.headerValueLabelColor = .insulinTintColor
        case let vc as PredictionTableViewController:
            vc.deviceManager = deviceManager
            vc.settingsManager = settingsManager
            vc.loopDataManager = loopManager
        default:
            break
        }
    }

    @IBAction func unwindFromEditing(_ segue: UIStoryboardSegue) {}

    @IBAction func unwindFromSettings(_ segue: UIStoryboardSegue) {}

    @IBAction func userTappedAddCarbs() {
        presentCarbEntryScreen(nil)
    }

    func presentCarbEntryScreen(_ activity: NSUserActivity?, value: LoopQuantity? = nil) {
        let navigationWrapper: UINavigationController
        if FeatureFlags.simpleBolusCalculatorEnabled && !settingsManager.dosingEnabled {
            let viewModel = SimpleBolusViewModel(delegate: loopManager, displayMealEntry: true, displayGlucosePreference: deviceManager.displayGlucosePreference)
            if let activity = activity {
                viewModel.restoreUserActivityState(activity)
            }
            if let carbString = value?.doubleValue(for: .gram) {
                viewModel.enteredCarbString = carbString.formatted()
            }
            let bolusEntryView = SimpleBolusView(viewModel: viewModel).environmentObject(deviceManager.displayGlucosePreference)
            let hostingController = DismissibleHostingController(rootView: bolusEntryView, isModalInPresentation: false)
            navigationWrapper = UINavigationController(rootViewController: hostingController)
            hostingController.navigationItem.leftBarButtonItem = UIBarButtonItem(title: NSLocalizedString("Cancel", comment: ""), style: .plain, target: navigationWrapper, action: #selector(dismissWithAnimation))
            present(navigationWrapper, animated: true)
        } else {
            let viewModel = CarbEntryViewModel(delegate: loopManager)
            viewModel.carbsQuantity = value?.doubleValue(for: .gram)
            viewModel.deliveryDelegate = deviceManager
            viewModel.analyticsServicesManager = loopManager.analyticsServicesManager
            if let activity {
                viewModel.restoreUserActivityState(activity)
            }
            let carbEntryView = CarbEntryView(viewModel: viewModel)
                .environmentObject(deviceManager.displayGlucosePreference)
            let hostingController = DismissibleHostingController(rootView: carbEntryView, isModalInPresentation: false)
            present(hostingController, animated: true)
        }
        analyticsServicesManager?.didDisplayCarbEntryScreen()
    }

    @IBAction func presentBolusScreen() {
        presentBolusEntryView()
    }
    
    @ViewBuilder
    func bolusEntryView(enableManualGlucoseEntry: Bool = false) -> some View {
        if FeatureFlags.simpleBolusCalculatorEnabled && !settingsManager.dosingEnabled {
            SimpleBolusView(
                viewModel: SimpleBolusViewModel(
                    delegate: loopManager,
                    displayMealEntry: false,
                    displayGlucosePreference: deviceManager.displayGlucosePreference
                )
            )
            .environmentObject(deviceManager.displayGlucosePreference)
        } else {
            let viewModel: BolusEntryViewModel = {
                let viewModel = BolusEntryViewModel(
                    delegate: loopManager,
                    screenWidth: UIScreen.main.bounds.width,
                    isManualGlucoseEntryEnabled: enableManualGlucoseEntry
                )
                viewModel.deliveryDelegate = deviceManager
                viewModel.analyticsServicesManager = analyticsServicesManager
                
                return viewModel
            }()
            
            BolusEntryView(viewModel: viewModel)
                .environmentObject(deviceManager.displayGlucosePreference)
        }
    }

    func presentBolusEntryView(enableManualGlucoseEntry: Bool = false) {
        let hostingController = DismissibleHostingController(
            rootView: bolusEntryView(
                enableManualGlucoseEntry: enableManualGlucoseEntry
            ),
            isModalInPresentation: false
        )
        
        let navigationWrapper = UINavigationController(rootViewController: hostingController)
        hostingController.navigationItem.leftBarButtonItem = UIBarButtonItem(title: NSLocalizedString("Cancel", comment: ""), style: .plain, target: navigationWrapper, action: #selector(dismissWithAnimation))
        present(navigationWrapper, animated: true)
        analyticsServicesManager?.didDisplayBolusScreen()
    }
    
    private(set) var isShowingPresets: Bool = false
    
    func presentPresets() {
        let hostingController = DismissibleHostingController(
            rootView: PresetsView(
                roundBasalRate: deviceManager.roundBasalRate,
                carbStore: deviceManager.carbStore,
                doseStore: deviceManager.doseStore,
                glucoseStore: deviceManager.glucoseStore,
                trainingContent: supportManager.availableSupports.flatMap({ $0.trainingMedia(for: .presets) }),
                automationHistory: { [weak self] in self?.loopManager.automationHistory ?? [] }
            )
            .onAppear { self.isShowingPresets = true }
            .onDisappear { self.isShowingPresets = false }
            .environmentObject(deviceManager.displayGlucosePreference)
            .environment(\.appName, Bundle.main.bundleDisplayName)
            .environment(\.isInvestigationalDevice, FeatureFlags.isInvestigationalDevice)
            .environment(\.colorPalette, .default)
            .environment(\.loopStatusColorPalette, .loopStatus)
            .environment(\.temporaryPresetsManager, temporaryPresetsManager)
            .environment(\.settingsManager, settingsManager),
        isModalInPresentation: false)
        present(hostingController, animated: true)
    }
    
    @IBAction func onSettingsTapped(_ sender: UIBarButtonItem) {
        presentSettings()
    }

    func presentSettings() {
        let hostingController = DismissibleHostingController(
            rootView: SettingsView(viewModel: statusTableViewModel.settingsViewModel, localizedAppNameAndVersion: supportManager.localizedAppNameAndVersion)
                .environmentObject(deviceManager.displayGlucosePreference)
                .environment(\.appName, Bundle.main.bundleDisplayName)
                .environment(\.isInvestigationalDevice, FeatureFlags.isInvestigationalDevice)
                .environment(\.loopStatusColorPalette, .loopStatus)
                .environment(\.colorPalette, .default)
                .environment(\.settingsManager, settingsManager)
                .environment(\.temporaryPresetsManager, temporaryPresetsManager)
                .environment(\.dosingStrategySelectionEnabled, FeatureFlags.dosingStrategySelectionEnabled),

            isModalInPresentation: false)
        present(hostingController, animated: true)
    }

    private func onPumpTapped() {
        guard let pumpManager = deviceManager.pumpManager as? PumpManagerUI else {
            return
        }

        var settingsViewController = pumpManager.settingsViewController(bluetoothProvider: deviceManager.bluetoothProvider, colorPalette: .default, allowDebugFeatures: FeatureFlags.allowDebugFeatures, allowedInsulinTypes: deviceManager.allowedInsulinTypes)
        settingsViewController.pumpManagerOnboardingDelegate = deviceManager
        settingsViewController.completionDelegate = self
        show(settingsViewController, sender: self)
    }

    private func onCGMTapped() {
        guard let cgmManager = deviceManager.cgmManager as? CGMManagerUI else {
            // assert?
            return
        }

        var settings = cgmManager.settingsViewController(bluetoothProvider: deviceManager.bluetoothProvider, displayGlucosePreference: deviceManager.displayGlucosePreference, colorPalette: .default, allowDebugFeatures: FeatureFlags.allowDebugFeatures)
        settings.cgmManagerOnboardingDelegate = deviceManager
        settings.completionDelegate = self
        show(settings, sender: self)
    }

    private func automaticDosingStatusChanged(_ automaticDosingEnabled: Bool) {
        log.debug("automaticDosingStatusChanged -> %{public}@", String(describing: automaticDosingEnabled))
        hudView?.loopCompletionHUD.loopIconClosed = automaticDosingEnabled
        hudView?.loopCompletionHUD.closedLoopDisallowedLocalizedDescription = deviceManager.closedLoopDisallowedLocalizedDescription
        
        if automaticDosingEnabled {
            Task {
                log.debug("Triggering loop() from automatic dosing flag")
                await loopManager.loop()
            }
        }
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
            hudView.loopCompletionHUD.loopIconClosed = settingsManager.dosingEnabled
            hudView.loopCompletionHUD.lastLoopCompleted = loopManager.lastLoopCompleted
            hudView.loopCompletionHUD.mostRecentGlucoseDataDate = loopManager.mostRecentGlucoseDataDate
            hudView.loopCompletionHUD.mostRecentPumpDataDate = loopManager.mostRecentPumpDataDate
            hudView.loopCompletionHUD.onAgoUpdate = { [weak self] ago in
                self?.loopCompletionModalViewModel.ago = ago
            }

            hudView.cgmStatusHUD.stateColors = .cgmStatus
            hudView.cgmStatusHUD.tintColor = .label
            hudView.pumpStatusHUD.stateColors = .pumpStatus
            hudView.pumpStatusHUD.tintColor = .insulinTintColor

            refreshContext.update(with: .status)
            Task { @MainActor in
                log.debug("[reloadData] after hudView loaded")
                await reloadData()
            }
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
    
    private lazy var loopCompletionModalViewModel = LoopStatusModalViewModel(
        deviceManager: deviceManager,
        loopManager: loopManager,
        settingsManager: settingsManager
    )
    
    @objc private func showLoopCompletionMessage(_: Any) {
        let modalVC = UIHostingController(
            rootView: LoopStatusModalView(viewModel: loopCompletionModalViewModel,
                                          onDismiss: { [weak self] in
                                             self?.dismiss(animated: false)
                                          },
                                          onNavigateToSettings: { [weak self] in
                                              self?.presentSettings()
                                          })
                .environment(\.loopStatusColorPalette, .loopStatus)
        )
        modalVC.modalPresentationStyle = .overCurrentContext
        modalVC.view.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        modalVC.view.frame = view.bounds
        modalVC.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        present(modalVC, animated: false)
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
                Task {
                    await self.deviceManager.refreshDeviceData()
                }
            })
            alertController.addAction(manualLoopAction)
            present(alertController, animated: true)
        }
    }

    @objc private func pumpStatusTapped(_ sender: UIGestureRecognizer) {
        if let pumpStatusView = sender.view as? PumpStatusHUDView {
            executeHUDTapAction(deviceManager.didTapOnPumpStatus(pumpStatusView.pumpManagerProvidedHUD), from: sender.view)
        }
    }

    @objc private func cgmStatusTapped( _ sender: UIGestureRecognizer) {
        executeHUDTapAction(deviceManager.didTapOnCGMStatus(), from: sender.view)
    }

    private func executeHUDTapAction(_ action: HUDTapAction?, from sourceView: UIView?) {
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
            addNewCGMManager(from: sourceView)
        case .setupNewPump:
            addNewPumpManager(from: sourceView)
        default:
            return
        }
    }

    private func addNewPumpManager(from sourceView: UIView?) {
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
            alert.popoverPresentationController?.sourceView = sourceView ?? view
            alert.popoverPresentationController?.sourceRect = sourceView?.bounds ?? view.bounds
            present(alert, animated: true, completion: nil)
        }
    }

    private func addNewCGMManager(from sourceView: UIView?) {
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
            alert.popoverPresentationController?.sourceView = sourceView ?? view
            alert.popoverPresentationController?.sourceRect = sourceView?.bounds ?? view.bounds
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
                    Task { @MainActor [weak self] in
                        self?.rotateCount = 0
                        self?.rotateTimer?.invalidate()
                        self?.rotateTimer = nil
                    }
                }
                rotateCount += 1
            }
        }
        lastOrientation = UIDevice.current.orientation
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
            if let error = self.criticalEventLogExportManager.removeExportsDirectory() {
                self.presentError(error)
            }
        })
        if FeatureFlags.mockTherapySettingsEnabled {
            actionSheet.addAction(UIAlertAction(title: "Mock Therapy Settings", style: .default) { _ in
                let therapySettings = TherapySettings.mockTherapySettings
                self.settingsManager.mutateLoopSettings { settings in
                    settings.glucoseTargetRangeSchedule = therapySettings.glucoseTargetRangeSchedule
                    settings.preMealTargetRange = therapySettings.correctionRangeOverrides?.preMeal
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
        
        actionSheet.addAction(UIAlertAction(title: "Delete Pump Manager", style: .destructive) { _ in
            self.deviceManager.pumpManager?.prepareForDeactivation(){ [weak self] _ in
                self?.deviceManager.pumpManager?.notifyDelegateOfDeactivation() { }
            }
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
            self.simulatedData.purgeHistoricalCoreData() { error in
                DispatchQueue.main.async {
                    if let error = error {
                        dismissActivityIndicator()
                        self.presentError(error)
                        return
                    }

                    self.simulatedData.generateSimulatedHistoricalCoreData() { error in
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
            self.simulatedData.purgeHistoricalCoreData() { error in
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
        log.default("PumpManager:%{public}@ did update status", String(describing: type(of: pumpManager)))
        
        if basalDeliveryState == status.basalDeliveryState,
           bolusState == status.bolusState
        {
            // if the basal and bolus states have not changed, still update UI
            Task { @MainActor in
                refreshContext.update(with: .status)
                await self.reloadData(animated: true)
            }
        } else {
            basalDeliveryState = status.basalDeliveryState
            bolusState = status.bolusState
        }
    }
}

extension StatusTableViewController: CGMManagerStatusObserver {
    func cgmManager(_ manager: CGMManager, didUpdate status: CGMManagerStatus) {
        refreshContext.update(with: .status)
        Task { await reloadData(animated: true) }
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
                Task {
                    self.refreshContext.update(with: .insulin)
                    await self.reloadData(animated: true)
                }
            })
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
        guard let maximumBasalRate = settingsManager.settings.maximumBasalRatePerHour,
              let maxBolus = settingsManager.settings.maximumBolus,
              let basalSchedule = settingsManager.settings.basalRateSchedule else
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
        Task { await reloadData(animated: true) }
    }
}

// MARK: - SettingsViewModel delegation
extension StatusTableViewController: SettingsViewModelDelegate {
    var automaticDosingEnabled: Bool {
        get {
            settingsManager.dosingEnabled
        }
        set {
            if settingsManager.dosingEnabled != newValue {
                settingsManager.dosingEnabled = newValue
            }
        }
    }
    
    var closedLoopDescriptiveText: String? {
        return deviceManager.closedLoopDisallowedLocalizedDescription
    }
    
    var automationHistory: [AutomationHistoryEntry] {
        loopManager.automationHistory
    }

    func dosingEnabledChanged(_ value: Bool) {
        settingsManager.mutateLoopSettings { settings in
            settings.dosingEnabled = value
        }
    }
    
    func dosingStrategyChanged(_ strategy: AutomaticDosingStrategy) {
        settingsManager.mutateLoopSettings { settings in
            settings.automaticDosingStrategy = strategy
        }
    }

    func didTapIssueReport() {
        // TODO: this dismiss here is temporary, until we know exactly where
        // we want this screen to belong in the navigation flow
        dismiss(animated: true) {
            let vc = CommandResponseViewController.generateDiagnosticReport(reportGenerator: self.diagnosticReportGenerator)
            vc.title = NSLocalizedString("Issue Report", comment: "The view controller title for the issue report screen")
            self.show(vc, sender: nil)
        }
    }
}

// MARK: - Services delegation

extension StatusTableViewController: ServicesViewModelDelegate {
    func addService(withIdentifier identifier: String) {
        switch servicesManager.setupService(withIdentifier: identifier) {
        case .failure(let error):
            log.default("Failure to setup service with identifier '%{public}@': %{public}@", identifier, String(describing: error))
        case .success(let success):
            switch success {
            case .userInteractionRequired(var setupViewController):
                setupViewController.serviceOnboardingDelegate = servicesManager
                setupViewController.completionDelegate = self
                show(setupViewController, sender: self)
            case .createdAndOnboarded:
                log.default("Service with identifier '%{public}@' created and onboarded", identifier)
            }
        }
    }

    func gotoService(withIdentifier identifier: String) {
        guard let serviceUI = servicesManager.activeServices.first(where: { $0.pluginIdentifier == identifier }) as? ServiceUI else {
            return
        }
        showServiceSettings(serviceUI)
    }

    fileprivate func showServiceSettings(_ serviceUI: ServiceUI) {
        var settingsViewController = serviceUI.settingsViewController(colorPalette: .default, allowDebugFeatures: FeatureFlags.allowDebugFeatures)
        settingsViewController.serviceOnboardingDelegate = servicesManager
        settingsViewController.completionDelegate = self
        show(settingsViewController, sender: self)
    }
}

extension StatusTableViewController {
    override func scrollViewDidScroll(_ scrollView: UIScrollView) {
        updateStatusBar()
    }
}
