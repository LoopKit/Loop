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


class StatusTableViewController: UITableViewController, UIGestureRecognizerDelegate {

    override func viewDidLoad() {
        super.viewDidLoad()

        let notificationCenter = NSNotificationCenter.defaultCenter()
        let mainQueue = NSOperationQueue.mainQueue()
        let application = UIApplication.sharedApplication()

        notificationObservers += [
            notificationCenter.addObserverForName(LoopDataManager.LoopDataUpdatedNotification, object: dataManager.loopManager, queue: nil) { (note) -> Void in
                dispatch_async(dispatch_get_main_queue()) {
                    self.needsRefresh = true
                    self.loopCompletionHUD.loopInProgress = false
                    self.reloadData()
                }
            },
            notificationCenter.addObserverForName(LoopDataManager.LoopRunningNotification, object: dataManager.loopManager, queue: nil) { (note) in
                dispatch_async(dispatch_get_main_queue()) {
                    self.loopCompletionHUD.loopInProgress = true
                }
            },
            notificationCenter.addObserverForName(UIApplicationWillResignActiveNotification, object: application, queue: mainQueue) { (note) -> Void in
                self.active = false
            },
            notificationCenter.addObserverForName(UIApplicationDidBecomeActiveNotification, object: application, queue: mainQueue) { (note) -> Void in
                self.active = true
            }
        ]

        let chartPanGestureRecognizer = UIPanGestureRecognizer()
        chartPanGestureRecognizer.delegate = self
        tableView.addGestureRecognizer(chartPanGestureRecognizer)
        charts.panGestureRecognizer = chartPanGestureRecognizer
    }

    deinit {
        for observer in notificationObservers {
            NSNotificationCenter.defaultCenter().removeObserver(observer)
        }
    }

    override func viewWillAppear(animated: Bool) {
        super.viewWillAppear(animated)

        visible = true
    }

    override func viewDidAppear(animated: Bool) {
        super.viewDidAppear(animated)

        AnalyticsManager.didDisplayStatusScreen()
    }

    override func viewWillDisappear(animated: Bool) {
        super.viewWillDisappear(animated)

        visible = false
    }

    override func viewWillTransitionToSize(size: CGSize, withTransitionCoordinator coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransitionToSize(size, withTransitionCoordinator: coordinator)

        if visible {
            coordinator.animateAlongsideTransition({ (_) -> Void in
                self.tableView.beginUpdates()
                self.tableView.reloadSections(NSIndexSet(index: Section.Charts.rawValue), withRowAnimation: .Fade)
                self.tableView.endUpdates()
            }, completion: nil)
        } else {
            needsRefresh = true
        }
    }

    // MARK: - State

    // References to registered notification center observers
    private var notificationObservers: [AnyObject] = []

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

