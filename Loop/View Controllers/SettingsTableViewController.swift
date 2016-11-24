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
import MinimedKit

private let ConfigCellIdentifier = "ConfigTableViewCell"

private let TapToSetString = NSLocalizedString("Tap to set", comment: "The empty-state text for a configuration value")


final class SettingsTableViewController: UITableViewController, DailyValueScheduleTableViewControllerDelegate {

    @IBOutlet var devicesSectionTitleView: UIView!

    override func viewDidLoad() {
        super.viewDidLoad()

        tableView.register(RileyLinkDeviceTableViewCell.nib(), forCellReuseIdentifier: RileyLinkDeviceTableViewCell.className)

        dataManagerObserver = NotificationCenter.default.addObserver(forName: nil, object: dataManager, queue: nil) { [weak self = self] (note) -> Void in
            if let deviceManager = self?.dataManager.rileyLinkManager {
                switch note.name {
                case Notification.Name.DeviceManagerDidDiscoverDevice:
                    self?.tableView.insertRows(at: [IndexPath(row: deviceManager.devices.count - 1, section: Section.devices.rawValue)], with: .automatic)
                case Notification.Name.DeviceConnectionStateDidChange:
                  if let device = note.userInfo?[RileyLinkDeviceManager.RileyLinkDeviceKey] as? RileyLinkDevice, let index = deviceManager.devices.index(where: { $0 === device }) {
                        self?.tableView.reloadRows(at: [IndexPath(row: index, section: Section.devices.rawValue)], with: .none)
                    }
                default:
                    break
                }
            }
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        dataManager.rileyLinkManager.deviceScanningEnabled = true

        if dataManager.transmitterID != nil || dataManager.receiverEnabled, let glucoseStore = dataManager.glucoseStore, glucoseStore.authorizationRequired {
            glucoseStore.authorize({ (success, error) -> Void in
                // Do nothing for now
            })
        }

        AnalyticsManager.sharedManager.didDisplaySettingsScreen()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)

        dataManager.rileyLinkManager.deviceScanningEnabled = false
    }

    deinit {
        dataManagerObserver = nil
    }

    var dataManager: DeviceDataManager!

    private var dataManagerObserver: Any? {
        willSet {
            if let observer = dataManagerObserver {
                NotificationCenter.default.removeObserver(observer)
            }
        }
    }

    fileprivate enum Section: Int {
        case loop = 0
        case devices
        case configuration
        case services

        static let count = 4
    }

    fileprivate enum LoopRow: Int {
        case dosing = 0
        case preferredInsulinDataSource
        case diagnostic

        static let count = 3
    }

    fileprivate enum ConfigurationRow: Int {
        case pumpID = 0
        case transmitterID
        case receiverEnabled
        case glucoseTargetRange
        case insulinActionDuration
        case basalRate
        case carbRatio
        case insulinSensitivity
        case maxBasal
        case maxBolus
        case batteryChemistry

        static let count = 11
    }

    fileprivate enum ServiceRow: Int {
        case share = 0
        case nightscout
        case mLab
        case amplitude

        static let count = 4
    }

    fileprivate lazy var valueNumberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()

        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2

