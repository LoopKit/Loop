//
//  StatusTableViewController.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 9/6/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

import UIKit
import CarbKit
import GlucoseKit
import HealthKit
import InsulinKit
import LoopKit
import LoopUI
import SwiftCharts


/// Describes the state within the bolus setting flow
///
/// - recommended: A bolus recommendation was discovered and the bolus view controller is presenting/presented
/// - enacting: A bolus was requested by the user and is pending with the device manager
private enum BolusState {
    case recommended
    case enacting
}


private extension RefreshContext {
    static let all: Set<RefreshContext> = [.status, .glucose, .insulin, .carbs, .targets]
}


final class StatusTableViewController: ChartsTableViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        charts.glucoseDisplayRange = (
            min: HKQuantity(unit: HKUnit.milligramsPerDeciliter(), doubleValue: 100),
            max: HKQuantity(unit: HKUnit.milligramsPerDeciliter(), doubleValue: 175)
        )

        let notificationCenter = NotificationCenter.default

        notificationObservers += [
            notificationCenter.addObserver(forName: .LoopDataUpdated, object: deviceManager.loopManager, queue: nil) { [unowned self] note in
                let context = note.userInfo?[LoopDataManager.LoopUpdateContextKey] as! LoopDataManager.LoopUpdateContext.RawValue
                DispatchQueue.main.async {
                    switch LoopDataManager.LoopUpdateContext(rawValue: context) {
                    case .none, .bolus?:
                        self.refreshContext.formUnion([.status, .insulin])
                    case .preferences?:
                        self.refreshContext.formUnion([.status, .targets])
                    case .carbs?:
                        self.refreshContext.update(with: .carbs)
                    case .glucose?:
                        self.refreshContext.formUnion([.glucose, .carbs])
                    case .tempBasal?:
                        self.refreshContext.update(with: .insulin)
                    }

                    self.hudView?.loopCompletionHUD.loopInProgress = false
                    self.reloadData(animated: true)
                }
            },
            notificationCenter.addObserver(forName: .LoopRunning, object: deviceManager.loopManager, queue: nil) { [unowned self] _ in
                DispatchQueue.main.async {
                    self.hudView?.loopCompletionHUD.loopInProgress = true
                }
            }
        ]

        if let gestureRecognizer = charts.gestureRecognizer {
            tableView.addGestureRecognizer(gestureRecognizer)
        }

        tableView.estimatedRowHeight = 70

        // Estimate an initial value
        landscapeMode = UIScreen.main.bounds.size.width > UIScreen.main.bounds.size.height

        // Toolbar
        toolbarItems![0].accessibilityLabel = NSLocalizedString("Add Meal", comment: "The label of the carb entry button")
        toolbarItems![0].tintColor = UIColor.COBTintColor
        toolbarItems![4].accessibilityLabel = NSLocalizedString("Bolus", comment: "The label of the bolus entry button")
        toolbarItems![4].tintColor = UIColor.doseTintColor
        toolbarItems![8].accessibilityLabel = NSLocalizedString("Settings", comment: "The label of the settings button")
        toolbarItems![8].tintColor = UIColor.secondaryLabelColor
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()

        if !visible {
            refreshContext.formUnion(RefreshContext.all)
        }
    }

    var appearedOnce = false

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        if !appearedOnce {
            appearedOnce = true

            if deviceManager.loopManager.authorizationRequired {
                deviceManager.loopManager.authorize {
                    DispatchQueue.main.async {
                        self.reloadData()
                    }
                }
            }
        }

        AnalyticsManager.shared.didDisplayStatusScreen()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        if presentedViewController == nil {
            navigationController?.setNavigationBarHidden(false, animated: animated)
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        refreshContext.update(with: .size(size))

        super.viewWillTransition(to: size, with: coordinator)
    }

    // MARK: - State

    override var active: Bool {
        didSet {
            hudView?.loopCompletionHUD.assertTimer(active)
        }
    }

    private var bolusState: BolusState? {
        didSet {
            refreshContext.update(with: .status)
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
        return !landscapeMode && recommendedTempBasal != nil
    }

    override func reloadData(animated: Bool = false) {
        guard active && visible && !reloading && !refreshContext.isEmpty && !deviceManager.loopManager.authorizationRequired else {
            return
        }
        var currentContext = refreshContext
        var retryContext: Set<RefreshContext> = []
        self.refreshContext = []
        reloading = true

        // How far back should we show data? Use the screen size as a guide.
        let minimumSegmentWidth: CGFloat = 50
        let availableWidth = (currentContext.newSize ?? self.tableView.bounds.size).width - self.charts.fixedHorizontalMargin
        let totalHours = floor(Double(availableWidth / minimumSegmentWidth))
        let futureHours = ceil((deviceManager.loopManager.insulinModelSettings?.model.effectDuration ?? .hours(4)).hours)
        let historyHours = max(1, totalHours - futureHours)

        var components = DateComponents()
        components.minute = 0
        let date = Date(timeIntervalSinceNow: -TimeInterval(hours: historyHours))
        let chartStartDate = Calendar.current.nextDate(after: date, matching: components, matchingPolicy: .strict, direction: .backward) ?? date
        if charts.startDate != chartStartDate {
            currentContext.formUnion(RefreshContext.all)
        }
        charts.startDate = chartStartDate

        charts.maxEndDate = chartStartDate.addingTimeInterval(.hours(totalHours))

        let reloadGroup = DispatchGroup()
        var dosingEnabled: Bool?
        var lastLoopCompleted: Date?
        var lastLoopError: Error?
        var lastReservoirValue: ReservoirValue?
        var lastTempBasal: DoseEntry?
        var newRecommendedTempBasal: LoopDataManager.TempBasalRecommendation?

        reloadGroup.enter()
        deviceManager.loopManager.glucoseStore.preferredUnit { (unit, error) in
            if let unit = unit {
                self.charts.glucoseUnit = unit
            }

            if currentContext.contains(.glucose) {
                reloadGroup.enter()
                self.deviceManager.loopManager.glucoseStore.getGlucoseValues(start: chartStartDate) { (result) -> Void in
                    switch result {
                    case .failure(let error):
                        self.deviceManager.logger.addError(error, fromSource: "GlucoseStore")
                        retryContext.update(with: .glucose)
                        self.charts.setGlucoseValues([])
                    case .success(let values):
                        self.charts.setGlucoseValues(values)
                    }

                    reloadGroup.leave()
                }
            }

            // TODO: Don't always assume currentContext.contains(.status)
            reloadGroup.enter()
            self.deviceManager.loopManager.getLoopState { (manager, state) -> Void in
                self.charts.setPredictedGlucoseValues(state.predictedGlucose ?? [])

                // Retry this refresh again if predicted glucose isn't available
                if state.predictedGlucose == nil {
                    retryContext.update(with: .status)
                }

                switch self.bolusState {
                case .recommended?, .enacting?:
                    newRecommendedTempBasal = nil
                case .none:
                    newRecommendedTempBasal = state.recommendedTempBasal
                }

                lastTempBasal = state.lastTempBasal
                lastLoopCompleted = state.lastLoopCompleted
                lastLoopError = state.error

                if let lastPoint = self.charts.predictedGlucosePoints.last?.y {
                    self.eventualGlucoseDescription = String(describing: lastPoint)
                } else {
                    self.eventualGlucoseDescription = nil
                }

                if currentContext.contains(.targets) {
                    if let schedule = manager.settings.glucoseTargetRangeSchedule {
                        self.charts.targetPointsCalculator = GlucoseRangeScheduleCalculator(schedule)
                    } else {
                        self.charts.targetPointsCalculator = nil
                    }
                }

                if currentContext.contains(.carbs) {
                    reloadGroup.enter()
                    manager.carbStore.getCarbsOnBoardValues(start: chartStartDate, effectVelocities: manager.settings.dynamicCarbAbsorptionEnabled ? state.insulinCounteractionEffects : nil) { (values) in
                        self.charts.setCOBValues(values)
                        reloadGroup.leave()
                    }
                }

                dosingEnabled = manager.settings.dosingEnabled

                reloadGroup.leave()
            }

            reloadGroup.leave()
        }

        if currentContext.contains(.insulin) {
            reloadGroup.enter()
            deviceManager.loopManager.doseStore.getInsulinOnBoardValues(start: chartStartDate) { (result) -> Void in
                switch result {
                case .failure(let error):
                    self.deviceManager.logger.addError(error, fromSource: "DoseStore")
                    retryContext.update(with: .insulin)
                    self.charts.setIOBValues([])
                case .success(let values):
                    self.charts.setIOBValues(values)
                }
                reloadGroup.leave()
            }

            reloadGroup.enter()
            deviceManager.loopManager.doseStore.getNormalizedDoseEntries(start: chartStartDate) { (result) -> Void in
                switch result {
                case .failure(let error):
                    self.deviceManager.logger.addError(error, fromSource: "DoseStore")
                    retryContext.update(with: .insulin)
                    self.charts.setDoseEntries([])
                case .success(let doses):
                    self.charts.setDoseEntries(doses)
                }
                reloadGroup.leave()
            }

            reloadGroup.enter()
            deviceManager.loopManager.doseStore.getTotalUnitsDelivered(since: Calendar.current.startOfDay(for: Date())) { (result) in
                switch result {
                case .failure:
                    retryContext.update(with: .insulin)
                    self.totalDelivery = nil
                case .success(let total):
                    self.totalDelivery = total.value
                }

                reloadGroup.leave()
            }

            reloadGroup.enter()
            deviceManager.loopManager.doseStore.getReservoirValues(since: Date(timeIntervalSinceNow: .minutes(-30))) { (result) in
                switch result {
                case .success(let values):
                    lastReservoirValue = values.first
                case .failure:
                    retryContext.update(with: .insulin)
                }

                reloadGroup.leave()
            }
        }

        workoutMode = deviceManager.loopManager.settings.glucoseTargetRangeSchedule?.overrideEnabledForContext(.workout)
        preMealMode = deviceManager.loopManager.settings.glucoseTargetRangeSchedule?.overrideEnabledForContext(.preMeal)

        reloadGroup.notify(queue: .main) {
            self.tableView.beginUpdates()
            if let hudView = self.hudView {
                // Loop completion HUD
                hudView.loopCompletionHUD.lastLoopCompleted = lastLoopCompleted
                self.lastLoopError = lastLoopError
                if let dosingEnabled = dosingEnabled {
                    hudView.loopCompletionHUD.dosingEnabled = dosingEnabled
                }

                // Glucose HUD
                if let glucose = self.deviceManager.loopManager.glucoseStore.latestGlucose {
                    hudView.glucoseHUD.setGlucoseQuantity(glucose.quantity.doubleValue(for: self.charts.glucoseUnit),
                        at: glucose.startDate,
                        unit: self.charts.glucoseUnit,
                        sensor: self.deviceManager.sensorInfo
                    )
                }

                // Net basal rate HUD
                let date = lastTempBasal?.startDate ?? Date()
                if let scheduledBasal = self.deviceManager.loopManager.basalRateSchedule?.between(start: date, end: date).first {
                    let netBasal = NetBasal(
                        lastTempBasal: lastTempBasal,
                        maxBasal: self.deviceManager.loopManager.settings.maximumBasalRatePerHour,
                        scheduledBasal: scheduledBasal
                    )

                    hudView.basalRateHUD.setNetBasalRate(netBasal.rate, percent: netBasal.percent, at: netBasal.start)
                }

                // Reservoir HUD
                if let reservoir = lastReservoirValue {
                    if let capacity = self.deviceManager.pumpState?.pumpModel?.reservoirCapacity {
                        hudView.reservoirVolumeHUD.reservoirLevel = min(1, max(0, Double(reservoir.unitVolume / Double(capacity))))
                    }

                    hudView.reservoirVolumeHUD.setReservoirVolume(volume: reservoir.unitVolume, at: reservoir.startDate)
                }

                // Battery HUD
                hudView.batteryHUD.batteryLevel = self.deviceManager.pumpBatteryChargeRemaining
            }

            // Fetch the current IOB subtitle
            if let index = self.charts.iobPoints.closestIndexPriorToDate(Date()) {
                self.currentIOBDescription = String(describing: self.charts.iobPoints[index].y)
            } else {
                self.currentIOBDescription = nil
            }
            // Fetch the current COB subtitle
            if let index = self.charts.cobPoints.closestIndexPriorToDate(Date()) {
                self.currentCOBDescription = String(describing: self.charts.cobPoints[index].y)
            } else {
                self.currentCOBDescription = nil
            }

            self.charts.prerender()

            // Show/hide the table view rows
            let hudWasVisible = self.shouldShowHUD
            let statusWasVisible = self.shouldShowStatus

            let oldRecommendedTempBasal = self.recommendedTempBasal
            self.recommendedTempBasal = newRecommendedTempBasal
            if let newSize = currentContext.newSize {
                self.landscapeMode = newSize.width > newSize.height
            }

            let hudIsVisible = self.shouldShowHUD
            let statusIsVisible = self.shouldShowStatus

            switch (hudWasVisible, hudIsVisible) {
            case (false, true):
                self.tableView.insertRows(at: [IndexPath(row: 0, section: Section.hud.rawValue)], with: animated ? .top : .none)
            case (true, false):
                self.tableView.deleteRows(at: [IndexPath(row: 0, section: Section.hud.rawValue)], with: animated ? .top : .none)
            default:
                break
            }

            switch (statusWasVisible, statusIsVisible) {
            case (true, true):
                if let old = oldRecommendedTempBasal, let new = newRecommendedTempBasal, old != new {
                    self.tableView.reloadRows(at: [IndexPath(row: 0, section: Section.status.rawValue)], with: animated ? .top : .none)
                }
            case (false, true):
                self.tableView.insertRows(at: [IndexPath(row: 0, section: Section.status.rawValue)], with: animated ? .top : .none)
            case (true, false):
                self.tableView.deleteRows(at: [IndexPath(row: 0, section: Section.status.rawValue)], with: animated ? .top : .none)
            default:
                break
            }

            for case let cell as ChartTableViewCell in self.tableView.visibleCells {
                cell.reloadChart()

                if let indexPath = self.tableView.indexPath(for: cell) {
                    self.tableView(self.tableView, updateSubtitleFor: cell, at: indexPath)
                }
            }
            self.tableView.endUpdates()

            self.reloading = false
            // Trigger a reload if new context exists.
            if !self.refreshContext.isEmpty {
                self.refreshContext.formUnion(retryContext)
                self.reloadData()
            } else {
                // If our only context is retry, wait for the next trigger
                self.refreshContext.formUnion(retryContext)
            }
        }
    }

    private enum Section: Int {
        case hud = 0
        case status
        case charts

        static let count = 3
    }

    // MARK: - Chart Section Data

    private enum ChartRow: Int {
        case glucose = 0
        case iob
        case dose
        case cob

        static let count = 4
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

    private enum StatusRow: Int {
        case recommendedBasal = 0

        static let count = 1
    }

    private var recommendedTempBasal: LoopDataManager.TempBasalRecommendation?

    private var settingTempBasal: Bool = false {
        didSet {
            if let cell = tableView.cellForRow(at: IndexPath(row: StatusRow.recommendedBasal.rawValue, section: Section.status.rawValue)) {
                if settingTempBasal {
                    let indicatorView = UIActivityIndicatorView(activityIndicatorStyle: .gray)
                    indicatorView.startAnimating()
                    cell.accessoryView = indicatorView
                } else {
                    cell.accessoryView = nil
                }
            }
        }
    }

    // MARK: - Toolbar data

    private var preMealMode: Bool? = nil {
        didSet {
            guard oldValue != preMealMode else {
                return
            }

            if let preMealMode = preMealMode {
                toolbarItems![2] = createPreMealButtonItem(selected: preMealMode)
            } else {
                toolbarItems![2].isEnabled = false
            }
        }
    }

    private var workoutMode: Bool? = nil {
        didSet {
            guard oldValue != workoutMode else {
                return
            }

            if let workoutMode = workoutMode {
                toolbarItems![6] = createWorkoutButtonItem(selected: workoutMode)
            } else {
                toolbarItems![6].isEnabled = false
            }
        }
    }

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        return Section.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .hud:
            return shouldShowHUD ? 1 : 0
        case .charts:
            return ChartRow.count
        case .status:
            return shouldShowStatus ? StatusRow.count : 0
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch Section(rawValue: indexPath.section)! {
        case .hud:
            let cell = tableView.dequeueReusableCell(withIdentifier: HUDViewTableViewCell.className, for: indexPath) as! HUDViewTableViewCell
            self.hudView = cell.hudView

            return cell
        case .charts:
            let cell = tableView.dequeueReusableCell(withIdentifier: ChartTableViewCell.className, for: indexPath) as! ChartTableViewCell

            switch ChartRow(rawValue: indexPath.row)! {
            case .glucose:
                cell.chartContentView.chartGenerator = { [unowned self] (frame) in
                    return self.charts.glucoseChartWithFrame(frame)?.view
                }
                cell.titleLabel?.text = NSLocalizedString("Glucose", comment: "The title of the glucose and prediction graph")
            case .iob:
                cell.chartContentView.chartGenerator = { [unowned self] (frame) in
                    return self.charts.iobChartWithFrame(frame)?.view
                }
                cell.titleLabel?.text = NSLocalizedString("Active Insulin", comment: "The title of the Insulin On-Board graph")
            case .dose:
                cell.chartContentView?.chartGenerator = { [unowned self] (frame) in
                    return self.charts.doseChartWithFrame(frame)?.view
                }
                cell.titleLabel?.text = NSLocalizedString("Insulin Delivery", comment: "The title of the insulin delivery graph")
            case .cob:
                cell.chartContentView?.chartGenerator = { [unowned self] (frame) in
                    return self.charts.cobChartWithFrame(frame)?.view
                }
                cell.titleLabel?.text = NSLocalizedString("Active Carbohydrates", comment: "The title of the Carbs On-Board graph")
            }

            self.tableView(tableView, updateSubtitleFor: cell, at: indexPath)

            let alpha: CGFloat = charts.gestureRecognizer?.state == .possible ? 1 : 0
            cell.titleLabel?.alpha = alpha
            cell.subtitleLabel?.alpha = alpha

            cell.subtitleLabel?.textColor = UIColor.secondaryLabelColor

            return cell
        case .status:
            let cell = tableView.dequeueReusableCell(withIdentifier: TitleSubtitleTableViewCell.className, for: indexPath) as! TitleSubtitleTableViewCell
            cell.selectionStyle = .none

            switch StatusRow(rawValue: indexPath.row)! {
            case .recommendedBasal:
                if let recommendedTempBasal = recommendedTempBasal {
                    let timeFormatter = DateFormatter()
                    timeFormatter.dateStyle = .none
                    timeFormatter.timeStyle = .short

                    cell.subtitleLabel?.text = String(format: NSLocalizedString("%1$@ U/hour @ %2$@", comment: "The format for recommended temp basal rate and time. (1: localized rate number)(2: localized time)"), NumberFormatter.localizedString(from: NSNumber(value: recommendedTempBasal.rate), number: .decimal), timeFormatter.string(from: recommendedTempBasal.recommendedDate))
                    cell.selectionStyle = .default
                } else {
                    cell.subtitleLabel?.text = "––"
                }

                if settingTempBasal {
                    let indicatorView = UIActivityIndicatorView(activityIndicatorStyle: .gray)
                    indicatorView.startAnimating()
                    cell.accessoryView = indicatorView
                } else {
                    cell.accessoryView = nil
                }
            }

            return cell
        }
    }

    private func tableView(_ tableView: UITableView, updateSubtitleFor cell: ChartTableViewCell, at indexPath: IndexPath) {
        switch Section(rawValue: indexPath.section)! {
        case .charts:
            switch ChartRow(rawValue: indexPath.row)! {
            case .glucose:
                if let eventualGlucose = eventualGlucoseDescription {
                    cell.subtitleLabel?.text = String(format: NSLocalizedString("Eventually %@", comment: "The subtitle format describing eventual glucose. (1: localized glucose value description)"), eventualGlucose)
                } else {
                    cell.subtitleLabel?.text = nil
                }
            case .iob:
                if let currentIOB = currentIOBDescription {
                    cell.subtitleLabel?.text = currentIOB
                } else {
                    cell.subtitleLabel?.text = nil
                }
            case .dose:
                let integerFormatter = NumberFormatter()
                integerFormatter.maximumFractionDigits = 0

                if  let total = totalDelivery,
                    let totalString = integerFormatter.string(from: NSNumber(value: total)) {
                    cell.subtitleLabel?.text = String(format: NSLocalizedString("%@ U Total", comment: "The subtitle format describing total insulin. (1: localized insulin total)"), totalString)
                } else {
                    cell.subtitleLabel?.text = nil
                }
            case .cob:
                if let currentCOB = currentCOBDescription {
                    cell.subtitleLabel?.text = currentCOB
                } else {
                    cell.subtitleLabel?.text = nil
                }
            }
        case .hud, .status:
            break
        }
    }

    // MARK: - UITableViewDelegate

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        switch Section(rawValue: indexPath.section)! {
        case .charts:
            // 20: Status bar
            // 70: HUD
            // 44: Toolbar
            let availableSize = max(tableView.bounds.width, tableView.bounds.height) - 20 - 70 - 44

            switch ChartRow(rawValue: indexPath.row)! {
            case .glucose:
                return max(106, 0.37 * availableSize)
            case .iob, .dose, .cob:
                return max(106, 0.21 * availableSize)
            }
        case .hud, .status:
            return UITableViewAutomaticDimension
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        switch Section(rawValue: indexPath.section)! {
        case .charts:
            switch ChartRow(rawValue: indexPath.row)! {
            case .glucose:
                performSegue(withIdentifier: PredictionTableViewController.className, sender: indexPath)
            case .iob, .dose:
                performSegue(withIdentifier: InsulinDeliveryTableViewController.className, sender: indexPath)
            case .cob:
                performSegue(withIdentifier: CarbAbsorptionViewController.className, sender: indexPath)
            }
        case .status:
            switch StatusRow(rawValue: indexPath.row)! {
            case .recommendedBasal:
                tableView.deselectRow(at: indexPath, animated: true)

                if recommendedTempBasal != nil && !settingTempBasal {
                    settingTempBasal = true
                    self.deviceManager.loopManager.enactRecommendedTempBasal { (error) in
                        DispatchQueue.main.async {
                            self.settingTempBasal = false

                            if let error = error {
                                self.deviceManager.logger.addError(error, fromSource: "TempBasal")
                                self.presentAlertController(with: error)
                            } else {
                                self.refreshContext.update(with: .status)
                                self.reloadData()
                            }
                        }
                    }
                }
            }
        case .hud:
            break
        }
    }

    // MARK: - Actions

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        super.prepare(for: segue, sender: sender)

        var targetViewController = segue.destination

        if let navVC = targetViewController as? UINavigationController, let topViewController = navVC.topViewController {
            targetViewController = topViewController
        }

        switch targetViewController {
        case let vc as CarbAbsorptionViewController:
            vc.deviceManager = deviceManager
            vc.hidesBottomBarWhenPushed = true
        case let vc as CarbEntryTableViewController:
            vc.carbStore = deviceManager.loopManager.carbStore
            vc.hidesBottomBarWhenPushed = true
        case let vc as CarbEntryEditViewController:
            vc.defaultAbsorptionTimes = deviceManager.loopManager.carbStore.defaultAbsorptionTimes
            vc.preferredUnit = deviceManager.loopManager.carbStore.preferredUnit
        case let vc as InsulinDeliveryTableViewController:
            vc.doseStore = deviceManager.loopManager.doseStore
            vc.hidesBottomBarWhenPushed = true
        case let vc as BolusViewController:
            vc.configureWithLoopManager(self.deviceManager.loopManager,
                recommendation: sender as? BolusRecommendation,
                glucoseUnit: self.charts.glucoseUnit
            )
        case let vc as PredictionTableViewController:
            vc.deviceManager = deviceManager
        case let vc as SettingsTableViewController:
            vc.dataManager = deviceManager
        default:
            break
        }
    }

    /// Unwind segue action from the CarbEntryEditViewController
    ///
    /// - parameter segue: The unwind segue
    @IBAction func unwindFromEditing(_ segue: UIStoryboardSegue) {
        guard let carbVC = segue.source as? CarbEntryEditViewController, let updatedEntry = carbVC.updatedCarbEntry else {
            return
        }

        deviceManager.loopManager.addCarbEntryAndRecommendBolus(updatedEntry) { (result) -> Void in
            DispatchQueue.main.async {
                switch result {
                case .success(let recommendation):
                    if self.active && self.visible, let bolus = recommendation?.amount, bolus > 0 {
                        self.bolusState = .recommended
                        self.performSegue(withIdentifier: BolusViewController.className, sender: recommendation)
                    }
                case .failure(let error):
                    // Ignore bolus wizard errors
                    if error is CarbStore.CarbStoreError {
                        self.presentAlertController(with: error)
                    } else {
                        self.deviceManager.logger.addError(error, fromSource: "Bolus")
                    }
                }
            }
        }
    }

    @IBAction func unwindFromBolusViewController(_ segue: UIStoryboardSegue) {
        if let bolusViewController = segue.source as? BolusViewController {
            if let bolus = bolusViewController.bolus, bolus > 0 {
                self.bolusState = .enacting
                deviceManager.enactBolus(units: bolus) { (_) in
                    self.bolusState = nil
                }
            } else {
                self.bolusState = nil
            }
        }
    }

    @IBAction func unwindFromSettings(_ segue: UIStoryboardSegue) {
    }

    private func createPreMealButtonItem(selected: Bool) -> UIBarButtonItem {
        let item = UIBarButtonItem(image: UIImage.preMealImage(selected: selected), style: .plain, target: self, action: #selector(togglePreMealMode(_:)))
        item.accessibilityLabel = NSLocalizedString("Pre-Meal Targets", comment: "The label of the pre-meal mode toggle button")

        if selected {
            item.accessibilityTraits = item.accessibilityTraits | UIAccessibilityTraitSelected
            item.accessibilityHint = NSLocalizedString("Disables", comment: "The action hint of the workout mode toggle button when enabled")
        } else {
            item.accessibilityHint = NSLocalizedString("Enables", comment: "The action hint of the workout mode toggle button when disabled")
        }

        item.tintColor = UIColor.COBTintColor

        return item
    }

    private func createWorkoutButtonItem(selected: Bool) -> UIBarButtonItem {
        let item = UIBarButtonItem(image: UIImage.workoutImage(selected: selected), style: .plain, target: self, action: #selector(toggleWorkoutMode(_:)))
        item.accessibilityLabel = NSLocalizedString("Workout Targets", comment: "The label of the workout mode toggle button")

        if selected {
            item.accessibilityTraits = item.accessibilityTraits | UIAccessibilityTraitSelected
            item.accessibilityHint = NSLocalizedString("Disables", comment: "The action hint of the workout mode toggle button when enabled")
        } else {
            item.accessibilityHint = NSLocalizedString("Enables", comment: "The action hint of the workout mode toggle button when disabled")
        }

        item.tintColor = UIColor.glucoseTintColor

        return item
    }

    @IBAction func togglePreMealMode(_ sender: UIBarButtonItem) {
        if preMealMode == true {
            deviceManager.loopManager.settings.glucoseTargetRangeSchedule?.clearOverride(matching: .preMeal)
        } else {
            _ = self.deviceManager.loopManager.settings.glucoseTargetRangeSchedule?.setOverride(.preMeal, until: Date(timeIntervalSinceNow: .hours(1)))
        }
    }

    @IBAction func toggleWorkoutMode(_ sender: UIBarButtonItem) {
        if workoutMode == true {
            deviceManager.loopManager.settings.glucoseTargetRangeSchedule?.clearOverride(matching: .workout)
        } else {
            let vc = UIAlertController(workoutDurationSelectionHandler: { (endDate) in
                _ = self.deviceManager.loopManager.settings.glucoseTargetRangeSchedule?.setOverride(.workout, until: endDate)
            })

            present(vc, animated: true, completion: nil)
        }
    }

    // MARK: - HUDs

    @IBOutlet var hudView: HUDView? {
        didSet {
            guard let hudView = hudView, hudView != oldValue else {
                return
            }

            let statusTapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(showLastError(_:)))
            hudView.loopCompletionHUD.addGestureRecognizer(statusTapGestureRecognizer)
            hudView.loopCompletionHUD.accessibilityHint = NSLocalizedString("Shows last loop error", comment: "Loop Completion HUD accessibility hint")

            let glucoseTapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(openCGMApp(_:)))
            hudView.glucoseHUD.addGestureRecognizer(glucoseTapGestureRecognizer)
            
            if deviceManager.cgm?.appURL != nil {
                hudView.glucoseHUD.accessibilityHint = NSLocalizedString("Launches CGM app", comment: "Glucose HUD accessibility hint")
            }

            hudView.loopCompletionHUD.stateColors = .loopStatus
            hudView.glucoseHUD.stateColors = .cgmStatus
            hudView.glucoseHUD.tintColor = .glucoseTintColor
            hudView.basalRateHUD.tintColor = .doseTintColor
            hudView.reservoirVolumeHUD.stateColors = .pumpStatus
            hudView.batteryHUD.stateColors = .pumpStatus

            refreshContext.update(with: .status)
            reloadData()
        }
    }

    @objc private func showLastError(_: Any) {
        // First, check whether we have a device error after the most recent completion date
        if let deviceError = deviceManager.lastError,
            deviceError.date > (hudView?.loopCompletionHUD.lastLoopCompleted ?? .distantPast)
        {
            self.presentAlertController(with: deviceError.error)
        } else if let lastLoopError = lastLoopError {
            self.presentAlertController(with: lastLoopError)
        }
    }

    @objc private func openCGMApp(_: Any) {
        if let url = deviceManager.cgm?.appURL, UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        }
    }
}