    private func reloadData() {
        if active && visible && needsRefresh {
            needsRefresh = false
            reloading = true

            tableView.reloadSections(NSIndexSet(indexesInRange: NSMakeRange(Section.Pump.rawValue, Section.count - Section.Pump.rawValue)
            ), withRowAnimation: visible ? .Automatic : .None)

            charts.startDate = NSDate(timeIntervalSinceNow: -NSTimeInterval(hours: 6))
            let reloadGroup = dispatch_group_create()

            if let glucoseStore = dataManager.glucoseStore {
                dispatch_group_enter(reloadGroup)
                glucoseStore.getRecentGlucoseValues(startDate: charts.startDate) { (values, error) -> Void in
                    if let error = error {
                        self.dataManager.logger?.addError(error, fromSource: "GlucoseStore")
                        self.needsRefresh = true
                        // TODO: Display error in the cell
                    } else {
                        self.charts.glucoseValues = values // FixtureData.recentGlucoseData
                    }

                    dispatch_group_leave(reloadGroup)
                }
            }

            dispatch_group_enter(reloadGroup)
            dataManager.loopManager.getLoopStatus { (predictedGlucose, recommendedTempBasal, lastTempBasal, lastLoopCompleted, error) -> Void in
                if error != nil {
                    self.needsRefresh = true
                }

                self.charts.predictedGlucoseValues = predictedGlucose ?? []  // FixtureData.predictedGlucoseData
                self.recommendedTempBasal = recommendedTempBasal
                self.lastTempBasal = lastTempBasal
                self.lastLoopCompleted = lastLoopCompleted

                dispatch_group_leave(reloadGroup)
            }

            dispatch_group_enter(reloadGroup)
            dataManager.doseStore.getInsulinOnBoardValues(startDate: charts.startDate) { (values, error) -> Void in
                if let error = error {
                    self.dataManager.logger?.addError(error, fromSource: "DoseStore")
                    self.needsRefresh = true
                    // TODO: Display error in the cell
                }

                self.charts.IOBValues = values  //FixtureData.recentIOBData

                dispatch_group_leave(reloadGroup)
            }

            dispatch_group_enter(reloadGroup)
            dataManager.doseStore.getRecentNormalizedReservoirDoseEntries(startDate: charts.startDate) { (doses, error) -> Void in
                if let error = error {
                    self.dataManager.logger?.addError(error, fromSource: "DoseStore")
                    self.needsRefresh = true
                    // TODO: Display error in the cell
                }

                self.charts.doseEntries = doses  // FixtureData.recentDoseData

                dispatch_group_leave(reloadGroup)
            }

            if let carbStore = dataManager.carbStore {
                dispatch_group_enter(reloadGroup)
                carbStore.getCarbsOnBoardValues(startDate: charts.startDate) { (values, error) -> Void in
                    if let error = error {
                        self.dataManager.logger?.addError(error, fromSource: "CarbStore")
                        self.needsRefresh = true
                        // TODO: Display error in the cell
                    }

                    self.charts.COBValues = values

                    dispatch_group_leave(reloadGroup)
                }
            }

            if let status = dataManager.latestPumpStatus {
                reservoirVolume = status.reservoirRemainingUnits
                reservoirLevel = Double(status.reservoirRemainingPercent) / 100
                batteryLevel = Double(status.batteryRemainingPercent) / 100
            }

            loopCompletionHUD.dosingEnabled = dataManager.loopManager.dosingEnabled

            charts.glucoseTargetRangeSchedule = dataManager.glucoseTargetRangeSchedule

            dispatch_group_notify(reloadGroup, dispatch_get_main_queue()) {
                self.charts.prerender()

                self.tableView.reloadSections(NSIndexSet(indexesInRange: NSMakeRange(Section.Charts.rawValue, 2)),
                    withRowAnimation: .None
                )

                self.reloading = false
            }
        }
    }

    private enum Section: Int {
        case Charts = 0
        case Status
        case Pump
        case Sensor

        static let count = 4
    }

    // MARK: - Chart Section Data

    private enum ChartRow: Int {
        case Glucose = 0
        case IOB
        case Dose
        case COB

        static let count = 4
    }

    private let charts = StatusChartsManager()

    // MARK: - Loop Status Section Data

    private enum StatusRow: Int {
        case RecommendedBasal = 0
        case LastBasal

        static let count = 2
    }

    private var recommendedTempBasal: LoopDataManager.TempBasalRecommendation?

    private var lastTempBasal: DoseEntry? {
        didSet {
            guard let scheduledBasal = dataManager.basalRateSchedule?.between(NSDate(), NSDate()).first else {
                return
            }

            let netBasalRate: Double
            let netBasalPercent: Double
            let basalStartDate: NSDate

            if let lastTempBasal = lastTempBasal where lastTempBasal.endDate > NSDate(), let maxBasal = dataManager.maximumBasalRatePerHour {
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

                if let lastTempBasal = lastTempBasal where lastTempBasal.endDate > scheduledBasal.startDate {
                    basalStartDate = lastTempBasal.endDate
                } else {
                    basalStartDate = scheduledBasal.startDate
                }
            }

            dispatch_async(dispatch_get_main_queue()) {
                self.basalRateHUD.setNetBasalRate(netBasalRate, percent: netBasalPercent, atDate: basalStartDate)
            }
        }
    }

    private var lastLoopCompleted: NSDate? {
        didSet {
            loopCompletionHUD.lastLoopCompleted = lastLoopCompleted
        }
    }

    private var reservoirLevel: Double? {
        didSet {
            reservoirVolumeHUD.reservoirLevel = reservoirLevel
        }
    }

    private var reservoirVolume: Double? {
        didSet {
            reservoirVolumeHUD.reservoirVolume = reservoirVolume
        }
    }

    private var batteryLevel: Double? {
        didSet {
            batteryLevelHUD.batteryLevel = batteryLevel
        }
    }

    private var settingTempBasal: Bool = false {
        didSet {
            if let cell = tableView.cellForRowAtIndexPath(NSIndexPath(forRow: StatusRow.RecommendedBasal.rawValue, inSection: Section.Status.rawValue)) {
                if settingTempBasal {
                    let indicatorView = UIActivityIndicatorView(activityIndicatorStyle: .Gray)
                    indicatorView.startAnimating()
                    cell.accessoryView = indicatorView
                } else {
                    cell.accessoryView = nil
                }
            }
        }
    }

    // MARK: - Pump/Sensor Section Data

