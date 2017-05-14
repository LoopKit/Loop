//
//  PredictionTableViewController.swift
//  Loop
//
//  Created by Nate Racklyeft on 9/3/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import UIKit
import HealthKit
import LoopKit
import LoopUI


private extension RefreshContext {
    static let all: RefreshContext = [.glucose, .targets]
}


class PredictionTableViewController: ChartsTableViewController, IdentifiableClass {

    override func viewDidLoad() {
        super.viewDidLoad()

        tableView.cellLayoutMarginsFollowReadableWidth = true

        charts.glucoseDisplayRange = (
            min: HKQuantity(unit: HKUnit.milligramsPerDeciliter(), doubleValue: 60),
            max: HKQuantity(unit: HKUnit.milligramsPerDeciliter(), doubleValue: 200)
        )

        let notificationCenter = NotificationCenter.default

        notificationObservers += [
            notificationCenter.addObserver(forName: .LoopDataUpdated, object: deviceManager.loopManager, queue: nil) { note in
                let context = note.userInfo?[LoopDataManager.LoopUpdateContextKey] as! LoopDataManager.LoopUpdateContext.RawValue
                DispatchQueue.main.async {
                    switch LoopDataManager.LoopUpdateContext(rawValue: context) {
                    case .preferences?:
                        self.refreshContext.update(with: [.status, .targets])
                    case .glucose?:
                        self.refreshContext.update(with: .glucose)
                    default:
                        break
                    }

                    self.reloadData(animated: true)
                }
            }
        ]
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()

        if !visible {
            refreshContext = .all
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        refreshContext.update(with: .status)

        super.viewWillTransition(to: size, with: coordinator)
    }

    // MARK: - State

    private var retrospectivePredictedGlucose: [GlucoseValue]?

    private var refreshContext = RefreshContext.all

    private var chartStartDate: Date {
        get {
            return charts.startDate
        }
        set {
            if newValue != chartStartDate {
                refreshContext = .all
            }

            charts.startDate = newValue
        }
    }

    override func reloadData(animated: Bool = false, to size: CGSize? = nil) {
        guard active && visible && !refreshContext.isEmpty else { return }

        let calendar = Calendar.current
        var components = DateComponents()
        components.minute = 0
        let date = Date(timeIntervalSinceNow: -TimeInterval(hours: 1))
        chartStartDate = calendar.nextDate(after: date, matching: components, matchingPolicy: .strict, direction: .backward) ?? date

        let reloadGroup = DispatchGroup()

        reloadGroup.enter()
        deviceManager.loopManager.glucoseStore.preferredUnit { (unit, error) in
            if let unit = unit {
                self.charts.glucoseUnit = unit
            }

            if self.refreshContext.remove(.glucose) != nil {
                reloadGroup.enter()
                self.deviceManager.loopManager.glucoseStore.getGlucoseValues(start: self.chartStartDate) { (result) -> Void in
                    switch result {
                    case .failure(let error):
                        self.deviceManager.logger.addError(error, fromSource: "GlucoseStore")
                        self.refreshContext.update(with: .glucose)
                        self.charts.setGlucoseValues([])
                    case .success(let values):
                        self.charts.setGlucoseValues(values)
                    }

                    reloadGroup.leave()
                }
            }

            // For now, do this every time
            _ = self.refreshContext.remove(.status)
            reloadGroup.enter()
            self.deviceManager.loopManager.getLoopState { (manager, state) in
                self.retrospectivePredictedGlucose = state.retrospectivePredictedGlucose
                self.charts.setPredictedGlucoseValues(state.predictedGlucose ?? [])

                do {
                    let glucose = try state.predictGlucose(using: self.selectedInputs)
                    self.charts.setAlternatePredictedGlucoseValues(glucose)
                } catch {
                    self.refreshContext.update(with: .status)
                    self.charts.setAlternatePredictedGlucoseValues([])
                }

                if let lastPoint = self.charts.alternatePredictedGlucosePoints?.last?.y {
                    self.eventualGlucoseDescription = String(describing: lastPoint)
                } else {
                    self.eventualGlucoseDescription = nil
                }

                if self.refreshContext.remove(.targets) != nil {
                    if let schedule = manager.settings.glucoseTargetRangeSchedule {
                        self.charts.targetPointsCalculator = GlucoseRangeScheduleCalculator(schedule)
                    } else {
                        self.charts.targetPointsCalculator = nil
                    }
                }

                reloadGroup.leave()
            }

            reloadGroup.leave()
        }

        reloadGroup.notify(queue: .main) {
            self.charts.prerender()

            for case let cell as ChartTableViewCell in self.tableView.visibleCells {
                cell.reloadChart()

                if let indexPath = self.tableView.indexPath(for: cell) {
                    self.tableView(self.tableView, updateTitleFor: cell, at: indexPath)
                }
            }
        }
    }

    // MARK: - UITableViewDataSource

    private enum Section: Int {
        case charts
        case inputs
        case settings

        static let count = 3
    }

    private var eventualGlucoseDescription: String?

    private var availableInputs: [PredictionInputEffect] = [.carbs, .insulin, .momentum, .retrospection]

    private var selectedInputs = PredictionInputEffect.all

    override func numberOfSections(in tableView: UITableView) -> Int {
        return Section.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .charts:
            return 1
        case .inputs:
            return availableInputs.count
        case .settings:
            return 1
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch Section(rawValue: indexPath.section)! {
        case .charts:
            let cell = tableView.dequeueReusableCell(withIdentifier: ChartTableViewCell.className, for: indexPath) as! ChartTableViewCell
            cell.titleLabel?.textColor = UIColor.secondaryLabelColor
            cell.contentView.layoutMargins.left = tableView.separatorInset.left
            cell.chartContentView.chartGenerator = { [weak self] (frame) in
                return self?.charts.glucoseChartWithFrame(frame)?.view
            }

            self.tableView(tableView, updateTitleFor: cell, at: indexPath)
            cell.titleLabel?.textColor = UIColor.secondaryLabelColor
            cell.selectionStyle = .none

            cell.addGestureRecognizer(charts.gestureRecognizer!)

            return cell
        case .inputs:
            let cell = tableView.dequeueReusableCell(withIdentifier: PredictionInputEffectTableViewCell.className, for: indexPath) as! PredictionInputEffectTableViewCell

            let input = availableInputs[indexPath.row]

            cell.titleLabel?.text = input.localizedTitle
            cell.accessoryType = selectedInputs.contains(input) ? .checkmark : .none
            cell.enabled = input != .retrospection || deviceManager.loopManager.settings.retrospectiveCorrectionEnabled

            var subtitleText = input.localizedDescription(forGlucoseUnit: charts.glucoseUnit) ?? ""

            if input == .retrospection,
                let startGlucose = retrospectivePredictedGlucose?.first,
                let endGlucose = retrospectivePredictedGlucose?.last,
                let currentGlucose = self.deviceManager.loopManager.glucoseStore.latestGlucose
            {
                let formatter = NumberFormatter.glucoseFormatter(for: charts.glucoseUnit)
                let values = [startGlucose, endGlucose, currentGlucose].map { formatter.string(from: NSNumber(value: $0.quantity.doubleValue(for: charts.glucoseUnit))) ?? "?" }

                let retro = String(
                    format: NSLocalizedString("Last comparison: %1$@ → %2$@ vs %3$@", comment: "Format string describing retrospective glucose prediction comparison. (1: Previous glucose)(2: Predicted glucose)(3: Actual glucose)"),
                    values[0], values[1], values[2]
                )

                subtitleText = String(format: "%@\n%@", subtitleText, retro)
            }

            cell.subtitleLabel?.text = subtitleText

            cell.contentView.layoutMargins.left = tableView.separatorInset.left

            return cell
        case .settings:
            let cell = tableView.dequeueReusableCell(withIdentifier: SwitchTableViewCell.className, for: indexPath) as! SwitchTableViewCell

            cell.titleLabel?.text = NSLocalizedString("Enable Retrospective Correction", comment: "Title of the switch which toggles retrospective correction effects")
            cell.subtitleLabel?.text = NSLocalizedString("This will more aggresively increase or decrease basal delivery when glucose movement doesn't match the carbohydrate and insulin-based model.", comment: "The description of the switch which toggles retrospective correction effects")
            cell.`switch`?.isOn = deviceManager.loopManager.settings.retrospectiveCorrectionEnabled
            cell.`switch`?.addTarget(self, action: #selector(retrospectiveCorrectionSwitchChanged(_:)), for: .valueChanged)

            cell.contentView.layoutMargins.left = tableView.separatorInset.left

            return cell
        }
    }

    private func tableView(_ tableView: UITableView, updateTitleFor cell: ChartTableViewCell, at indexPath: IndexPath) {
        switch Section(rawValue: indexPath.section)! {
        case .charts:
            if let eventualGlucose = eventualGlucoseDescription {
                cell.titleLabel?.text = String(format: NSLocalizedString("Eventually %@", comment: "The subtitle format describing eventual glucose. (1: localized glucose value description)"), eventualGlucose)
            } else {
                cell.titleLabel?.text = "–"
            }
        default:
            break
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .settings:
            return NSLocalizedString("Algorithm Settings", comment: "The title of the section containing algorithm settings")
        default:
            return nil
        }
    }

    // MARK: - UITableViewDelegate

    override func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        switch Section(rawValue: indexPath.section)! {
        case .charts:
            return 275
        case .inputs, .settings:
            return 60
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard Section(rawValue: indexPath.section) == .inputs else { return }

        let input = availableInputs[indexPath.row]
        let isSelected = selectedInputs.contains(input)

        if let cell = tableView.cellForRow(at: indexPath) {
            cell.accessoryType = !isSelected ? .checkmark : .none
        }

        selectedInputs.formSymmetricDifference(input)

        tableView.deselectRow(at: indexPath, animated: true)

        refreshContext.update(with: .status)
        reloadData()
    }

    // MARK: - Actions

    @objc private func retrospectiveCorrectionSwitchChanged(_ sender: UISwitch) {
        deviceManager.loopManager.settings.retrospectiveCorrectionEnabled = sender.isOn

        if  let row = availableInputs.index(where: { $0 == .retrospection }),
            let cell = tableView.cellForRow(at: IndexPath(row: row, section: Section.inputs.rawValue)) as? PredictionInputEffectTableViewCell
        {
            cell.enabled = self.deviceManager.loopManager.settings.retrospectiveCorrectionEnabled
        }
    }
}
