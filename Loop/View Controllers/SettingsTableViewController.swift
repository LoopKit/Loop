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
import LoopKitUI


final class SettingsTableViewController: UITableViewController {

    @IBOutlet var devicesSectionTitleView: UIView?

    override func viewDidLoad() {
        super.viewDidLoad()

        tableView.rowHeight = UITableViewAutomaticDimension
        tableView.estimatedRowHeight = 44

        tableView.register(SettingsTableViewCell.self, forCellReuseIdentifier: SettingsTableViewCell.className)
        tableView.register(SettingsImageTableViewCell.self, forCellReuseIdentifier: SettingsImageTableViewCell.className)
        tableView.register(TextButtonTableViewCell.self, forCellReuseIdentifier: TextButtonTableViewCell.className)
    }

    override func viewWillAppear(_ animated: Bool) {
        if clearsSelectionOnViewWillAppear {
            // Manually invoke the delegate for rows deselecting on appear
            for indexPath in tableView.indexPathsForSelectedRows ?? [] {
                _ = tableView(tableView, willDeselectRowAt: indexPath)
            }
        }

        super.viewWillAppear(animated)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        AnalyticsManager.shared.didDisplaySettingsScreen()
    }

    var dataManager: DeviceDataManager!

    fileprivate enum Section: Int, CaseCountable {
        case loop = 0
        case pump
        case cgm
        case configuration
        case services
    }

    fileprivate enum LoopRow: Int, CaseCountable {
        case dosing = 0
        case diagnostic
    }

    fileprivate enum PumpRow: Int, CaseCountable {
        case pumpSettings = 0
    }

    fileprivate enum CGMRow: Int, CaseCountable {
        case cgmSettings = 0
    }

    fileprivate enum ConfigurationRow: Int, CaseCountable {
        case glucoseTargetRange = 0
        case suspendThreshold
        case basalRate
        case deliveryLimits
        case insulinModel
        case carbRatio
        case insulinSensitivity
    }

    fileprivate enum ServiceRow: Int, CaseCountable {
        case nightscout = 0
        case loggly
        case amplitude
    }

    fileprivate lazy var valueNumberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()

        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2

