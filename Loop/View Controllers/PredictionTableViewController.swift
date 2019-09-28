//
//  PredictionTableViewController.swift
//  Loop
//
//  Created by Nate Racklyeft on 9/3/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import HealthKit
import LoopCore
import LoopKit
import LoopKitUI
import LoopUI
import UIKit


private extension RefreshContext {
    static let all: Set<RefreshContext> = [.glucose, .targets]
}


class PredictionTableViewController: ChartsTableViewController, IdentifiableClass {

    override func viewDidLoad() {
        super.viewDidLoad()

        tableView.rowHeight = UITableView.automaticDimension
        tableView.cellLayoutMarginsFollowReadableWidth = true
        
        tableView.register(SwitchTableViewCell.self, forCellReuseIdentifier: SwitchTableViewCell.className)

        glucoseChart.glucoseDisplayRange = HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 60)...HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 200)

        let notificationCenter = NotificationCenter.default

        notificationObservers += [
            notificationCenter.addObserver(forName: .LoopDataUpdated, object: deviceManager.loopManager, queue: nil) { [weak self] note in
                let context = note.userInfo?[LoopDataManager.LoopUpdateContextKey] as! LoopDataManager.LoopUpdateContext.RawValue
                DispatchQueue.main.async {
                    switch LoopDataManager.LoopUpdateContext(rawValue: context) {
                    case .preferences?:
                        self?.refreshContext.formUnion([.status, .targets])
                    case .glucose?:
                        self?.refreshContext.update(with: .glucose)
                    default:
                        break
                    }

                    self?.reloadData(animated: true)
                }
            }
        ]
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()

        if !visible {
            refreshContext = RefreshContext.all
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        refreshContext.update(with: .size(size))

        super.viewWillTransition(to: size, with: coordinator)
    }

    // MARK: - State

    private var retrospectiveGlucoseDiscrepancies: [GlucoseChange]?

    private var totalRetrospectiveCorrection: HKQuantity?

    private var refreshContext = RefreshContext.all

    private var chartStartDate: Date {
        get {
            return charts.startDate
        }
        set {
            if newValue != chartStartDate {
                refreshContext = RefreshContext.all
            }

            charts.startDate = newValue
        }
    }

    let glucoseChart = PredictedGlucoseChart()

    override func createChartsManager() -> ChartsManager {
        return ChartsManager(colors: .default, settings: .default, charts: [glucoseChart], traitCollection: traitCollection)
    }

    override func glucoseUnitDidChange() {
        refreshContext = RefreshContext.all
    }

    override func reloadData(animated: Bool = false) {
        guard active && visible && !refreshContext.isEmpty else { return }

        refreshContext.remove(.size(.zero))
        let calendar = Calendar.current
        var components = DateComponents()
        components.minute = 0
        let date = Date(timeIntervalSinceNow: -TimeInterval(hours: 1))
        chartStartDate = calendar.nextDate(after: date, matching: components, matchingPolicy: .strict, direction: .backward) ?? date

        let reloadGroup = DispatchGroup()
        var glucoseValues: [StoredGlucoseSample]?
        var totalRetrospectiveCorrection: HKQuantity?

        if self.refreshContext.remove(.glucose) != nil {
            reloadGroup.enter()
            self.deviceManager.loopManager.glucoseStore.getCachedGlucoseSamples(start: self.chartStartDate) { (values) -> Void in
                glucoseValues = values
                reloadGroup.leave()
            }
        }

        // For now, do this every time
        _ = self.refreshContext.remove(.status)
        reloadGroup.enter()
        self.deviceManager.loopManager.getLoopState { (manager, state) in
            self.retrospectiveGlucoseDiscrepancies = state.retrospectiveGlucoseDiscrepancies
            totalRetrospectiveCorrection = state.totalRetrospectiveCorrection
            self.glucoseChart.setPredictedGlucoseValues(state.predictedGlucose ?? [])

            do {
                let glucose = try state.predictGlucose(using: self.selectedInputs)
                self.glucoseChart.setAlternatePredictedGlucoseValues(glucose)
            } catch {
                self.refreshContext.update(with: .status)
                self.glucoseChart.setAlternatePredictedGlucoseValues([])
            }

            if let lastPoint = self.glucoseChart.alternatePredictedGlucosePoints?.last?.y {
                self.eventualGlucoseDescription = String(describing: lastPoint)
            } else {
                self.eventualGlucoseDescription = nil
            }

            if self.refreshContext.remove(.targets) != nil {
                self.glucoseChart.targetGlucoseSchedule = manager.settings.glucoseTargetRangeSchedule
            }

            reloadGroup.leave()
        }

        reloadGroup.notify(queue: .main) {
            if let glucoseValues = glucoseValues {
                self.glucoseChart.setGlucoseValues(glucoseValues)
            }
            self.charts.invalidateChart(atIndex: 0)

            if let totalRetrospectiveCorrection = totalRetrospectiveCorrection {
                self.totalRetrospectiveCorrection = totalRetrospectiveCorrection
            }

            self.charts.prerender()

            self.tableView.beginUpdates()
            for cell in self.tableView.visibleCells {
                switch cell {
                case let cell as ChartTableViewCell:
                    cell.reloadChart()

                    if let indexPath = self.tableView.indexPath(for: cell) {
                        self.tableView(self.tableView, updateTitleFor: cell, at: indexPath)
                    }
                case let cell as PredictionInputEffectTableViewCell:
                    if let indexPath = self.tableView.indexPath(for: cell) {
                        self.tableView(self.tableView, updateTextFor: cell, at: indexPath)
                    }
                default:
                    break
                }
            }
            self.tableView.endUpdates()
        }
    }

    // MARK: - UITableViewDataSource

    private enum Section: Int, CaseIterable {
        case charts
        case inputs
        case settings
        
        static let count = 3
    }

    fileprivate enum SettingsRow: Int, CaseCountable {
        case integralRetrospectiveCorrection

        static let count = 1
    }

    private var eventualGlucoseDescription: String?

    private var availableInputs: [PredictionInputEffect] = [.carbs, .insulin, .momentum, .retrospection]

    private var selectedInputs = PredictionInputEffect.all

    override func numberOfSections(in tableView: UITableView) -> Int {
        return Section.allCases.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .charts:
            return 1
        case .inputs:
            return availableInputs.count
        case .settings:
            return SettingsRow.count
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

            self.tableView(tableView, updateTitleFor: cell, at: indexPath)
            cell.titleLabel?.textColor = UIColor.secondaryLabelColor
            cell.selectionStyle = .none

            cell.addGestureRecognizer(charts.gestureRecognizer!)

            return cell
        case .inputs:
            let cell = tableView.dequeueReusableCell(withIdentifier: PredictionInputEffectTableViewCell.className, for: indexPath) as! PredictionInputEffectTableViewCell
            self.tableView(tableView, updateTextFor: cell, at: indexPath)
            return cell
        case .settings:
            let switchCell = tableView.dequeueReusableCell(withIdentifier: SwitchTableViewCell.className, for: indexPath) as! SwitchTableViewCell

            switch SettingsRow(rawValue: indexPath.row)! {
            case .integralRetrospectiveCorrection:
                switchCell.textLabel?.text = NSLocalizedString("Integral Retrospective Correction", comment: "Title of the switch which toggles integral retrospective correction effects")
                // switchCell.detailTextLabel?.text = NSLocalizedString("Respond more aggressively to persistent discrepancies between observed glucose movement and predictions based on carbohydrate and insulin models.", comment: "The description of the switch which toggles integral retrospective correction effects")
                switchCell.switch?.isOn = deviceManager.loopManager.settings.integralRetrospectiveCorrectionEnabled
                switchCell.switch?.addTarget(self, action: #selector(integralRetrospectiveCorrectionSwitchChanged(_:)), for: .valueChanged)

                switchCell.contentView.layoutMargins.left = tableView.separatorInset.left
            }

            return switchCell
        }
    }

    private func tableView(_ tableView: UITableView, updateTitleFor cell: ChartTableViewCell, at indexPath: IndexPath) {
        guard case .charts? = Section(rawValue: indexPath.section) else {
            return
        }

        if let eventualGlucose = eventualGlucoseDescription {
            cell.titleLabel?.text = String(format: NSLocalizedString("Eventually %@", comment: "The subtitle format describing eventual glucose. (1: localized glucose value description)"), eventualGlucose)
        } else {
            cell.titleLabel?.text = SettingsTableViewCell.NoValueString
        }
    }

    private func tableView(_ tableView: UITableView, updateTextFor cell: PredictionInputEffectTableViewCell, at indexPath: IndexPath) {
        guard case .inputs? = Section(rawValue: indexPath.section) else {
            return
        }

        let input = availableInputs[indexPath.row]

        cell.titleLabel?.text = input.localizedTitle
        cell.accessoryType = selectedInputs.contains(input) ? .checkmark : .none

        var subtitleText = input.localizedDescription(forGlucoseUnit: glucoseChart.glucoseUnit) ?? ""

        if input == .retrospection,
            let lastDiscrepancy = retrospectiveGlucoseDiscrepancies?.last,
            let currentGlucose = self.deviceManager.loopManager.glucoseStore.latestGlucose
        {
            let formatter = QuantityFormatter()
            formatter.setPreferredNumberFormatter(for: glucoseChart.glucoseUnit)
            let predicted = HKQuantity(unit: glucoseChart.glucoseUnit, doubleValue: currentGlucose.quantity.doubleValue(for: glucoseChart.glucoseUnit) - lastDiscrepancy.quantity.doubleValue(for: glucoseChart.glucoseUnit))
            var values = [predicted, currentGlucose.quantity].map { formatter.string(from: $0, for: glucoseChart.glucoseUnit) ?? "?" }
            formatter.numberFormatter.positivePrefix = formatter.numberFormatter.plusSign
            values.append(formatter.string(from: lastDiscrepancy.quantity, for: glucoseChart.glucoseUnit) ?? "?")

            let retro = String(
                format: NSLocalizedString("prediction-description-retrospective-correction", comment: "Format string describing retrospective glucose prediction comparison. (1: Predicted glucose)(2: Actual glucose)(3: difference)"),
                values[0], values[1], values[2]
            )
            if !deviceManager.loopManager.settings.integralRetrospectiveCorrectionEnabled {
                // Standard retrospective correction
                subtitleText = String(format: "%@\n%@", subtitleText, retro)
            } else {
                // Integral retrospective correction
                var integralEffectDisplay = "?"
                var totalEffectDisplay = "?"
                if let totalEffect = self.totalRetrospectiveCorrection {
                    let integralEffectValue = totalEffect.doubleValue(for: glucoseChart.glucoseUnit) - lastDiscrepancy.quantity.doubleValue(for: glucoseChart.glucoseUnit)
                    let integralEffect = HKQuantity(unit: glucoseChart.glucoseUnit, doubleValue: integralEffectValue)
                    integralEffectDisplay = formatter.string(from: integralEffect, for: glucoseChart.glucoseUnit) ?? "?"
                    totalEffectDisplay = formatter.string(from: totalEffect, for: glucoseChart.glucoseUnit) ?? "?"
                }
                let integralRetro = String(
                    format: NSLocalizedString("prediction-description-integral-retrospective-correction", comment: "Format string describing integral retrospective correction. (1: Integral glucose effect)(2: Total glucose effect)"),
                    integralEffectDisplay, totalEffectDisplay
                )
                subtitleText = String(format: "%@\n%@", retro, integralRetro)
            }
        }

        cell.subtitleLabel?.text = subtitleText
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
        case .inputs:
            return 60
        case .settings:
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

    @objc private func integralRetrospectiveCorrectionSwitchChanged(_ sender: UISwitch) {
        deviceManager.loopManager.settings.integralRetrospectiveCorrectionEnabled = sender.isOn
    }
}
