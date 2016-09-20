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


class PredictionTableViewController: UITableViewController, IdentifiableClass {

    override func viewDidLoad() {
        super.viewDidLoad()

        tableView.cellLayoutMarginsFollowReadableWidth = true

        let notificationCenter = NotificationCenter.default
        let mainQueue = OperationQueue.main
        let application = UIApplication.shared

        notificationObservers += [
            notificationCenter.addObserver(forName: .LoopDataUpdated, object: dataManager.loopManager, queue: nil) { note in
                guard let rawContext = note.userInfo?[LoopDataManager.LoopUpdateContextKey] as? Int, LoopDataManager.LoopUpdateContext(rawValue: rawContext) != .preferences else {
                    return
                }

                DispatchQueue.main.async {
                    self.needsRefresh = true
                    self.reloadData(animated: true)
                }
            },
            notificationCenter.addObserver(forName: .UIApplicationWillResignActive, object: application, queue: mainQueue) { _ in
                self.active = false
            },
            notificationCenter.addObserver(forName: .UIApplicationDidBecomeActive, object: application, queue: mainQueue) { _ in
                self.active = true
            }
        ]
    }

    deinit {
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        visible = true
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        AnalyticsManager.sharedManager.didDisplayStatusScreen()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        visible = false
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        if !visible {
            needsRefresh = true
        }
    }

    // MARK: - State

    // References to registered notification center observers
    private var notificationObservers: [Any] = []

    var dataManager: DeviceDataManager!

    private lazy var charts: StatusChartsManager = {
        let charts = StatusChartsManager()

        charts.glucoseDisplayRange = (
            min: HKQuantity(unit: HKUnit.milligramsPerDeciliterUnit(), doubleValue: 60),
            max: HKQuantity(unit: HKUnit.milligramsPerDeciliterUnit(), doubleValue: 200)
        )

        return charts
    }()

    private var retrospectivePredictedGlucose: [GlucoseValue]?

    private var active = true {
        didSet {
            reloadData()
        }
    }

    private var needsRefresh = true

    private var visible = false {
        didSet {
            reloadData()
        }
    }

    private var reloading = false

    private func reloadData(animated: Bool = false) {
        if active && visible && needsRefresh {
            needsRefresh = false
            reloading = true

            let calendar = Calendar.current
            var components = DateComponents()
            components.minute = 0
            let date = Date(timeIntervalSinceNow: -TimeInterval(hours: 1))
            charts.startDate = (calendar as NSCalendar).nextDate(after: date, matching: components, options: [.matchStrictly, .searchBackwards]) ?? date

            let reloadGroup = DispatchGroup()
            var glucoseUnit: HKUnit?

            if let glucoseStore = dataManager.glucoseStore {
                reloadGroup.enter()
                glucoseStore.getRecentGlucoseValues(startDate: charts.startDate) { (values, error) -> Void in
                    if let error = error {
                        self.dataManager.logger.addError(error, fromSource: "GlucoseStore")
                        self.needsRefresh = true
                        // TODO: Display error in the cell
                    } else {
                        self.charts.glucoseValues = values
                    }

                    reloadGroup.leave()
                }

                reloadGroup.enter()
                glucoseStore.preferredUnit { (unit, error) in
                    glucoseUnit = unit

                    reloadGroup.leave()
                }
            }

            reloadGroup.enter()
            dataManager.loopManager.getLoopStatus { (predictedGlucose, retrospectivePredictedGlucose, _, _, _, _, error) in
                if error != nil {
                    self.needsRefresh = true
                }

                self.retrospectivePredictedGlucose = retrospectivePredictedGlucose
                self.charts.predictedGlucoseValues = predictedGlucose ?? []

                reloadGroup.leave()
            }

            reloadGroup.enter()
            dataManager.loopManager.modelPredictedGlucose(using: selectedInputs.flatMap { $0.selected ? $0.input : nil }) { (predictedGlucose, error) in
                if error != nil {
                    self.needsRefresh = true
                }

                self.charts.alternatePredictedGlucoseValues = predictedGlucose ?? []

                reloadGroup.leave()
            }

            charts.glucoseTargetRangeSchedule = dataManager.glucoseTargetRangeSchedule

            reloadGroup.notify(queue: DispatchQueue.main) {
                if let unit = glucoseUnit {
                    self.charts.glucoseUnit = unit
                }
                
                self.charts.prerender()
                
                self.tableView.reloadSections(IndexSet(integersIn: NSMakeRange(Section.charts.rawValue, 1).toRange() ?? 0..<0),
                                              with: .none
                )
                
                self.reloading = false
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

    private lazy var selectedInputs: [(input: PredictionInputEffect, selected: Bool)] = [
        (.carbs, true), (.insulin, true), (.momentum, true), (.retrospection, true)
    ]

    override func numberOfSections(in tableView: UITableView) -> Int {
        return Section.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .charts:
            return 1
        case .inputs:
            return selectedInputs.count
        case .settings:
            return 1
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch Section(rawValue: indexPath.section)! {
        case .charts:
            let cell = tableView.dequeueReusableCell(withIdentifier: ChartTableViewCell.className, for: indexPath) as! ChartTableViewCell
            cell.contentView.layoutMargins.left = tableView.separatorInset.left
            cell.chartContentView.chartGenerator = { [unowned self] (frame) in
                return self.charts.glucoseChartWithFrame(frame)?.view
            }

            cell.selectionStyle = .none

            return cell
        case .inputs:
            let cell = tableView.dequeueReusableCell(withIdentifier: PredictionInputEffectTableViewCell.className, for: indexPath) as! PredictionInputEffectTableViewCell

            let (input, selected) = selectedInputs[indexPath.row]

            cell.titleLabel?.text = input.localizedTitle
            cell.accessoryType = selected ? .checkmark : .none
            cell.enabled = input != .retrospection || dataManager.loopManager.retrospectiveCorrectionEnabled

            var subtitleText = input.localizedDescription(forGlucoseUnit: charts.glucoseUnit)

            if input == .retrospection,
                let startGlucose = retrospectivePredictedGlucose?.first,
                let endGlucose = retrospectivePredictedGlucose?.last,
                let currentGlucose = self.dataManager.glucoseStore?.latestGlucose
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
            cell.`switch`?.isOn = dataManager.loopManager.retrospectiveCorrectionEnabled
            cell.`switch`?.addTarget(self, action: #selector(retrospectiveCorrectionSwitchChanged(_:)), for: .valueChanged)

            cell.contentView.layoutMargins.left = tableView.separatorInset.left

            return cell
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
            return 220
        case .inputs, .settings:
            return 60
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard Section(rawValue: indexPath.section) == .inputs else { return }

        let (input, selected) = selectedInputs[indexPath.row]

        if let cell = tableView.cellForRow(at: indexPath) {
            cell.accessoryType = !selected ? .checkmark : .none
        }

        selectedInputs[indexPath.row] = (input, !selected)

        tableView.deselectRow(at: indexPath, animated: true)

        needsRefresh = true
        reloadData()
    }

    // MARK: - Actions

    @objc private func retrospectiveCorrectionSwitchChanged(_ sender: UISwitch) {
        dataManager.loopManager.retrospectiveCorrectionEnabled = sender.isOn

        if  let row = selectedInputs.index(where: { $0.input == PredictionInputEffect.retrospection }),
            let cell = tableView.cellForRow(at: IndexPath(row: row, section: Section.inputs.rawValue)) as? PredictionInputEffectTableViewCell
        {
            cell.enabled = self.dataManager.loopManager.retrospectiveCorrectionEnabled
        }
    }
}