        return formatter
    }()

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        switch segue.destination {
        case let vc as InsulinModelSettingsViewController:
            vc.deviceManager = dataManager
            vc.insulinModel = dataManager.loopManager.insulinModelSettings?.model

            if let insulinSensitivitySchedule = dataManager.loopManager.insulinSensitivitySchedule {
                vc.insulinSensitivitySchedule = insulinSensitivitySchedule
            }

            vc.delegate = self
        default:
            break
        }
    }
    
    // MARK: - UITableViewDataSource

    override func numberOfSections(in tableView: UITableView) -> Int {
        return Section.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .loop:
            return LoopRow.count
        case .pump:
            return PumpRow.count
        case .cgm:
            return 1
        case .configuration:
            return ConfigurationRow.count
        case .services:
            return ServiceRow.count
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch Section(rawValue: indexPath.section)! {
        case .loop:
            switch LoopRow(rawValue: indexPath.row)! {
            case .dosing:
                let switchCell = tableView.dequeueReusableCell(withIdentifier: SwitchTableViewCell.className, for: indexPath) as! SwitchTableViewCell

                switchCell.switch?.isOn = dataManager.loopManager.settings.dosingEnabled
                switchCell.textLabel?.text = NSLocalizedString("Closed Loop", comment: "The title text for the looping enabled switch cell")

                switchCell.switch?.addTarget(self, action: #selector(dosingEnabledChanged(_:)), for: .valueChanged)

                return switchCell
            case .diagnostic:
                let cell = tableView.dequeueReusableCell(withIdentifier: SettingsTableViewCell.className, for: indexPath)

                cell.textLabel?.text = NSLocalizedString("Issue Report", comment: "The title text for the issue report cell")
                cell.detailTextLabel?.text = nil
                cell.accessoryType = .disclosureIndicator

                return cell
            }
        case .pump:
            switch PumpRow(rawValue: indexPath.row)! {
            case .pumpSettings:
                if let pumpManager = dataManager.pumpManager {
                    let cell = tableView.dequeueReusableCell(withIdentifier: SettingsImageTableViewCell.className, for: indexPath)
                    cell.imageView?.image = pumpManager.smallImage
                    cell.textLabel?.text = pumpManager.localizedTitle
                    cell.detailTextLabel?.text = nil
                    cell.accessoryType = .disclosureIndicator
                    return cell
                } else {
                    let cell = tableView.dequeueReusableCell(withIdentifier: TextButtonTableViewCell.className, for: indexPath)
                    cell.textLabel?.text = NSLocalizedString("Add Pump", comment: "Title text for button to set up a new pump")
                    return cell
                }
            }
        case .cgm:
            if let cgmManager = dataManager.cgmManager {
                let cgmManagerUI = cgmManager as? CGMManagerUI

                let image = cgmManagerUI?.smallImage
                let cell = tableView.dequeueReusableCell(withIdentifier: image == nil ? SettingsTableViewCell.className : SettingsImageTableViewCell.className, for: indexPath)
                if let image = image {
                    cell.imageView?.image = image
                }
                cell.textLabel?.text = cgmManager.localizedTitle
                cell.detailTextLabel?.text = nil
                if cgmManagerUI != nil {
                    cell.accessoryType = .disclosureIndicator
                }
                return cell
            } else {
                let cell = tableView.dequeueReusableCell(withIdentifier: TextButtonTableViewCell.className, for: indexPath)
                cell.textLabel?.text = NSLocalizedString("Add CGM", comment: "Title text for button to set up a CGM")
                return cell
            }
        case .configuration:
            let configCell = tableView.dequeueReusableCell(withIdentifier: SettingsTableViewCell.className, for: indexPath)

            switch ConfigurationRow(rawValue: indexPath.row)! {
            case .carbRatio:
                configCell.textLabel?.text = NSLocalizedString("Carb Ratios", comment: "The title text for the carb ratio schedule")

                if let carbRatioSchedule = dataManager.loopManager.carbRatioSchedule {
                    let unit = carbRatioSchedule.unit
                    let value = valueNumberFormatter.string(from: carbRatioSchedule.averageQuantity().doubleValue(for: unit)) ?? SettingsTableViewCell.NoValueString

                    configCell.detailTextLabel?.text = String(format: NSLocalizedString("%1$@ %2$@/U", comment: "Format string for carb ratio average. (1: value)(2: carb unit)"), value, unit)
                } else {
                    configCell.detailTextLabel?.text = SettingsTableViewCell.TapToSetString
                }
            case .insulinSensitivity:
                configCell.textLabel?.text = NSLocalizedString("Insulin Sensitivities", comment: "The title text for the insulin sensitivity schedule")

                if let insulinSensitivitySchedule = dataManager.loopManager.insulinSensitivitySchedule {
                    let unit = insulinSensitivitySchedule.unit
                    let value = valueNumberFormatter.string(from: insulinSensitivitySchedule.averageQuantity().doubleValue(for: unit)) ?? SettingsTableViewCell.NoValueString

                    configCell.detailTextLabel?.text = String(format: NSLocalizedString("%1$@ %2$@/U", comment: "Format string for insulin sensitivity average (1: value)(2: glucose unit)"), value, unit.localizedShortUnitString
                    )
                } else {
                    configCell.detailTextLabel?.text = SettingsTableViewCell.TapToSetString
                }
            case .glucoseTargetRange:
                configCell.textLabel?.text = NSLocalizedString("Correction Range", comment: "The title text for the glucose target range schedule")

                if let glucoseTargetRangeSchedule = dataManager.loopManager.settings.glucoseTargetRangeSchedule {
                    let unit = glucoseTargetRangeSchedule.unit
                    let value = glucoseTargetRangeSchedule.value(at: Date())
                    let minTarget = valueNumberFormatter.string(from: value.minValue) ?? SettingsTableViewCell.NoValueString
                    let maxTarget = valueNumberFormatter.string(from: value.maxValue) ?? SettingsTableViewCell.NoValueString

                    configCell.detailTextLabel?.text = String(format: NSLocalizedString("%1$@ – %2$@ %3$@", comment: "Format string for glucose target range. (1: Min target)(2: Max target)(3: glucose unit)"), minTarget, maxTarget, unit.localizedShortUnitString)
                } else {
                    configCell.detailTextLabel?.text = SettingsTableViewCell.TapToSetString
                }
            case .suspendThreshold:
                configCell.textLabel?.text = NSLocalizedString("Suspend Threshold", comment: "The title text in settings")
                
                if let suspendThreshold = dataManager.loopManager.settings.suspendThreshold {
                    let value = valueNumberFormatter.string(from: suspendThreshold.value, unit: suspendThreshold.unit) ?? SettingsTableViewCell.TapToSetString
                    configCell.detailTextLabel?.text = value
                } else {
                    configCell.detailTextLabel?.text = SettingsTableViewCell.TapToSetString
                }
            case .insulinModel:
                configCell.textLabel?.text = NSLocalizedString("Insulin Model", comment: "The title text for the insulin model setting row")

                if let settings = dataManager.loopManager.insulinModelSettings {
                    configCell.detailTextLabel?.text = settings.title
                } else {
                    configCell.detailTextLabel?.text = SettingsTableViewCell.TapToSetString
                }
            case .deliveryLimits:
                configCell.textLabel?.text = NSLocalizedString("Delivery Limits", comment: "Title text for delivery limits")

                if dataManager.loopManager.settings.maximumBolus == nil || dataManager.loopManager.settings.maximumBasalRatePerHour == nil {
                    configCell.detailTextLabel?.text = SettingsTableViewCell.TapToSetString
                } else {
                    configCell.detailTextLabel?.text = SettingsTableViewCell.EnabledString
                }
            case .basalRate:
                configCell.textLabel?.text = NSLocalizedString("Basal Rates", comment: "The title text for the basal rate schedule")

                if let basalRateSchedule = dataManager.loopManager.basalRateSchedule {
                    configCell.detailTextLabel?.text = valueNumberFormatter.string(from: basalRateSchedule.total(), unit: "U")
                } else {
                    configCell.detailTextLabel?.text = SettingsTableViewCell.TapToSetString
                }
            }

            configCell.accessoryType = .disclosureIndicator
            return configCell
        case .services:
            let configCell = tableView.dequeueReusableCell(withIdentifier: SettingsTableViewCell.className, for: indexPath)

            switch ServiceRow(rawValue: indexPath.row)! {
            case .nightscout:
                let nightscoutService = dataManager.remoteDataManager.nightscoutService

                configCell.textLabel?.text = nightscoutService.title
                configCell.detailTextLabel?.text = nightscoutService.siteURL?.absoluteString ?? SettingsTableViewCell.TapToSetString
            case .loggly:
                let logglyService = dataManager.logger.logglyService

                configCell.textLabel?.text = logglyService.title
                configCell.detailTextLabel?.text = logglyService.isAuthorized ? SettingsTableViewCell.EnabledString : SettingsTableViewCell.TapToSetString
            case .amplitude:
                let amplitudeService = AnalyticsManager.shared.amplitudeService

                configCell.textLabel?.text = amplitudeService.title
                configCell.detailTextLabel?.text = amplitudeService.isAuthorized ? SettingsTableViewCell.EnabledString : SettingsTableViewCell.TapToSetString
            }

            configCell.accessoryType = .disclosureIndicator
            return configCell
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .loop:
            return Bundle.main.localizedNameAndVersion
        case .pump:
            return NSLocalizedString("Pump", comment: "The title of the pump section in settings")
        case .cgm:
            return NSLocalizedString("Continuous Glucose Monitor", comment: "The title of the continuous glucose monitor section in settings")
        case .configuration:
            return NSLocalizedString("Configuration", comment: "The title of the configuration section in settings")
        case .services:
            return NSLocalizedString("Services", comment: "The title of the services section in settings")
        }
    }

    // MARK: - UITableViewDelegate

    override func tableView(_ tableView: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
        return true
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let sender = tableView.cellForRow(at: indexPath)

        switch Section(rawValue: indexPath.section)! {
        case .pump:
            switch PumpRow(rawValue: indexPath.row)! {
            case .pumpSettings:
                if let settings = dataManager.pumpManager?.settingsViewController() {
                    show(settings, sender: sender)
                } else {
                    // Add new pump
                    let pumpManagers = allPumpManagers.compactMap({ $0 as? PumpManagerUI.Type })

                    switch pumpManagers.count {
                    case 1:
                        if let PumpManagerType = pumpManagers.first {
                            var setupViewController = PumpManagerType.setupViewController()
                            setupViewController.setupDelegate = self
                            present(setupViewController, animated: true, completion: nil)
                        }
                    case let x where x > 1:
                        let alert = UIAlertController(pumpManagers: pumpManagers) { [weak self] (manager) in
                            var setupViewController = manager.setupViewController()
                            setupViewController.setupDelegate = self
                            self?.present(setupViewController, animated: true, completion: nil)
                        }

                        alert.addCancelAction { (_) in
                            tableView.deselectRow(at: indexPath, animated: true)
                        }

                        present(alert, animated: true, completion: nil)
                    default:
                        break
                    }
                }
            }
        case .cgm:
            if let cgmManager = dataManager.cgmManager as? CGMManagerUI {
                if let unit = dataManager.loopManager.glucoseStore.preferredUnit {
                    show(cgmManager.settingsViewController(for: unit), sender: sender)
                }
            } else if dataManager.cgmManager is PumpManagerUI {
                // The pump manager is providing glucose, but allow reverting the CGM
                let alert = UIAlertController(deleteCGMManagerHandler: { [weak self] (isDeleted) in
                    if isDeleted {
                        self?.dataManager.cgmManager = nil
                    }

                    tableView.deselectRow(at: indexPath, animated: true)
                    _ = self?.tableView(tableView, willDeselectRowAt: indexPath)
                })
                present(alert, animated: true, completion: nil)
            } else {
                // Add new CGM
                let cgmManagers = allCGMManagers.compactMap({ $0 as? CGMManagerUI.Type })

                switch cgmManagers.count {
                case 1:
                    if let CGMManagerType = cgmManagers.first {
                        setupCGMManager(CGMManagerType, indexPath: indexPath)
                    }
                case let x where x > 1:
                    let alert = UIAlertController(cgmManagers: cgmManagers, pumpManager: dataManager.pumpManager as? CGMManager) { [weak self] (cgmManager, pumpManager) in
                        if let CGMManagerType = cgmManager {
                            self?.setupCGMManager(CGMManagerType, indexPath: indexPath)
                        } else if let pumpManager = pumpManager {
                            self?.completeCGMManagerSetup(pumpManager, indexPath: indexPath)
                        }
                    }

                    alert.addCancelAction { (_) in
                        tableView.deselectRow(at: indexPath, animated: true)
                    }

                    present(alert, animated: true, completion: nil)
                default:
                    break
                }
            }
        case .configuration:
            let row = ConfigurationRow(rawValue: indexPath.row)!
            switch row {
            case .carbRatio:
                let scheduleVC = DailyQuantityScheduleTableViewController()

                scheduleVC.delegate = self
                scheduleVC.title = NSLocalizedString("Carb Ratios", comment: "The title of the carb ratios schedule screen")
                scheduleVC.unit = .gram()

                if let schedule = dataManager.loopManager.carbRatioSchedule {
                    scheduleVC.timeZone = schedule.timeZone
                    scheduleVC.scheduleItems = schedule.items
                    scheduleVC.unit = schedule.unit
                } else if let timeZone = dataManager.pumpManager?.pumpTimeZone {
                    scheduleVC.timeZone = timeZone
                }

                show(scheduleVC, sender: sender)
            case .insulinSensitivity:
                let scheduleVC = DailyQuantityScheduleTableViewController()

                scheduleVC.delegate = self
                scheduleVC.title = NSLocalizedString("Insulin Sensitivities", comment: "The title of the insulin sensitivities schedule screen")

                if let schedule = dataManager.loopManager.insulinSensitivitySchedule {
                    scheduleVC.timeZone = schedule.timeZone
                    scheduleVC.scheduleItems = schedule.items
                    scheduleVC.unit = schedule.unit

                    show(scheduleVC, sender: sender)
                } else {
                    if let timeZone = dataManager.pumpManager?.pumpTimeZone {
                        scheduleVC.timeZone = timeZone
                    }

                    if let unit = dataManager.loopManager.glucoseStore.preferredUnit {
                        scheduleVC.unit = unit
                        self.show(scheduleVC, sender: sender)
                    }
                }
            case .glucoseTargetRange:
                let scheduleVC = GlucoseRangeScheduleTableViewController()

                scheduleVC.delegate = self
                scheduleVC.title = NSLocalizedString("Correction Range", comment: "The title of the glucose target range schedule screen")

                if let schedule = dataManager.loopManager.settings.glucoseTargetRangeSchedule {
                    scheduleVC.timeZone = schedule.timeZone
                    scheduleVC.scheduleItems = schedule.items
                    scheduleVC.unit = schedule.unit
                    scheduleVC.overrideRanges = schedule.overrideRanges

                    show(scheduleVC, sender: sender)
                } else {
                    if let timeZone = dataManager.pumpManager?.pumpTimeZone {
                        scheduleVC.timeZone = timeZone
                    }

                    if let unit = dataManager.loopManager.glucoseStore.preferredUnit {
                        scheduleVC.unit = unit
                        self.show(scheduleVC, sender: sender)
                    }
                }
            case .suspendThreshold:
                if let minBGGuard = dataManager.loopManager.settings.suspendThreshold {
                    let vc = GlucoseThresholdTableViewController(threshold: minBGGuard.value, glucoseUnit: minBGGuard.unit)
                    vc.delegate = self
                    vc.indexPath = indexPath
                    vc.title = sender?.textLabel?.text
                    self.show(vc, sender: sender)
                } else if let unit = dataManager.loopManager.glucoseStore.preferredUnit {
                    let vc = GlucoseThresholdTableViewController(threshold: nil, glucoseUnit: unit)
                    vc.delegate = self
                    vc.indexPath = indexPath
                    vc.title = sender?.textLabel?.text
                    self.show(vc, sender: sender)
                }
            case .insulinModel:
                performSegue(withIdentifier: InsulinModelSettingsViewController.className, sender: sender)
            case .deliveryLimits:
                let vc = DeliveryLimitSettingsTableViewController(style: .grouped)

                vc.maximumBasalRatePerHour = dataManager.loopManager.settings.maximumBasalRatePerHour
                vc.maximumBolus = dataManager.loopManager.settings.maximumBolus

                vc.title = sender?.textLabel?.text
                vc.delegate = self
                vc.syncSource = dataManager.pumpManager

                show(vc, sender: sender)
            case .basalRate:
                let vc = SingleValueScheduleTableViewController(style: .grouped)

                if let profile = dataManager.loopManager.basalRateSchedule {
                    vc.scheduleItems = profile.items
                    vc.timeZone = profile.timeZone
                } else if let timeZone = dataManager.pumpManager?.pumpTimeZone {
                    vc.timeZone = timeZone
                }

                vc.title = NSLocalizedString("Basal Rates", comment: "The title of the basal rate profile screen")
                vc.delegate = self
                vc.syncSource = dataManager.pumpManager

                show(vc, sender: sender)
            }
        case .loop:
            switch LoopRow(rawValue: indexPath.row)! {
            case .diagnostic:
                let vc = CommandResponseViewController.generateDiagnosticReport(deviceManager: dataManager)
                vc.title = sender?.textLabel?.text

                show(vc, sender: sender)
            case .dosing:
                break
            }
        case .services:
            switch ServiceRow(rawValue: indexPath.row)! {
            case .nightscout:
                let service = dataManager.remoteDataManager.nightscoutService
                let vc = AuthenticationViewController(authentication: service)
                vc.authenticationObserver = { [weak self] (service) in
                    self?.dataManager.remoteDataManager.nightscoutService = service

                    self?.tableView.reloadRows(at: [indexPath], with: .none)
                }

                show(vc, sender: sender)
            case .loggly:
                let service = dataManager.logger.logglyService
                let vc = AuthenticationViewController(authentication: service)
                vc.authenticationObserver = { [weak self] (service) in
                    self?.dataManager.logger.logglyService = service

                    self?.tableView.reloadRows(at: [indexPath], with: .none)
                }

                show(vc, sender: sender)
            case .amplitude:
                let service = AnalyticsManager.shared.amplitudeService
                let vc = AuthenticationViewController(authentication: service)
                vc.authenticationObserver = { [weak self] (service) in
                    AnalyticsManager.shared.amplitudeService = service

                    self?.tableView.reloadRows(at: [indexPath], with: .none)
                }

                show(vc, sender: sender)
            }
        }
    }

    override func tableView(_ tableView: UITableView, willDeselectRowAt indexPath: IndexPath) -> IndexPath? {
        switch Section(rawValue: indexPath.section)! {
        case .loop:
            break
        case .pump:
            tableView.reloadRows(at: [indexPath], with: .fade)
            tableView.reloadRows(at: [[Section.cgm.rawValue, CGMRow.cgmSettings.rawValue]], with: .fade)
        case .cgm:
            tableView.reloadRows(at: [indexPath], with: .fade)
        case .configuration:
            break
        case .services:
            break
        }

        return indexPath
    }

    @objc private func dosingEnabledChanged(_ sender: UISwitch) {
        dataManager.loopManager.settings.dosingEnabled = sender.isOn
    }
}


