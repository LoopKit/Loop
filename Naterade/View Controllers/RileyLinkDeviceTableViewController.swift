//
//  RileyLinkDeviceTableViewController.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 3/5/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import UIKit
import MinimedKit
import RileyLinkKit


class RileyLinkDeviceTableViewController: UITableViewController {

    var device: RileyLinkDevice!

    private var appeared = false

    override func viewDidLoad() {
        super.viewDidLoad()

        title = device.name
    }

    override func viewWillAppear(animated: Bool) {
        super.viewWillAppear(animated)

        if appeared {
            tableView.reloadData()
        }

        appeared = true
    }

    // MARK: - Formatters

    private lazy var dateFormatter: NSDateFormatter = {
        let dateFormatter = NSDateFormatter()

        dateFormatter.dateStyle = .MediumStyle
        dateFormatter.timeStyle = .MediumStyle

        return dateFormatter
    }()

    private lazy var decimalFormatter: NSNumberFormatter = {
        let decimalFormatter = NSNumberFormatter()

        decimalFormatter.numberStyle = .DecimalStyle
        decimalFormatter.minimumFractionDigits = 2
        decimalFormatter.maximumFractionDigits = 2

        return decimalFormatter
    }()

    // MARK: - Table view data source

    private enum Section: Int {
        case Device
        case Pump
        case Commands

        static let count = 3
    }

    private enum DeviceRow: Int {
        case RSSI
        case Connection

        static let count = 2
    }

    private enum PumpRow: Int {
        case ID
        case Awake

        static let count = 2
    }

    private enum CommandRow: Int {
        case Tune
        case Bolus
        case TempBasal

        static let count = 3
    }

    override func numberOfSectionsInTableView(tableView: UITableView) -> Int {
        if device.pumpState == nil {
            return Section.count - 1
        } else {
            return Section.count
        }
    }

