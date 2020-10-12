//
//  InsulinModelSettingsViewController.swift
//  Loop
//
//  Copyright © 2017 LoopKit Authors. All rights reserved.
//

import UIKit
import HealthKit
import LoopCore
import LoopKit
import LoopUI


protocol InsulinModelSettingsViewControllerDelegate: class {
    func insulinModelSettingsViewControllerDidChangeValue(_ controller: InsulinModelSettingsViewController)
}


class InsulinModelSettingsViewController: ChartsTableViewController, IdentifiableClass {

    var glucoseUnit: HKUnit {
        get {
            return insulinModelChart.glucoseUnit
        }
        set {
            insulinModelChart.glucoseUnit = newValue

            refreshContext = true
            if visible && active {
                reloadData()
            }
        }
    }

    weak var delegate: InsulinModelSettingsViewControllerDelegate?

    private var initialInsulinModel: InsulinModel?

    /// The currently-selected model.
    var insulinModel: InsulinModel? {
        didSet {
            if let newValue = insulinModel as? WalshInsulinModel {
                allModels[walshModelIndex] = newValue
            }

            refreshContext = true
            reloadData()
        }
    }

    override func glucoseUnitDidChange() {
        refreshContext = true
    }

    /// The sensitivity (in glucose units) to use for demonstrating the model
    var insulinSensitivitySchedule = InsulinSensitivitySchedule(unit: .milligramsPerDeciliter, dailyItems: [RepeatingScheduleValue<Double>(startTime: 0, value: 40)])!

    fileprivate let walshModelIndex = 0

    private var allModels: [InsulinModel] = [
        WalshInsulinModel(actionDuration: .hours(6)),
        ExponentialInsulinModelPreset.humalogNovologAdult,
        ExponentialInsulinModelPreset.humalogNovologChild,
        ExponentialInsulinModelPreset.fiasp,
        ExponentialInsulinModelPreset.lyumjev,
    ]

    private var selectedModelIndex: Int? {
        switch insulinModel {
        case .none:
            return nil
        case is WalshInsulinModel:
            return walshModelIndex
        case let selectedModel as ExponentialInsulinModelPreset:
            for index in 1..<allModels.count {
                if selectedModel == (allModels[index] as! ExponentialInsulinModelPreset) {
                    return index
                }
            }
        default:
            assertionFailure("Unknown insulin model: \(String(describing: insulinModel))")
        }

        return nil
    }

    private var refreshContext = true

    /// The range of durations considered valid for Walsh models
    fileprivate let validDuration = (min: TimeInterval(hours: 2), max: TimeInterval(hours: 8))

