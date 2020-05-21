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
import LoopCore
import LoopTestingKit


final class SettingsTableViewController: UITableViewController {

    @IBOutlet var devicesSectionTitleView: UIView?

    override func viewDidLoad() {
        super.viewDidLoad()

        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 44

        tableView.register(SettingsTableViewCell.self, forCellReuseIdentifier: SettingsTableViewCell.className)
        tableView.register(SettingsImageTableViewCell.self, forCellReuseIdentifier: SettingsImageTableViewCell.className)
        tableView.register(SwitchTableViewCell.self, forCellReuseIdentifier: SwitchTableViewCell.className)
        tableView.register(TextButtonTableViewCell.self, forCellReuseIdentifier: TextButtonTableViewCell.className)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        dataManager.analyticsServicesManager.didDisplaySettingsScreen()
    }

    var dataManager: DeviceDataManager!

    private lazy var isTestingPumpManager = dataManager.pumpManager is TestingPumpManager
    private lazy var isTestingCGMManager = dataManager.cgmManager is TestingCGMManager

    fileprivate enum Section: Int, CaseIterable {
        case loop = 0
        case pump
        case cgm
        case configuration
        case services
        case testingPumpDataDeletion
        case testingCGMDataDeletion
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
        case correctionRangeOverrides
        case suspendThreshold
        case basalRate
        case deliveryLimits
        case insulinModel
        case carbRatio
        case insulinSensitivity
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

    func configuredSetupViewController(for pumpManager: PumpManagerUI.Type) -> (UIViewController & PumpManagerSetupViewController & CompletionNotifying) {
        var setupViewController = pumpManager.setupViewController()
        setupViewController.setupDelegate = self
        setupViewController.completionDelegate = self
        setupViewController.basalSchedule = dataManager.loopManager.basalRateSchedule
        setupViewController.maxBolusUnits = dataManager.loopManager.settings.maximumBolus
        setupViewController.maxBasalRateUnitsPerHour = dataManager.loopManager.settings.maximumBasalRatePerHour
        return setupViewController
    }

    // MARK: - UITableViewDataSource

    private var sections: [Section] {
        var sections = Section.allCases
        if !isTestingPumpManager {
            sections.remove(.testingPumpDataDeletion)
        }
        if !isTestingCGMManager {
            sections.remove(.testingCGMDataDeletion)
        }
        return sections
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        return sections.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch sections[section] {
        case .loop:
            return LoopRow.count
        case .pump:
            return PumpRow.count
        case .cgm:
            return CGMRow.count
        case .configuration:
            return ConfigurationRow.count
        case .services:
            return min(activeServices.count + 1, availableServices.count)
        case .testingPumpDataDeletion, .testingCGMDataDeletion:
            return 1
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch sections[indexPath.section] {
        case .loop:
            switch LoopRow(rawValue: indexPath.row)! {
            case .dosing:
                let switchCell = tableView.dequeueReusableCell(withIdentifier: SwitchTableViewCell.className, for: indexPath) as! SwitchTableViewCell

                switchCell.selectionStyle = .none
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
                    // Schedule is in mg/dL or mmol/L, but we display as mg/dL/U or mmol/L/U
                    let average = insulinSensitivitySchedule.averageQuantity().doubleValue(for: unit)
                    let unitPerU = unit.unitDivided(by: .internationalUnit())
                    let averageQuantity = HKQuantity(unit: unitPerU, doubleValue: average)
                    let formatter = QuantityFormatter()
                    formatter.setPreferredNumberFormatter(for: unit)
                    configCell.detailTextLabel?.text = formatter.string(from: averageQuantity, for: unitPerU)
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
            case .correctionRangeOverrides:
                configCell.textLabel?.text = NSLocalizedString("Temporary Correction Ranges", comment: "The title text for the correction range overrides")
                if dataManager.loopManager.settings.preMealTargetRange == nil {
                    configCell.detailTextLabel?.text = SettingsTableViewCell.TapToSetString
                } else {
                    // TODO: Show some text in the detail label.
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
            if indexPath.row < activeServices.count {
                let service = activeServices[indexPath.row]
                let cell = tableView.dequeueReusableCell(withIdentifier: SettingsTableViewCell.className, for: indexPath)
                cell.textLabel?.text = service.localizedTitle
                cell.detailTextLabel?.text = nil
                return cell
            } else {
                let cell = tableView.dequeueReusableCell(withIdentifier: TextButtonTableViewCell.className, for: indexPath)
                cell.textLabel?.text = NSLocalizedString("Add Service", comment: "Title text for button to set up a service")
                return cell
            }
        case .testingPumpDataDeletion:
            let cell = tableView.dequeueReusableCell(withIdentifier: TextButtonTableViewCell.className, for: indexPath) as! TextButtonTableViewCell
            cell.textLabel?.text = "Delete Pump Data"
            cell.textLabel?.textAlignment = .center
            cell.tintColor = .delete
            cell.isEnabled = true
            return cell
        case .testingCGMDataDeletion:
            let cell = tableView.dequeueReusableCell(withIdentifier: TextButtonTableViewCell.className, for: indexPath) as! TextButtonTableViewCell
            cell.textLabel?.text = "Delete CGM Data"
            cell.textLabel?.textAlignment = .center
            cell.tintColor = .delete
            cell.isEnabled = true
            return cell
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch sections[section] {
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
        case .testingPumpDataDeletion, .testingCGMDataDeletion:
            return nil
        }
    }

    // MARK: - UITableViewDelegate

    override func tableView(_ tableView: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
        return true
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let sender = tableView.cellForRow(at: indexPath)

        switch sections[indexPath.section] {
        case .pump:
            switch PumpRow(rawValue: indexPath.row)! {
            case .pumpSettings:
                if var settings = dataManager.pumpManager?.settingsViewController() {
                    settings.completionDelegate = self
                    present(settings, animated: true)
                    tableView.deselectRow(at: indexPath, animated: true)
                } else {
                    // Add new pump
                    let pumpManagers = dataManager.availablePumpManagers

                    switch pumpManagers.count {
                    case 1:
                        if let pumpManager = pumpManagers.first, let PumpManagerType = dataManager.pumpManagerTypeByIdentifier(pumpManager.identifier) {

                            let setupViewController = configuredSetupViewController(for: PumpManagerType)
                            present(setupViewController, animated: true, completion: nil)
                        }
                        tableView.deselectRow(at: indexPath, animated: true)
                    case let x where x > 1:
                        let alert = UIAlertController(pumpManagers: pumpManagers) { [weak self] (identifier) in
                            if let self = self, let manager = self.dataManager.pumpManagerTypeByIdentifier(identifier) {
                                let setupViewController = self.configuredSetupViewController(for: manager)
                                self.present(setupViewController, animated: true, completion: nil)
                                self.tableView.deselectRow(at: indexPath, animated: true)
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
            }
        case .cgm:
            if let cgmManager = dataManager.cgmManager as? CGMManagerUI {
                if let unit = dataManager.loopManager.glucoseStore.preferredUnit {
                    var settings = cgmManager.settingsViewController(for: unit)
                    settings.completionDelegate = self
                    present(settings, animated: true)
                    tableView.deselectRow(at: indexPath, animated: true)
                }
            } else if dataManager.cgmManager is PumpManagerUI {
                // The pump manager is providing glucose, but allow reverting the CGM
                let alert = UIAlertController(deleteCGMManagerHandler: { [weak self] (isDeleted) in
                    if isDeleted {
                        self?.dataManager.cgmManager = nil
                    }

                    tableView.deselectRow(at: indexPath, animated: true)
                    self?.updateCGMManagerRows()
                })
                present(alert, animated: true, completion: nil)
            } else {
                // Add new CGM
                let cgmManagers = dataManager.availableCGMManagers

                switch cgmManagers.count {
                case 1:
                    if let cgmManager = cgmManagers.first, let CGMManagerType = dataManager.cgmManagerTypeByIdentifier(cgmManager.identifier) {
                        setupCGMManager(CGMManagerType)
                    }

                    tableView.deselectRow(at: indexPath, animated: true)
                case let x where x > 1:
                    let alert = UIAlertController(cgmManagers: cgmManagers, pumpManager: dataManager.pumpManager as? CGMManager) { [weak self] (identifier, pumpManager) in
                        if let self = self {
                            if let cgmManagerIdentifier = identifier, let CGMManagerType = self.dataManager.cgmManagerTypeByIdentifier(cgmManagerIdentifier) {
                                self.setupCGMManager(CGMManagerType)
                            } else if let pumpManager = pumpManager {
                                self.completeCGMManagerSetup(pumpManager)
                            }
                        }

                        tableView.deselectRow(at: indexPath, animated: true)
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
                let editor = CarbRatioScheduleEditor(
                    schedule: dataManager.loopManager.carbRatioSchedule,
                    onSave: { [dataManager] newSchedule in
                        dataManager?.loopManager.carbRatioSchedule = newSchedule
                        dataManager?.analyticsServicesManager.didChangeCarbRatioSchedule()
                        tableView.reloadRows(at: [indexPath], with: .automatic)
                    }
                )

                let hostingController = DismissibleHostingController(rootView: editor, onDisappear: {
                    tableView.deselectRow(at: indexPath, animated: true)
                })

                present(hostingController, animated: true)
            case .insulinSensitivity:
                let glucoseUnit = dataManager.loopManager.insulinSensitivitySchedule?.unit ?? dataManager.loopManager.glucoseStore.preferredUnit ?? HKUnit.milligramsPerDeciliter

                let editor = InsulinSensitivityScheduleEditor(
                    schedule: dataManager.loopManager.insulinSensitivitySchedule,
                    glucoseUnit: glucoseUnit,
                    onSave: { [dataManager] newSchedule in
                        dataManager?.loopManager.insulinSensitivitySchedule = newSchedule
                        dataManager?.analyticsServicesManager.didChangeInsulinSensitivitySchedule()
                        tableView.reloadRows(at: [indexPath], with: .automatic)
                    }
                )

                let hostingController = DismissibleHostingController(rootView: editor, onDisappear: {
                    tableView.deselectRow(at: indexPath, animated: true)
                })
                
                present(hostingController, animated: true)
            case .glucoseTargetRange:
                let unit = dataManager.loopManager.settings.glucoseTargetRangeSchedule?.unit ?? dataManager.loopManager.glucoseStore.preferredUnit ?? HKUnit.milligramsPerDeciliter

                let editor = CorrectionRangeScheduleEditor(
                    schedule: dataManager.loopManager.settings.glucoseTargetRangeSchedule,
                    unit: unit,
                    minValue: dataManager.loopManager.settings.suspendThreshold?.quantity,
                    onSave: { [dataManager] newSchedule in
                        dataManager?.loopManager.settings.glucoseTargetRangeSchedule = newSchedule
                        tableView.reloadRows(at: [indexPath], with: .automatic)
                    }
                )

                let hostingController = DismissibleHostingController(rootView: editor, onDisappear: {
                    tableView.deselectRow(at: indexPath, animated: true)
                })

                present(hostingController, animated: true)
            case .correctionRangeOverrides:
                let unit = dataManager.loopManager.settings.glucoseTargetRangeSchedule?.unit ?? dataManager.loopManager.glucoseStore.preferredUnit ?? HKUnit.milligramsPerDeciliter

                let editor = CorrectionRangeOverridesEditor(
                    value: CorrectionRangeOverrides(
                        preMeal: dataManager.loopManager.settings.preMealTargetRange,
                        workout: dataManager.loopManager.settings.legacyWorkoutTargetRange,
                        unit: unit
                    ),
                    unit: unit,
                    minValue: dataManager.loopManager.settings.suspendThreshold?.quantity,
                    onSave: { [dataManager] overrides in
                        dataManager?.loopManager.settings.preMealTargetRange = overrides.preMeal?.doubleRange(for: unit)
                        dataManager?.loopManager.settings.legacyWorkoutTargetRange = overrides.workout?.doubleRange(for: unit)
                    }
                )

                let hostingController = ExplicitlyDismissibleModal(rootView: editor, onDisappear: {
                    tableView.deselectRow(at: indexPath, animated: true)
                })

                present(hostingController, animated: true)
            case .suspendThreshold:
                func presentSuspendThresholdEditor(initialValue: HKQuantity?, unit: HKUnit) {
                    let editor = SuspendThresholdEditor(
                        value: initialValue,
                        unit: unit,
                        maxValue: dataManager.loopManager.settings.glucoseTargetRangeSchedule?.minLowerBound(),
                        onSave: { [dataManager, tableView] newValue in
                            dataManager!.loopManager.settings.suspendThreshold = GlucoseThreshold(unit: unit, value: newValue.doubleValue(for: unit))

                            tableView.reloadRows(at: [indexPath], with: .automatic)
                        }
                    )

                    let hostingController = ExplicitlyDismissibleModal(rootView: editor, onDisappear: {
                        tableView.deselectRow(at: indexPath, animated: true)
                    })

                    present(hostingController, animated: true)
                }

                if let minBGGuard = dataManager.loopManager.settings.suspendThreshold {
                    presentSuspendThresholdEditor(initialValue: minBGGuard.quantity, unit: minBGGuard.unit)
                } else if let unit = dataManager.loopManager.glucoseStore.preferredUnit {
                    presentSuspendThresholdEditor(initialValue: nil, unit: unit)
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
                guard let pumpManager = dataManager.pumpManager else {
                    // Not allowing basal schedule entry without a configured pump.
                    tableView.deselectRow(at: indexPath, animated: true)
                    return
                }
                let vc = BasalScheduleTableViewController(allowedBasalRates: pumpManager.supportedBasalRates, maximumScheduleItemCount: pumpManager.maximumBasalScheduleEntryCount, minimumTimeInterval: pumpManager.minimumBasalScheduleEntryDuration)

                if let profile = dataManager.loopManager.basalRateSchedule {
                    vc.scheduleItems = profile.items
                    vc.timeZone = profile.timeZone
                } else {
                    vc.timeZone = pumpManager.status.timeZone
                }

                vc.title = NSLocalizedString("Basal Rates", comment: "The title of the basal rate profile screen")
                vc.delegate = self
                vc.syncSource = pumpManager

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
            if indexPath.row < activeServices.count {
                if let serviceUI = activeServices[indexPath.row] as? ServiceUI {
                    var settings = serviceUI.settingsViewController()
                    settings.serviceSettingsDelegate = self
                    settings.completionDelegate = self
                    present(settings, animated: true)
                }
                tableView.deselectRow(at: indexPath, animated: true)
            } else {
                let alert = UIAlertController(services: inactiveServices) { [weak self] (identifier) in
                    self?.setupService(withIdentifier: identifier)
                }

                alert.addCancelAction { (_) in
                    tableView.deselectRow(at: indexPath, animated: true)
                }

                present(alert, animated: true, completion: nil)
            }
        case .testingPumpDataDeletion:
            let confirmVC = UIAlertController(pumpDataDeletionHandler: { self.dataManager.deleteTestingPumpData() })
            present(confirmVC, animated: true) {
                tableView.deselectRow(at: indexPath, animated: true)
            }
        case .testingCGMDataDeletion:
            let confirmVC = UIAlertController(cgmDataDeletionHandler: { self.dataManager.deleteTestingCGMData() })
            present(confirmVC, animated: true) {
                tableView.deselectRow(at: indexPath, animated: true)
            }
        }
    }

    @objc private func dosingEnabledChanged(_ sender: UISwitch) {
        dataManager.loopManager.settings.dosingEnabled = sender.isOn
    }
}

// MARK: - DeviceManager view controller delegation

extension SettingsTableViewController: CompletionDelegate {
    func completionNotifyingDidComplete(_ object: CompletionNotifying) {
        if let vc = object as? UIViewController, presentedViewController === vc {
            dismiss(animated: true, completion: nil)

            updateSelectedDeviceManagerAndServicesRows()
        }
    }

    private func updateSelectedDeviceManagerAndServicesRows() {
        tableView.beginUpdates()
        updateSelectedDeviceManagerRows()
        updateSelectedServicesRows()
        tableView.endUpdates()
    }

    private func updateSelectedDeviceManagerRows() {
        tableView.beginUpdates()
        updatePumpManagerRows()
        updateCGMManagerRows()
        tableView.endUpdates()
    }

    private func updatePumpManagerRows() {
        tableView.beginUpdates()

        let previousTestingPumpDataDeletionSection = sections.firstIndex(of: .testingPumpDataDeletion)
        let wasTestingPumpManager = isTestingPumpManager
        isTestingPumpManager = dataManager.pumpManager is TestingPumpManager
        if !wasTestingPumpManager, isTestingPumpManager {
            guard let testingPumpDataDeletionSection = sections.firstIndex(of: .testingPumpDataDeletion) else {
                fatalError("Expected to find testing pump data deletion section with testing pump in use")
            }
            tableView.insertSections([testingPumpDataDeletionSection], with: .automatic)
        } else if wasTestingPumpManager, !isTestingPumpManager {
            guard let previousTestingPumpDataDeletionSection = previousTestingPumpDataDeletionSection else {
                fatalError("Expected to have had testing pump data deletion section when testing pump was in use")
            }
            tableView.deleteSections([previousTestingPumpDataDeletionSection], with: .automatic)
        }


        tableView.reloadSections([Section.pump.rawValue], with: .fade)
        tableView.reloadSections([Section.cgm.rawValue], with: .fade)
        tableView.endUpdates()
    }

    private func updateCGMManagerRows() {
        tableView.beginUpdates()

        let previousTestingCGMDataDeletionSection = sections.firstIndex(of: .testingCGMDataDeletion)
        let wasTestingCGMManager = isTestingCGMManager
        isTestingCGMManager = dataManager.cgmManager is TestingCGMManager
        if !wasTestingCGMManager, isTestingCGMManager {
            guard let testingCGMDataDeletionSection = sections.firstIndex(of: .testingCGMDataDeletion) else {
                fatalError("Expected to find testing CGM data deletion section with testing CGM in use")
            }
            tableView.insertSections([testingCGMDataDeletionSection], with: .automatic)
        } else if wasTestingCGMManager, !isTestingCGMManager {
            guard let previousTestingCGMDataDeletionSection = previousTestingCGMDataDeletionSection else {
                fatalError("Expected to have had testing CGM data deletion section when testing CGM was in use")
            }
            tableView.deleteSections([previousTestingCGMDataDeletionSection], with: .automatic)
        }

        tableView.reloadSections([Section.cgm.rawValue], with: .fade)
        tableView.endUpdates()
    }

    private func updateSelectedServicesRows() {
        tableView.beginUpdates()
        tableView.reloadSections([Section.services.rawValue], with: .fade)
        tableView.endUpdates()
    }
}


extension SettingsTableViewController: PumpManagerSetupViewControllerDelegate {
    func pumpManagerSetupViewController(_ pumpManagerSetupViewController: PumpManagerSetupViewController, didSetUpPumpManager pumpManager: PumpManagerUI) {
        dataManager.pumpManager = pumpManager

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
    }
}


extension SettingsTableViewController: CGMManagerSetupViewControllerDelegate {
    fileprivate func setupCGMManager(_ CGMManagerType: CGMManagerUI.Type) {
        if var setupViewController = CGMManagerType.setupViewController() {
            setupViewController.setupDelegate = self
            setupViewController.completionDelegate = self
            present(setupViewController, animated: true, completion: nil)
        } else {
            completeCGMManagerSetup(CGMManagerType.init(rawState: [:]))
        }
    }

    fileprivate func completeCGMManagerSetup(_ cgmManager: CGMManager?) {
        dataManager.cgmManager = cgmManager

        updateSelectedDeviceManagerRows()
    }

    func cgmManagerSetupViewController(_ cgmManagerSetupViewController: CGMManagerSetupViewController, didSetUpCGMManager cgmManager: CGMManagerUI) {
        completeCGMManagerSetup(cgmManager)
    }
}

extension SettingsTableViewController {
    fileprivate var availableServices: [AvailableService] {
        return dataManager.servicesManager.availableServices
    }

    fileprivate var activeServices: [Service] {
        return dataManager.servicesManager.activeServices.sorted { $0.localizedTitle < $1.localizedTitle }
    }

    fileprivate var inactiveServices: [AvailableService] {
        return availableServices.filter { availableService in !dataManager.servicesManager.activeServices.contains { type(of: $0).serviceIdentifier == availableService.identifier } }
    }

    fileprivate func setupService(withIdentifier identifier: String) {
        guard let serviceUIType = dataManager.servicesManager.serviceUITypeByIdentifier(identifier) else {
            return
        }

        if var setupViewController = serviceUIType.setupViewController() {
            setupViewController.serviceSetupDelegate = self
            setupViewController.completionDelegate = self
            present(setupViewController, animated: true, completion: nil)
        } else if let service = serviceUIType.init(rawState: [:]) {
            dataManager.servicesManager.addActiveService(service)
            updateSelectedServicesRows()
        }
    }
}

extension SettingsTableViewController: ServiceSetupDelegate {
    func serviceSetupNotifying(_ object: ServiceSetupNotifying, didCreateService service: Service) {
        dataManager.servicesManager.addActiveService(service)
    }
}

extension SettingsTableViewController: ServiceSettingsDelegate {
    func serviceSettingsNotifying(_ object: ServiceSettingsNotifying, didDeleteService service: Service) {
        dataManager.servicesManager.removeActiveService(service)
    }
}

extension SettingsTableViewController: DailyValueScheduleTableViewControllerDelegate {
    func dailyValueScheduleTableViewControllerWillFinishUpdating(_ controller: DailyValueScheduleTableViewController) {
        guard let indexPath = tableView.indexPathForSelectedRow else {
            return
        }

        switch sections[indexPath.section] {
        case .configuration:
            switch ConfigurationRow(rawValue: indexPath.row)! {
            case .basalRate:
                if let controller = controller as? BasalScheduleTableViewController {
                    dataManager.loopManager.basalRateSchedule = BasalRateSchedule(dailyItems: controller.scheduleItems, timeZone: controller.timeZone)
                }
            default:
                break
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

        switch sections[indexPath.section] {
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


extension SettingsTableViewController: DeliveryLimitSettingsTableViewControllerDelegate {
    func deliveryLimitSettingsTableViewControllerDidUpdateMaximumBasalRatePerHour(_ vc: DeliveryLimitSettingsTableViewController) {
        dataManager.maximumBasalRatePerHour = vc.maximumBasalRatePerHour

        tableView.reloadRows(at: [[Section.configuration.rawValue, ConfigurationRow.deliveryLimits.rawValue]], with: .none)
    }

    func deliveryLimitSettingsTableViewControllerDidUpdateMaximumBolus(_ vc: DeliveryLimitSettingsTableViewController) {
        dataManager.loopManager.settings.maximumBolus = vc.maximumBolus

        tableView.reloadRows(at: [[Section.configuration.rawValue, ConfigurationRow.deliveryLimits.rawValue]], with: .none)
    }
}


private extension UIAlertController {
    convenience init(pumpDataDeletionHandler handler: @escaping () -> Void) {
        self.init(
            title: nil,
            message: "Are you sure you want to delete testing pump health data?",
            preferredStyle: .actionSheet
        )

        addAction(UIAlertAction(
            title: "Delete Pump Data",
            style: .destructive,
            handler: { _ in handler() }
        ))

        addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
    }

    convenience init(cgmDataDeletionHandler handler: @escaping () -> Void) {
        self.init(
            title: nil,
            message: "Are you sure you want to delete testing CGM health data?",
            preferredStyle: .actionSheet
        )

        addAction(UIAlertAction(
            title: "Delete CGM Data",
            style: .destructive,
            handler: { _ in handler() }
        ))

        addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
    }
}
