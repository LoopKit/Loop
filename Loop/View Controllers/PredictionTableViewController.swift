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

        let notificationCenter = NSNotificationCenter.defaultCenter()
        let mainQueue = NSOperationQueue.mainQueue()
        let application = UIApplication.sharedApplication()

        notificationObservers += [
            notificationCenter.addObserverForName(LoopDataManager.LoopDataUpdatedNotification, object: dataManager.loopManager, queue: nil) { note in
                guard let rawContext = note.userInfo?[LoopDataManager.LoopUpdateContextKey] as? Int where LoopDataManager.LoopUpdateContext(rawValue: rawContext) != .Preferences else {
                    return
                }

                dispatch_async(dispatch_get_main_queue()) {
                    self.needsRefresh = true
                    self.reloadData(animated: true)
                }
            },
            notificationCenter.addObserverForName(UIApplicationWillResignActiveNotification, object: application, queue: mainQueue) { _ in
                self.active = false
            },
            notificationCenter.addObserverForName(UIApplicationDidBecomeActiveNotification, object: application, queue: mainQueue) { _ in
                self.active = true
            }
        ]
    }

    deinit {
        for observer in notificationObservers {
            NSNotificationCenter.defaultCenter().removeObserver(observer)
        }
    }

    override func viewWillAppear(animated: Bool) {
        super.viewWillAppear(animated)

        visible = true
    }

    override func viewDidAppear(animated: Bool) {
        super.viewDidAppear(animated)

        AnalyticsManager.sharedManager.didDisplayStatusScreen()
    }

    override func viewWillDisappear(animated: Bool) {
        super.viewWillDisappear(animated)

        visible = false
    }

    override func viewWillTransitionToSize(size: CGSize, withTransitionCoordinator coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransitionToSize(size, withTransitionCoordinator: coordinator)

        if visible {
            coordinator.animateAlongsideTransition({ (_) -> Void in
                self.tableView.beginUpdates()
                self.tableView.reloadSections(NSIndexSet(index: Section.charts.rawValue), withRowAnimation: .Fade)
                self.tableView.endUpdates()
            }, completion: nil)
        } else {
            needsRefresh = true
        }
    }

    // MARK: - State

    // References to registered notification center observers
    private var notificationObservers: [AnyObject] = []

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

    private func reloadData(animated animated: Bool = false) {
        if active && visible && needsRefresh {
            needsRefresh = false
            reloading = true

            let calendar = NSCalendar.currentCalendar()
            let components = NSDateComponents()
            components.minute = 0
            let date = NSDate(timeIntervalSinceNow: -NSTimeInterval(hours: 1))
            charts.startDate = calendar.nextDateAfterDate(date, matchingComponents: components, options: [.MatchStrictly, .SearchBackwards]) ?? date

            let reloadGroup = dispatch_group_create()
            var glucoseUnit: HKUnit?

            if let glucoseStore = dataManager.glucoseStore {
                dispatch_group_enter(reloadGroup)
                glucoseStore.getRecentGlucoseValues(startDate: charts.startDate) { (values, error) -> Void in
                    if let error = error {
                        self.dataManager.logger.addError(error, fromSource: "GlucoseStore")
                        self.needsRefresh = true
                        // TODO: Display error in the cell
                    } else {
                        self.charts.glucoseValues = values
                    }

                    dispatch_group_leave(reloadGroup)
                }

                dispatch_group_enter(reloadGroup)
                glucoseStore.preferredUnit { (unit, error) in
                    glucoseUnit = unit

                    dispatch_group_leave(reloadGroup)
                }
            }

            dispatch_group_enter(reloadGroup)
            dataManager.loopManager.getLoopStatus { (predictedGlucose, retrospectivePredictedGlucose, _, _, _, _, error) in
                if error != nil {
                    self.needsRefresh = true
                }

                self.retrospectivePredictedGlucose = retrospectivePredictedGlucose
                self.charts.predictedGlucoseValues = predictedGlucose ?? []

                dispatch_group_leave(reloadGroup)
            }

            dispatch_group_enter(reloadGroup)
            dataManager.loopManager.modelPredictedGlucose(using: selectedInputs.flatMap { $0.selected ? $0.input : nil }) { (predictedGlucose, error) in
                if error != nil {
                    self.needsRefresh = true
                }

                self.charts.alternatePredictedGlucoseValues = predictedGlucose ?? []

                dispatch_group_leave(reloadGroup)
            }

            charts.glucoseTargetRangeSchedule = dataManager.glucoseTargetRangeSchedule

            dispatch_group_notify(reloadGroup, dispatch_get_main_queue()) {
                if let unit = glucoseUnit {
                    self.charts.glucoseUnit = unit
                }
                
                self.charts.prerender()
                
                self.tableView.reloadSections(NSIndexSet(indexesInRange: NSMakeRange(Section.charts.rawValue, 1)),
                                              withRowAnimation: .None
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

    override func numberOfSectionsInTableView(tableView: UITableView) -> Int {
        return Section.count
    }

    override func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .charts:
            return 1
        case .inputs:
            return selectedInputs.count
        case .settings:
            return 1
        }
    }

    override func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        switch Section(rawValue: indexPath.section)! {
        case .charts:
            let cell = tableView.dequeueReusableCellWithIdentifier(ChartTableViewCell.className, forIndexPath: indexPath) as! ChartTableViewCell

            let frame = CGRect(origin: .zero, size: CGSize(width: tableView.bounds.width, height: cell.placeholderView!.bounds.height))

            cell.contentView.layoutMargins.left = tableView.separatorInset.left

            if let chart = charts.glucoseChartWithFrame(frame) {
                cell.chartView = chart.view
            } else {
                cell.chartView = nil
                // TODO: Display empty state
            }

            cell.selectionStyle = .None

            return cell
        case .inputs:
            let cell = tableView.dequeueReusableCellWithIdentifier(PredictionInputEffectTableViewCell.className, forIndexPath: indexPath) as! PredictionInputEffectTableViewCell

            let (input, selected) = selectedInputs[indexPath.row]

            cell.titleLabel?.text = input.localizedTitle
            cell.accessoryType = selected ? .Checkmark : .None
            cell.enabled = input != .retrospection || dataManager.loopManager.retrospectiveCorrectionEnabled

            var subtitleText = input.localizedDescription(forGlucoseUnit: charts.glucoseUnit)

            if input == .retrospection,
                let startGlucose = retrospectivePredictedGlucose?.first,
                let endGlucose = retrospectivePredictedGlucose?.last,
                let currentGlucose = self.dataManager.glucoseStore?.latestGlucose
            {
                let formatter = NSNumberFormatter.glucoseFormatter(for: charts.glucoseUnit)
                let values = [startGlucose, endGlucose, currentGlucose].map { formatter.stringFromNumber($0.quantity.doubleValueForUnit(charts.glucoseUnit)) ?? "?" }

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
            let cell = tableView.dequeueReusableCellWithIdentifier(SwitchTableViewCell.className, forIndexPath: indexPath) as! SwitchTableViewCell

            cell.titleLabel?.text = NSLocalizedString("Enable Retrospective Correction", comment: "Title of the switch which toggles retrospective correction effects")
            cell.subtitleLabel?.text = NSLocalizedString("This will more aggresively increase or decrease basal delivery when glucose movement doesn't match the carbohydrate and insulin-based model.", comment: "The description of the switch which toggles retrospective correction effects")
            cell.`switch`?.on = dataManager.loopManager.retrospectiveCorrectionEnabled
            cell.`switch`?.addTarget(self, action: #selector(retrospectiveCorrectionSwitchChanged(_:)), forControlEvents: .ValueChanged)

            cell.contentView.layoutMargins.left = tableView.separatorInset.left

            return cell
        }
    }

    override func tableView(tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .settings:
            return NSLocalizedString("Algorithm Settings", comment: "The title of the section containing algorithm settings")
        default:
            return nil
        }
    }

    // MARK: - UITableViewDelegate

    override func tableView(tableView: UITableView, estimatedHeightForRowAtIndexPath indexPath: NSIndexPath) -> CGFloat {
        switch Section(rawValue: indexPath.section)! {
        case .charts:
            return 220
        case .inputs, .settings:
            return 60
        }
    }

    override func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
        guard Section(rawValue: indexPath.section) == .inputs else { return }

        let (input, selected) = selectedInputs[indexPath.row]

        if let cell = tableView.cellForRowAtIndexPath(indexPath) {
            cell.accessoryType = !selected ? .Checkmark : .None
        }

        selectedInputs[indexPath.row] = (input, !selected)

        tableView.deselectRowAtIndexPath(indexPath, animated: true)

        needsRefresh = true
        reloadData()
    }

    // MARK: - Actions

    @objc private func retrospectiveCorrectionSwitchChanged(sender: UISwitch) {
        dataManager.loopManager.retrospectiveCorrectionEnabled = sender.on

        if  let row = selectedInputs.indexOf({ $0.input == PredictionInputEffect.retrospection }),
            let cell = tableView.cellForRowAtIndexPath(NSIndexPath(forRow: row, inSection: Section.inputs.rawValue)) as? PredictionInputEffectTableViewCell
        {
            cell.enabled = self.dataManager.loopManager.retrospectiveCorrectionEnabled
        }
    }
}