    fileprivate lazy var durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.collapsesLargestUnit = true
        formatter.unitsStyle = .short
        formatter.allowsFractionalUnits = true
        formatter.allowedUnits = [.hour, .minute]
        return formatter
    }()

    // MARK: - UIViewController

    @IBOutlet fileprivate var durationPicker: UIDatePicker!

    override func viewDidLoad() {
        super.viewDidLoad()

        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 91
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        // Record the configured insulinModel for change tracking
        initialInsulinModel = insulinModel
    }

    override func viewWillDisappear(_ animated: Bool) {
        // Notify observers if the model changed since viewDidAppear
        switch (initialInsulinModel, insulinModel) {
        case let (lhs, rhs) as (WalshInsulinModel, WalshInsulinModel):
            if lhs != rhs {
                delegate?.insulinModelSettingsViewControllerDidChangeValue(self)
            }
        case let (lhs, rhs) as (ExponentialInsulinModelPreset, ExponentialInsulinModelPreset):
            if lhs != rhs {
                delegate?.insulinModelSettingsViewControllerDidChangeValue(self)
            }
        default:
            delegate?.insulinModelSettingsViewControllerDidChangeValue(self)
        }

        super.viewWillDisappear(animated)
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        refreshContext = true

        super.viewWillTransition(to: size, with: coordinator)
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()

        refreshContext = true
    }

    // MARK: - ChartsTableViewController

    private let insulinModelChart = InsulinModelChart()

    override func createChartsManager() -> ChartsManager {
        return ChartsManager(colors: .default, settings: .default, charts: [insulinModelChart], traitCollection: traitCollection)
    }

    override func reloadData(animated: Bool = true) {
        if active && visible && refreshContext {
            refreshContext = false
            charts.startDate = Calendar.current.nextDate(after: Date(), matching: DateComponents(minute: 0), matchingPolicy: .strict, direction: .backward) ?? Date()

            let bolus = DoseEntry(type: .bolus, startDate: charts.startDate, value: 1, unit: .units)
            let selectedModelIndex = self.selectedModelIndex

            let startingGlucoseValue = insulinSensitivitySchedule.quantity(at: charts.startDate).doubleValue(for: glucoseUnit) + glucoseUnit.glucoseExampleTargetValue
            let startingGlucoseQuantity = HKQuantity(unit: glucoseUnit, doubleValue: startingGlucoseValue)
            let endingGlucoseQuantity = HKQuantity(unit: glucoseUnit, doubleValue: glucoseUnit.glucoseExampleTargetValue)
            let startingGlucoseSample = HKQuantitySample(type: HKQuantityType.quantityType(forIdentifier: .bloodGlucose)!, quantity: startingGlucoseQuantity, start: charts.startDate, end: charts.startDate)

            insulinModelChart.glucoseDisplayRange = endingGlucoseQuantity...startingGlucoseQuantity

            var unselectedModelValues = [[GlucoseValue]]()

            for (index, model) in allModels.enumerated() {
                let effects = [bolus].glucoseEffects(insulinModel: model, insulinSensitivity: insulinSensitivitySchedule)
                let values = LoopMath.predictGlucose(startingAt: startingGlucoseSample, effects: effects)

                if selectedModelIndex == index {
                    insulinModelChart.setSelectedInsulinModelValues(values)
                } else {
                    unselectedModelValues.append(values)
                }
            }

            insulinModelChart.setUnselectedInsulinModelValues(unselectedModelValues)
            charts.invalidateChart(atIndex: 0)

            // Rendering
            charts.prerender()

            for case let cell as ChartTableViewCell in self.tableView.visibleCells {
                cell.reloadChart()
            }
        }
    }

    // MARK: - UITableViewDataSource

    fileprivate enum Section: Int {
        case charts
        case models

        static let count = 2
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        return Section.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .charts:
            return 1
        case .models:
            return allModels.count
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch Section(rawValue: indexPath.section)! {
        case .charts:
            let cell = tableView.dequeueReusableCell(withIdentifier: ChartTableViewCell.className, for: indexPath) as! ChartTableViewCell
            cell.contentView.layoutMargins.left = tableView.separatorInset.left
            cell.chartContentView.chartGenerator = { [weak self] (frame) in
                return self?.charts.chart(atIndex: 0, frame: frame)?.view
            }

            return cell
        case .models:
            let cell = tableView.dequeueReusableCell(withIdentifier: TitleSubtitleTextFieldTableViewCell.className, for: indexPath) as! TitleSubtitleTextFieldTableViewCell
            let isSelected = selectedModelIndex == indexPath.row
            cell.tintColor = isSelected ? nil : .clear
            cell.textField.isEnabled = isSelected

            switch allModels[indexPath.row] {
            case let model as WalshInsulinModel:
                configureCell(cell, duration: model.actionDuration)

                cell.titleLabel.text = model.title
                cell.subtitleLabel.text = model.subtitle
            case let model as ExponentialInsulinModelPreset:
                configureCell(cell, duration: nil)

                cell.titleLabel.text = model.title
                cell.subtitleLabel.text = model.subtitle
            case let model:
                assertionFailure("Unknown insulin model: \(model)")
            }

            return cell
        }
    }

    // MARK: - UITableViewDelegate

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard case .models? = Section(rawValue: indexPath.section) else {
            return
        }

        insulinModel = allModels[indexPath.row]
        let selectedIndex = selectedModelIndex

        for index in 0..<allModels.count {
            guard let cell = tableView.cellForRow(at: IndexPath(row: index, section: Section.models.rawValue)) as? TitleSubtitleTextFieldTableViewCell else {
                continue
            }

            let isSelected = selectedIndex == index
            cell.tintColor = isSelected ? nil : .clear

            let walshModel = allModels[index] as? WalshInsulinModel
            configureCell(cell, duration: walshModel?.actionDuration)
            cell.textField.isEnabled = isSelected

            if walshModel != nil && isSelected && !cell.textField.isFirstResponder {
                cell.textField.becomeFirstResponder()
            } else {
                cell.textField.resignFirstResponder()
            }
        }

        tableView.deselectRow(at: indexPath, animated: true)
    }
}


// MARK: - Duration editing
fileprivate extension InsulinModelSettingsViewController {
    func configureCell(_ cell: TitleSubtitleTextFieldTableViewCell, duration: TimeInterval?) {
        if let duration = duration {
            cell.textField.isHidden = false
            cell.textField.delegate = self
            cell.textField.tintColor = .clear  // Makes the cursor invisible
            cell.textField.inputView = durationPicker
            cell.textField.text = durationFormatter.string(from: duration)

            self.durationPicker.countDownDuration = duration
            durationPicker.addTarget(self, action: #selector(durationPickerChanged(_:)), for: .valueChanged)
        } else {
            cell.textField.isHidden = true
            cell.textField.delegate = nil
            cell.textField.tintColor = nil
            cell.textField.inputView = nil
            cell.textField.text = nil
        }
    }

    @IBAction func durationPickerChanged(_ sender: UIDatePicker) {
        guard let cell = tableView.cellForRow(at: IndexPath(row: walshModelIndex, section: Section.models.rawValue)) as? TitleSubtitleTextFieldTableViewCell
        else {
            return
        }

        sender.countDownDuration = min(validDuration.max, max(validDuration.min, sender.countDownDuration))
        cell.textField.text = durationFormatter.string(from: sender.countDownDuration)
        cell.contentView.setNeedsLayout()

        insulinModel = WalshInsulinModel(actionDuration: sender.countDownDuration)
    }
}


extension InsulinModelSettingsViewController: UITextFieldDelegate {
    func textFieldDidBeginEditing(_ textField: UITextField) {
        // Set duration again as a workaround for valueChanged actions not being triggered
        guard let model = insulinModel as? WalshInsulinModel else {
            return
        }

        DispatchQueue.main.async {
            self.durationPicker.countDownDuration = model.actionDuration
        }
    }
}


fileprivate extension HKUnit {
    /// An example value for the "ideal" target
    var glucoseExampleTargetValue: Double {
        if self == .milligramsPerDeciliter {
            return 100
        } else {
            return 5.5
        }
    }
}