extension SettingsTableViewController: PumpManagerSetupViewControllerDelegate {
    func pumpManagerSetupViewController(_ pumpManagerSetupViewController: PumpManagerSetupViewController, didSetUpPumpManager pumpManager: PumpManagerUI) {
        dataManager.pumpManager = pumpManager
        tableView.selectRow(at: IndexPath(row: PumpRow.pumpSettings.rawValue, section: Section.pump.rawValue), animated: false, scrollPosition: .none)

        if let basalRateSchedule = pumpManagerSetupViewController.basalSchedule {
            dataManager.loopManager.basalRateSchedule = basalRateSchedule
            tableView.reloadRows(at: [[Section.configuration.rawValue, ConfigurationRow.basalRate.rawValue]], with: .none)
        }

        if let maxBasalRateUnitsPerHour = pumpManagerSetupViewController.maxBasalRateUnitsPerHour {
            dataManager.loopManager.settings.maximumBasalRatePerHour = maxBasalRateUnitsPerHour
            tableView.reloadRows(at: [[Section.configuration.rawValue, ConfigurationRow.deliveryLimits.rawValue]], with: .none)
        }

        if let maxBolusUnits = pumpManagerSetupViewController.maxBolusUnits {
            dataManager.loopManager.settings.maximumBolus = maxBolusUnits
            tableView.reloadRows(at: [[Section.configuration.rawValue, ConfigurationRow.deliveryLimits.rawValue]], with: .none)
        }

        show(pumpManager.settingsViewController(), sender: nil)
        dismiss(animated: true, completion: nil)
    }

