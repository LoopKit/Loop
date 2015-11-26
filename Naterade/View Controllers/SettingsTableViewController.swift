//
//  SettingsTableViewController.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 8/29/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

import UIKit
import RileyLinkKit

class SettingsTableViewController: UITableViewController, TextFieldTableViewControllerDelegate {

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
                for (index, device) in deviceManager.devices.enumerate() {
                    if device.peripheral == peripheral {
                        tableView.reloadRowsAtIndexPaths([NSIndexPath(forRow: index, inSection: 1)], withRowAnimation: .Automatic)
                    }
                }
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
        switch section {
        case 0:
            return 2
        case 1:
            switch dataManager.rileyLinkState {
            case .Ready(manager: let manager):
                return manager.devices.count
            case .NeedsConfiguration:
                return 0
            }
        default:
            return 0
        }
    }

    override func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        var cell: UITableViewCell?

        switch indexPath.section {
        case 0:
            switch indexPath.row {
            case 0:
                let pumpIDCell = tableView.dequeueReusableCellWithIdentifier("ConfigTableViewCell", forIndexPath: indexPath)
                pumpIDCell.textLabel?.text = NSLocalizedString("Pump ID", comment: "The title text for the pump ID config value")
                pumpIDCell.detailTextLabel?.text = dataManager.pumpID ?? NSLocalizedString("Tap to set", comment: "The empty-state text for the Pump ID value")

                cell = pumpIDCell
            case 1:
                let transmitterIDCell = tableView.dequeueReusableCellWithIdentifier("ConfigTableViewCell", forIndexPath: indexPath)
                transmitterIDCell.textLabel?.text = NSLocalizedString("Transmitter ID", comment: "The title text for the transmitter ID config value")
                transmitterIDCell.detailTextLabel?.text = dataManager.transmitterID ?? NSLocalizedString("Tap to set", comment: "The empty-state text for the Transmitter ID value")

                cell = transmitterIDCell
            default:
                assertionFailure()
            }

        case 1:
            let deviceCell = tableView.dequeueReusableCellWithIdentifier("RileyLinkDeviceTableViewCell") as! RileyLinkDeviceTableViewCell

            let device = dataManager.rileyLinkManager?.devices[indexPath.row]

            deviceCell.configureCellWithName(device?.name,
                signal: device?.RSSI?.integerValue,
                peripheralState: device?.peripheral.state
            )

            deviceCell.connectSwitch.addTarget(self, action: "deviceConnectionChanged:", forControlEvents: .ValueChanged)

            cell = deviceCell
        default:
            assertionFailure()
        }
        return cell!
    }

    override func tableView(tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0:
            return NSLocalizedString("Configuration", comment: "The title of the configuration section in settings")
        default:
            return nil
        }
    }

    // MARK: - UITableViewDelegate

    override func tableView(tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        switch section {
        case 1:
            return devicesSectionTitleView
        default:
            return nil
        }
    }

    override func tableView(tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        switch section {
        case 0:
            return 55  // Give the top section extra spacing
        default:
            return 37
        }
    }

    // MARK: - Navigation

    override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
        if let vc = segue.destinationViewController as? TextFieldTableViewController,
            cell = sender as? UITableViewCell,
            indexPath = tableView.indexPathForCell(cell)
        {
            switch indexPath.row {
            case 0:
                vc.placeholder = NSLocalizedString("Enter the 6-digit pump ID", comment: "The placeholder text instructing users how to enter a pump ID")
                vc.value = dataManager.pumpID
            case 1:
                vc.placeholder = NSLocalizedString("Enter the 6-digit transmitter ID", comment: "The placeholder text instructing users how to enter a pump ID")
                vc.value = dataManager.transmitterID
            default:
                assertionFailure()
            }

            vc.title = cell.textLabel?.text
            vc.indexPath = indexPath
            vc.delegate = self
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
            switch indexPath.row {
            case 0:
                dataManager.pumpID = controller.value
            case 1:
                dataManager.transmitterID = controller.value
            default:
                assertionFailure()
            }
        }

        tableView.reloadData()
    }

}
