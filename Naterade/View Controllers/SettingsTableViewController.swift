//
//  SettingsTableViewController.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 8/29/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

import UIKit
import HealthKit
import LoopKit
import RileyLinkKit

private let ConfigCellIdentifier = "ConfigTableViewCell"

private let TapToSetString = NSLocalizedString("Tap to set", comment: "The empty-state text for a configuration value")


class SettingsTableViewController: UITableViewController, DailyValueScheduleTableViewControllerDelegate, TextFieldTableViewControllerDelegate {

    @IBOutlet var devicesSectionTitleView: UIView!

    private var peripheralStateChangeContext = 0

    override func viewDidLoad() {
        super.viewDidLoad()

        dataManagerObserver = NSNotificationCenter.defaultCenter().addObserverForName(RileyLinkManagerDidDiscoverDeviceNotification, object: dataManager, queue: nil) { [weak self = self] (note) -> Void in
            if let strongSelf = self,
                deviceManager = strongSelf.dataManager.rileyLinkManager
            {
                strongSelf.tableView.insertRowsAtIndexPaths([NSIndexPath(forRow: deviceManager.devices.count - 1, inSection: 1)], withRowAnimation: .Automatic)

                deviceManager.devices.last?.peripheral.addObserver(strongSelf, forKeyPath: "state", options: [], context: &(strongSelf.peripheralStateChangeContext))
            }
        }
    }

    override func viewDidAppear(animated: Bool) {
        super.viewDidAppear(animated)

        if let deviceManager = dataManager.rileyLinkManager {
            deviceManager.deviceScanningEnabled = true

            deviceManager.devices.forEach { device in
                device.peripheral.addObserver(self, forKeyPath: "state", options: [], context: &peripheralStateChangeContext)
            }
        }

        if dataManager.transmitterID != nil, let glucoseStore = dataManager.glucoseStore where glucoseStore.authorizationRequired {
            glucoseStore.authorize({ (success, error) -> Void in
                // Do nothing for now
            })
        }
    }

    override func viewWillDisappear(animated: Bool) {
        super.viewWillDisappear(animated)

        if let deviceManager = dataManager.rileyLinkManager {
            deviceManager.deviceScanningEnabled = false

            deviceManager.devices.forEach { device in
                device.peripheral.removeObserver(self, forKeyPath: "state", context: &peripheralStateChangeContext)
            }
        }
    }

    deinit {
        dataManagerObserver = nil
    }

    override func observeValueForKeyPath(keyPath: String?, ofObject object: AnyObject?, change: [String : AnyObject]?, context: UnsafeMutablePointer<Void>) {
        if context == &peripheralStateChangeContext {
            if let peripheral = object as? CBPeripheral,
                deviceManager = dataManager.rileyLinkManager
            {
                tableView.beginUpdates()
                for (index, device) in deviceManager.devices.enumerate() {
                    if device.peripheral == peripheral {
                        tableView.reloadRowsAtIndexPaths([NSIndexPath(forRow: index, inSection: 1)], withRowAnimation: .Automatic)
                    }
                }
                tableView.endUpdates()
            }
        } else {
            super.observeValueForKeyPath(keyPath, ofObject: object, change: change, context: context)
        }
    }

    private var dataManager: PumpDataManager {
        return PumpDataManager.sharedManager
    }

    private var dataManagerObserver: AnyObject? {
        willSet {
            if let observer = dataManagerObserver {
                NSNotificationCenter.defaultCenter().removeObserver(observer)
            }
        }
    }

    private enum Section: Int {
        case Configuration = 0
        case Devices
    }

    private enum ConfigurationRow: Int {
        case PumpID = 0
        case TransmitterID
        case BasalRate
        case CarbRatio
    }

    // MARK: - UITableViewDataSource

    override func numberOfSectionsInTableView(tableView: UITableView) -> Int {
        switch dataManager.rileyLinkState {
        case .Ready(manager: _):
            return 2
        case .NeedsConfiguration:
            return 1
        }
    }