    func pumpManagerSetupViewControllerDidCancel(_ pumpManagerSetupViewController: PumpManagerSetupViewController) {
        dismiss(animated: true, completion: nil)
    }
}


extension SettingsTableViewController: CGMManagerSetupViewControllerDelegate {
    fileprivate func setupCGMManager(_ CGMManagerType: CGMManagerUI.Type, indexPath: IndexPath) {
        if var setupViewController = CGMManagerType.setupViewController() {
            setupViewController.setupDelegate = self
            present(setupViewController, animated: true, completion: nil)
        } else {
            completeCGMManagerSetup(CGMManagerType.init(rawState: [:]), indexPath: indexPath)
        }
    }

    fileprivate func completeCGMManagerSetup(_ cgmManager: CGMManager?, indexPath: IndexPath) {
        dataManager.cgmManager = cgmManager
        tableView.deselectRow(at: indexPath, animated: true)
        _ = self.tableView(tableView, willDeselectRowAt: indexPath)
    }

    func cgmManagerSetupViewController(_ cgmManagerSetupViewController: CGMManagerSetupViewController, didSetUpCGMManager cgmManager: CGMManagerUI) {
        dataManager.cgmManager = cgmManager
        tableView.selectRow(at: IndexPath(row: CGMRow.cgmSettings.rawValue, section: Section.cgm.rawValue), animated: false, scrollPosition: .none)
        show(cgmManager.settingsViewController(for: dataManager.loopManager.glucoseStore.preferredUnit ?? .milligramsPerDeciliter), sender: nil)
        dismiss(animated: true, completion: nil)
    }

