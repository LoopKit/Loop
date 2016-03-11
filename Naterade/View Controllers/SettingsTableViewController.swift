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

    override func viewDidLoad() {
        super.viewDidLoad()

        dataManagerObserver = NSNotificationCenter.defaultCenter().addObserverForName(nil, object: dataManager, queue: nil) { [weak self = self] (note) -> Void in
            if let deviceManager = self?.dataManager.rileyLinkManager {
                switch note.name {
                case RileyLinkManagerDidDiscoverDeviceNotification:
                    self?.tableView.insertRowsAtIndexPaths([NSIndexPath(forRow: deviceManager.devices.count - 1, inSection: Section.Devices.rawValue)], withRowAnimation: .Automatic)
                case RileyLinkDeviceConnectionStateDidChangeNotification:
                    if let device = note.userInfo?[RileyLinkDeviceKey] as? RileyLinkDevice, index = deviceManager.devices.indexOf(device) {
                        self?.tableView.reloadRowsAtIndexPaths([NSIndexPath(forRow: index, inSection: Section.Devices.rawValue)], withRowAnimation: .None)
                    }
                default:
                    break
                }
            }
        }
    }

    override func viewDidAppear(animated: Bool) {
        super.viewDidAppear(animated)

        if let deviceManager = dataManager.rileyLinkManager {
            deviceManager.deviceScanningEnabled = true
        }

        if dataManager.transmitterID != nil, let glucoseStore = dataManager.glucoseStore where glucoseStore.authorizationRequired {
            glucoseStore.authorize({ (success, error) -> Void in
                // Do nothing for now
            })
        }
    }

    override func viewDidDisappear(animated: Bool) {
        super.viewDidDisappear(animated)

        if let deviceManager = dataManager.rileyLinkManager {
            deviceManager.deviceScanningEnabled = false
        }
    }

    override func viewWillDisappear(animated: Bool) {
        super.viewWillDisappear(animated)
    }

    deinit {
        dataManagerObserver = nil
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

        static let count = 2
    }

    private enum ConfigurationRow: Int {
        case PumpID = 0
        case TransmitterID
        case GlucoseTargetRange
        case InsulinActionDuration
        case BasalRate
        case CarbRatio
        case InsulinSensitivity

        static let count = 7
    }

    private lazy var valueNumberFormatter: NSNumberFormatter = {
        let formatter = NSNumberFormatter()

        formatter.numberStyle = .DecimalStyle
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2

        return formatter
    }()

    // MARK: - UITableViewDataSource

    override func numberOfSectionsInTableView(tableView: UITableView) -> Int {
        switch dataManager.rileyLinkState {
        case .Ready(manager: _):
            return Section.count
        case .NeedsConfiguration:
            return Section.count - 1
        }
    }

    override func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .Configuration:
            return ConfigurationRow.count
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
                    let value = carbRatioSchedule.averageQuantity().doubleValueForUnit(unit)

                    valueNumberFormatter.minimumFractionDigits = 2

                    configCell.detailTextLabel?.text = "\(valueNumberFormatter.stringFromNumber(value)!) \(unit)/U"
                } else {
                    configCell.detailTextLabel?.text = TapToSetString
                }
            case .InsulinSensitivity:
                configCell.textLabel?.text = NSLocalizedString("Insulin Sensitivities", comment: "The title text for the insulin sensitivity schedule")

                if let insulinSensitivitySchedule = dataManager.insulinSensitivitySchedule {
                    let unit = insulinSensitivitySchedule.unit
                    let value = insulinSensitivitySchedule.averageQuantity().doubleValueForUnit(unit)

                    valueNumberFormatter.minimumFractionDigits = unit == HKUnit.milligramsPerDeciliterUnit() ? 0 : 1

                    configCell.detailTextLabel?.text = "\(valueNumberFormatter.stringFromNumber(value)!) \(unit)/U"
                } else {
                    configCell.detailTextLabel?.text = TapToSetString
                }
            case .GlucoseTargetRange:
                configCell.textLabel?.text = NSLocalizedString("Target Range", comment: "The title text for the glucose target range schedule")

                if let glucoseTargetRangeSchedule = dataManager.glucoseTargetRangeSchedule {
                    let unit = glucoseTargetRangeSchedule.unit
                    let value = glucoseTargetRangeSchedule.valueAt(NSDate())

                    valueNumberFormatter.minimumFractionDigits = unit == HKUnit.milligramsPerDeciliterUnit() ? 0 : 1

                    configCell.detailTextLabel?.text = "\(valueNumberFormatter.stringFromNumber(value.minValue)!) – \(valueNumberFormatter.stringFromNumber(value.maxValue)!) \(unit)"
                } else {
                    configCell.detailTextLabel?.text = TapToSetString
                }
            case .InsulinActionDuration:
                configCell.textLabel?.text = NSLocalizedString("Insulin Action Duration", comment: "The title text for the insulin action duration value")

                if let insulinActionDuration = dataManager.insulinActionDuration {

                    configCell.detailTextLabel?.text = "\(insulinActionDuration.hours) hours"
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
            let sender = tableView.cellForRowAtIndexPath(indexPath)

            switch ConfigurationRow(rawValue: indexPath.row)! {
            case .PumpID, .TransmitterID, .InsulinActionDuration:
                performSegueWithIdentifier(TextFieldTableViewController.className, sender: sender)
            case .BasalRate:
                let scheduleVC = SingleValueScheduleTableViewController()

                if let profile = dataManager.basalRateSchedule {
                    scheduleVC.timeZone = profile.timeZone
                    scheduleVC.scheduleItems = profile.items
                }
                scheduleVC.delegate = self
                scheduleVC.title = NSLocalizedString("Basal Rates", comment: "The title of the basal rate profile screen")

                showViewController(scheduleVC, sender: sender)
            case .CarbRatio:
                let scheduleVC = DailyQuantityScheduleTableViewController()

                scheduleVC.delegate = self
                scheduleVC.title = NSLocalizedString("Carb Ratios", comment: "The title of the carb ratios schedule screen")

                if let schedule = dataManager.carbRatioSchedule {
                    scheduleVC.timeZone = schedule.timeZone
                    scheduleVC.scheduleItems = schedule.items
                    scheduleVC.unit = schedule.unit

                    showViewController(scheduleVC, sender: sender)
                } else if let carbStore = dataManager.carbStore {
                    carbStore.preferredUnit({ (unit, error) -> Void in
                        dispatch_async(dispatch_get_main_queue()) {
                            if let error = error {
                                self.presentAlertControllerWithError(error)
                            } else if let unit = unit {
                                scheduleVC.unit = unit
                                self.showViewController(scheduleVC, sender: sender)
                            }
                        }
                    })
                } else {
                    showViewController(scheduleVC, sender: sender)
                }
            case .InsulinSensitivity:
                let scheduleVC = DailyQuantityScheduleTableViewController()

                scheduleVC.delegate = self
                scheduleVC.title = NSLocalizedString("Insulin Sensitivities", comment: "The title of the insulin sensitivities schedule screen")

                if let schedule = dataManager.insulinSensitivitySchedule {
                    scheduleVC.timeZone = schedule.timeZone
                    scheduleVC.scheduleItems = schedule.items
                    scheduleVC.unit = schedule.unit

                    showViewController(scheduleVC, sender: sender)
                } else if let glucoseStore = dataManager.glucoseStore {
                    glucoseStore.preferredUnit({ (unit, error) -> Void in
                        dispatch_async(dispatch_get_main_queue()) {
                            if let error = error {
                                self.presentAlertControllerWithError(error)
                            } else if let unit = unit {
                                scheduleVC.unit = unit
                                self.showViewController(scheduleVC, sender: sender)
                            }
                        }
                    })
                } else {
                    showViewController(scheduleVC, sender: sender)
                }
            case .GlucoseTargetRange:
                let scheduleVC = GlucoseRangeScheduleTableViewController()

                scheduleVC.delegate = self
                scheduleVC.title = NSLocalizedString("Target Range", comment: "The title of the glucose target range schedule screen")

                if let schedule = dataManager.glucoseTargetRangeSchedule {
                    scheduleVC.timeZone = schedule.timeZone
                    scheduleVC.scheduleItems = schedule.items
                    scheduleVC.unit = schedule.unit

                    showViewController(scheduleVC, sender: sender)
                } else if let glucoseStore = dataManager.glucoseStore {
                    glucoseStore.preferredUnit({ (unit, error) -> Void in
                        dispatch_async(dispatch_get_main_queue()) {
                            if let error = error {
                                self.presentAlertControllerWithError(error)
                            } else if let unit = unit {
                                scheduleVC.unit = unit
                                self.showViewController(scheduleVC, sender: sender)
                            }
                        }
                    })
                } else {
                    showViewController(scheduleVC, sender: sender)
                }
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
                case .InsulinActionDuration:
                    vc.placeholder = NSLocalizedString("Enter a number of hours", comment: "The placeholder text instructing users how to enter an insulin action duration")
                    vc.keyboardType = .DecimalPad

                    if let insulinActionDuration = dataManager.insulinActionDuration {
                        valueNumberFormatter.minimumFractionDigits = 0
                        vc.value = valueNumberFormatter.stringFromNumber(insulinActionDuration.hours)
                    }
                default:
                    assertionFailure()
                }

                vc.title = cell.textLabel?.text
                vc.indexPath = indexPath
                vc.delegate = self
            case let vc as RileyLinkDeviceTableViewController:
                vc.device = dataManager.rileyLinkManager?.devices[indexPath.row]
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
            case .InsulinActionDuration:
                if let value = controller.value, duration = valueNumberFormatter.numberFromString(value)?.doubleValue {
                    dataManager.insulinActionDuration = NSTimeInterval(hours: duration)
                } else {
                    dataManager.insulinActionDuration = nil
                }
            default:
                assertionFailure()
            }
        }

        tableView.reloadData()
    }

    // MARK: - DailyValueScheduleTableViewControllerDelegate

    func dailyValueScheduleTableViewControllerWillFinishUpdating(controller: DailyValueScheduleTableViewController) {
        if let indexPath = tableView.indexPathForSelectedRow {
            switch Section(rawValue: indexPath.section)! {
            case .Configuration:
                switch ConfigurationRow(rawValue: indexPath.row)! {
                case .BasalRate:
                    if let controller = controller as? SingleValueScheduleTableViewController {
                        dataManager.basalRateSchedule = BasalRateSchedule(dailyItems: controller.scheduleItems, timeZone: controller.timeZone)
                    }
                case .GlucoseTargetRange:
                    if let controller = controller as? GlucoseRangeScheduleTableViewController {
                        dataManager.glucoseTargetRangeSchedule = GlucoseRangeSchedule(unit: controller.unit, dailyItems: controller.scheduleItems, timeZone: controller.timeZone)
                    }
                case let section:
                    if let controller = controller as? DailyQuantityScheduleTableViewController {
                        switch section {
                        case .CarbRatio:
                            dataManager.carbRatioSchedule = CarbRatioSchedule(unit: controller.unit, dailyItems: controller.scheduleItems, timeZone: controller.timeZone)
                        case .InsulinSensitivity:
                            dataManager.insulinSensitivitySchedule = InsulinSensitivitySchedule(unit: controller.unit, dailyItems: controller.scheduleItems, timeZone: controller.timeZone)
                        default:
                            break
                        }
                    }
                }

                tableView.reloadRowsAtIndexPaths([indexPath], withRowAnimation: .None)
            default:
                break
            }
        }
    }
}