        return formatter
    }()

    // MARK: - UITableViewDataSource

    override func numberOfSections(in tableView: UITableView) -> Int {
        return Section.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .loop:
            return LoopRow.count
        case .configuration:
            return ConfigurationRow.count
        case .devices:
            return dataManager.rileyLinkManager.devices.count
        case .services:
            return ServiceRow.count
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell: UITableViewCell

        switch Section(rawValue: indexPath.section)! {
        case .loop:
            switch LoopRow(rawValue: indexPath.row)! {
            case .dosing:
                let switchCell = tableView.dequeueReusableCell(withIdentifier: SwitchTableViewCell.className, for: indexPath) as! SwitchTableViewCell

                switchCell.`switch`?.isOn = dataManager.loopManager.dosingEnabled
                switchCell.titleLabel.text = NSLocalizedString("Closed Loop", comment: "The title text for the looping enabled switch cell")

                switchCell.`switch`?.addTarget(self, action: #selector(dosingEnabledChanged(_:)), for: .valueChanged)

                return switchCell
            case .preferredInsulinDataSource:
                let cell = tableView.dequeueReusableCell(withIdentifier: ConfigCellIdentifier, for: indexPath)

                cell.textLabel?.text = NSLocalizedString("Preferred Data Source", comment: "The title text for the preferred insulin data source config")
                cell.detailTextLabel?.text = String(describing: dataManager.preferredInsulinDataSource)

                return cell
            case .diagnostic:
                let cell = tableView.dequeueReusableCell(withIdentifier: ConfigCellIdentifier, for: indexPath)

                cell.textLabel?.text = NSLocalizedString("Issue Report", comment: "The title text for the issue report cell")
                cell.detailTextLabel?.text = nil

                return cell
            }
        case .configuration:
            if case .receiverEnabled = ConfigurationRow(rawValue: indexPath.row)! {
                let switchCell = tableView.dequeueReusableCell(withIdentifier: SwitchTableViewCell.className, for: indexPath) as! SwitchTableViewCell

                switchCell.`switch`?.isOn = dataManager.receiverEnabled
                switchCell.titleLabel.text = NSLocalizedString("G4 Share Receiver", comment: "The title text for the G4 Share Receiver enabled switch cell")

                switchCell.`switch`?.addTarget(self, action: #selector(receiverEnabledChanged(_:)), for: .valueChanged)

                return switchCell
            }

            let configCell = tableView.dequeueReusableCell(withIdentifier: ConfigCellIdentifier, for: indexPath)

            switch ConfigurationRow(rawValue: indexPath.row)! {
            case .pumpID:
                configCell.textLabel?.text = NSLocalizedString("Pump ID", comment: "The title text for the pump ID config value")
                configCell.detailTextLabel?.text = dataManager.pumpID ?? TapToSetString
            case .transmitterID:
                configCell.textLabel?.text = NSLocalizedString("G5 Transmitter ID", comment: "The title text for the Dexcom G5 transmitter ID config value")
                configCell.detailTextLabel?.text = dataManager.transmitterID ?? TapToSetString
            case .receiverEnabled:
                break
            case .basalRate:
                configCell.textLabel?.text = NSLocalizedString("Basal Rates", comment: "The title text for the basal rate schedule")

                if let basalRateSchedule = dataManager.basalRateSchedule {
                    configCell.detailTextLabel?.text = "\(basalRateSchedule.total()) U"
                } else {
                    configCell.detailTextLabel?.text = TapToSetString
                }
            case .carbRatio:
                configCell.textLabel?.text = NSLocalizedString("Carb Ratios", comment: "The title text for the carb ratio schedule")

                if let carbRatioSchedule = dataManager.carbRatioSchedule {
                    let unit = carbRatioSchedule.unit
                    let value = valueNumberFormatter.string(from: NSNumber(value: carbRatioSchedule.averageQuantity().doubleValue(for: unit))) ?? "—"

                    configCell.detailTextLabel?.text = String(format: NSLocalizedString("%1$@ %2$@/U", comment: "Format string for carb ratio average. (1: value)(2: carb unit)"), value, unit)
                } else {
                    configCell.detailTextLabel?.text = TapToSetString
                }
            case .insulinSensitivity:
                configCell.textLabel?.text = NSLocalizedString("Insulin Sensitivities", comment: "The title text for the insulin sensitivity schedule")

                if let insulinSensitivitySchedule = dataManager.insulinSensitivitySchedule {
                    let unit = insulinSensitivitySchedule.unit
                    let value = valueNumberFormatter.string(from: NSNumber(value: insulinSensitivitySchedule.averageQuantity().doubleValue(for: unit))) ?? "—"

                    configCell.detailTextLabel?.text = String(format: NSLocalizedString("%1$@ %2$@/U", comment: "Format string for insulin sensitivity average (1: value)(2: glucose unit)"), value, unit.glucoseUnitDisplayString)
                } else {
                    configCell.detailTextLabel?.text = TapToSetString
                }
            case .glucoseTargetRange:
                configCell.textLabel?.text = NSLocalizedString("Target Range", comment: "The title text for the glucose target range schedule")

                if let glucoseTargetRangeSchedule = dataManager.glucoseTargetRangeSchedule {
                    let unit = glucoseTargetRangeSchedule.unit
                    let value = glucoseTargetRangeSchedule.value(at: Date())
                    let minTarget = valueNumberFormatter.string(from: NSNumber(value: value.minValue)) ?? "—"
                    let maxTarget = valueNumberFormatter.string(from: NSNumber(value: value.maxValue)) ?? "—"

                    configCell.detailTextLabel?.text = String(format: NSLocalizedString("%1$@ – %2$@ %3$@", comment: "Format string for glucose target range. (1: Min target)(2: Max target)(3: glucose unit)"), minTarget, maxTarget, unit.glucoseUnitDisplayString)
                } else {
                    configCell.detailTextLabel?.text = TapToSetString
                }
            case .insulinActionDuration:
                configCell.textLabel?.text = NSLocalizedString("Insulin Action Duration", comment: "The title text for the insulin action duration value")

                if let insulinActionDuration = dataManager.insulinActionDuration {
                    let formatter = DateComponentsFormatter()
                    formatter.unitsStyle = .abbreviated
                    // Seems to have no effect.
                    // http://stackoverflow.com/questions/32522965/what-am-i-doing-wrong-with-allowsfractionalunits-on-nsdatecomponentsformatter
                    formatter.allowsFractionalUnits = true
                    // formatter.allowedUnits = [.hour]

                    configCell.detailTextLabel?.text = formatter.string(from: insulinActionDuration)
                } else {
                    configCell.detailTextLabel?.text = TapToSetString
                }
            case .maxBasal:
            configCell.textLabel?.text = NSLocalizedString("Maximum Basal Rate", comment: "The title text for the maximum basal rate value")

                if let maxBasal = dataManager.maximumBasalRatePerHour {
                    configCell.detailTextLabel?.text = "\(valueNumberFormatter.string(from: NSNumber(value: maxBasal))!) U/hour"
                } else {
                    configCell.detailTextLabel?.text = TapToSetString
                }
            case .maxBolus:
                configCell.textLabel?.text = NSLocalizedString("Maximum Bolus", comment: "The title text for the maximum bolus value")

                if let maxBolus = dataManager.maximumBolus {
                    configCell.detailTextLabel?.text = "\(valueNumberFormatter.string(from: NSNumber(value: maxBolus))!) U"
                } else {
                    configCell.detailTextLabel?.text = TapToSetString
                }
            case .batteryChemistry:
                configCell.textLabel?.text = NSLocalizedString("Pump Battery Type", comment: "The title text for the battery type value")
                configCell.detailTextLabel?.text = String(describing: dataManager.batteryChemistry)
//                if let sentrySupported = dataManager.pumpState?.pumpModel?.hasMySentry, sentrySupported {
//                    configCell.textLabel?.isEnabled = false
//                    configCell.detailTextLabel?.isEnabled = false
//                    configCell.isUserInteractionEnabled = false
//                }
            }

            cell = configCell
        case .devices:
            let deviceCell = tableView.dequeueReusableCell(withIdentifier: RileyLinkDeviceTableViewCell.className) as! RileyLinkDeviceTableViewCell
            let device = dataManager.rileyLinkManager.devices[indexPath.row]

            deviceCell.configureCellWithName(device.name,
                signal: device.RSSI,
                peripheralState: device.peripheral.state
            )

            deviceCell.connectSwitch.addTarget(self, action: #selector(deviceConnectionChanged(_:)), for: .valueChanged)

            cell = deviceCell
        case .services:
            let configCell = tableView.dequeueReusableCell(withIdentifier: ConfigCellIdentifier, for: indexPath)

            switch ServiceRow(rawValue: indexPath.row)! {
            case .share:
                let shareService = dataManager.remoteDataManager.shareService

                configCell.textLabel?.text = shareService.title
                configCell.detailTextLabel?.text = shareService.username ?? TapToSetString
            case .nightscout:
                let nightscoutService = dataManager.remoteDataManager.nightscoutService

                configCell.textLabel?.text = nightscoutService.title
                configCell.detailTextLabel?.text = nightscoutService.siteURL?.absoluteString ?? TapToSetString
            case .mLab:
                let mLabService = dataManager.logger.mLabService

                configCell.textLabel?.text = mLabService.title
                configCell.detailTextLabel?.text = mLabService.databaseName ?? TapToSetString
            case .amplitude:
                let amplitudeService = AnalyticsManager.sharedManager.amplitudeService

                configCell.textLabel?.text = amplitudeService.title
                configCell.detailTextLabel?.text = amplitudeService.isAuthorized ? NSLocalizedString("Enabled", comment: "The detail text describing an enabled setting") : TapToSetString
            }

            return configCell
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .loop:
            let bundle = Bundle.main
            return bundle.localizedNameAndVersion
        case .configuration:
            return NSLocalizedString("Configuration", comment: "The title of the configuration section in settings")
        case .devices:
            return nil
        case .services:
            return NSLocalizedString("Services", comment: "The title of the services section in settings")
        }
    }

    // MARK: - UITableViewDelegate

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let sender = tableView.cellForRow(at: indexPath)

        switch Section(rawValue: indexPath.section)! {
        case .configuration:
            let row = ConfigurationRow(rawValue: indexPath.row)!
            switch row {
            case .pumpID, .transmitterID, .insulinActionDuration, .maxBasal, .maxBolus:
                let vc: TextFieldTableViewController

                switch row {
                case .pumpID:
                    vc = PumpIDTableViewController(pumpID: dataManager.pumpID, region: dataManager.pumpState?.pumpRegion)
                case .transmitterID:
                    vc = .transmitterID(dataManager.transmitterID)
                case .insulinActionDuration:
                    vc = .insulinActionDuration(dataManager.insulinActionDuration)
                case .maxBasal:
                    vc = .maxBasal(dataManager.maximumBasalRatePerHour)
                case .maxBolus:
                    vc = .maxBolus(dataManager.maximumBolus)
                default:
                    fatalError()
                }

                vc.title = sender?.textLabel?.text
                vc.indexPath = indexPath
                vc.delegate = self

                show(vc, sender: indexPath)
            case .basalRate:
                let scheduleVC = SingleValueScheduleTableViewController()

                if let profile = dataManager.basalRateSchedule {
                    scheduleVC.timeZone = profile.timeZone
                    scheduleVC.scheduleItems = profile.items
                }
                scheduleVC.delegate = self
                scheduleVC.title = NSLocalizedString("Basal Rates", comment: "The title of the basal rate profile screen")

                show(scheduleVC, sender: sender)
            case .carbRatio:
                let scheduleVC = DailyQuantityScheduleTableViewController()

                scheduleVC.delegate = self
                scheduleVC.title = NSLocalizedString("Carb Ratios", comment: "The title of the carb ratios schedule screen")

                if let schedule = dataManager.carbRatioSchedule {
                    scheduleVC.timeZone = schedule.timeZone
                    scheduleVC.scheduleItems = schedule.items
                    scheduleVC.unit = schedule.unit

                    show(scheduleVC, sender: sender)
                } else if let carbStore = dataManager.carbStore {
                    carbStore.preferredUnit({ (unit, error) -> Void in
                        DispatchQueue.main.async {
                            if let error = error {
                                self.presentAlertController(with: error)
                            } else if let unit = unit {
                                scheduleVC.unit = unit
                                self.show(scheduleVC, sender: sender)
                            }
                        }
                    })
                } else {
                    show(scheduleVC, sender: sender)
                }
            case .insulinSensitivity:
                let scheduleVC = DailyQuantityScheduleTableViewController()

                scheduleVC.delegate = self
                scheduleVC.title = NSLocalizedString("Insulin Sensitivities", comment: "The title of the insulin sensitivities schedule screen")

                if let schedule = dataManager.insulinSensitivitySchedule {
                    scheduleVC.timeZone = schedule.timeZone
                    scheduleVC.scheduleItems = schedule.items
                    scheduleVC.unit = schedule.unit

                    show(scheduleVC, sender: sender)
                } else if let glucoseStore = dataManager.glucoseStore {
                    glucoseStore.preferredUnit({ (unit, error) -> Void in
                        DispatchQueue.main.async {
                            if let error = error {
                                self.presentAlertController(with: error)
                            } else if let unit = unit {
                                scheduleVC.unit = unit
                                self.show(scheduleVC, sender: sender)
                            }
                        }
                    })
                } else {
                    show(scheduleVC, sender: sender)
                }
            case .glucoseTargetRange:
                let scheduleVC = GlucoseRangeScheduleTableViewController()

                scheduleVC.delegate = self
                scheduleVC.title = NSLocalizedString("Target Range", comment: "The title of the glucose target range schedule screen")

                if let schedule = dataManager.glucoseTargetRangeSchedule {
                    scheduleVC.timeZone = schedule.timeZone
                    scheduleVC.scheduleItems = schedule.items
                    scheduleVC.unit = schedule.unit
                    scheduleVC.workoutRange = schedule.workoutRange

                    show(scheduleVC, sender: sender)
                } else if let glucoseStore = dataManager.glucoseStore {
                    glucoseStore.preferredUnit({ (unit, error) -> Void in
                        DispatchQueue.main.async {
                            if let error = error {
                                self.presentAlertController(with: error)
                            } else if let unit = unit {
                                scheduleVC.unit = unit
                                self.show(scheduleVC, sender: sender)
                            }
                        }
                    })
                } else {
                    show(scheduleVC, sender: sender)
                }
            case .receiverEnabled:
                break
            case .batteryChemistry:
                let vc = RadioSelectionTableViewController.batteryChemistryType(dataManager.batteryChemistry)
                vc.title = sender?.textLabel?.text
                vc.delegate = self
                
                show(vc, sender: sender)
            }
        case .devices:
            let vc = RileyLinkDeviceTableViewController()
            vc.device = dataManager.rileyLinkManager.devices[indexPath.row]

            show(vc, sender: sender)
        case .loop:
            switch LoopRow(rawValue: indexPath.row)! {
            case .preferredInsulinDataSource:
                let vc = RadioSelectionTableViewController.insulinDataSource(dataManager.preferredInsulinDataSource)
                vc.title = sender?.textLabel?.text
                vc.delegate = self

                show(vc, sender: sender)
            case .diagnostic:
                let vc = CommandResponseViewController.generateDiagnosticReport(dataManager: dataManager)
                vc.title = sender?.textLabel?.text

                show(vc, sender: sender)
            case .dosing:
                break
            }
        case .services:
            switch ServiceRow(rawValue: indexPath.row)! {
            case .share:
                let service = dataManager.remoteDataManager.shareService
                let vc = AuthenticationViewController(authentication: service)
                vc.authenticationObserver = { [unowned self] (service) in
                    self.dataManager.remoteDataManager.shareService = service

                    self.tableView.reloadRows(at: [indexPath], with: .none)
                }

                show(vc, sender: sender)
            case .nightscout:
                let service = dataManager.remoteDataManager.nightscoutService
                let vc = AuthenticationViewController(authentication: service)
                vc.authenticationObserver = { [unowned self] (service) in
                    self.dataManager.remoteDataManager.nightscoutService = service

                    self.tableView.reloadRows(at: [indexPath], with: .none)
                }

                show(vc, sender: sender)
            case .mLab:
                let service = dataManager.logger.mLabService
                let vc = AuthenticationViewController(authentication: service)
                vc.authenticationObserver = { [unowned self] (service) in
                    self.dataManager.logger.mLabService = service

                    self.tableView.reloadRows(at: [indexPath], with: .none)
                }

                show(vc, sender: sender)
            case .amplitude:
                let service = AnalyticsManager.sharedManager.amplitudeService
                let vc = AuthenticationViewController(authentication: service)
                vc.authenticationObserver = { [unowned self] (service) in
                    AnalyticsManager.sharedManager.amplitudeService = service

                    self.tableView.reloadRows(at: [indexPath], with: .none)
                }

                show(vc, sender: sender)
            }
        }
    }

    override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        switch Section(rawValue: section)! {
        case .devices:
            return devicesSectionTitleView
        case .loop, .configuration, .services:
            return nil
        }
    }

    // MARK: - Device mangement

    func dosingEnabledChanged(_ sender: UISwitch) {
        dataManager.loopManager.dosingEnabled = sender.isOn
    }

    func deviceConnectionChanged(_ connectSwitch: UISwitch) {
        let switchOrigin = connectSwitch.convert(CGPoint.zero, to: tableView)

        if let indexPath = tableView.indexPathForRow(at: switchOrigin), indexPath.section == Section.devices.rawValue
        {
            let device = dataManager.rileyLinkManager.devices[indexPath.row]

            if connectSwitch.isOn {
                dataManager.connectToRileyLink(device)
            } else {
                dataManager.disconnectFromRileyLink(device)
            }
        }
    }

    func receiverEnabledChanged(_ sender: UISwitch) {
        dataManager.receiverEnabled = sender.isOn
    }

    // MARK: - DailyValueScheduleTableViewControllerDelegate

    func dailyValueScheduleTableViewControllerWillFinishUpdating(_ controller: DailyValueScheduleTableViewController) {
        if let indexPath = tableView.indexPathForSelectedRow {
            switch Section(rawValue: indexPath.section)! {
            case .configuration:
                switch ConfigurationRow(rawValue: indexPath.row)! {
                case .basalRate:
                    if let controller = controller as? SingleValueScheduleTableViewController {
                        dataManager.basalRateSchedule = BasalRateSchedule(dailyItems: controller.scheduleItems, timeZone: controller.timeZone)
                    }
                case .glucoseTargetRange:
                    if let controller = controller as? GlucoseRangeScheduleTableViewController {
                        dataManager.glucoseTargetRangeSchedule = GlucoseRangeSchedule(unit: controller.unit, dailyItems: controller.scheduleItems, workoutRange: controller.workoutRange, timeZone: controller.timeZone)
                    }
                case let row:
                    if let controller = controller as? DailyQuantityScheduleTableViewController {
                        switch row {
                        case .carbRatio:
                            dataManager.carbRatioSchedule = CarbRatioSchedule(unit: controller.unit, dailyItems: controller.scheduleItems, timeZone: controller.timeZone)
                        case .insulinSensitivity:
                            dataManager.insulinSensitivitySchedule = InsulinSensitivitySchedule(unit: controller.unit, dailyItems: controller.scheduleItems, timeZone: controller.timeZone)
                        default:
                            break
                        }
                    }
                }

                tableView.reloadRows(at: [indexPath], with: .none)
            default:
                break
            }
        }
    }
}


