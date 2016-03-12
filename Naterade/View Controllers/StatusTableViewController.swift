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
            notificationCenter.addObserverForName(nil, object: dataManager, queue: mainQueue) { (note) -> Void in
                self.needsRefresh = true
                self.reloadData()
            },
            notificationCenter.addObserverForName(UIApplicationWillResignActiveNotification, object: application, queue: mainQueue) { (note) -> Void in
                self.active = false
            },
            notificationCenter.addObserverForName(UIApplicationDidBecomeActiveNotification, object: application, queue: mainQueue) { (note) -> Void in
                self.active = true
            }
        ]

        if let carbStore = dataManager.carbStore {
            notificationObservers.append(notificationCenter.addObserverForName(CarbStore.CarbEntriesDidUpdateNotification, object: carbStore, queue: mainQueue) { (note) -> Void in
                self.needsRefresh = true
                self.reloadData()
            })
        }

        let chartPanGestureRecognizer = TouchAndPanGestureRecognizer()
        chartPanGestureRecognizer.delegate = self
        tableView.addGestureRecognizer(chartPanGestureRecognizer)
        charts.panGestureRecognizer = chartPanGestureRecognizer

        needsRefresh = true
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

    unowned let dataManager = PumpDataManager.sharedManager

    private var active = true {
        didSet {
            reloadData()
        }
    }

    private var needsRefresh = false

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

            tableView.beginUpdates()
            tableView.reloadSections(NSIndexSet(indexesInRange: NSMakeRange(Section.Pump.rawValue, Section.count - Section.Pump.rawValue)
            ), withRowAnimation: visible ? .Automatic : .None)
            tableView.endUpdates()

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
            dataManager.getPredictedGlucose { (values, error) -> Void in
                if error != nil {
                    self.needsRefresh = true
                } else {
                    self.charts.predictedGlucoseValues = values  // FixtureData.predictedGlucoseData
                }

                dispatch_group_leave(reloadGroup)
            }

            dispatch_group_enter(reloadGroup)
            dataManager.doseStore.getInsulinOnBoardValues(startDate: charts.startDate) { (values, error) -> Void in
                if let error = error {
                    self.dataManager.logger?.addError(error, fromSource: "DoseStore")
                    self.needsRefresh = true
                    // TODO: Display error in the cell
                } else {
                    self.charts.IOBValues = values  //FixtureData.recentIOBData
                }

                dispatch_group_leave(reloadGroup)
            }

            dispatch_group_enter(reloadGroup)
            dataManager.doseStore.getRecentNormalizedReservoirDoseEntries(startDate: charts.startDate) { (doses, error) -> Void in
                if let error = error {
                    self.dataManager.logger?.addError(error, fromSource: "DoseStore")
                    self.needsRefresh = true
                    // TODO: Display error in the cell
                } else {
                    self.charts.doseEntries = doses  // FixtureData.recentDoseData
                }

                dispatch_group_leave(reloadGroup)
            }

            if let carbStore = dataManager.carbStore {
                dispatch_group_enter(reloadGroup)
                carbStore.getCarbsOnBoardValues(startDate: charts.startDate) { (values, error) -> Void in
                    if let error = error {
                        self.dataManager.logger?.addError(error, fromSource: "CarbStore")
                        self.needsRefresh = true
                        // TODO: Display error in the cell
                    } else {
                        self.charts.COBValues = values
                    }

                    dispatch_group_leave(reloadGroup)
                }
            }

            charts.glucoseTargetRangeSchedule = dataManager.glucoseTargetRangeSchedule

            dispatch_group_notify(reloadGroup, dispatch_get_main_queue()) {
                self.charts.prerender()

                self.tableView.beginUpdates()
                self.tableView.reloadSections(NSIndexSet(index: Section.Charts.rawValue), withRowAnimation: .None)
                self.tableView.endUpdates()

                self.reloading = false
            }
        }
    }

    private enum Section: Int {
        case Charts = 0
        case Pump
        case Sensor

        static let count = 3
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

    // MARK: - Pump/Sensor Section Data

    private enum PumpRow: Int {
        case Date = 0
        case Battery
        case ReservoirRemaining
        case InsulinOnBoard

        static let count = 4
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

    private lazy var percentFormatter: NSNumberFormatter = {
        let formatter = NSNumberFormatter()
        formatter.numberStyle = .PercentStyle
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
        case .Pump:
            switch dataManager.latestPumpStatus {
            case .None:
                return 1
            case .Some:
                return PumpRow.count
            }
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
        case .Pump:
            let cell = tableView.dequeueReusableCellWithIdentifier("Cell", forIndexPath: indexPath)

            switch PumpRow(rawValue: indexPath.row)! {
            case .Date:
                cell.textLabel?.text = NSLocalizedString("Last Updated", comment: "The title of the cell containing the last updated date")

                if let date = dataManager.latestPumpStatus?.pumpDate {
                    cell.detailTextLabel?.text = dateFormatter.stringFromDate(date)
                } else {
                    cell.detailTextLabel?.text = emptyDateString
                }
            case .Battery:
                cell.textLabel?.text = NSLocalizedString("Battery", comment: "The title of the cell containing the remaining battery level")

                if let batteryRemainingPercent = dataManager.latestPumpStatus?.batteryRemainingPercent {
                    cell.detailTextLabel?.text = percentFormatter.stringFromNumber(Double(batteryRemainingPercent) / 100.0)
                } else {
                    cell.detailTextLabel?.text = emptyValueString
                }
            case .ReservoirRemaining:
                cell.textLabel?.text = NSLocalizedString("Reservoir", comment: "The title of the cell containing the amount of remaining insulin in the reservoir")

                if let status = dataManager.latestPumpStatus {
                    let components = NSDateComponents()
                    components.minute = status.reservoirRemainingMinutes

                    let componentsFormatter = NSDateComponentsFormatter()
                    componentsFormatter.unitsStyle = .Short
                    componentsFormatter.allowedUnits = [.Day, .Hour, .Minute]
                    componentsFormatter.includesApproximationPhrase = components.day > 0
                    componentsFormatter.includesTimeRemainingPhrase = true

                    let numberValue = NSNumber(double: status.reservoirRemainingUnits).descriptionWithLocale(locale)
                    let daysValue = componentsFormatter.stringFromDateComponents(components) ?? ""

                    cell.detailTextLabel?.text = "\(numberValue) Units (\(daysValue))"
                } else {
                    cell.detailTextLabel?.text = emptyValueString
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
            let cell = tableView.dequeueReusableCellWithIdentifier("Cell", forIndexPath: indexPath)

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
        case .Pump, .Sensor:
            return 44
        }
    }

    // MARK: - UIGestureRecognizerDelegate

    func gestureRecognizer(gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWithGestureRecognizer otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }

    func gestureRecognizer(gestureRecognizer: UIGestureRecognizer, shouldReceiveTouch touch: UITouch) -> Bool {
        if let headerView = tableView.tableHeaderView where touch.view?.isDescendantOfView(headerView) == true {
            return false
        } else {
            return true
        }
    }

    // MARK: - Actions

    override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
        super.prepareForSegue(segue, sender: sender)

        if let carbVC = segue.destinationViewController as? CarbEntryEditViewController, carbStore = dataManager.carbStore {
            carbVC.defaultAbsorptionTimes = carbStore.defaultAbsorptionTimes
            carbVC.preferredUnit = carbStore.preferredUnit
        }
    }

    @IBAction func unwindFromEditing(segue: UIStoryboardSegue) {
        if let carbVC = segue.sourceViewController as? CarbEntryEditViewController, carbStore = dataManager.carbStore, updatedEntry = carbVC.updatedCarbEntry {
            carbStore.addCarbEntry(updatedEntry) { (_, _, error) -> Void in
                if let error = error {
                    dispatch_async(dispatch_get_main_queue()) {
                        self.presentAlertControllerWithError(error)
                    }
                }
            }
        }
    }

    @IBAction func unwindFromBolusViewController(segue: UIStoryboardSegue) {
        if let bolusViewController = segue.sourceViewController as? BolusViewController {
            if let bolus = bolusViewController.bolus {
                print("Now bolusing \(bolus) Units")
            } else {
                print("Bolus cancelled")
            }
        }
    }
}
