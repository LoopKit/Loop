//
//  CarbAbsorptionViewController.swift
//  Loop
//
//  Copyright © 2017 LoopKit Authors. All rights reserved.
//

import UIKit
import HealthKit
import Intents
import LoopCore
import LoopKit
import LoopKitUI
import LoopUI
import os.log


private extension RefreshContext {
    static let all: Set<RefreshContext> = [.glucose, .carbs, .status]
}


final class CarbAbsorptionViewController: ChartsTableViewController, IdentifiableClass {

    private let log = OSLog(category: "StatusTableViewController")

    override func viewDidLoad() {
        super.viewDidLoad()

        carbEffectChart.glucoseDisplayRange = HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 100)...HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 175)

        let notificationCenter = NotificationCenter.default

        notificationObservers += [
            notificationCenter.addObserver(forName: .LoopDataUpdated, object: deviceManager.loopManager, queue: nil) { [weak self] note in
                let context = note.userInfo?[LoopDataManager.LoopUpdateContextKey] as! LoopDataManager.LoopUpdateContext.RawValue
                DispatchQueue.main.async {
                    switch LoopDataManager.LoopUpdateContext(rawValue: context) {
                    case .carbs?:
                        self?.refreshContext.formUnion([.carbs, .glucose])
                    case .glucose?:
                        self?.refreshContext.update(with: .glucose)
                    default:
                        break
                    }

                    self?.refreshContext.update(with: .status)
                    self?.reloadData(animated: true)
                }
            }
        ]

        if let gestureRecognizer = charts.gestureRecognizer {
            tableView.addGestureRecognizer(gestureRecognizer)
        }

        navigationItem.rightBarButtonItems?.append(editButtonItem)

        tableView.rowHeight = UITableView.automaticDimension

        reloadData(animated: false)
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

    private var refreshContext = RefreshContext.all

    private var reloading = false

    private var carbStatuses: [CarbStatus<StoredCarbEntry>] = []

    private var carbsOnBoard: CarbValue?

    private var carbTotal: CarbValue?

    // MARK: - Data loading

    private let carbEffectChart = CarbEffectChart()

    override func createChartsManager() -> ChartsManager {
        return ChartsManager(colors: .default, settings: .default, charts: [carbEffectChart], traitCollection: traitCollection)
    }

    override func glucoseUnitDidChange() {
        refreshContext = RefreshContext.all
    }

    override func reloadData(animated: Bool = false) {
        guard active && !reloading && !self.refreshContext.isEmpty else { return }
        var currentContext = self.refreshContext
        var retryContext: Set<RefreshContext> = []
        self.refreshContext = []
        reloading = true

        // How far back should we show data? Use the screen size as a guide.
        let minimumSegmentWidth: CGFloat = 75

        let size = currentContext.newSize ?? self.tableView.bounds.size
        let availableWidth = size.width - self.charts.fixedHorizontalMargin
        let totalHours = floor(Double(availableWidth / minimumSegmentWidth))

        var components = DateComponents()
        components.minute = 0
        let date = Date(timeIntervalSinceNow: -TimeInterval(hours: max(1, totalHours)))
        let chartStartDate = Calendar.current.nextDate(after: date, matching: components, matchingPolicy: .strict, direction: .backward) ?? date
        if charts.startDate != chartStartDate {
            currentContext.formUnion(RefreshContext.all)
        }
        charts.startDate = chartStartDate

        let midnight = Calendar.current.startOfDay(for: Date())
        let listStart = min(midnight, chartStartDate, Date(timeIntervalSinceNow: -deviceManager.loopManager.carbStore.maximumAbsorptionTimeInterval))

        let reloadGroup = DispatchGroup()
        let shouldUpdateGlucose = currentContext.contains(.glucose)
        let shouldUpdateCarbs = currentContext.contains(.carbs)

        var carbEffects: [GlucoseEffect]?
        var carbStatuses: [CarbStatus<StoredCarbEntry>]?
        var carbsOnBoard: CarbValue?
        var carbTotal: CarbValue?
        var insulinCounteractionEffects: [GlucoseEffectVelocity]?

        // TODO: Don't always assume currentContext.contains(.status)
        reloadGroup.enter()
        deviceManager.loopManager.getLoopState { (manager, state) in
            if shouldUpdateGlucose || shouldUpdateCarbs {
                let allInsulinCounteractionEffects = state.insulinCounteractionEffects
                insulinCounteractionEffects = allInsulinCounteractionEffects.filterDateRange(chartStartDate, nil)

                reloadGroup.enter()
                manager.carbStore.getCarbStatus(start: listStart, effectVelocities: manager.settings.dynamicCarbAbsorptionEnabled ? allInsulinCounteractionEffects : nil) { (result) in
                    switch result {
                    case .success(let status):
                        carbStatuses = status
                        carbsOnBoard = status.getClampedCarbsOnBoard()
                    case .failure(let error):
                        self.log.error("CarbStore failed to get carbStatus: %{public}@", String(describing: error))
                        retryContext.update(with: .carbs)
                    }

                    reloadGroup.leave()
                }

                reloadGroup.enter()
                manager.carbStore.getGlucoseEffects(start: chartStartDate, effectVelocities: manager.settings.dynamicCarbAbsorptionEnabled ? insulinCounteractionEffects : nil) { (result) in
                    switch result {
                    case .success(let effects):
                        carbEffects = effects
                    case .failure(let error):
                        carbEffects = []
                        self.log.error("CarbStore failed to get glucoseEffects: %{public}@", String(describing: error))
                        retryContext.update(with: .carbs)
                    }
                    reloadGroup.leave()
                }
            }

            reloadGroup.leave()
        }

        if shouldUpdateCarbs {
            reloadGroup.enter()
            deviceManager.loopManager.carbStore.getTotalCarbs(since: midnight) { (result) in
                switch result {
                case .success(let total):
                    carbTotal = total
                case .failure(let error):
                    self.log.error("CarbStore failed to get total carbs: %{public}@", String(describing: error))
                    retryContext.update(with: .carbs)
                }

                reloadGroup.leave()
            }
        }

        reloadGroup.notify(queue: .main) {
            if let carbEffects = carbEffects {
                self.carbEffectChart.setCarbEffects(carbEffects)
                self.charts.invalidateChart(atIndex: 0)
            }

            if let insulinCounteractionEffects = insulinCounteractionEffects {
                self.carbEffectChart.setInsulinCounteractionEffects(insulinCounteractionEffects)
                self.charts.invalidateChart(atIndex: 0)
            }

            self.charts.prerender()

            for case let cell as ChartTableViewCell in self.tableView.visibleCells {
                cell.reloadChart()
            }

            if shouldUpdateCarbs || shouldUpdateGlucose {
                // Change to descending order for display
                self.carbStatuses = carbStatuses?.reversed() ?? []

                if shouldUpdateCarbs {
                    self.carbTotal = carbTotal
                }

                self.carbsOnBoard = carbsOnBoard

                self.tableView.reloadSections(IndexSet(integer: Section.entries.rawValue), with: .fade)
            }

            if let cell = self.tableView.cellForRow(at: IndexPath(row: 0, section: Section.totals.rawValue)) as? HeaderValuesTableViewCell {
                self.updateCell(cell)
            }

            self.reloading = false
            let reloadNow = !self.refreshContext.isEmpty
            self.refreshContext.formUnion(retryContext)

            // Trigger a reload if new context exists.
            if reloadNow {
                self.reloadData()
            }
        }
    }

    // MARK: - UITableViewDataSource

    private enum Section: Int {
        case charts
        case totals
        case entries

        static let count = 3
    }

    private enum ChartRow: Int {
        case carbEffect

        static let count = 1
    }

    private lazy var carbFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        return formatter
    }()

    private lazy var absorptionFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.collapsesLargestUnit = true
        formatter.unitsStyle = .abbreviated
        formatter.allowsFractionalUnits = true
        formatter.allowedUnits = [.hour, .minute]
        return formatter
    }()

    private lazy var timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    override func numberOfSections(in tableView: UITableView) -> Int {
        return Section.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .charts:
            return ChartRow.count
        case .totals:
            return 1
        case .entries:
            return carbStatuses.count
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch Section(rawValue: indexPath.section)! {
        case .charts:
            let cell = tableView.dequeueReusableCell(withIdentifier: ChartTableViewCell.className, for: indexPath) as! ChartTableViewCell

            switch ChartRow(rawValue: indexPath.row)! {
            case .carbEffect:
                cell.chartContentView.chartGenerator = { [weak self] (frame) in
                    return self?.charts.chart(atIndex: 0, frame: frame)?.view
                }
            }

            let alpha: CGFloat = charts.gestureRecognizer?.state == .possible ? 1 : 0
            cell.titleLabel?.alpha = alpha
            cell.subtitleLabel?.alpha = alpha

            cell.subtitleLabel?.textColor = UIColor.secondaryLabelColor

            return cell
        case .totals:
            let cell = tableView.dequeueReusableCell(withIdentifier: HeaderValuesTableViewCell.className, for: indexPath) as! HeaderValuesTableViewCell
            updateCell(cell)

            return cell
        case .entries:
            let unit = HKUnit.gram()
            let cell = tableView.dequeueReusableCell(withIdentifier: CarbEntryTableViewCell.className, for: indexPath) as! CarbEntryTableViewCell

            // Entry value
            let status = carbStatuses[indexPath.row]
            let carbText = carbFormatter.string(from: status.entry.quantity.doubleValue(for: unit), unit: unit.unitString)

            if let carbText = carbText, let foodType = status.entry.foodType {
                cell.valueLabel?.text = String(
                    format: NSLocalizedString("%1$@: %2$@", comment: "Formats (1: carb value) and (2: food type)"),
                    carbText, foodType
                )
            } else {
                cell.valueLabel?.text = carbText
            }

            // Entry time
            let startTime = timeFormatter.string(from: status.entry.startDate)
            if  let absorptionTime = status.entry.absorptionTime,
                let duration = absorptionFormatter.string(from: absorptionTime)
            {
                cell.dateLabel?.text = String(
                    format: NSLocalizedString("%1$@ + %2$@", comment: "Formats (1: carb start time) and (2: carb absorption duration)"),
                    startTime, duration
                )
            } else {
                cell.dateLabel?.text = startTime
            }

            if let absorption = status.absorption {
                // Absorbed value
                let observedProgress = Float(absorption.observedProgress.doubleValue(for: .percent()))
                let observedCarbs = max(0, absorption.observed.doubleValue(for: unit))

                if let observedCarbsText = carbFormatter.string(from: observedCarbs, unit: unit.unitString) {
                    cell.observedValueText = String(
                        format: NSLocalizedString("%@ absorbed", comment: "Formats absorbed carb value"),
                        observedCarbsText
                    )

                    if absorption.isActive {
                        cell.observedValueTextColor = UIColor.COBTintColor
                    } else if 0.9 <= observedProgress && observedProgress <= 1.1 {
                        cell.observedValueTextColor = UIColor.systemGray
                    } else {
                        cell.observedValueTextColor = UIColor.agingColor
                    }
                }

                cell.observedProgress = observedProgress
                cell.clampedProgress = Float(absorption.clampedProgress.doubleValue(for: .percent()))
                cell.observedDateText = absorptionFormatter.string(from: absorption.estimatedDate.duration)

                // Absorbed time
                if absorption.isActive {
                    cell.observedDateTextColor = UIColor.COBTintColor
                } else {
                    cell.observedDateTextColor = UIColor.systemGray

                    if let absorptionTime = status.entry.absorptionTime {
                        let durationProgress = absorption.estimatedDate.duration / absorptionTime
                        if 0.9 > durationProgress || durationProgress > 1.1 {
                            cell.observedDateTextColor = UIColor.agingColor
                        }
                    }
                }
            }

            cell.isUploading = !status.entry.isUploaded && (deviceManager.loopManager.carbStore.syncDelegate != nil)
            return cell
        }
    }

    private func updateCell(_ cell: HeaderValuesTableViewCell) {
        let unit = HKUnit.gram()

        if let carbsOnBoard = carbsOnBoard, carbsOnBoard.quantity.doubleValue(for: unit) > 0 {
            cell.COBDateLabel.text = String(
                format: NSLocalizedString("at %@", comment: "Format fragment for a specific time"),
                timeFormatter.string(from: carbsOnBoard.startDate)
            )
            cell.COBValueLabel.text = carbFormatter.string(from: carbsOnBoard.quantity.doubleValue(for: unit))

            // Warn the user if the carbsOnBoard value isn't recent
            let textColor: UIColor
            switch carbsOnBoard.startDate.timeIntervalSinceNow {
            case let t where t < .minutes(-30):
                textColor = .staleColor
            case let t where t < .minutes(-15):
                textColor = .agingColor
            default:
                textColor = .secondaryLabelColor
            }

            cell.COBDateLabel.textColor = textColor
        } else {
            cell.COBDateLabel.text = nil
            cell.COBValueLabel.text = carbFormatter.string(from: 0.0)
        }

        if let carbTotal = carbTotal {
            cell.totalDateLabel.text = String(
                format: NSLocalizedString("since %@", comment: "Format fragment for a start time"),
                timeFormatter.string(from: carbTotal.startDate)
            )
            cell.totalValueLabel.text = carbFormatter.string(from: carbTotal.quantity.doubleValue(for: unit))
        } else {
            cell.totalDateLabel.text = nil
            cell.totalValueLabel.text = carbFormatter.string(from: 0.0)
        }
    }

    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        switch Section(rawValue: indexPath.section)! {
        case .charts, .totals:
            return false
        case .entries:
            return carbStatuses[indexPath.row].entry.createdByCurrentApp
        }
    }

    public override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            let status = carbStatuses[indexPath.row]
            deviceManager.loopManager.carbStore.deleteCarbEntry(status.entry) { (result) -> Void in
                DispatchQueue.main.async {
                    switch result {
                    case .success:
                        self.isEditing = false
                        break  // Notification will trigger update
                    case .failure(let error):
                        self.refreshContext.update(with: .carbs)
                        self.present(UIAlertController(with: error), animated: true)
                    }
                }
            }
        }
    }

    // MARK: - UITableViewDelegate

    override func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        switch Section(rawValue: indexPath.section)! {
        case .charts:
            return 170
        case .totals:
            return 66
        case .entries:
            return 66
        }
    }

    override func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
        switch Section(rawValue: indexPath.section)! {
        case .charts:
            return indexPath
        case .totals:
            return nil
        case .entries:
            return carbStatuses[indexPath.row].entry.createdByCurrentApp ? indexPath : nil
        }
    }

    // MARK: - Navigation

    override func restoreUserActivityState(_ activity: NSUserActivity) {
        switch activity.activityType {
        case NSUserActivity.newCarbEntryActivityType:
            performSegue(withIdentifier: CarbEntryEditViewController.className, sender: activity)
        default:
            break
        }
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        super.prepare(for: segue, sender: sender)

        var targetViewController = segue.destination

        if let navVC = targetViewController as? UINavigationController, let topViewController = navVC.topViewController {
            targetViewController = topViewController
        }

        switch targetViewController {
        case let vc as BolusViewController:
            vc.configureWithLoopManager(self.deviceManager.loopManager,
                recommendation: sender as? BolusRecommendation,
                glucoseUnit: self.carbEffectChart.glucoseUnit
            )
        case let vc as CarbEntryEditViewController:
            if let selectedCell = sender as? UITableViewCell, let indexPath = tableView.indexPath(for: selectedCell), indexPath.row < carbStatuses.count {
                vc.originalCarbEntry = carbStatuses[indexPath.row].entry
            } else if let activity = sender as? NSUserActivity {
                vc.restoreUserActivityState(activity)
            }

            vc.defaultAbsorptionTimes = deviceManager.loopManager.carbStore.defaultAbsorptionTimes
            vc.preferredUnit = deviceManager.loopManager.carbStore.preferredUnit
        default:
            break
        }
    }

    /// Unwind segue action from the CarbEntryEditViewController
    ///
    /// - parameter segue: The unwind segue
    @IBAction func unwindFromEditing(_ segue: UIStoryboardSegue) {
        guard let editVC = segue.source as? CarbEntryEditViewController,
            let updatedEntry = editVC.updatedCarbEntry
        else {
            return
        }

        if #available(iOS 12.0, *), editVC.originalCarbEntry == nil {
            let interaction = INInteraction(intent: NewCarbEntryIntent(), response: nil)
            interaction.donate { (error) in
                if let error = error {
                    os_log(.error, "Failed to donate intent: %{public}@", String(describing: error))
                }
            }
        }
        deviceManager.loopManager.addCarbEntryAndRecommendBolus(updatedEntry, replacing: editVC.originalCarbEntry) { (result) in
            DispatchQueue.main.async {
                switch result {
                case .success(let recommendation):
                    if self.active && self.visible, let bolus = recommendation?.amount, bolus > 0 {
                        self.performSegue(withIdentifier: BolusViewController.className, sender: recommendation)
                    }
                case .failure(let error):
                    // Ignore bolus wizard errors
                    if error is CarbStore.CarbStoreError {
                        self.present(UIAlertController(with: error), animated: true)
                    }
                }
            }
        }
    }
    
    @IBAction func unwindFromBolusViewController(_ segue: UIStoryboardSegue) {
        if let bolusViewController = segue.source as? BolusViewController {
            if let bolus = bolusViewController.bolus, bolus > 0 {
                deviceManager.enactBolus(units: bolus) { (_) in
                }
            }
        }
    }

}
