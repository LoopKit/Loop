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


final class SettingsTableViewController: UITableViewController, DailyValueScheduleTableViewControllerDelegate, TextFieldTableViewControllerDelegate {

    @IBOutlet var devicesSectionTitleView: UIView!

    override func viewDidLoad() {
        super.viewDidLoad()

        tableView.registerNib(RileyLinkDeviceTableViewCell.nib(), forCellReuseIdentifier: RileyLinkDeviceTableViewCell.className)

        dataManagerObserver = NSNotificationCenter.defaultCenter().addObserverForName(nil, object: dataManager, queue: nil) { [weak self = self] (note) -> Void in
            if let deviceManager = self?.dataManager.rileyLinkManager {
                switch note.name {
                case RileyLinkDeviceManager.DidDiscoverDeviceNotification:
                    self?.tableView.insertRowsAtIndexPaths([NSIndexPath(forRow: deviceManager.devices.count - 1, inSection: Section.Devices.rawValue)], withRowAnimation: .Automatic)
                case RileyLinkDeviceManager.ConnectionStateDidChangeNotification:
                  if let device = note.userInfo?[RileyLinkDeviceManager.RileyLinkDeviceKey] as? RileyLinkDevice, index = deviceManager.devices.indexOf({ $0 === device }) {
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

        dataManager.rileyLinkManager.deviceScanningEnabled = true

        if dataManager.transmitterID != nil || dataManager.receiverEnabled, let glucoseStore = dataManager.glucoseStore where glucoseStore.authorizationRequired {
            glucoseStore.authorize({ (success, error) -> Void in
                // Do nothing for now
            })
        }

        AnalyticsManager.sharedManager.didDisplaySettingsScreen()
    }

    override func viewDidDisappear(animated: Bool) {
        super.viewDidDisappear(animated)

        dataManager.rileyLinkManager.deviceScanningEnabled = false
    }

    deinit {
        dataManagerObserver = nil
    }

    private var dataManager: DeviceDataManager {
        return DeviceDataManager.sharedManager
    }

    private var dataManagerObserver: AnyObject? {
        willSet {
            if let observer = dataManagerObserver {
                NSNotificationCenter.defaultCenter().removeObserver(observer)
            }
        }
    }

    private enum Section: Int {
        case Loop = 0
        case Devices
        case Configuration
        case Services

        static let count = 4
    }

    private enum LoopRow: Int {
        case Dosing = 0
        case PreferredInsulinDataSource

        static let count = 2
    }

    private enum ConfigurationRow: Int {
        case PumpID = 0
        case TransmitterID
        case ReceiverEnabled
        case GlucoseTargetRange
        case InsulinActionDuration
        case BasalRate
        case CarbRatio
        case InsulinSensitivity
        case MaxBasal
        case MaxBolus

        static let count = 10
    }

    private enum ServiceRow: Int {
        case Share = 0
        case Nightscout
        case MLab
        case Amplitude

        static let count = 4
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
        return Section.count
    }

    override func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .Loop:
            return LoopRow.count
        case .Configuration:
            return ConfigurationRow.count
        case .Devices:
            return dataManager.rileyLinkManager.devices.count
        case .Services:
            return ServiceRow.count
        }
    }

    override func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        let cell: UITableViewCell

        switch Section(rawValue: indexPath.section)! {
        case .Loop:
            switch LoopRow(rawValue: indexPath.row)! {
            case .Dosing:
                let switchCell = tableView.dequeueReusableCellWithIdentifier(SwitchTableViewCell.className, forIndexPath: indexPath) as! SwitchTableViewCell

                switchCell.`switch`?.on = dataManager.loopManager.dosingEnabled
                switchCell.titleLabel.text = NSLocalizedString("Closed Loop", comment: "The title text for the looping enabled switch cell")

                switchCell.`switch`?.addTarget(self, action: #selector(dosingEnabledChanged(_:)), forControlEvents: .ValueChanged)

                return switchCell
            case .PreferredInsulinDataSource:
                let cell = tableView.dequeueReusableCellWithIdentifier(ConfigCellIdentifier, forIndexPath: indexPath)

                cell.textLabel?.text = NSLocalizedString("Preferred Data Source", comment: "The title text for the preferred insulin data source config")
                cell.detailTextLabel?.text = String(dataManager.preferredInsulinDataSource)

                return cell
            }
        case .Configuration:
            if case .ReceiverEnabled = ConfigurationRow(rawValue: indexPath.row)! {
                let switchCell = tableView.dequeueReusableCellWithIdentifier(SwitchTableViewCell.className, forIndexPath: indexPath) as! SwitchTableViewCell

                switchCell.`switch`?.on = dataManager.receiverEnabled
                switchCell.titleLabel.text = NSLocalizedString("G4 Share Receiver", comment: "The title text for the G4 Share Receiver enabled switch cell")

                switchCell.`switch`?.addTarget(self, action: #selector(receiverEnabledChanged(_:)), forControlEvents: .ValueChanged)

                return switchCell
            }

            let configCell = tableView.dequeueReusableCellWithIdentifier(ConfigCellIdentifier, forIndexPath: indexPath)

            switch ConfigurationRow(rawValue: indexPath.row)! {
            case .PumpID:
                configCell.textLabel?.text = NSLocalizedString("Pump ID", comment: "The title text for the pump ID config value")
                configCell.detailTextLabel?.text = dataManager.pumpID ?? TapToSetString
            case .TransmitterID:
                configCell.textLabel?.text = NSLocalizedString("G5 Transmitter ID", comment: "The title text for the Dexcom G5 transmitter ID config value")
                configCell.detailTextLabel?.text = dataManager.transmitterID ?? TapToSetString
            case .ReceiverEnabled:
                break
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

                    configCell.detailTextLabel?.text = "\(valueNumberFormatter.stringFromNumber(value)!) \(unit)/U"
                } else {
                    configCell.detailTextLabel?.text = TapToSetString
                }
            case .InsulinSensitivity:
                configCell.textLabel?.text = NSLocalizedString("Insulin Sensitivities", comment: "The title text for the insulin sensitivity schedule")

                if let insulinSensitivitySchedule = dataManager.insulinSensitivitySchedule {
                    let unit = insulinSensitivitySchedule.unit
                    let value = insulinSensitivitySchedule.averageQuantity().doubleValueForUnit(unit)

                    configCell.detailTextLabel?.text = "\(valueNumberFormatter.stringFromNumber(value)!) \(unit)/U"
                } else {
                    configCell.detailTextLabel?.text = TapToSetString
                }
            case .GlucoseTargetRange:
                configCell.textLabel?.text = NSLocalizedString("Target Range", comment: "The title text for the glucose target range schedule")

                if let glucoseTargetRangeSchedule = dataManager.glucoseTargetRangeSchedule {
                    let unit = glucoseTargetRangeSchedule.unit
                    let value = glucoseTargetRangeSchedule.valueAt(NSDate())

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
            case .MaxBasal:
                configCell.textLabel?.text = NSLocalizedString("Maximum Basal Rate", comment: "The title text for the maximum basal rate value")

                if let maxBasal = dataManager.maximumBasalRatePerHour {
                    configCell.detailTextLabel?.text = "\(valueNumberFormatter.stringFromNumber(maxBasal)!) U/hour"
                } else {
                    configCell.detailTextLabel?.text = TapToSetString
                }
            case .MaxBolus:
                configCell.textLabel?.text = NSLocalizedString("Maximum Bolus", comment: "The title text for the maximum bolus value")

                if let maxBolus = dataManager.maximumBolus {
                    configCell.detailTextLabel?.text = "\(valueNumberFormatter.stringFromNumber(maxBolus)!) U"
                } else {
                    configCell.detailTextLabel?.text = TapToSetString
                }
            }

            cell = configCell
        case .Devices:
            let deviceCell = tableView.dequeueReusableCellWithIdentifier(RileyLinkDeviceTableViewCell.className) as! RileyLinkDeviceTableViewCell
            let device = dataManager.rileyLinkManager.devices[indexPath.row]

            deviceCell.configureCellWithName(device.name,
                signal: device.RSSI,
                peripheralState: device.peripheral.state
            )

            deviceCell.connectSwitch.addTarget(self, action: #selector(deviceConnectionChanged(_:)), forControlEvents: .ValueChanged)

            cell = deviceCell
        case .Services:
            let configCell = tableView.dequeueReusableCellWithIdentifier(ConfigCellIdentifier, forIndexPath: indexPath)

            switch ServiceRow(rawValue: indexPath.row)! {
            case .Share:
                let shareService = dataManager.remoteDataManager.shareService

                configCell.textLabel?.text = shareService.title
                configCell.detailTextLabel?.text = shareService.username ?? TapToSetString
            case .Nightscout:
                let nightscoutService = dataManager.remoteDataManager.nightscoutService

                configCell.textLabel?.text = nightscoutService.title
                configCell.detailTextLabel?.text = nightscoutService.siteURL?.absoluteString ?? TapToSetString
            case .MLab:
                let mLabService = dataManager.logger.mLabService

                configCell.textLabel?.text = mLabService.title
                configCell.detailTextLabel?.text = mLabService.databaseName ?? TapToSetString
            case .Amplitude:
                let amplitudeService = AnalyticsManager.sharedManager.amplitudeService

                configCell.textLabel?.text = amplitudeService.title
                configCell.detailTextLabel?.text = amplitudeService.isAuthorized ? NSLocalizedString("Enabled", comment: "The detail text describing an enabled setting") : TapToSetString
            }

            return configCell
        }
        return cell
    }

    override func tableView(tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .Loop:
            let bundle = NSBundle.mainBundle()
            return bundle.localizedNameAndVersion
        case .Configuration:
            return NSLocalizedString("Configuration", comment: "The title of the configuration section in settings")
        case .Devices:
            return nil
        case .Services:
            return NSLocalizedString("Services", comment: "The title of the services section in settings")
        }
    }

    // MARK: - UITableViewDelegate

    override func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
        let sender = tableView.cellForRowAtIndexPath(indexPath)

        switch Section(rawValue: indexPath.section)! {
        case .Configuration:
            let row = ConfigurationRow(rawValue: indexPath.row)!
            switch row {
            case .PumpID, .TransmitterID, .InsulinActionDuration, .MaxBasal, .MaxBolus:
                let vc: TextFieldTableViewController

                switch row {
                case .PumpID:
                    vc = .pumpID(dataManager.pumpID)
                case .TransmitterID:
                    vc = .transmitterID(dataManager.transmitterID)
                case .InsulinActionDuration:
                    vc = .insulinActionDuration(dataManager.insulinActionDuration)
                case .MaxBasal:
                    vc = .maxBasal(dataManager.maximumBasalRatePerHour)
                case .MaxBolus:
                    vc = .maxBolus(dataManager.maximumBolus)
                default:
                    fatalError()
                }

                vc.title = sender?.textLabel?.text
                vc.indexPath = indexPath
                vc.delegate = self

                showViewController(vc, sender: indexPath)
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
                    scheduleVC.workoutRange = schedule.workoutRange

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
            case .ReceiverEnabled:
                break
            }
        case .Devices:
            let vc = RileyLinkDeviceTableViewController()
            vc.device = dataManager.rileyLinkManager.devices[indexPath.row]

            showViewController(vc, sender: sender)
        case .Loop:
            switch LoopRow(rawValue: indexPath.row)! {
            case .PreferredInsulinDataSource:
                let vc = RadioSelectionTableViewController.insulinDataSource(dataManager.preferredInsulinDataSource)
                vc.title = sender?.textLabel?.text
                vc.delegate = self

                showViewController(vc, sender: sender)
            default:
                break
            }
        case .Services:
            switch ServiceRow(rawValue: indexPath.row)! {
            case .Share:
                let service = dataManager.remoteDataManager.shareService
                let vc = AuthenticationViewController(authentication: service)
                vc.authenticationObserver = { [unowned self] (service) in
                    self.dataManager.remoteDataManager.shareService = service

                    self.tableView.reloadRowsAtIndexPaths([indexPath], withRowAnimation: .None)
                }

                showViewController(vc, sender: sender)
            case .Nightscout:
                let service = dataManager.remoteDataManager.nightscoutService
                let vc = AuthenticationViewController(authentication: service)
                vc.authenticationObserver = { [unowned self] (service) in
                    self.dataManager.remoteDataManager.nightscoutService = service

                    self.tableView.reloadRowsAtIndexPaths([indexPath], withRowAnimation: .None)
                }

                showViewController(vc, sender: sender)
            case .MLab:
                let service = dataManager.logger.mLabService
                let vc = AuthenticationViewController(authentication: service)
                vc.authenticationObserver = { [unowned self] (service) in
                    self.dataManager.logger.mLabService = service

                    self.tableView.reloadRowsAtIndexPaths([indexPath], withRowAnimation: .None)
                }

                showViewController(vc, sender: sender)
            case .Amplitude:
                let service = AnalyticsManager.sharedManager.amplitudeService
                let vc = AuthenticationViewController(authentication: service)
                vc.authenticationObserver = { [unowned self] (service) in
                    AnalyticsManager.sharedManager.amplitudeService = service

                    self.tableView.reloadRowsAtIndexPaths([indexPath], withRowAnimation: .None)
                }

                showViewController(vc, sender: sender)
            }
        }
    }

    override func tableView(tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        switch Section(rawValue: section)! {
        case .Devices:
            return devicesSectionTitleView
        case .Loop, .Configuration, .Services:
            return nil
        }
    }

    // MARK: - Device mangement

    func dosingEnabledChanged(sender: UISwitch) {
        dataManager.loopManager.dosingEnabled = sender.on
    }

    func deviceConnectionChanged(connectSwitch: UISwitch) {
        let switchOrigin = connectSwitch.convertPoint(.zero, toView: tableView)

        if let indexPath = tableView.indexPathForRowAtPoint(switchOrigin) where indexPath.section == Section.Devices.rawValue
        {
            let device = dataManager.rileyLinkManager.devices[indexPath.row]

            if connectSwitch.on {
                dataManager.connectToRileyLink(device)
            } else {
                dataManager.disconnectFromRileyLink(device)
            }
        }
    }

    func receiverEnabledChanged(sender: UISwitch) {
        dataManager.receiverEnabled = sender.on
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
            case .MaxBasal:
                if let value = controller.value, rate = valueNumberFormatter.numberFromString(value)?.doubleValue {
                    dataManager.maximumBasalRatePerHour = rate
                } else {
                    dataManager.maximumBasalRatePerHour = nil
                }
            case .MaxBolus:
                if let value = controller.value, units = valueNumberFormatter.numberFromString(value)?.doubleValue {
                    dataManager.maximumBolus = units
                } else {
                    dataManager.maximumBolus = nil
                }
            default:
                assertionFailure()
            }
        }

        tableView.reloadData()
    }

    func textFieldTableViewControllerDidReturn(controller: TextFieldTableViewController) {
        navigationController?.popViewControllerAnimated(true)
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
                        dataManager.glucoseTargetRangeSchedule = GlucoseRangeSchedule(unit: controller.unit, dailyItems: controller.scheduleItems, workoutRange: controller.workoutRange, timeZone: controller.timeZone)
                    }
                case let row:
                    if let controller = controller as? DailyQuantityScheduleTableViewController {
                        switch row {
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


extension SettingsTableViewController: RadioSelectionTableViewControllerDelegate {
    func radioSelectionTableViewControllerDidChangeSelectedIndex(controller: RadioSelectionTableViewController) {
        if let selectedIndex = controller.selectedIndex, dataSource = InsulinDataSource(rawValue: selectedIndex) {
            dataManager.preferredInsulinDataSource = dataSource

            tableView.reloadRowsAtIndexPaths([NSIndexPath(forRow: LoopRow.PreferredInsulinDataSource.rawValue, inSection: Section.Loop.rawValue)], withRowAnimation: .None)
        }
    }
}
