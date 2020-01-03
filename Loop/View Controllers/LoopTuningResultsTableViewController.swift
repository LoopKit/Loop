//
//  LoopTuningResultsTableViewController.swift
//  Loop
//
//  Created by marius eriksen on 12/16/19.
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import UIKit
import LoopKit
import LoopCore
import LoopKitUI
import HealthKit

class LoopTuningResultsTableViewController: SetupTableViewController {
    // XXX: replace with LoopTuningTunedParameters
    var basalRateSchedule: BasalRateSchedule!
    var carbRatioSchedule: CarbRatioSchedule!
    var sensitivitySchedule: InsulinSensitivitySchedule!
    
    var loopTuningDelegate: LoopTuningDelegate?

    // For user modifications:
    var allowedBasalRates: [Double]!
    var maximumScheduleItemCount: Int!
    var minimumTimeInterval: TimeInterval!
    
    var settings: LoopSettings!

    fileprivate lazy var valueNumberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()

        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2

        return formatter
    }()
    
    fileprivate enum ResultRow: Int, CaseCountable {
        case basalRate = 0
        case carbRatio
        case sensitivity
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        tableView.register(SettingsTableViewCell.self, forCellReuseIdentifier: SettingsTableViewCell.className)
        footerView.primaryButton.setTitle("Save", for: .normal)
    }
    
    override func continueButtonPressed(_ sender: Any) {
        footerView.primaryButton.isEnabled = false      // XXX
        // footerView.primaryButton.isIndicatingActivity = true
        navigationItem.rightBarButtonItem?.isEnabled = false   // disable "Cancel"; we can't do anything.
        loopTuningDelegate?.loopTuningCompleted(withParameters: LoopTuningTunedParameters(basalRateSchedule: basalRateSchedule, carbRatioSchedule: carbRatioSchedule, insulinSensitivitySchedule: sensitivitySchedule))
    }
    
    override func cancelButtonPressed(_: Any) {
        loopTuningDelegate?.loopTuningCanceled()
    }


    // MARK: - UITableViewDataSource
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard section == 0 else { return super.tableView(tableView, numberOfRowsInSection: section) }
        return ResultRow.count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard indexPath.section == 0 else { return super.tableView(tableView, cellForRowAt: indexPath) }
        
        let configCell = tableView.dequeueReusableCell(withIdentifier: SettingsTableViewCell.className, for: indexPath)

        switch ResultRow(rawValue: indexPath.row)! {
        case .basalRate:
            configCell.textLabel?.text = NSLocalizedString("Basal Rates", comment: "The title text for the basal rate schedule")
            configCell.detailTextLabel?.text = valueNumberFormatter.string(from: basalRateSchedule.total(), unit: "U")
        case .carbRatio:
            configCell.textLabel?.text = NSLocalizedString("Carb Ratios", comment: "The title text for the carb ratio schedule")
            let unit = carbRatioSchedule.unit
            let value = valueNumberFormatter.string(from: carbRatioSchedule.averageQuantity().doubleValue(for: unit)) ?? SettingsTableViewCell.NoValueString
            configCell.detailTextLabel?.text = String(format: NSLocalizedString("%1$@ %2$@/U", comment: "Format string for carb ratio average. (1: value)(2: carb unit)"), value, unit)
        case .sensitivity:
            configCell.textLabel?.text = NSLocalizedString("Insulin Sensitivities", comment: "The title text for the insulin sensitivity schedule")
            let unit = sensitivitySchedule.unit
            // Schedule is in mg/dL or mmol/L, but we display as mg/dL/U or mmol/L/U
            let average = sensitivitySchedule.averageQuantity().doubleValue(for: unit)
            let unitPerU = unit.unitDivided(by: .internationalUnit())
            let averageQuantity = HKQuantity(unit: unitPerU, doubleValue: average)
            let formatter = QuantityFormatter()
            formatter.setPreferredNumberFormatter(for: unit)
            configCell.detailTextLabel?.text = formatter.string(from: averageQuantity, for: unitPerU)
        }

        return configCell
    }

    override func tableView(_ tableView: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
        return true
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let sender = tableView.cellForRow(at: indexPath)
        switch ResultRow(rawValue: indexPath.row)! {
        case .basalRate:
            let vc = BasalScheduleTableViewController(allowedBasalRates: allowedBasalRates, maximumScheduleItemCount: maximumScheduleItemCount, minimumTimeInterval: minimumTimeInterval)
            vc.scheduleItems = basalRateSchedule.items
            vc.timeZone = basalRateSchedule.timeZone

            vc.title = NSLocalizedString("Basal Rates", comment: "The title of the basal rate profile screen")
            vc.delegate = self
            vc.syncSource = nil // TODO: set sync source on the the results table view controller instead, and sync on "save"

            show(vc, sender: sender)
        case .carbRatio:
            let scheduleVC = DailyQuantityScheduleTableViewController()

            scheduleVC.delegate = self
            scheduleVC.title = NSLocalizedString("Carb Ratios", comment: "The title of the carb ratios schedule screen")
            scheduleVC.unit = .gram()

            scheduleVC.timeZone = carbRatioSchedule.timeZone
            scheduleVC.scheduleItems = carbRatioSchedule.items
            scheduleVC.unit = carbRatioSchedule.unit
            show(scheduleVC, sender: sender)
        case .sensitivity:
            let unit = sensitivitySchedule.unit
            let allowedSensitivityValues = settings.allowedSensitivityValues(for: unit)
            let scheduleVC = InsulinSensitivityScheduleViewController(allowedValues: allowedSensitivityValues, unit: unit)

            scheduleVC.delegate = self
            scheduleVC.insulinSensitivityScheduleStorageDelegate = self
            scheduleVC.title = NSLocalizedString("Insulin Sensitivities", comment: "The title of the insulin sensitivities schedule screen")
            scheduleVC.schedule = sensitivitySchedule

            show(scheduleVC, sender: sender)
        }
    }
}

extension LoopTuningResultsTableViewController: DailyValueScheduleTableViewControllerDelegate {
    func dailyValueScheduleTableViewControllerWillFinishUpdating(_ controller: DailyValueScheduleTableViewController) {
        guard let indexPath = tableView.indexPathForSelectedRow else { return }

        switch ResultRow(rawValue: indexPath.row)! {
        case .basalRate:
            let basalVC = controller as! BasalScheduleTableViewController
            basalRateSchedule = BasalRateSchedule(dailyItems: basalVC.scheduleItems, timeZone: basalVC.timeZone)
        case let row:
            if let controller = controller as? DailyQuantityScheduleTableViewController {
                switch row {
                case .carbRatio:
                    carbRatioSchedule = CarbRatioSchedule(unit: controller.unit, dailyItems: controller.scheduleItems, timeZone: controller.timeZone)
                default:
                    break
                }
            }
        }
        
        tableView.reloadRows(at: [indexPath], with: .none)
    }
}

extension LoopTuningResultsTableViewController: InsulinSensitivityScheduleStorageDelegate {
    func saveSchedule(_ schedule: InsulinSensitivitySchedule, for viewController: InsulinSensitivityScheduleViewController, completion: @escaping (SaveInsulinSensitivityScheduleResult) -> Void) {
        sensitivitySchedule = schedule
        completion(.success)
        tableView.reloadRows(at: [IndexPath(row: ResultRow.sensitivity.rawValue, section: 0)], with: .none)
    }
}