extension SettingsTableViewController: RadioSelectionTableViewControllerDelegate {
    func radioSelectionTableViewControllerDidChangeSelectedIndex(_ controller: RadioSelectionTableViewController) {
        if let indexPath = self.tableView.indexPathForSelectedRow {
            switch Section(rawValue: indexPath.section)! {
            case .loop:
                switch LoopRow(rawValue: indexPath.row)! {
                case .preferredInsulinDataSource:
                    if let selectedIndex = controller.selectedIndex, let dataSource = InsulinDataSource(rawValue: selectedIndex) {
                        dataManager.preferredInsulinDataSource = dataSource

                        tableView.reloadRows(at: [IndexPath(row: LoopRow.preferredInsulinDataSource.rawValue, section: Section.loop.rawValue)], with: .none)
                    }
                default:
                    assertionFailure()
                }

            case .configuration:
                switch ConfigurationRow(rawValue: indexPath.row)! {
                case .batteryChemistry:
                    if let selectedIndex = controller.selectedIndex, let dataSource = BatteryChemistryType(rawValue: selectedIndex) {
                        dataManager.batteryChemistry = dataSource

                        tableView.reloadRows(at: [IndexPath(row: ConfigurationRow.batteryChemistry.rawValue, section: Section.configuration.rawValue)], with: .none)
                    }
                default:
                    assertionFailure()
                }
            default:
                assertionFailure()
            }
        }
    }
}

