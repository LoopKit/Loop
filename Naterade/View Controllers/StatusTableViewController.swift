//
//  StatusTableViewController.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 9/6/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

import UIKit

class StatusTableViewController: UITableViewController {

    private var pumpDataStatusObserver: AnyObject?

    unowned let dataManager = PumpDataManager.sharedManager

    override func viewDidLoad() {
        super.viewDidLoad()

        tableView.rowHeight = 44

        pumpDataStatusObserver = NSNotificationCenter.defaultCenter().addObserverForName(PumpDataManager.PumpStatusUpdatedNotification, object: dataManager, queue: nil) { (note) -> Void in
            self.tableView.reloadData()
        }
    }

    deinit {
        if let observer = pumpDataStatusObserver {
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
        case Watch
        case Sensor

        static let count = 3
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
        case PreviousGlucose
        case Age
        case NextCalibration

        static let count = 5
    }

    override func numberOfSectionsInTableView(tableView: UITableView) -> Int {
        switch dataManager.latestPumpStatus?.glucose {
        case .None:
            return Section.count - 1
        case .Some(let glucose):
            switch glucose {
            case .Off:
                return Section.count - 1
            default:
                return Section.count
            }
        }
    }

    override func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .Pump:
            switch dataManager.latestPumpStatus {
            case .None:
                return 1
            case .Some(_):
                return PumpRow.count
            }
        case .Sensor:
            switch dataManager.latestPumpStatus?.glucose {
            case .None:
                return 0
            case .Some(let glucose):
                switch glucose {
                case .Off:
                    return 0
                case .Ended:
                    return 3
                default:
                    return SensorRow.count
                }
            }
        case .Watch:
            return 1
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

                if let date = dataManager.latestPumpStatus?.glucoseDate {
                    cell.detailTextLabel?.text = dateFormatter.stringFromDate(date)
                } else {
                    cell.detailTextLabel?.text = emptyValueString
                }
            case .Glucose:
                cell.textLabel?.text = NSLocalizedString("Glucose", comment: "The title of the cell containing the current glucose")

                if let status = dataManager.latestPumpStatus {

                    switch status.glucose {
                    case .Active(glucose: let value):
                        let direction: String

                        switch status.glucoseTrend {
                        case .Flat:
                            direction = ""
                        case .Down:
                            direction = "↓ "
                        case .DownDown:
                            direction = "⇊ "
                        case .Up:
                            direction = "↑ "
                        case .UpUp:
                            direction = "⇈ "
                        }

                        let numberString = NSNumber(integer: value).descriptionWithLocale(locale)
                        cell.detailTextLabel?.text = "\(direction)\(numberString) mg/dL"
                    default:
                        cell.detailTextLabel?.text = String(status.glucose)
                    }
                    
                } else {
                    cell.detailTextLabel?.text = emptyValueString
                }
            case .PreviousGlucose:
                cell.textLabel?.text = NSLocalizedString("Previous Glucose", comment: "The title of the cell containing the next most-recent glucose reading")

                switch dataManager.latestPumpStatus?.previousGlucose {
                case .None:
                    cell.detailTextLabel?.text = emptyValueString
                case .Active(glucose: let value)?:
                    let numberString = NSNumber(integer: value).descriptionWithLocale(locale)
                    cell.detailTextLabel?.text = "\(numberString) mg/dL"
                case .Some(let glucose):
                    cell.detailTextLabel?.text = String(glucose)
                }
            case .Age:
                cell.textLabel?.text = NSLocalizedString("Sensor Age", comment: "The title of the cell containing the sensor age and time remaining")

                switch dataManager.latestPumpStatus {
                case .None:
                    cell.detailTextLabel?.text = emptyValueString
                case let status?:
                    let dateFormatter = NSDateComponentsFormatter()
                    dateFormatter.unitsStyle = .Short

                    let displayString = NSLocalizedString("%1$@ (%2$@)", comment: "The format of the sensor age (1) and sensor remaining (2) combined description")

                    let sensorAge = dateFormatter.stringFromTimeInterval(NSTimeInterval(status.sensorAgeHours * 60 * 60))

                    dateFormatter.includesTimeRemainingPhrase = true

                    let sensorRemaining = dateFormatter.stringFromTimeInterval(NSTimeInterval(status.sensorRemainingHours * 60 * 60))

                    if let sensorAge = sensorAge, sensorRemaining = sensorRemaining {
                        cell.detailTextLabel?.text = String(format: displayString, sensorAge, sensorRemaining)
                    } else {
                        cell.detailTextLabel?.text = emptyValueString
                    }
                }
            case .NextCalibration:
                cell.textLabel?.text = NSLocalizedString("Next calibration", comment: "The title of the cell containing the date of next sensor calibration")

                if let date = dataManager.latestPumpStatus?.nextSensorCalibration {
                    cell.detailTextLabel?.text = dateFormatter.stringFromDate(date)
                } else {
                    cell.detailTextLabel?.text = emptyValueString
                }
            }
        case .Watch:
            cell.textLabel?.text = NSLocalizedString("Watch App", comment: "The title of the cell containing Apple Watch App status")

            let detailText: String

            switch dataManager.watchSession {
            case .None:
                detailText = NSLocalizedString("Not available", comment: "The watch status detail displayed when connectivity is unavailable")
            case let session?:
                switch session.paired {
                case false:
                    detailText = NSLocalizedString("Not paired", comment: "The watch status detail displayed when there is no paired watch")
                case true:
                    switch session.watchAppInstalled {
                    case false:
                        detailText = NSLocalizedString("Not installed", comment: "The watch status detail displayed when the watch app is not installed")
                    case true:
                        detailText = String(session)
                    }
                }
            }

            cell.detailTextLabel?.text = detailText
        }

        return cell
    }
}
