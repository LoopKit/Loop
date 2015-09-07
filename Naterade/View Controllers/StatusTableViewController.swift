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
            self.tableView.reloadSections(NSIndexSet(index: 0), withRowAnimation: .Automatic)
        }
    }

    deinit {
        if let observer = pumpDataStatusObserver {
            NSNotificationCenter.defaultCenter().removeObserver(observer)
        }
    }

    // MARK: - Table view data source

    private lazy var dateFormatter: NSDateFormatter = {
        let formatter = NSDateFormatter()
        formatter.dateStyle = .MediumStyle
        formatter.timeStyle = .MediumStyle
        return formatter
    }()

    private enum Row: Int {
        case PumpDate = 0
        case Glucose
        case GlucoseDate
        case ReservoirRemaining
        case InsulinOnBoard
    }

    override func numberOfSectionsInTableView(tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch dataManager.latestPumpStatus?.glucose {
        case .None:
            return 1
        case .Some(let glucose):
            switch glucose {
            case .Off:
                return 5
            default:
                return 5
            }
        }
    }

    override func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {

        let cell = tableView.dequeueReusableCellWithIdentifier("Cell", forIndexPath: indexPath)

        switch Row(rawValue: indexPath.row)! {
        case .PumpDate:
            cell.textLabel?.text = NSLocalizedString("Last Updated", comment: "The title of the cell containing the last updated date")

            if let date = dataManager.latestPumpStatus?.pumpDate {
                cell.detailTextLabel?.text = dateFormatter.stringFromDate(date)
            } else {
                cell.detailTextLabel?.text = NSLocalizedString("Never", comment: "The detail value of a date cell with no value")
            }
        case .Glucose:
            cell.textLabel?.text = NSLocalizedString("Glucose (mg/dL)", comment: "The title of the cell containing the current glucose")

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

                    let numberString = NSNumber(integer: value).descriptionWithLocale(NSLocale.currentLocale())
                    cell.detailTextLabel?.text = "\(direction)\(numberString) mg/dL"
                default:
                    cell.detailTextLabel?.text = "\(status.glucose)"
                }

            } else {
                cell.detailTextLabel?.text = NSLocalizedString("––", comment: "The detail value of a numeric cell with no value")
            }

        case .GlucoseDate:
            cell.textLabel?.text = NSLocalizedString("Last Read", comment: "The title of the cell containing the last updated sensor date")

            if let date = dataManager.latestPumpStatus?.glucoseDate {
                cell.detailTextLabel?.text = dateFormatter.stringFromDate(date)
            } else {
                cell.detailTextLabel?.text = NSLocalizedString("Never", comment: "The detail value of a date cell with no value")
            }

        case .ReservoirRemaining:
            cell.textLabel?.text = NSLocalizedString("Units left", comment: "The title of the cell containing the amount of remaining insulin in the reservoir")

            if let remaining = dataManager.latestPumpStatus?.reservoirRemaining {
                let numberValue = NSNumber(double: remaining).descriptionWithLocale(NSLocale.currentLocale())
                cell.detailTextLabel?.text = "\(numberValue) Units"
            } else {
                cell.detailTextLabel?.text = NSLocalizedString("––", comment: "The detail value of a numeric cell with no value")
            }

        case .InsulinOnBoard:
            cell.textLabel?.text = NSLocalizedString("Insulin on Board", comment: "The title of the cell containing the estimated amount of active insulin in the body")

            if let iob = dataManager.latestPumpStatus?.iob {
                let numberValue = NSNumber(double: iob).descriptionWithLocale(NSLocale.currentLocale())
                cell.detailTextLabel?.text = "\(numberValue) Units"
            } else {
                cell.detailTextLabel?.text = NSLocalizedString("––", comment: "The detail value of a numeric cell with no value")
            }
        }

        return cell
    }
}
