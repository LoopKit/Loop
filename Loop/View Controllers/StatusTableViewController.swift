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

        if !visible {
            needsRefresh = true
        }
    }

    // MARK: - State

    // References to registered notification center observers
    private var notificationObservers: [Any] = []

    unowned let dataManager = DeviceDataManager.sharedManager

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

    private func reloadData(animated: Bool = false) {
        if active && visible && needsRefresh {
            needsRefresh = false
            reloading = true

            let calendar = Calendar.current
            var components = DateComponents()
            components.minute = 0
            let date = Date(timeIntervalSinceNow: -TimeInterval(hours: 6))
            charts.startDate = (calendar as NSCalendar).nextDate(after: date, matching: components, options: [.matchStrictly, .searchBackwards]) ?? date

            let reloadGroup = DispatchGroup()
            var glucoseUnit: HKUnit?

            if let glucoseStore = dataManager.glucoseStore {
                reloadGroup.enter()
                glucoseStore.getRecentGlucoseValues(startDate: charts.startDate) { (values, error) -> Void in
                    if let error = error {
                        self.dataManager.logger.addError(error, fromSource: "GlucoseStore")
                        self.needsRefresh = true
                        // TODO: Display error in the cell
                    } else {
                        self.charts.glucoseValues = values
                    }

                    reloadGroup.leave()
                }

                reloadGroup.enter()
                glucoseStore.preferredUnit { (unit, error) in
                    glucoseUnit = unit

                    reloadGroup.leave()
                }
            }

            reloadGroup.enter()
            dataManager.loopManager.getLoopStatus { (predictedGlucose, _, recommendedTempBasal, lastTempBasal, lastLoopCompleted, _, error) -> Void in
                if error != nil {
                    self.needsRefresh = true
                }

                self.charts.predictedGlucoseValues = predictedGlucose ?? []
                self.recommendedTempBasal = recommendedTempBasal
                self.lastTempBasal = lastTempBasal
                self.lastLoopCompleted = lastLoopCompleted

                reloadGroup.leave()
            }

            reloadGroup.enter()
            dataManager.doseStore.getInsulinOnBoardValues(startDate: charts.startDate) { (values, error) -> Void in
                if let error = error {
                    self.dataManager.logger.addError(error, fromSource: "DoseStore")
                    self.needsRefresh = true
                    // TODO: Display error in the cell
                }

                self.charts.IOBValues = values

                reloadGroup.leave()
            }

            reloadGroup.enter()
            dataManager.doseStore.getRecentNormalizedDoseEntries(startDate: charts.startDate) { (doses, error) -> Void in
                if let error = error {
                    self.dataManager.logger.addError(error, fromSource: "DoseStore")
                    self.needsRefresh = true
                    // TODO: Display error in the cell
                }

                self.charts.doseEntries = doses

                reloadGroup.leave()
            }

            if let carbStore = dataManager.carbStore {
                reloadGroup.enter()
                carbStore.getCarbsOnBoardValues(startDate: charts.startDate) { (values, error) -> Void in
                    if let error = error {
                        self.dataManager.logger.addError(error, fromSource: "CarbStore")
                        self.needsRefresh = true
                        // TODO: Display error in the cell
                    }

                    self.charts.COBValues = values

                    reloadGroup.leave()
                }
            }

            if let reservoir = dataManager.doseStore.lastReservoirValue {
                if let capacity = dataManager.pumpState?.pumpModel?.reservoirCapacity {
                    reservoirVolumeHUD.reservoirLevel = min(1, max(0, Double(reservoir.unitVolume / Double(capacity))))
                }

                reservoirVolumeHUD.reservoirVolume = reservoir.unitVolume
                reservoirVolumeHUD.lastUpdated = reservoir.startDate
            }

            if let status = dataManager.latestPumpStatusFromMySentry {
                batteryLevelHUD.batteryLevel = Double(status.batteryRemainingPercent) / 100
            }

            loopCompletionHUD.dosingEnabled = dataManager.loopManager.dosingEnabled

            charts.glucoseTargetRangeSchedule = dataManager.glucoseTargetRangeSchedule

            workoutMode = dataManager.workoutModeEnabled

            reloadGroup.notify(queue: DispatchQueue.main) {
                if let unit = glucoseUnit, let glucose = self.dataManager.glucoseStore?.latestGlucose {
                    self.charts.glucoseUnit = unit

                    self.glucoseHUD.set(glucose, for: unit, from: self.dataManager.sensorInfo)
                }

                self.charts.prerender()

                self.tableView.reloadSections(IndexSet(integersIn: NSMakeRange(Section.charts.rawValue, 2).toRange() ?? 0..<0),
                    with: animated ? .fade : .none
                )

                self.reloading = false
            }
        }
    }

    private enum Section: Int {
        case charts = 0
        case status

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

    private let charts = StatusChartsManager()

    // MARK: - Loop Status Section Data

    private enum StatusRow: Int {
        case recommendedBasal = 0

        static let count = 1
    }

    private var recommendedTempBasal: LoopDataManager.TempBasalRecommendation?

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
                self.basalRateHUD.setNetBasalRate(netBasalRate, percent: netBasalPercent, atDate: basalStartDate)
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

    // MARK: - Pump/Sensor Section Data

    private lazy var emptyValueString: String = NSLocalizedString("––",
        comment: "The detail value of a numeric cell with no value"
    )

    private lazy var timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short

        return formatter
    }()

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        return Section.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .charts:
            return ChartRow.count
        case .status:
            return StatusRow.count
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {

        let locale = Locale.current

        switch Section(rawValue: indexPath.section)! {
        case .charts:
            let cell = tableView.dequeueReusableCell(withIdentifier: ChartTableViewCell.className, for: indexPath) as! ChartTableViewCell

            switch ChartRow(rawValue: indexPath.row)! {
            case .glucose:
                cell.chartContentView.chartGenerator = { [unowned self] (frame) in
                    return self.charts.glucoseChartWithFrame(frame)?.view
                }
            case .iob:
                cell.chartContentView.chartGenerator = { [unowned self] (frame) in
                    return self.charts.IOBChartWithFrame(frame)?.view
                }
            case .dose:
                cell.chartContentView?.chartGenerator = { [unowned self] (frame) in
                    return self.charts.doseChartWithFrame(frame)?.view
                }
            case .cob:
                cell.chartContentView?.chartGenerator = { [unowned self] (frame) in
                    return self.charts.COBChartWithFrame(frame)?.view
                }
            }

            return cell
        case .status:
            let cell = tableView.dequeueReusableCell(withIdentifier: UITableViewCell.className, for: indexPath)
            cell.selectionStyle = .none

            switch StatusRow(rawValue: indexPath.row)! {
            case .recommendedBasal:
                cell.textLabel?.text = NSLocalizedString("Recommended Basal", comment: "The title of the cell containing the recommended basal")

                if let recommendedTempBasal = recommendedTempBasal {
                    cell.detailTextLabel?.text = "\(NSNumber(value: recommendedTempBasal.rate as Double).description(withLocale: locale)) U/hour @ \(timeFormatter.string(from: recommendedTempBasal.recommendedDate))"
                    cell.selectionStyle = .default
                } else {
                    cell.detailTextLabel?.text = emptyValueString
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

    // MARK: - UITableViewDelegate

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        switch Section(rawValue: indexPath.section)! {
        case .charts:
            switch ChartRow(rawValue: indexPath.row)! {
            case .glucose:
                return 170
            case .iob, .dose, .cob:
                return 85
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

    // MARK: - UIGestureRecognizerDelegate

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
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
            if let bolus = sender as? Double {
                vc.recommendedBolus = bolus
            } else {
                self.dataManager.loopManager.getRecommendedBolus { (units, error) -> Void in
                    if let error = error {
                        self.dataManager.logger.addError(error, fromSource: "Bolus")
                    } else if let bolus = units {
                        vc.recommendedBolus = bolus
                    }
                }
            }
        case let vc as PredictionTableViewController:
            vc.dataManager = dataManager
        default:
            break
        }
    }

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
                dataManager.enactBolus(bolus) { (error) in
                    if error != nil {
                        NotificationManager.sendBolusFailureNotificationForAmount(bolus, atDate: startDate)
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
        item.accessibilityHint = selected ? NSLocalizedString("Disables", comment: "The action hint of the workout mode toggle button when enabled") : NSLocalizedString("Enables", comment: "The action hint of the workout mode toggle button when disabled")
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

    @IBOutlet var loopCompletionHUD: LoopCompletionHUDView!

    @IBOutlet var glucoseHUD: GlucoseHUDView! {
        didSet {
            let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(openCGMApp(_:)))
            glucoseHUD.addGestureRecognizer(tapGestureRecognizer)
        }
    }

    @objc private func openCGMApp(_: Any) {
        if let URL = URL(string: "dexcomcgm://"), UIApplication.shared.canOpenURL(URL) {
            UIApplication.shared.openURL(URL)
        }
        else if let URL = URL(string: "dexcomshare://"), UIApplication.shared.canOpenURL(URL) {
            UIApplication.shared.openURL(URL)
        }
    }

    @IBOutlet var basalRateHUD: BasalRateHUDView!

    @IBOutlet var reservoirVolumeHUD: ReservoirVolumeHUDView!

    @IBOutlet var batteryLevelHUD: BatteryLevelHUDView!
}
