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

    private var chartPanGestureRecognizer: UIPanGestureRecognizer?

    override func viewDidLoad() {
        super.viewDidLoad()

        let notificationCenter = NSNotificationCenter.defaultCenter()
        let mainQueue = NSOperationQueue.mainQueue()
        let application = UIApplication.sharedApplication()

        dataManagerObserver = notificationCenter.addObserverForName(nil, object: dataManager, queue: mainQueue) { (note) -> Void in
            self.needsRefresh = true
            self.reloadData()
        }

        resignObserver = notificationCenter.addObserverForName(UIApplicationWillResignActiveNotification, object: application, queue: mainQueue) { (note) -> Void in
            self.active = false
        }

        notificationCenter.addObserverForName(UIApplicationDidBecomeActiveNotification, object: application, queue: mainQueue) { (note) -> Void in
            self.active = true
        }

        chartPanGestureRecognizer = TouchAndPanGestureRecognizer()
        chartPanGestureRecognizer?.delegate = self
        tableView.addGestureRecognizer(chartPanGestureRecognizer!)

        needsRefresh = true
    }

    deinit {
        if let observer = dataManagerObserver {
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

        self.glucoseChart = nil
        self.iobChart = nil
        self.doseChart = nil
        self.cobChart = nil

        coordinator.animateAlongsideTransition({ (_) -> Void in
            self.tableView.reloadSections(NSIndexSet(index: Section.Charts.rawValue), withRowAnimation: .Fade)
        }, completion: nil)
    }

    // MARK: - State

    private var dataManagerObserver: AnyObject?

    private var resignObserver: AnyObject?

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

    private func reloadData() {
        if active && visible && needsRefresh {
            needsRefresh = false

            tableView.reloadSections(NSIndexSet(indexesInRange: NSMakeRange(Section.Pump.rawValue, Section.count - Section.Pump.rawValue)
            ), withRowAnimation: visible ? .Automatic : .None)

            chartStartDate = NSDate(timeIntervalSinceNow: -NSTimeInterval(hours: 6))
            let reloadGroup = dispatch_group_create()

            dispatch_group_enter(reloadGroup)
            dataManager.glucoseStore?.getRecentGlucoseValues(startDate: chartStartDate) { (values, error) -> Void in
                if let error = error {
                    self.dataManager.logger?.addError(error, fromSource: "GlucoseStore")
                    self.needsRefresh = true
                    // TODO: Display error in the cell
                } else {
                    self.glucoseValues = values // FixtureData.recentGlucoseData
                }

                dispatch_group_leave(reloadGroup)
            }

            dispatch_group_enter(reloadGroup)
            dataManager.doseStore.getInsulinOnBoardValues(startDate: chartStartDate) { (values, error) -> Void in
                if let error = error {
                    self.dataManager.logger?.addError(error, fromSource: "DoseStore")
                    self.needsRefresh = true
                    // TODO: Display error in the cell
                } else {
                    self.iobValues = values // FixtureData.recentIOBData
                }

                dispatch_group_leave(reloadGroup)
            }

            dispatch_group_notify(reloadGroup, dispatch_get_main_queue()) {
                let timeFormatter = NSDateFormatter()
                timeFormatter.dateFormat = "h a"

                self.glucosePoints = self.glucoseValues.map({
                    return ChartPoint(
                        x: ChartAxisValueDate(date: $0.startDate, formatter: timeFormatter),
                        y: ChartAxisValueDouble($0.quantity.doubleValueForUnit(HKUnit.milligramsPerDeciliterUnit()))
                    )
                })

                self.iobPoints = self.iobValues.map {
                    return ChartPoint(
                        x: ChartAxisValueDate(date: $0.startDate, formatter: timeFormatter),
                        y: ChartAxisValueDouble($0.value)
                    )
                }

                let allPoints = self.glucosePoints + self.iobPoints

                self.xAxisValues = Chart.generateXAxisValuesWithChartPoints(allPoints)

                self.tableView.reloadSections(NSIndexSet(index: Section.Charts.rawValue), withRowAnimation: .None)
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

        static let count = 2
    }

    private var chartStartDate = NSDate()

    private var xAxisValues: [ChartAxisValue] = []

    private var glucoseChart: Chart?

    private var glucoseValues: [GlucoseValue] = [] {
        didSet {
            glucoseChart = nil
        }
    }

    private var glucosePoints: [ChartPoint] = []

    private var iobChart: Chart?

    private var iobValues: [InsulinValue] = [] {
        didSet {
            iobChart = nil
        }
    }

    private var iobPoints: [ChartPoint] = []

    private var doseChart: Chart?

    private var doses: [DoseEntry] = []

    private var cobChart: Chart?

    private var carbEntries: [CarbEntry] = []

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
                if let chart = glucoseChart {
                    cell.chartView = chart.view
                } else if let chart = Chart.chartWithGlucosePoints(self.glucosePoints, xAxisValues: self.xAxisValues, targets: dataManager.glucoseTargetRangeSchedule, frame: frame, gestureRecognizer: chartPanGestureRecognizer) {

                    cell.chartView = chart.view
                    glucoseChart = chart
                }
            case .IOB:
                if let chart = iobChart {
                    cell.chartView = chart.view
                } else if let chart = Chart.chartWithIOBPoints(self.iobPoints, xAxisValues: self.xAxisValues, frame: frame, gestureRecognizer: chartPanGestureRecognizer) {

                    cell.chartView = chart.view
                    iobChart = chart
                }
            case .Dose:
                break
            case .COB:
                break
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

                if let glucose = dataManager.latestGlucose, startTime = dataManager.transmitterStartTime {
                    let date = NSDate(timeIntervalSince1970: startTime).dateByAddingTimeInterval(NSTimeInterval(glucose.timestamp))

                    cell.detailTextLabel?.text = dateFormatter.stringFromDate(date)
                } else {
                    cell.detailTextLabel?.text = emptyValueString
                }
            case .Glucose:
                cell.textLabel?.text = NSLocalizedString("Glucose", comment: "The title of the cell containing the current glucose")

                if let glucose = dataManager.latestGlucose {
                    let numberString = NSNumber(unsignedShort: glucose.glucose).descriptionWithLocale(locale)
                    cell.detailTextLabel?.text = "\(numberString) mg/dL"
                } else {
                    cell.detailTextLabel?.text = emptyValueString
                }
            case .Trend:
                cell.textLabel?.text = NSLocalizedString("Trend", comment: "The title of the cell containing the current glucose trend")

                if let glucose = dataManager.latestGlucose where glucose.state > 5 {
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

                if let glucose = dataManager.latestGlucose {
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
        return gestureRecognizer === chartPanGestureRecognizer
    }
}