    func cgmManagerSetupViewControllerDidCancel(_ cgmManagerSetupViewController: CGMManagerSetupViewController) {
        dismiss(animated: true, completion: nil)
    }
}


extension SettingsTableViewController: DailyValueScheduleTableViewControllerDelegate {
    func dailyValueScheduleTableViewControllerWillFinishUpdating(_ controller: DailyValueScheduleTableViewController) {
        guard let indexPath = tableView.indexPathForSelectedRow else {
            return
        }

        switch Section(rawValue: indexPath.section)! {
        case .configuration:
            switch ConfigurationRow(rawValue: indexPath.row)! {
            case .glucoseTargetRange:
                if let controller = controller as? GlucoseRangeScheduleTableViewController {
                    dataManager.loopManager.settings.glucoseTargetRangeSchedule = GlucoseRangeSchedule(unit: controller.unit, dailyItems: controller.scheduleItems, timeZone: controller.timeZone, overrideRanges: controller.overrideRanges, override: dataManager.loopManager.settings.glucoseTargetRangeSchedule?.override)
                }
            case .basalRate:
                if let controller = controller as? SingleValueScheduleTableViewController {
                    dataManager.loopManager.basalRateSchedule = BasalRateSchedule(dailyItems: controller.scheduleItems, timeZone: controller.timeZone)
                }
            case let row:
                if let controller = controller as? DailyQuantityScheduleTableViewController {
                    switch row {
                    case .carbRatio:
                        dataManager.loopManager.carbRatioSchedule = CarbRatioSchedule(unit: controller.unit, dailyItems: controller.scheduleItems, timeZone: controller.timeZone)
                        AnalyticsManager.shared.didChangeCarbRatioSchedule()
                    case .insulinSensitivity:
                        dataManager.loopManager.insulinSensitivitySchedule = InsulinSensitivitySchedule(unit: controller.unit, dailyItems: controller.scheduleItems, timeZone: controller.timeZone)
                        AnalyticsManager.shared.didChangeInsulinSensitivitySchedule()
                    default:
                        break
                    }
                }
            }
        default:
            break
        }

        tableView.reloadRows(at: [indexPath], with: .none)
    }
}


