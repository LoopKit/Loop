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
    static let all: RefreshContext = [.status, .glucose, .insulin, .carbs, .targets]
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
            notificationCenter.addObserver(forName: .LoopDataUpdated, object: deviceManager.loopManager, queue: nil) { note in
                let context = note.userInfo?[LoopDataManager.LoopUpdateContextKey] as! LoopDataManager.LoopUpdateContext.RawValue
                DispatchQueue.main.async {
                    switch LoopDataManager.LoopUpdateContext(rawValue: context) {
                    case .none, .bolus?:
                        self.refreshContext.update(with: .status)
                    case .preferences?:
                        self.refreshContext.update(with: [.status, .targets])
                    case .carbs?:
                        self.refreshContext.update(with: .carbs)
                    case .glucose?:
                        self.refreshContext.update(with: .glucose)
                    case .tempBasal?:
                        self.refreshContext.update(with: .insulin)
                    }

                    self.hudView.loopCompletionHUD.loopInProgress = false
                    self.reloadData(animated: true)
                }
            },
            notificationCenter.addObserver(forName: .LoopRunning, object: deviceManager.loopManager, queue: nil) { _ in
                DispatchQueue.main.async {
                    self.hudView.loopCompletionHUD.loopInProgress = true
                }
            }
        ]

        if let gestureRecognizer = charts.gestureRecognizer {
            tableView.addGestureRecognizer(gestureRecognizer)
        }

        // Toolbar
        toolbarItems![0].accessibilityLabel = NSLocalizedString("Add Meal", comment: "The label of the carb entry button")
        toolbarItems![0].tintColor = UIColor.COBTintColor
        toolbarItems![2].accessibilityLabel = NSLocalizedString("Bolus", comment: "The label of the bolus entry button")
        toolbarItems![2].tintColor = UIColor.doseTintColor
        toolbarItems![6].accessibilityLabel = NSLocalizedString("Settings", comment: "The label of the settings button")
        toolbarItems![6].tintColor = UIColor.secondaryLabelColor
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()

        if !visible {
            refreshContext = .all
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        AnalyticsManager.sharedManager.didDisplayStatusScreen()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        if presentedViewController == nil {
            navigationController?.setNavigationBarHidden(false, animated: animated)
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        refreshContext.update(with: .status)

        super.viewWillTransition(to: size, with: coordinator)
    }

    // MARK: - State

    override var active: Bool {
        didSet {
            hudView.loopCompletionHUD.assertTimer(active)
        }
    }

    private var refreshContext = RefreshContext.all

    private var bolusState: BolusState? {
        didSet {
            refreshContext.update(with: .status)
        }
    }

    private var chartStartDate: Date {
        get {
            return charts.startDate
        }
        set {
            if newValue != chartStartDate {
                refreshContext = .all
            }

            charts.startDate = newValue
        }
    }

    override func reloadData(animated: Bool = false, to size: CGSize? = nil) {
        guard active && visible && !refreshContext.isEmpty else { return }

        // How far back should we show data? Use the screen size as a guide.
        let minimumSegmentWidth: CGFloat = 50
        let availableWidth = (size ?? self.tableView.bounds.size).width - self.charts.fixedHorizontalMargin
        let totalHours = floor(Double(availableWidth / minimumSegmentWidth))
        let historyHours = totalHours - (deviceManager.loopManager.insulinActionDuration ?? TimeInterval(hours: 4)).hours

        var components = DateComponents()
        components.minute = 0
        let date = Date(timeIntervalSinceNow: -TimeInterval(hours: max(1, historyHours)))
        chartStartDate = Calendar.current.nextDate(after: date, matching: components, matchingPolicy: .strict, direction: .backward) ?? date

        let reloadGroup = DispatchGroup()
        var newLastLoopCompleted: Date?
        var newLastTempBasal: DoseEntry?
        var newRecommendedTempBasal: LoopDataManager.TempBasalRecommendation?

        reloadGroup.enter()
        deviceManager.loopManager.glucoseStore.preferredUnit { (unit, error) in
            if let unit = unit {
                self.charts.glucoseUnit = unit
            }

            if self.refreshContext.remove(.glucose) != nil {
                reloadGroup.enter()
                self.deviceManager.loopManager.glucoseStore.getGlucoseValues(start: self.chartStartDate) { (result) -> Void in
                    switch result {
                    case .failure(let error):
                        self.deviceManager.logger.addError(error, fromSource: "GlucoseStore")
                        self.refreshContext.update(with: .glucose)
                        self.charts.setGlucoseValues([])
                    case .success(let values):
                        self.charts.setGlucoseValues(values)
                    }

                    reloadGroup.leave()
                }
            }

            // For now, do this every time
            _ = self.refreshContext.remove(.status)
            reloadGroup.enter()
            self.deviceManager.loopManager.getLoopState { (manager, state) -> Void in
                self.charts.setPredictedGlucoseValues(state.predictedGlucose ?? [])

                // Retry this refresh again if predicted glucose isn't available
                if state.predictedGlucose == nil {
                    self.refreshContext.update(with: .status)
                }

                switch self.bolusState {
                case .recommended?, .enacting?:
                    newRecommendedTempBasal = nil
                case .none:
                    newRecommendedTempBasal = state.recommendedTempBasal
                }

                newLastTempBasal = state.lastTempBasal
                newLastLoopCompleted = state.lastLoopCompleted

                if let lastPoint = self.charts.predictedGlucosePoints.last?.y {
                    self.eventualGlucoseDescription = String(describing: lastPoint)
                } else {
                    self.eventualGlucoseDescription = nil
                }

                if self.refreshContext.remove(.targets) != nil {
                    if let schedule = manager.settings.glucoseTargetRangeSchedule {
                        self.charts.targetPointsCalculator = GlucoseRangeScheduleCalculator(schedule)
                    } else {
                        self.charts.targetPointsCalculator = nil
                    }
                }

                reloadGroup.leave()
            }

            reloadGroup.leave()
        }

        if refreshContext.remove(.insulin) != nil {
            reloadGroup.enter()
            deviceManager.loopManager.doseStore.getInsulinOnBoardValues(start: chartStartDate) { (result) -> Void in
                switch result {
                case .failure(let error):
                    self.deviceManager.logger.addError(error, fromSource: "DoseStore")
                    self.refreshContext.update(with: .insulin)
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
                    self.refreshContext.update(with: .insulin)
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
                    self.refreshContext.update(with: .insulin)
                    self.totalDelivery = nil
                case .success(let total):
                    self.totalDelivery = total.value
                }

                reloadGroup.leave()
            }
        }

        if refreshContext.remove(.carbs) != nil {
            reloadGroup.enter()
            deviceManager.loopManager.carbStore.getCarbsOnBoardValues(startDate: chartStartDate) { (values, error) -> Void in
                if let error = error {
                    self.deviceManager.logger.addError(error, fromSource: "CarbStore")
                    self.refreshContext.update(with: .carbs)
                }

                self.charts.setCOBValues(values)

                reloadGroup.leave()
            }
        }

        if let reservoir = deviceManager.loopManager.doseStore.lastReservoirValue {
            if let capacity = deviceManager.pumpState?.pumpModel?.reservoirCapacity {
                hudView.reservoirVolumeHUD.reservoirLevel = min(1, max(0, Double(reservoir.unitVolume / Double(capacity))))
            }
            
            hudView.reservoirVolumeHUD.setReservoirVolume(volume: reservoir.unitVolume, at: reservoir.startDate)
        }

        if let level = deviceManager.pumpBatteryChargeRemaining {
            hudView.batteryHUD.batteryLevel = level
        }

        hudView.loopCompletionHUD.dosingEnabled = deviceManager.loopManager.settings.dosingEnabled

        workoutMode = deviceManager.loopManager.settings.glucoseTargetRangeSchedule?.workoutModeEnabled

        reloadGroup.notify(queue: .main) {
            if let glucose = self.deviceManager.loopManager.glucoseStore.latestGlucose {
                self.hudView.glucoseHUD.setGlucoseQuantity(glucose.quantity.doubleValue(for: self.charts.glucoseUnit),
                    at: glucose.startDate,
                    unit: self.charts.glucoseUnit,
                    sensor: self.deviceManager.sensorInfo
                )
            }

            // Loop completion HUD
            self.hudView.loopCompletionHUD.lastLoopCompleted = newLastLoopCompleted

            // Net basal rate HUD
            let date = newLastTempBasal?.startDate ?? Date()
            if let scheduledBasal = self.deviceManager.loopManager.basalRateSchedule?.between(start: date,
                                                                                end: date).first
            {
                let netBasal = NetBasal(
                    lastTempBasal: newLastTempBasal,
                    maxBasal: self.deviceManager.loopManager.settings.maximumBasalRatePerHour,
                    scheduledBasal: scheduledBasal
                )

                self.hudView.basalRateHUD.setNetBasalRate(netBasal.rate, percent: netBasal.percent, at: netBasal.startDate)
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

            // Show/hide the recommended temp basal row
            let oldRecommendedTempBasal = self.recommendedTempBasal
            self.recommendedTempBasal = newRecommendedTempBasal
            switch (oldRecommendedTempBasal, newRecommendedTempBasal) {
            case (let old?, let new?) where old != new:
                self.tableView.reloadRows(at: [IndexPath(row: 0, section: Section.status.rawValue)], with: animated ? .top : .none)
            case (.none, .some):
                self.tableView.insertRows(at: [IndexPath(row: 0, section: Section.status.rawValue)], with: animated ? .top : .none)
            case (.some, .none):
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
        }
    }

    private enum Section: Int {
        case status = 0
        case charts

        static let count = 2
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

    private var workoutMode: Bool? = nil {
        didSet {
            guard oldValue != workoutMode else {
                return
            }

            if let workoutMode = workoutMode {
                toolbarItems![4] = createWorkoutButtonItem(selected: workoutMode)
            } else {
                toolbarItems![4].isEnabled = false
            }
        }
    }

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        return Section.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .charts:
            return ChartRow.count
        case .status:
            return self.recommendedTempBasal == nil ? 0 : StatusRow.count
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch Section(rawValue: indexPath.section)! {
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
        case .status:
            break
        }
    }

    // MARK: - UITableViewDelegate

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        switch Section(rawValue: indexPath.section)! {
        case .charts:
            // 20: Status bar
            // 44: Toolbar
            let availableSize = max(tableView.bounds.width, tableView.bounds.height) - 20 - (tableView.tableHeaderView?.frame.height ?? 0) - 44

            switch ChartRow(rawValue: indexPath.row)! {
            case .glucose:
                return max(100, 0.37 * availableSize)
            case .iob, .dose, .cob:
                return max(100, 0.21 * availableSize)
            }
        case .status:
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
                performSegue(withIdentifier: CarbEntryTableViewController.className, sender: indexPath)
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
        }
    }

    // MARK: - Actions

    override func shouldPerformSegue(withIdentifier identifier: String, sender: Any?) -> Bool {
        if identifier == CarbEntryEditViewController.className {
            if deviceManager.loopManager.carbStore.authorizationRequired {
                deviceManager.loopManager.carbStore.authorize { (success, error) in
                    if success {
                        self.performSegue(withIdentifier: CarbEntryEditViewController.className, sender: sender)
                    }
                }
                return false
            }
        }

        return true
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        super.prepare(for: segue, sender: sender)

        var targetViewController = segue.destination

        if let navVC = targetViewController as? UINavigationController, let topViewController = navVC.topViewController {
            targetViewController = topViewController
        }

        switch targetViewController {
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
            self.deviceManager.loopManager.getLoopState { (manager, state) in
                let maximumBolus = manager.settings.maximumBolus

                let activeInsulin = state.insulinOnBoard?.value
                let activeCarbohydrates = state.carbsOnBoard?.quantity.doubleValue(for: HKUnit.gram())
                let bolusRecommendation: BolusRecommendation?

                if let recommendation = sender as? BolusRecommendation {
                    bolusRecommendation = recommendation
                } else {
                    do {
                        bolusRecommendation = try state.recommendBolus()
                    } catch let error {
                        bolusRecommendation = nil
                        self.deviceManager.logger.addError(error, fromSource: "Bolus")
                    }
                }

                DispatchQueue.main.async {
                    if let maxBolus = maximumBolus {
                        vc.maxBolus = maxBolus
                    }

                    vc.glucoseUnit = self.charts.glucoseUnit
                    vc.activeInsulin = activeInsulin
                    vc.activeCarbohydrates = activeCarbohydrates
                    vc.bolusRecommendation = bolusRecommendation
                }
            }
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
        if let carbVC = segue.source as? CarbEntryEditViewController, let updatedEntry = carbVC.updatedCarbEntry {
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

    private func createWorkoutButtonItem(selected: Bool) -> UIBarButtonItem {
        let item = UIBarButtonItem(image: UIImage.workoutImage(selected: selected), style: .plain, target: self, action: #selector(toggleWorkoutMode(_:)))
        item.accessibilityLabel = NSLocalizedString("Workout Mode", comment: "The label of the workout mode toggle button")

        if selected {
            item.accessibilityTraits = item.accessibilityTraits | UIAccessibilityTraitSelected
            item.accessibilityHint = NSLocalizedString("Disables", comment: "The action hint of the workout mode toggle button when enabled")
        } else {
            item.accessibilityHint = NSLocalizedString("Enables", comment: "The action hint of the workout mode toggle button when disabled")
        }

        item.tintColor = UIColor.glucoseTintColor

        return item
    }

    @IBAction func toggleWorkoutMode(_ sender: UIBarButtonItem) {
        if let workoutModeEnabled = workoutMode, workoutModeEnabled {
            deviceManager.loopManager.disableWorkoutMode()
        } else {
            let vc = UIAlertController(workoutDurationSelectionHandler: { (endDate) in
                self.deviceManager.loopManager.enableWorkoutMode(until: endDate)
            })

            present(vc, animated: true, completion: nil)
        }
    }

    // MARK: - HUDs

    @IBOutlet weak var hudView: HUDView! {
        didSet {
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
        }
    }

    @objc private func showLastError(_: Any) {
        self.deviceManager.loopManager.getLoopState { (_, state) in
            if let error = state.error {
                self.presentAlertController(with: error)
            }
        }
    }

    @objc private func openCGMApp(_: Any) {
        if let url = deviceManager.cgm?.appURL, UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        }
    }
}
