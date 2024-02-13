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
import os.log
import LoopAlgorithm


private extension RefreshContext {
    static let all: Set<RefreshContext> = [.glucose, .targets]
}


class PredictionTableViewController: LoopChartsTableViewController, IdentifiableClass {
    private let log = OSLog(category: "PredictionTableViewController")

    var settingsManager: SettingsManager!
    var loopDataManager: LoopDataManager!

    override func viewDidLoad() {
        super.viewDidLoad()

        tableView.rowHeight = UITableView.automaticDimension
        tableView.cellLayoutMarginsFollowReadableWidth = true

        glucoseChart.glucoseDisplayRange = LoopConstants.glucoseChartDefaultDisplayRangeWide

        let notificationCenter = NotificationCenter.default

        notificationObservers += [
            notificationCenter.addObserver(forName: .LoopDataUpdated, object: nil, queue: nil) { [weak self] note in
                let context = note.userInfo?[LoopDataManager.LoopUpdateContextKey] as! LoopUpdateContext.RawValue
                DispatchQueue.main.async {
                    switch LoopUpdateContext(rawValue: context) {
                    case .preferences?:
                        self?.refreshContext.formUnion([.status, .targets])
                    case .glucose?:
                        self?.refreshContext.update(with: .glucose)
                    default:
                        break
                    }

                    Task {
                        await self?.reloadData(animated: true)
                    }
                }
            },
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

    let glucoseChart = PredictedGlucoseChart(yAxisStepSizeMGDLOverride: FeatureFlags.predictedGlucoseChartClampEnabled ? 40 : nil)

    override func createChartsManager() -> ChartsManager {
        return ChartsManager(colors: .primary, settings: .default, charts: [glucoseChart], traitCollection: traitCollection)
    }

    override func glucoseUnitDidChange() {
        self.log.debug("[reloadData] for HealthKit unit preference change")
        refreshContext = RefreshContext.all
    }

    override func reloadData(animated: Bool = false) async {
        guard active && visible && !refreshContext.isEmpty else { return }

        refreshContext.remove(.size(.zero))
        let calendar = Calendar.current
        var components = DateComponents()
        components.minute = 0
        let date = Date(timeIntervalSinceNow: -TimeInterval(hours: 1))
        chartStartDate = calendar.nextDate(after: date, matching: components, matchingPolicy: .strict, direction: .backward) ?? date

        var glucoseSamples: [StoredGlucoseSample]?
        var totalRetrospectiveCorrection: HKQuantity?

        // For now, do this every time
        _ = self.refreshContext.remove(.status)
        let (algoInput, algoOutput) = await loopDataManager.algorithmDisplayState.asTuple

        if self.refreshContext.remove(.glucose) != nil, let algoInput {
            glucoseSamples = algoInput.glucoseHistory.filterDateRange(self.chartStartDate, nil)
        }

        self.retrospectiveGlucoseDiscrepancies = algoOutput?.effects.retrospectiveGlucoseDiscrepancies
        totalRetrospectiveCorrection = algoOutput?.effects.totalRetrospectiveCorrectionEffect

        self.glucoseChart.setPredictedGlucoseValues(algoOutput?.predictedGlucose ?? [])

        do {
            let glucose = try algoInput?.predictGlucose(effectsOptions: self.selectedInputs.algorithmEffectOptions) ?? []
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
            self.glucoseChart.targetGlucoseSchedule = self.settingsManager.settings.glucoseTargetRangeSchedule
        }

        if let glucoseSamples = glucoseSamples {
            self.glucoseChart.setGlucoseValues(glucoseSamples)
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

    // MARK: - UITableViewDataSource

    private enum Section: Int, CaseIterable {
        case charts
        case inputs
    }

    private var eventualGlucoseDescription: String?

    private var availableInputs: [PredictionInputEffect] = [.carbs, .insulin, .momentum, .retrospection, .suspend]

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
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch Section(rawValue: indexPath.section)! {
        case .charts:
            let cell = tableView.dequeueReusableCell(withIdentifier: ChartTableViewCell.className, for: indexPath) as! ChartTableViewCell
            cell.contentView.layoutMargins.left = tableView.separatorInset.left
            cell.setChartGenerator(generator: { [weak self] (frame) in
                return self?.charts.chart(atIndex: 0, frame: frame)?.view
            })

            self.tableView(tableView, updateTitleFor: cell, at: indexPath)
            cell.setTitleTextColor(color: UIColor.secondaryLabel)
            cell.selectionStyle = .none

            cell.addGestureRecognizer(charts.gestureRecognizer!)

            return cell
        case .inputs:
            let cell = tableView.dequeueReusableCell(withIdentifier: PredictionInputEffectTableViewCell.className, for: indexPath) as! PredictionInputEffectTableViewCell
            self.tableView(tableView, updateTextFor: cell, at: indexPath)
            return cell
        }
    }

    private func tableView(_ tableView: UITableView, updateTitleFor cell: ChartTableViewCell, at indexPath: IndexPath) {
        guard case .charts? = Section(rawValue: indexPath.section) else {
            return
        }

        if let eventualGlucose = eventualGlucoseDescription {
            cell.setTitleLabelText(label: String(format: NSLocalizedString("Eventually %@", comment: "The subtitle format describing eventual glucose. (1: localized glucose value description)"), eventualGlucose))
        } else {
            cell.setTitleLabelText(label: SettingsTableViewCell.NoValueString)
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
            let currentGlucose = loopDataManager.latestGlucose
        {
            let formatter = QuantityFormatter(for: glucoseChart.glucoseUnit)
            let predicted = HKQuantity(unit: glucoseChart.glucoseUnit, doubleValue: currentGlucose.quantity.doubleValue(for: glucoseChart.glucoseUnit) - lastDiscrepancy.quantity.doubleValue(for: glucoseChart.glucoseUnit))
            var values = [predicted, currentGlucose.quantity].map { formatter.string(from: $0) ?? "?" }
            formatter.numberFormatter.positivePrefix = formatter.numberFormatter.plusSign
            values.append(formatter.string(from: lastDiscrepancy.quantity) ?? "?")

            let retro = String(
                format: NSLocalizedString("Predicted: %1$@\nActual: %2$@ (%3$@)", comment: "Format string describing retrospective glucose prediction comparison. (1: Predicted glucose)(2: Actual glucose)(3: difference)"),
                values[0], values[1], values[2]
            )
            let isIntegralRetrospectiveCorrectionEnabled = UserDefaults.standard.integralRetrospectiveCorrectionEnabled
            
            if isIntegralRetrospectiveCorrectionEnabled {
                var integralEffectDisplay = "?"
                var totalEffectDisplay = "?"
                if let totalEffect = self.totalRetrospectiveCorrection {
                    let integralEffectValue = totalEffect.doubleValue(for: glucoseChart.glucoseUnit) - lastDiscrepancy.quantity.doubleValue(for: glucoseChart.glucoseUnit)
                    let integralEffect = HKQuantity(unit: glucoseChart.glucoseUnit, doubleValue: integralEffectValue)
                    integralEffectDisplay = formatter.string(from: integralEffect) ?? "?"
                    totalEffectDisplay = formatter.string(from: totalEffect) ?? "?"
                }
                let integralRetro = String(
                    format: NSLocalizedString("prediction-description-integral-retrospective-correction", comment: "Format string describing integral retrospective correction. (1: Integral glucose effect)(2: Total glucose effect)"),
                    integralEffectDisplay, totalEffectDisplay
                )
                subtitleText = String(format: "%@\n%@", retro, integralRetro)
            } else {
                subtitleText = String(format: "%@\n%@", subtitleText, retro)
            }
        
        }

        cell.subtitleLabel?.text = subtitleText
    }

    // MARK: - UITableViewDelegate

    override func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        switch Section(rawValue: indexPath.section)! {
        case .charts:
            return 275
        case .inputs:
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

        Task {
            await reloadData()
        }
    }
}
