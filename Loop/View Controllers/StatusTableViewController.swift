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
import SwiftCharts


final class StatusTableViewController: UITableViewController, UIGestureRecognizerDelegate {

    override func viewDidLoad() {
        super.viewDidLoad()

        let notificationCenter = NotificationCenter.default
        let mainQueue = OperationQueue.main
        let application = UIApplication.shared

        notificationObservers += [
            notificationCenter.addObserver(forName: .LoopDataUpdated, object: dataManager.loopManager, queue: nil) { _ in
                DispatchQueue.main.async {
                    self.needsRefresh = true
                    self.loopCompletionHUD.loopInProgress = false
                    self.reloadData(animated: true)
                }
            },
            notificationCenter.addObserver(forName: .LoopRunning, object: dataManager.loopManager, queue: nil) { _ in
                DispatchQueue.main.async {
                    self.loopCompletionHUD.loopInProgress = true
                }
            },
            notificationCenter.addObserver(forName: .LoopSettingsUpdated, object: dataManager, queue: nil) { _ in
                DispatchQueue.main.async {
                    self.needsRefresh = true
                    self.reloadData(animated: true)
                }
            },
            notificationCenter.addObserver(forName: .UIApplicationWillResignActive, object: application, queue: mainQueue) { _ in
                self.active = false
            },
            notificationCenter.addObserver(forName: .UIApplicationDidBecomeActive, object: application, queue: mainQueue) { _ in
                self.active = true
            }
        ]

        let chartPanGestureRecognizer = UIPanGestureRecognizer()
        chartPanGestureRecognizer.delegate = self
        chartPanGestureRecognizer.addTarget(self, action: #selector(handlePan(_:)))
        tableView.addGestureRecognizer(chartPanGestureRecognizer)
        charts.panGestureRecognizer = chartPanGestureRecognizer

        // Toolbar
        toolbarItems![0].accessibilityLabel = NSLocalizedString("Add Meal", comment: "The label of the carb entry button")
        toolbarItems![0].tintColor = UIColor.COBTintColor
        toolbarItems![2].accessibilityLabel = NSLocalizedString("Bolus", comment: "The label of the bolus entry button")
        toolbarItems![2].tintColor = UIColor.doseTintColor
        toolbarItems![6].accessibilityLabel = NSLocalizedString("Settings", comment: "The label of the settings button")
        toolbarItems![6].tintColor = UIColor.secondaryLabelColor
    }

    deinit {
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        navigationController?.setNavigationBarHidden(true, animated: animated)
        visible = true
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
        visible = false
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        needsRefresh = true
        if visible {
            reloadData(animated: false, to: size)
        }
    }

    // MARK: - State

    // References to registered notification center observers
    private var notificationObservers: [Any] = []

    weak var dataManager: DeviceDataManager!

    private var active = true {
        didSet {
            reloadData()
            loopCompletionHUD.assertTimer(active)
        }
    }

    private var needsRefresh = true

    private var visible = false {
        didSet {
            reloadData()
        }
    }

    private var reloading = false

    /// Refetches all data and updates the views. Must be called on the main queue.
    ///
    /// - parameter animated: Whether the updating should be animated if possible
    private func reloadData(animated: Bool = false, to size: CGSize? = nil) {
        if active && visible && needsRefresh {
            needsRefresh = false
            reloading = true

            // How far back should we show data? Use the screen size as a guid.
            let minimumSegmentWidth: CGFloat = 50
            let availableWidth = (size ?? self.tableView.bounds.size).width - self.charts.fixedHorizontalMargin
            let totalHours = floor(Double(availableWidth / minimumSegmentWidth))
            let historyHours = totalHours - (dataManager.insulinActionDuration ?? TimeInterval(hours: 4)).hours

            var components = DateComponents()
            components.minute = 0
            let date = Date(timeIntervalSinceNow: -TimeInterval(hours: max(1, historyHours)))
            charts.startDate = Calendar.current.nextDate(after: date, matching: components, matchingPolicy: .strict, direction: .backward) ?? date

            let reloadGroup = DispatchGroup()
            var newRecommendedTempBasal: LoopDataManager.TempBasalRecommendation?

            if let glucoseStore = dataManager.glucoseStore {
                reloadGroup.enter()
                glucoseStore.preferredUnit { (unit, error) in
                    if let unit = unit {
                        self.charts.glucoseUnit = unit
                    }

                    reloadGroup.enter()
                    glucoseStore.getRecentGlucoseValues(startDate: self.charts.startDate) { (values, error) -> Void in
                        if let error = error {
                            self.dataManager.logger.addError(error, fromSource: "GlucoseStore")
                            self.needsRefresh = true
                        } else {
                            self.charts.glucoseValues = values
                        }

                        reloadGroup.leave()
                    }

                    reloadGroup.enter()
                    self.dataManager.loopManager.getLoopStatus { (predictedGlucose, _, recommendedTempBasal, lastTempBasal, lastLoopCompleted, _, _, error) -> Void in
                        if error != nil {
                            self.needsRefresh = true
                        }

                        self.charts.predictedGlucoseValues = predictedGlucose ?? []
                        newRecommendedTempBasal = recommendedTempBasal
                        self.lastTempBasal = lastTempBasal
                        self.lastLoopCompleted = lastLoopCompleted

                        if let lastPoint = self.charts.predictedGlucosePoints.last?.y {
                            self.eventualGlucoseDescription = String(describing: lastPoint)
                        }

                        reloadGroup.leave()
                    }

                    reloadGroup.leave()
                }
            }

            reloadGroup.enter()
            dataManager.doseStore.getInsulinOnBoardValues(startDate: charts.startDate) { (values, error) -> Void in
                if let error = error {
                    self.dataManager.logger.addError(error, fromSource: "DoseStore")
                    self.needsRefresh = true
                }

                self.charts.iobValues = values

                if let index = values.closestIndexPriorToDate(Date()) {
                    self.currentIOBDescription = String(describing: self.charts.iobPoints[index].y)
                }

                reloadGroup.leave()
            }

            reloadGroup.enter()
            dataManager.doseStore.getRecentNormalizedDoseEntries(startDate: charts.startDate) { (doses, error) -> Void in
                if let error = error {
                    self.dataManager.logger.addError(error, fromSource: "DoseStore")
                    self.needsRefresh = true
                }

                self.charts.doseEntries = doses

                reloadGroup.leave()
            }

            reloadGroup.enter()
            dataManager.doseStore.getTotalRecentUnitsDelivered { (units, _, error) in
                if error != nil {
                    self.needsRefresh = true
                } else {
                    self.totalDelivery = units
                }

                reloadGroup.leave()
            }

            if let carbStore = dataManager.carbStore {
                reloadGroup.enter()
                carbStore.getCarbsOnBoardValues(startDate: charts.startDate) { (values, error) -> Void in
                    if let error = error {
                        self.dataManager.logger.addError(error, fromSource: "CarbStore")
                        self.needsRefresh = true
                    }

                    self.charts.cobValues = values

                    if let index = values.closestIndexPriorToDate(Date()) {
                        self.currentCOBDescription = String(describing: self.charts.cobPoints[index].y)
                    }

                    reloadGroup.leave()
                }
            }

            if let reservoir = dataManager.doseStore.lastReservoirValue {
                if let capacity = dataManager.pumpState?.pumpModel?.reservoirCapacity {
                    reservoirVolumeHUD.reservoirLevel = min(1, max(0, Double(reservoir.unitVolume / Double(capacity))))
                }
                
                reservoirVolumeHUD.setReservoirVolume(volume: reservoir.unitVolume, at: reservoir.startDate)
            }

            if let level = dataManager.pumpBatteryChargeRemaining {
                batteryLevelHUD.batteryLevel = level
            }

            loopCompletionHUD.dosingEnabled = dataManager.loopManager.dosingEnabled

            charts.glucoseTargetRangeSchedule = dataManager.glucoseTargetRangeSchedule

            workoutMode = dataManager.workoutModeEnabled

            reloadGroup.notify(queue: DispatchQueue.main) {
                if let glucose = self.dataManager.glucoseStore?.latestGlucose {
                    self.glucoseHUD.set(glucose, for: self.charts.glucoseUnit, from: self.dataManager.sensorInfo)
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

                self.reloading = false
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

    private lazy var charts: StatusChartsManager = {
        let charts = StatusChartsManager()

        charts.glucoseDisplayRange = (
            min: HKQuantity(unit: HKUnit.milligramsPerDeciliterUnit(), doubleValue: 100),
            max: HKQuantity(unit: HKUnit.milligramsPerDeciliterUnit(), doubleValue: 175)
        )

        return charts
    }()

    // MARK: Glucose

    private var eventualGlucoseDescription: String?

    // MARK: IOB

    private var currentIOBDescription: String?

    // MARK: Dose

    private var totalDelivery: Double?

    private lazy var integerFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = 0

        return formatter
    }()

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

    private lazy var timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short

        return formatter
    }()

    // MARK: - HUD Data

    private var lastTempBasal: DoseEntry? {
        didSet {
            guard let scheduledBasal = dataManager.basalRateSchedule?.between(start: Date(), end: Date()).first else {
                return
            }

            let netBasalRate: Double
            let netBasalPercent: Double
            let basalStartDate: Date

            if let lastTempBasal = lastTempBasal, lastTempBasal.endDate > Date(), let maxBasal = dataManager.maximumBasalRatePerHour {
                netBasalRate = lastTempBasal.value - scheduledBasal.value
                basalStartDate = lastTempBasal.startDate

                if netBasalRate < 0 {
                    netBasalPercent = netBasalRate / scheduledBasal.value
                } else {
                    netBasalPercent = netBasalRate / (maxBasal - scheduledBasal.value)
                }
            } else {
                netBasalRate = 0
                netBasalPercent = 0

                if let lastTempBasal = lastTempBasal, lastTempBasal.endDate > scheduledBasal.startDate {
                    basalStartDate = lastTempBasal.endDate
                } else {
                    basalStartDate = scheduledBasal.startDate
                }
            }

            DispatchQueue.main.async {
                self.basalRateHUD.setNetBasalRate(netBasalRate, percent: netBasalPercent, at: basalStartDate)
            }
        }
    }

    private var lastLoopCompleted: Date? {
        didSet {
            DispatchQueue.main.async {
                self.loopCompletionHUD.lastLoopCompleted = self.lastLoopCompleted
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

            let alpha: CGFloat = charts.panGestureRecognizer?.state == .possible ? 1 : 0
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
                    self.dataManager.loopManager.enactRecommendedTempBasal { (success, error) -> Void in
                        DispatchQueue.main.async {
                            self.settingTempBasal = false

                            if let error = error {
                                self.dataManager.logger.addError(error, fromSource: "TempBasal")
                                self.presentAlertController(with: error)
                            } else if success {
                                self.needsRefresh = true
                                self.reloadData()
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - UIGestureRecognizer

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }

    @objc func handlePan(_ gestureRecognizer: UIGestureRecognizer) {
        switch gestureRecognizer.state {
        case .possible, .changed:
            // Follow your dreams!
            break
        case .began, .cancelled, .ended, .failed:
            for case let row as ChartTableViewCell in self.tableView.visibleCells {
                let forwards = gestureRecognizer.state == .began
                UIView.animate(withDuration: forwards ? 0.2 : 0.5, delay: forwards ? 0 : 1, animations: {
                    let alpha: CGFloat = forwards ? 0 : 1
                    row.titleLabel?.alpha = alpha
                    row.subtitleLabel?.alpha = alpha
                })
            }
        }
    }

    // MARK: - Actions

    override func shouldPerformSegue(withIdentifier identifier: String, sender: Any?) -> Bool {
        if identifier == CarbEntryEditViewController.className {
            if let carbStore = dataManager.carbStore {
                if carbStore.authorizationRequired {
                    carbStore.authorize { (success, error) in
                        if success {
                            self.performSegue(withIdentifier: CarbEntryEditViewController.className, sender: sender)
                        }
                    }
                    return false
                }
            } else {
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
            vc.carbStore = dataManager.carbStore
            vc.hidesBottomBarWhenPushed = true
            self.needsRefresh = true
        case let vc as CarbEntryEditViewController:
            if let carbStore = dataManager.carbStore {
                vc.defaultAbsorptionTimes = carbStore.defaultAbsorptionTimes
                vc.preferredUnit = carbStore.preferredUnit
            }
        case let vc as InsulinDeliveryTableViewController:
            vc.doseStore = dataManager.doseStore
            vc.hidesBottomBarWhenPushed = true
        case let vc as BolusViewController:
            if let maxBolus = self.dataManager.maximumBolus {
                vc.maxBolus = maxBolus
            }

            if let bolus = sender as? Double {
                vc.recommendedBolus = bolus
            } else {
                self.dataManager.loopManager.getRecommendedBolus { (units, error) -> Void in
                    if let error = error {
                        self.dataManager.logger.addError(error, fromSource: "Bolus")
                    } else if let bolus = units {
                        DispatchQueue.main.async {
                            vc.recommendedBolus = bolus
                        }
                    }
                }
            }
        case let vc as PredictionTableViewController:
            vc.dataManager = dataManager
        case let vc as SettingsTableViewController:
            vc.dataManager = dataManager
        default:
            break
        }
    }

    /// Unwind segue action from the CarbEntryEditViewController
    ///
    /// - parameter segue: The unwind segue
    @IBAction func unwindFromEditing(_ segue: UIStoryboardSegue) {
        if let carbVC = segue.source as? CarbEntryEditViewController, let updatedEntry = carbVC.updatedCarbEntry {

            dataManager.loopManager.addCarbEntryAndRecommendBolus(updatedEntry) { (units, error) -> Void in
                DispatchQueue.main.async {
                    if let error = error {
                        // Ignore bolus wizard errors
                        if error is CarbStore.CarbStoreError {
                            self.presentAlertController(with: error)
                        } else {
                            self.dataManager.logger.addError(error, fromSource: "Bolus")
                            self.needsRefresh = true
                            self.reloadData()
                        }
                    } else if self.active && self.visible, let bolus = units, bolus > 0 {
                        self.performSegue(withIdentifier: BolusViewController.className, sender: bolus)
                        self.needsRefresh = true
                    } else {
                        self.needsRefresh = true
                        self.reloadData()
                    }
                }
            }
        }
    }

    @IBAction func unwindFromBolusViewController(_ segue: UIStoryboardSegue) {
        if let bolusViewController = segue.source as? BolusViewController {
            if let bolus = bolusViewController.bolus, bolus > 0 {
                let startDate = Date()
                dataManager.enactBolus(units: bolus) { (error) in
                    if error != nil {
                        NotificationManager.sendBolusFailureNotificationForAmount(bolus, atStartDate: startDate)
                    }
                }
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
            dataManager.disableWorkoutMode()
        } else {
            let vc = UIAlertController(workoutDurationSelectionHandler: { (endDate) in
                self.dataManager.enableWorkoutMode(until: endDate)
            })

            present(vc, animated: true, completion: nil)
        }
    }

    // MARK: - HUDs

    @IBOutlet weak var loopCompletionHUD: LoopCompletionHUDView!

    @IBOutlet weak var glucoseHUD: GlucoseHUDView! {
        didSet {
            let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(openCGMApp(_:)))
            glucoseHUD.addGestureRecognizer(tapGestureRecognizer)

            if cgmAppURL != nil {
                glucoseHUD.accessibilityHint = NSLocalizedString("Launches CGM app", comment: "Glucose HUD accessibility hint")
            }
        }
    }

    private var cgmAppURL: URL? {
        if let url = URL(string: "dexcomcgm://"), UIApplication.shared.canOpenURL(url) {
            return url
        } else if let url = URL(string: "dexcomshare://"), UIApplication.shared.canOpenURL(url) {
            return url
        } else {
            return nil
        }
    }

    @objc private func openCGMApp(_: Any) {
        if let url = cgmAppURL {
            UIApplication.shared.open(url)
        }
    }

    @IBOutlet weak var basalRateHUD: BasalRateHUDView!

    @IBOutlet weak var reservoirVolumeHUD: ReservoirVolumeHUDView!

    @IBOutlet weak var batteryLevelHUD: BatteryLevelHUDView!
}