    override func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .Device:
            return DeviceRow.count
        case .Pump:
            return PumpRow.count
        case .Commands:
            return CommandRow.count
        }
    }

    override func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCellWithIdentifier("Cell", forIndexPath: indexPath)

        cell.accessoryType = .None

        switch Section(rawValue: indexPath.section)! {
        case .Device:
            switch DeviceRow(rawValue: indexPath.row)! {
            case .Connection:
                cell.textLabel?.text = NSLocalizedString("Connection State", comment: "The title of the cell showing connection state")
                cell.detailTextLabel?.text = device.peripheral.state.description
            case .RSSI:
                cell.textLabel?.text = NSLocalizedString("Signal strength", comment: "The title of the cell showing signal strength (RSSI)")
                if let RSSI = device.RSSI?.integerValue {
                    cell.detailTextLabel?.text = "\(RSSI) dB"
                } else {
                    cell.detailTextLabel?.text = "–"
                }
            }
        case .Pump:
            switch PumpRow(rawValue: indexPath.row)! {
            case .ID:
                cell.textLabel?.text = NSLocalizedString("Pump ID", comment: "The title of the cell showing pump ID")
                if let pumpID = device.pumpState?.pumpId {
                    cell.detailTextLabel?.text = pumpID
                } else {
                    cell.detailTextLabel?.text = "–"
                }
            case .Awake:
                switch device.pumpState?.awakeUntil {
                case let until? where until < NSDate():
                    cell.textLabel?.text = NSLocalizedString("Last Awake", comment: "The title of the cell describing an awake radio")
                    cell.detailTextLabel?.text = dateFormatter.stringFromDate(until)
                case let until?:
                    cell.textLabel?.text = NSLocalizedString("Awake Until", comment: "The title of the cell describing an awake radio")
                    cell.detailTextLabel?.text = dateFormatter.stringFromDate(until)
                default:
                    cell.textLabel?.text = NSLocalizedString("Listening Off", comment: "The title of the cell describing no radio awake data")
                    cell.detailTextLabel?.text = nil
                }
            }
        case .Commands:
            switch CommandRow(rawValue: indexPath.row)! {
            case .Tune:
                switch (device.radioFrequency, device.lastTuned) {
                case (let frequency?, let date?):
                    cell.textLabel?.text = "\(decimalFormatter.stringFromNumber(frequency)!) MHz"
                    cell.detailTextLabel?.text = dateFormatter.stringFromDate(date)
                default:
                    cell.textLabel?.text = NSLocalizedString("Tune radio frequency", comment: "The title of the cell describing the command to re-tune the radio")
                    cell.detailTextLabel?.text = nil
                }
                cell.accessoryType = .DisclosureIndicator
            case .Bolus:
                cell.textLabel?.text = "Bolus"
                cell.detailTextLabel?.text = "0.1 U"
                cell.accessoryType = .DisclosureIndicator
            case .TempBasal:
                cell.textLabel?.text = "Set Temporary Basal"
                cell.detailTextLabel?.text = "0.5 U/hour"
                cell.accessoryType = .DisclosureIndicator
            }
        }

        return cell
    }

    override func tableView(tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .Device:
            return NSLocalizedString("Bluetooth", comment: "The title of the section describing the device")
        case .Pump:
            return NSLocalizedString("Pump", comment: "The title of the section describing the pump")
        case .Commands:
            return NSLocalizedString("Commands", comment: "The title of the section describing commands")
        }
    }

    // MARK: - UITableViewDelegate

    override func tableView(tableView: UITableView, shouldHighlightRowAtIndexPath indexPath: NSIndexPath) -> Bool {
        switch Section(rawValue: indexPath.section)! {
        case .Device, .Pump:
            return false
        case .Commands:
            return true
        }
    }

    override func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
        switch Section(rawValue: indexPath.section)! {
        case .Commands:
            switch CommandRow(rawValue: indexPath.row)! {
            case .Tune:
                let vc = CommandResponseViewController(command: { [unowned self] (completionHandler) -> String in
                    self.device.tunePumpWithCompletionHandler({ (response) -> Void in
                        if let data = try? NSJSONSerialization.dataWithJSONObject(response, options: .PrettyPrinted) {
                            let string = String(data: data, encoding: NSUTF8StringEncoding)

                            completionHandler(responseText: string ?? "No response found")
                        } else {
                            completionHandler(responseText: "An Unknown Issue Occured")
                        }
                    })

                    return "Tuning radio..."
                })

                vc.title = "Tuning device radio"

                self.showViewController(vc, sender: indexPath)
            case .Bolus:
                let vc = CommandResponseViewController(command: { [unowned self] (completionHandler) -> String in
                    self.device.sendBolusDose(0.1) { (success, error) -> Void in
                        dispatch_async(dispatch_get_main_queue()) {
                            if success {
                                completionHandler(responseText: "Succeeded")
                            } else if let error = error {
                                completionHandler(responseText: "Failed: \(error)")
                            } else {
                                completionHandler(responseText: "Failed")
                            }
                        }
                    }

                    return "Sending bolus..."
                })

                vc.title = "Bolus"
                
                self.showViewController(vc, sender: indexPath)
            case .TempBasal:
                let vc = CommandResponseViewController(command: { [unowned self] (completionHandler) -> String in
                    self.device.sendTempBasalDose(0.5, duration: NSTimeInterval(minutes: 30)) { (success, message, error) -> Void in
                        dispatch_async(dispatch_get_main_queue()) {
                            if success, let body = message?.messageBody as? ReadTempBasalCarelinkMessageBody {
                                completionHandler(responseText: "Succeeded: \(body.rate) U, \(body.timeRemaining.minutes) minutes remaining")
                            } else if let error = error {
                                completionHandler(responseText: "Failed: \(error)")
                            } else {
                                completionHandler(responseText: "Failed")
                            }
                        }
                    }

                    return "Setting temp basal..."
                })

                vc.title = "Set Temp Basal"

                self.showViewController(vc, sender: indexPath)
            }
        case .Device, .Pump:
            break
        }
    }
}