extension SettingsTableViewController: TextFieldTableViewControllerDelegate {
    func textFieldTableViewControllerDidEndEditing(_ controller: TextFieldTableViewController) {
        if let indexPath = controller.indexPath {
            switch ConfigurationRow(rawValue: indexPath.row)! {
            case .pumpID:
                dataManager.pumpID = controller.value

                if  let controller = controller as? PumpIDTableViewController,
                    let region = controller.region
                {
                    dataManager.pumpState?.pumpRegion = region
                }
            case .transmitterID:
                dataManager.transmitterID = controller.value
            case .insulinActionDuration:
                if let value = controller.value, let duration = valueNumberFormatter.number(from: value)?.doubleValue {
                    dataManager.insulinActionDuration = TimeInterval(hours: duration)
                } else {
                    dataManager.insulinActionDuration = nil
                }
            case .maxBasal:
                if let value = controller.value, let rate = valueNumberFormatter.number(from: value)?.doubleValue {
                    dataManager.maximumBasalRatePerHour = rate
                } else {
                    dataManager.maximumBasalRatePerHour = nil
                }
            case .maxBolus:
                if let value = controller.value, let units = valueNumberFormatter.number(from: value)?.doubleValue {
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

    func textFieldTableViewControllerDidReturn(_ controller: TextFieldTableViewController) {
        _ = navigationController?.popViewController(animated: true)
    }
}


extension SettingsTableViewController: PumpIDTableViewControllerDelegate {
    func pumpIDTableViewControllerDidChangePumpRegion(_ controller: PumpIDTableViewController) {
        if let region = controller.region {
            dataManager.pumpState?.pumpRegion = region
        }
    }
}
