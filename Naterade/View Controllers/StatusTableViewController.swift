//
//  StatusTableViewController.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 9/6/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

import UIKit

class StatusTableViewController: UITableViewController {

    private var dataManagerObserver: AnyObject?

    unowned let dataManager = PumpDataManager.sharedManager

    override func viewDidLoad() {
        super.viewDidLoad()

        tableView.rowHeight = 44

        dataManagerObserver = NSNotificationCenter.defaultCenter().addObserverForName(nil, object: dataManager, queue: NSOperationQueue.mainQueue()) { (note) -> Void in
            self.tableView.reloadData()
        }
    }

    deinit {
        if let observer = dataManagerObserver {
            NSNotificationCenter.defaultCenter().removeObserver(observer)
        }
    }

    // MARK: - Table view data source

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

    private enum Section: Int {
        case Pump = 0
        case Sensor

        static let count = 2
    }

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

    override func numberOfSectionsInTableView(tableView: UITableView) -> Int {
        switch dataManager.latestGlucose {
        case .None:
            return Section.count - 1
        case .Some:
            return Section.count
        }
    }

    override func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
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

        let cell = tableView.dequeueReusableCellWithIdentifier("Cell", forIndexPath: indexPath)
        let locale = NSLocale.currentLocale()

        switch Section(rawValue: indexPath.section)! {
        case .Pump:
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
                    components.day = status.reservoirRemainingDays
                    components.minute = status.reservoirRemainingMinutes

                    let componentsFormatter = NSDateComponentsFormatter()
                    componentsFormatter.unitsStyle = .Short
                    componentsFormatter.allowedUnits = [.Day, .Hour, .Minute]
                    componentsFormatter.includesApproximationPhrase = components.day > 0
                    componentsFormatter.includesTimeRemainingPhrase = true

                    let daysValue = componentsFormatter.stringFromDateComponents(components) ?? ""
                    let numberValue = NSNumber(double: status.reservoirRemainingUnits).descriptionWithLocale(locale)

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
        case .Sensor:
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
        }

        return cell
    }
}