extension SettingsTableViewController: InsulinModelSettingsViewControllerDelegate {
    func insulinModelSettingsViewControllerDidChangeValue(_ controller: InsulinModelSettingsViewController) {
        guard let indexPath = self.tableView.indexPathForSelectedRow else {
            return
        }

        switch Section(rawValue: indexPath.section)! {
        case .configuration:
            switch ConfigurationRow(rawValue: indexPath.row)! {
            case .insulinModel:
                if let model = controller.insulinModel {
                    dataManager.loopManager.insulinModelSettings = InsulinModelSettings(model: model)
                }

                tableView.reloadRows(at: [indexPath], with: .none)
            default:
                assertionFailure()
            }
        default:
            assertionFailure()
        }
    }
}


extension SettingsTableViewController: LoopKitUI.TextFieldTableViewControllerDelegate {
    func textFieldTableViewControllerDidEndEditing(_ controller: LoopKitUI.TextFieldTableViewController) {
        if let indexPath = controller.indexPath {
            switch Section(rawValue: indexPath.section)! {
            case .configuration:
                switch ConfigurationRow(rawValue: indexPath.row)! {
                case .suspendThreshold:
                    if let controller = controller as? GlucoseThresholdTableViewController,
                        let value = controller.value, let minBGGuard = valueNumberFormatter.number(from: value)?.doubleValue {
                        dataManager.loopManager.settings.suspendThreshold = GlucoseThreshold(unit: controller.glucoseUnit, value: minBGGuard)
                    } else {
                        dataManager.loopManager.settings.suspendThreshold = nil
                    }
                default:
                    assertionFailure()
                }
            default:
                assertionFailure()
            }
        }

        tableView.reloadData()
    }

    func textFieldTableViewControllerDidReturn(_ controller: LoopKitUI.TextFieldTableViewController) {
        _ = navigationController?.popViewController(animated: true)
    }
}


extension SettingsTableViewController: DeliveryLimitSettingsTableViewControllerDelegate {
    func deliveryLimitSettingsTableViewControllerDidUpdateMaximumBasalRatePerHour(_ vc: DeliveryLimitSettingsTableViewController) {
        dataManager.loopManager.settings.maximumBasalRatePerHour = vc.maximumBasalRatePerHour

        tableView.reloadRows(at: [[Section.configuration.rawValue, ConfigurationRow.deliveryLimits.rawValue]], with: .none)
    }

    func deliveryLimitSettingsTableViewControllerDidUpdateMaximumBolus(_ vc: DeliveryLimitSettingsTableViewController) {
        dataManager.loopManager.settings.maximumBolus = vc.maximumBolus

        tableView.reloadRows(at: [[Section.configuration.rawValue, ConfigurationRow.deliveryLimits.rawValue]], with: .none)
    }
}
