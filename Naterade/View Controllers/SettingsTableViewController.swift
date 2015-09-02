//
//  SettingsTableViewController.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 8/29/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

import UIKit
import RileyLinkKit

class SettingsTableViewController: UITableViewController, PumpIDTableViewControllerDelegate {

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
        dataManagerObserver = nil  // iOS 8 only
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
        switch dataManager.state {
        case .Ready(manager: _):
            return 2
        case .NeedsConfiguration:
            return 1
        }
    }

    override func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0:
            return 1
        case 1:
            switch dataManager.state {
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
            let pumpIDCell = tableView.dequeueReusableCellWithIdentifier("PumpIDTableViewCell")!

            pumpIDCell.detailTextLabel?.text = dataManager.pumpID ?? NSLocalizedString("Tap to set", comment: "The empty-state text for the Pump ID value")

            cell = pumpIDCell
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
        if let pumpIDTVC = segue.destinationViewController as? PumpIDTableViewController {
            pumpIDTVC.pumpID = dataManager.pumpID
            pumpIDTVC.delegate = self
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

    // MARK: - PumpIDTableViewControllerDelegate

    func pumpIDTableViewControllerDidEndEditing(controller: PumpIDTableViewController) {
        dataManager.pumpID = controller.pumpID

        tableView.reloadData()
    }

}
