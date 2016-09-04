//
//  PredictionTableViewController.swift
//  Loop
//
//  Created by Nate Racklyeft on 9/3/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import UIKit
import HealthKit

class PredictionTableViewController: UITableViewController {

    init(dataManager: DeviceDataManager) {
        self.dataManager = dataManager

        super.init(style: .Plain)

        title = NSLocalizedString("Predicted Glucose", comment: "Title of the PredictionTableViewController")

        hidesBottomBarWhenPushed = true

        reloadData()
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        tableView.registerClass(ChartTableViewCell.self, forCellReuseIdentifier: ChartTableViewCell.className)
    }

    override func viewDidAppear(animated: Bool) {
        super.viewDidAppear(animated)
    }

    // MARK: - 

    private let dataManager: DeviceDataManager

    private let charts = StatusChartsManager()

    private var needsRefresh = true

    private var reloading = false

    private func reloadData(animated animated: Bool = false) {
        if needsRefresh {
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
            dataManager.loopManager.modelPredictedGlucose(using: selectedInputs.flatMap { $0.selected ? $0.input : nil }) { (predictedGlucose, error) in
                if error != nil {
                    self.needsRefresh = true
                }

                self.charts.predictedGlucoseValues = predictedGlucose ?? []

                dispatch_group_leave(reloadGroup)
            }

            charts.glucoseTargetRangeSchedule = dataManager.glucoseTargetRangeSchedule

            dispatch_group_notify(reloadGroup, dispatch_get_main_queue()) {
                if let unit = glucoseUnit {
                    self.charts.glucoseUnit = unit
                }
                
                self.charts.prerender()
                
                self.tableView.reloadSections(NSIndexSet(indexesInRange: NSMakeRange(Section.charts.rawValue, 1)),
                                              withRowAnimation: animated ? .Fade : .None
                )
                
                self.reloading = false
            }
        }
    }

    // MARK: - UITableViewDataSource

    private enum Section: Int {
        case charts
        case inputs

        static let count = 2
    }

    private lazy var selectedInputs: [(input: LoopDataManager.PredictionInput, selected: Bool)] = [
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
        }
    }

    override func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        switch Section(rawValue: indexPath.section)! {
        case .charts:
            let cell = tableView.dequeueReusableCellWithIdentifier(ChartTableViewCell.className, forIndexPath: indexPath) as! ChartTableViewCell

            if let chart = charts.glucoseChartWithFrame(cell.contentView.frame) {
                cell.chartView = chart.view
            } else {
                cell.chartView = nil
                // TODO: Display empty state
            }

            cell.selectionStyle = .None

            return cell
        case .inputs:
            let cell = tableView.dequeueReusableCellWithIdentifier(UITableViewCell.className) ?? UITableViewCell(style: .Default, reuseIdentifier: UITableViewCell.className)

            let (input, selected) = selectedInputs[indexPath.row]

            cell.textLabel?.text = String(input)
            cell.accessoryType = selected ? .Checkmark : .None

            return cell
        }
    }

    override func tableView(tableView: UITableView, heightForRowAtIndexPath indexPath: NSIndexPath) -> CGFloat {
        switch Section(rawValue: indexPath.section)! {
        case .charts:
            return 170
        case .inputs:
            return UITableViewAutomaticDimension
        }
    }

    // MARK: - UITableViewDelegate

    override func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
        let (input, selected) = selectedInputs[indexPath.row]

        if let cell = tableView.cellForRowAtIndexPath(indexPath) {
            cell.accessoryType = !selected ? .Checkmark : .None
        }

        selectedInputs[indexPath.row] = (input, !selected)

        tableView.deselectRowAtIndexPath(indexPath, animated: true)

        needsRefresh = true
        reloadData()
    }
}