    private enum PumpRow: Int {
        case Date = 0
        case InsulinOnBoard

        static let count = 2
    }

    private enum SensorRow: Int {
        case Date
        case Glucose
        case Trend
        case State

        static let count = 4
    }

    private lazy var emptyDateString: String = NSLocalizedString("Never", comment: "The detail value of a date cell with no value")

    private lazy var emptyValueString: String = NSLocalizedString("––",
        comment: "The detail value of a numeric cell with no value"
    )

    private lazy var dateComponentsFormatter: NSDateComponentsFormatter = {
        let formatter = NSDateComponentsFormatter()
        formatter.unitsStyle = .Short

        return formatter
    }()

    private lazy var dateFormatter: NSDateFormatter = {
        let formatter = NSDateFormatter()
        formatter.dateStyle = .MediumStyle
        formatter.timeStyle = .MediumStyle
        return formatter
    }()

    private lazy var timeFormatter: NSDateFormatter = {
        let formatter = NSDateFormatter()
        formatter.dateStyle = .NoStyle
        formatter.timeStyle = .ShortStyle

        return formatter
    }()

    // MARK: - Table view data source

    override func numberOfSectionsInTableView(tableView: UITableView) -> Int {
        return Section.count
    }

    override func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .Charts:
            return ChartRow.count
        case .Status:
            return StatusRow.count
        case .Pump:
            return PumpRow.count
        case .Sensor:
            return SensorRow.count
        }
    }

    override func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {

        let locale = NSLocale.currentLocale()

        switch Section(rawValue: indexPath.section)! {
        case .Charts:
            let cell = tableView.dequeueReusableCellWithIdentifier(ChartTableViewCell.className, forIndexPath: indexPath) as! ChartTableViewCell
            let frame = cell.contentView.frame

            switch ChartRow(rawValue: indexPath.row)! {
            case .Glucose:
                if let chart = charts.glucoseChartWithFrame(frame) {
                    cell.chartView = chart.view
                } else {
                    cell.chartView = nil
                    // TODO: Display empty state
                }
            case .IOB:
                if let chart = charts.IOBChartWithFrame(frame) {
                    cell.chartView = chart.view
                } else {
                    cell.chartView = nil
                    // TODO: Display empty state
                }
            case .Dose:
                if let chart = charts.doseChartWithFrame(frame) {
                    cell.chartView = chart.view
                } else {
                    cell.chartView = nil
                    // TODO: Display empty state
                }
            case .COB:
                if let chart = charts.COBChartWithFrame(frame) {
                    cell.chartView = chart.view
                } else {
                    cell.chartView = nil
                    // TODO: Display empty state
                }
            }

            return cell
        case .Status:
            let cell = tableView.dequeueReusableCellWithIdentifier(UITableViewCell.className, forIndexPath: indexPath)
            cell.selectionStyle = .None

            switch StatusRow(rawValue: indexPath.row)! {
            case .RecommendedBasal:
                cell.textLabel?.text = NSLocalizedString("Recommended Basal", comment: "The title of the cell containing the recommended basal")

                if let recommendedTempBasal = recommendedTempBasal {
                    cell.detailTextLabel?.text = "\(NSNumber(double: recommendedTempBasal.rate).descriptionWithLocale(locale)) U/hour @ \(timeFormatter.stringFromDate(recommendedTempBasal.recommendedDate))"
                    cell.selectionStyle = .Default
                } else {
                    cell.detailTextLabel?.text = emptyValueString
                }

                if settingTempBasal {
                    let indicatorView = UIActivityIndicatorView(activityIndicatorStyle: .Gray)
                    indicatorView.startAnimating()
                    cell.accessoryView = indicatorView
                } else {
                    cell.accessoryView = nil
                }
            case .LastBasal:
                cell.textLabel?.text = NSLocalizedString("Current Basal", comment: "The title of the cell containing the last delivered basal")
                let basalRate: Double
                let date: NSDate

                if let lastTempBasal = lastTempBasal where lastTempBasal.endDate > NSDate() {
                    basalRate = lastTempBasal.value
                    date = lastTempBasal.startDate
                } else if let basalSchedule = dataManager.basalRateSchedule {
                    let scheduledBasal = basalSchedule.between(NSDate(), NSDate()).first!

                    basalRate = scheduledBasal.value

                    if let lastTempBasal = lastTempBasal where lastTempBasal.endDate > scheduledBasal.startDate {
                        date = lastTempBasal.endDate
                    } else {
                        date = scheduledBasal.startDate
                    }
                } else {
                    cell.detailTextLabel?.text = nil
                    return cell
                }

                cell.detailTextLabel?.text = "\(NSNumber(double: basalRate).descriptionWithLocale(locale)) U/hour @ \(timeFormatter.stringFromDate(date))"
            }

            return cell
        case .Pump:
            let cell = tableView.dequeueReusableCellWithIdentifier(UITableViewCell.className, forIndexPath: indexPath)
            cell.selectionStyle = .None

            switch PumpRow(rawValue: indexPath.row)! {
            case .Date:
                cell.textLabel?.text = NSLocalizedString("Last Updated", comment: "The title of the cell containing the last updated date")

                if let date = dataManager.latestPumpStatus?.pumpDateComponents.date {
                    cell.detailTextLabel?.text = dateFormatter.stringFromDate(date)
                } else {
                    cell.detailTextLabel?.text = emptyDateString
                }
            case .InsulinOnBoard:
                cell.textLabel?.text = NSLocalizedString("Insulin on Board", comment: "The title of the cell containing the estimated amount of active insulin in the body")

                if let iob = dataManager.latestPumpStatus?.iob {
                    let numberValue = NSNumber(double: iob).descriptionWithLocale(locale)
                    cell.detailTextLabel?.text = "\(numberValue) Units"
                } else {
                    cell.detailTextLabel?.text = emptyValueString
                }
            }

            return cell
        case .Sensor:
            let cell = tableView.dequeueReusableCellWithIdentifier(UITableViewCell.className, forIndexPath: indexPath)
            cell.selectionStyle = .None

            switch SensorRow(rawValue: indexPath.row)! {
            case .Date:
                cell.textLabel?.text = NSLocalizedString("Last Read", comment: "The title of the cell containing the last updated sensor date")

                if let glucose = dataManager.latestGlucoseMessage, startTime = dataManager.transmitterStartTime {
                    let date = NSDate(timeIntervalSince1970: startTime).dateByAddingTimeInterval(NSTimeInterval(glucose.timestamp))

                    cell.detailTextLabel?.text = dateFormatter.stringFromDate(date)
                } else {
                    cell.detailTextLabel?.text = emptyValueString
                }
            case .Glucose:
                cell.textLabel?.text = NSLocalizedString("Glucose", comment: "The title of the cell containing the current glucose")

                if let glucose = dataManager.latestGlucoseMessage {
                    let numberString = NSNumber(unsignedShort: glucose.glucose).descriptionWithLocale(locale)
                    cell.detailTextLabel?.text = "\(numberString) mg/dL"
                } else {
                    cell.detailTextLabel?.text = emptyValueString
                }
            case .Trend:
                cell.textLabel?.text = NSLocalizedString("Trend", comment: "The title of the cell containing the current glucose trend")

                if let glucose = dataManager.latestGlucoseMessage where glucose.state > 5 {
                    let direction: String

                    switch glucose.trend {
                    case let x where x < -10:
                        direction = "⇊"
                    case let x where x < 0:
                        direction = "↓"
                    case let x where x > 10:
                        direction = "⇈"
                    case let x where x > 0:
                        direction = "↑"
                    default:
                        direction = ""
                    }

                    let numberString = NSNumber(char: glucose.trend).descriptionWithLocale(locale)
                    cell.detailTextLabel?.text = "\(numberString)\(direction)"
                } else {
                    cell.detailTextLabel?.text = emptyValueString
                }
            case .State:
                cell.textLabel?.text = NSLocalizedString("Calibration state", comment: "The title of the cell containing the current sensor state")

                if let glucose = dataManager.latestGlucoseMessage {
                    cell.detailTextLabel?.text = String(format: "%02x", glucose.state)
                } else {
                    cell.detailTextLabel?.text = nil
                }
            }

            return cell
        }
    }

    // MARK: - UITableViewDelegate

    override func tableView(tableView: UITableView, heightForRowAtIndexPath indexPath: NSIndexPath) -> CGFloat {
        switch Section(rawValue: indexPath.section)! {
        case .Charts:
            switch ChartRow(rawValue: indexPath.row)! {
            case .Glucose:
                return 170
            case .IOB, .Dose, .COB:
                return 85
            }
        case .Status, .Pump, .Sensor:
            return 44
        }
    }

    override func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
        switch Section(rawValue: indexPath.section)! {
        case .Charts:
            switch ChartRow(rawValue: indexPath.row)! {
            case .Glucose:
                if let URL = NSURL(string: "dexcomcgm://") {
                    UIApplication.sharedApplication().openURL(URL)
                }
            case .IOB, .Dose:
                performSegueWithIdentifier(ReservoirTableViewController.className, sender: indexPath)
            case .COB:
                performSegueWithIdentifier(CarbEntryTableViewController.className, sender: indexPath)
            }
        case .Status:
            switch StatusRow(rawValue: indexPath.row)! {
            case .RecommendedBasal:
                tableView.deselectRowAtIndexPath(indexPath, animated: true)

                if recommendedTempBasal != nil && !settingTempBasal {
                    settingTempBasal = true
                    self.dataManager.loopManager.enactRecommendedTempBasal { (success, error) -> Void in
                        dispatch_async(dispatch_get_main_queue()) {
                            self.settingTempBasal = false

                            if let error = error {
                                self.dataManager.logger?.addError(error, fromSource: "TempBasal")
                                self.presentAlertControllerWithError(error)
                            } else if success {
                                self.needsRefresh = true
                                self.reloadData()
                            }
                        }
                    }
                }
            case .LastBasal:
                break
            }
        case .Sensor:
            if let URL = NSURL(string: "dexcomcgm://") {
                UIApplication.sharedApplication().openURL(URL)
            }
        case .Pump:
            break
        }
    }

    // MARK: - UIGestureRecognizerDelegate

    func gestureRecognizer(gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWithGestureRecognizer otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }

    // MARK: - Actions

    override func shouldPerformSegueWithIdentifier(identifier: String, sender: AnyObject?) -> Bool {
        if identifier == CarbEntryEditViewController.className {
            if let carbStore = dataManager.carbStore {
                if carbStore.authorizationRequired {
                    carbStore.authorize { (success, error) in
                        if success {
                            self.performSegueWithIdentifier(CarbEntryEditViewController.className, sender: sender)
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

    override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
        super.prepareForSegue(segue, sender: sender)

        switch segue.destinationViewController {
        case let vc as CarbEntryTableViewController:
            vc.carbStore = dataManager.carbStore
            vc.hidesBottomBarWhenPushed = true
            self.needsRefresh = true
        case let vc as CarbEntryEditViewController:
            if let carbStore = dataManager.carbStore {
                vc.defaultAbsorptionTimes = carbStore.defaultAbsorptionTimes
                vc.preferredUnit = carbStore.preferredUnit
            }
        case let vc as ReservoirTableViewController:
            vc.doseStore = dataManager.doseStore
            vc.hidesBottomBarWhenPushed = true
        case let vc as BolusViewController:
            if let bolus = sender as? Double {
                vc.recommendedBolus = bolus
            } else {
                self.dataManager.loopManager.getRecommendedBolus { (units, error) -> Void in
                    if let error = error {
                        self.dataManager.logger?.addError(error, fromSource: "Bolus")
                    } else if let bolus = units {
                        vc.recommendedBolus = bolus
                    }
                }
            }
        default:
            break
        }
    }

    @IBAction func unwindFromEditing(segue: UIStoryboardSegue) {
        if let carbVC = segue.sourceViewController as? CarbEntryEditViewController, updatedEntry = carbVC.updatedCarbEntry {

            dataManager.loopManager.addCarbEntryAndRecommendBolus(updatedEntry) { (units, error) -> Void in
                dispatch_async(dispatch_get_main_queue()) {
                    if let error = error {
                        // Ignore bolus wizard errors
                        if error is CarbStore.Error {
                            self.presentAlertControllerWithError(error)
                        } else {
                            self.dataManager.logger?.addError(error, fromSource: "Bolus")
                            self.needsRefresh = true
                            self.reloadData()
                        }
                    } else if self.active && self.visible, let bolus = units where bolus > 0 {
                        self.performSegueWithIdentifier(BolusViewController.className, sender: bolus)
                        self.needsRefresh = true
                    } else {
                        self.needsRefresh = true
                        self.reloadData()
                    }
                }
            }
        }
    }

    @IBAction func unwindFromBolusViewController(segue: UIStoryboardSegue) {
        if let bolusViewController = segue.sourceViewController as? BolusViewController {
            if let bolus = bolusViewController.bolus where bolus > 0 {
                let startDate = NSDate()
                dataManager.loopManager.enactBolus(bolus) { (success, error) in
                    if !success {
                        NotificationManager.sendBolusFailureNotificationForAmount(bolus, atDate: startDate)
                    }
                }
            }
        }
    }

    @IBAction func unwindFromSettings(segue: UIStoryboardSegue) {
        
    }

    // MARK: - HUDs

    @IBOutlet var loopCompletionHUD: LoopCompletionHUDView!

    @IBOutlet var basalRateHUD: BasalRateHUDView!

    @IBOutlet var reservoirVolumeHUD: ReservoirVolumeHUDView!

    @IBOutlet var batteryLevelHUD: BatteryLevelHUDView!
}