    override func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .Configuration:
            return 3
        case .Devices:
            switch dataManager.rileyLinkState {
            case .Ready(manager: let manager):
                return manager.devices.count
            case .NeedsConfiguration:
                return 0
            }
        }
    }

    override func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        let cell: UITableViewCell

        switch Section(rawValue: indexPath.section)! {
        case .Configuration:
            let configCell = tableView.dequeueReusableCellWithIdentifier(ConfigCellIdentifier, forIndexPath: indexPath)

            switch ConfigurationRow(rawValue: indexPath.row)! {
            case .PumpID:
                configCell.textLabel?.text = NSLocalizedString("Pump ID", comment: "The title text for the pump ID config value")
                configCell.detailTextLabel?.text = dataManager.pumpID ?? TapToSetString
            case .TransmitterID:
                configCell.textLabel?.text = NSLocalizedString("Transmitter ID", comment: "The title text for the transmitter ID config value")
                configCell.detailTextLabel?.text = dataManager.transmitterID ?? TapToSetString
            case .BasalRate:
                configCell.textLabel?.text = NSLocalizedString("Basal Rates", comment: "The title text for the basal rate schedule")

                if let basalRateSchedule = dataManager.basalRateSchedule {
                    configCell.detailTextLabel?.text = "\(basalRateSchedule.total()) U"
                } else {
                    configCell.detailTextLabel?.text = TapToSetString
                }
            case .CarbRatio:
                configCell.textLabel?.text = NSLocalizedString("Carb Ratios", comment: "The title text for the carb ratio schedule")

                if let carbRatioSchedule = dataManager.carbRatioSchedule {
                    let unit = carbRatioSchedule.unit
                    let value = carbRatioSchedule.quantityAt(NSDate()).doubleValueForUnit(unit)

                    configCell.detailTextLabel?.text = "\(value) \(unit)"
                } else {
                    configCell.detailTextLabel?.text = TapToSetString
                }
            }

            cell = configCell
        case .Devices:
            let deviceCell = tableView.dequeueReusableCellWithIdentifier(RileyLinkDeviceTableViewCell.className) as! RileyLinkDeviceTableViewCell

            let device = dataManager.rileyLinkManager?.devices[indexPath.row]

            deviceCell.configureCellWithName(device?.name,
                signal: device?.RSSI?.integerValue,
                peripheralState: device?.peripheral.state
            )

            deviceCell.connectSwitch.addTarget(self, action: "deviceConnectionChanged:", forControlEvents: .ValueChanged)

            cell = deviceCell
        }
        return cell
    }

    override func tableView(tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .Configuration:
            return NSLocalizedString("Configuration", comment: "The title of the configuration section in settings")
        case .Devices:
            return nil
        }
    }

    // MARK: - UITableViewDelegate

    override func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
        switch Section(rawValue: indexPath.section)! {
        case .Configuration:
            switch ConfigurationRow(rawValue: indexPath.row)! {
            case .PumpID, .TransmitterID:
                performSegueWithIdentifier(TextFieldTableViewController.className, sender: tableView.cellForRowAtIndexPath(indexPath))
            case .BasalRate:
                let scheduleVC = BasalRateScheduleTableViewController()

                if let profile = dataManager.basalRateSchedule {
                    scheduleVC.timeZone = profile.timeZone
                    scheduleVC.scheduleItems = profile.items ?? []
                }
                scheduleVC.delegate = self
                scheduleVC.title = NSLocalizedString("Basal Rates", comment: "The title of the basal rate profile screen")

                showViewController(scheduleVC, sender: tableView.cellForRowAtIndexPath(indexPath))
            case .CarbRatio:
                break
            }
        case .Devices:
            break
        }
    }

    override func tableView(tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        switch Section(rawValue: section)! {
        case .Devices:
            return devicesSectionTitleView
        case .Configuration:
            return nil
        }
    }

    override func tableView(tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        switch Section(rawValue: section)! {
        case .Configuration:
            return 55  // Give the top section extra spacing
        case .Devices:
            return 37
        }
    }

    // MARK: - Navigation

    override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
        if let
            cell = sender as? UITableViewCell,
            indexPath = tableView.indexPathForCell(cell)
        {
            switch segue.destinationViewController {
            case let vc as TextFieldTableViewController:
                switch ConfigurationRow(rawValue: indexPath.row)! {
                case .PumpID:
                    vc.placeholder = NSLocalizedString("Enter the 6-digit pump ID", comment: "The placeholder text instructing users how to enter a pump ID")
                    vc.value = dataManager.pumpID
                case .TransmitterID:
                    vc.placeholder = NSLocalizedString("Enter the 6-digit transmitter ID", comment: "The placeholder text instructing users how to enter a pump ID")
                    vc.value = dataManager.transmitterID
                default:
                    assertionFailure()
                }

                vc.title = cell.textLabel?.text
                vc.indexPath = indexPath
                vc.delegate = self
            default:
                break
            }
        }
    }

    // MARK: - Device mangement

    func deviceConnectionChanged(connectSwitch: UISwitch) {
        let switchOrigin = connectSwitch.convertPoint(.zero, toView: tableView)

        if let indexPath = tableView.indexPathForRowAtPoint(switchOrigin) where indexPath.section == 1,
            let deviceManager = dataManager.rileyLinkManager
        {
            let device = deviceManager.devices[indexPath.row]

            if connectSwitch.on {
                dataManager.connectToRileyLink(device)
            } else {
                dataManager.disconnectFromRileyLink(device)
            }
        }
    }

    // MARK: - TextFieldTableViewControllerDelegate

    func textFieldTableViewControllerDidEndEditing(controller: TextFieldTableViewController) {
        if let indexPath = controller.indexPath {
            switch ConfigurationRow(rawValue: indexPath.row)! {
            case .PumpID:
                dataManager.pumpID = controller.value
            case .TransmitterID:
                dataManager.transmitterID = controller.value
            default:
                assertionFailure()
            }
        }

        tableView.reloadData()
    }

    // MARK: - DailyValueScheduleTableViewControllerDelegate

    func dailyValueScheduleTableViewControllerWillFinishUpdating(controller: BasalRateScheduleTableViewController) {
        if let indexPath = tableView.indexPathForSelectedRow {
            switch Section(rawValue: indexPath.section)! {
            case .Configuration:
                switch ConfigurationRow(rawValue: indexPath.row)! {
                case .BasalRate:
                    dataManager.basalRateSchedule = BasalRateSchedule(dailyItems: controller.scheduleItems, timeZone: controller.timeZone)
                default:
                    break
                }

                tableView.reloadRowsAtIndexPaths([indexPath], withRowAnimation: .None)
            default:
                break
            }
        }
    }
}
