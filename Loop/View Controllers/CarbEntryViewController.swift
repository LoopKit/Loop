//
//  CarbEntryViewController.swift
//  CarbKit
//
//  Created by Nathan Racklyeft on 1/15/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import UIKit
import HealthKit
import LoopKit
import LoopKitUI
import LoopCore
import LoopUI

final class CarbEntryViewController: LoopChartsTableViewController, IdentifiableClass {

    var defaultAbsorptionTimes: CarbStore.DefaultAbsorptionTimes? {
        didSet {
            if let times = defaultAbsorptionTimes {
                orderedAbsorptionTimes = [times.fast, times.medium, times.slow]
            }
        }
    }

    fileprivate var orderedAbsorptionTimes = [TimeInterval]()

    var preferredCarbUnit = HKUnit.gram()
    
    private var glucoseUnit: HKUnit {
        return deviceManager.displayGlucoseUnitObservable.displayGlucoseUnit
    }

    var maxCarbEntryQuantity = LoopConstants.maxCarbEntryQuantity

    var warningCarbEntryQuantity = LoopConstants.warningCarbEntryQuantity

    /// Entry configuration values. Must be set before presenting.
    var absorptionTimePickerInterval = TimeInterval(minutes: 30)

    var maxAbsorptionTime = LoopConstants.maxCarbAbsorptionTime

    var maximumDateFutureInterval = TimeInterval(hours: 4)

    var originalCarbEntry: StoredCarbEntry? {
        didSet {
            if let entry = originalCarbEntry {
                quantity = entry.quantity
                date = entry.startDate
                foodType = entry.foodType
                absorptionTime = entry.absorptionTime

                absorptionTimeWasEdited = true
                usesCustomFoodType = true

                shouldBeginEditingQuantity = false
            }
        }
    }

    fileprivate var lastEntryDate: Date?

    fileprivate func updateLastEntryDate() { lastEntryDate = Date() }

    fileprivate var quantity: HKQuantity? {
        didSet {
            if quantity != oldValue {
                updateLastEntryDate()
            }
            updateContinueButtonEnabled()
        }
    }

    fileprivate var date = Date() {
        didSet {
            if date != oldValue {
                updateLastEntryDate()
            }
            updateContinueButtonEnabled()
        }
    }

    fileprivate var foodType: String? {
        didSet {
            if foodType != oldValue {
                updateLastEntryDate()
            }
            updateContinueButtonEnabled()
        }
    }

    fileprivate var absorptionTime: TimeInterval? {
        didSet {
            if absorptionTime != oldValue {
                updateLastEntryDate()
            }
            updateContinueButtonEnabled()
        }
    }

    private var selectedDefaultAbsorptionTimeEmoji: String?

    fileprivate var absorptionTimeWasEdited = false

    fileprivate var usesCustomFoodType = false

    private var shouldBeginEditingQuantity = true

    private var shouldBeginEditingFoodType = false
    
    private var shouldDisplayAccurateCarbEntryWarning = false {
        didSet {
            if shouldDisplayAccurateCarbEntryWarning != oldValue {
                if shouldDisplayOverrideEnabledWarning {
                    self.displayWarningRow(rowType: WarningRow.carbEntry, isAddingRow: shouldDisplayAccurateCarbEntryWarning)
                } else {
                    self.shouldDisplayWarning = shouldDisplayAccurateCarbEntryWarning || shouldDisplayOverrideEnabledWarning
                }
            }
        }
    }
    
    private var shouldDisplayOverrideEnabledWarning = false {
        didSet {
            if shouldDisplayOverrideEnabledWarning != oldValue {
                if shouldDisplayAccurateCarbEntryWarning {
                    self.displayWarningRow(rowType: WarningRow.override, isAddingRow: shouldDisplayOverrideEnabledWarning)
                } else {
                    self.shouldDisplayWarning = shouldDisplayOverrideEnabledWarning || shouldDisplayAccurateCarbEntryWarning
                }
            }
        }
    }
    
    private var shouldDisplayWarning = false {
        didSet {
            if shouldDisplayWarning != oldValue {
                self.displayWarning()
            }
        }
    }

    var updatedCarbEntry: NewCarbEntry? {
        if  let lastEntryDate = lastEntryDate,
            let quantity = quantity,
            let absorptionTime = absorptionTime ?? defaultAbsorptionTimes?.medium
        {
            if let o = originalCarbEntry, o.quantity == quantity && o.startDate == date && o.foodType == foodType && o.absorptionTime == absorptionTime {
                return nil  // No changes were made
            }

            return NewCarbEntry(
                date: lastEntryDate,
                quantity: quantity,
                startDate: date,
                foodType: foodType ?? selectedDefaultAbsorptionTimeEmoji,
                absorptionTime: absorptionTime
            )
        } else {
            return nil
        }
    }

    private var isSampleEditable: Bool {
        return originalCarbEntry?.createdByCurrentApp != false
    }

    private(set) lazy var footerView: SetupTableFooterView = {
        let footerView = SetupTableFooterView(frame: .zero)
        footerView.primaryButton.addTarget(self, action: #selector(continueButtonPressed), for: .touchUpInside)
        footerView.primaryButton.isEnabled = quantity != nil && quantity!.doubleValue(for: preferredCarbUnit) > 0
        return footerView
    }()

    private var lastContentHeight: CGFloat = 0

    override func createChartsManager() -> ChartsManager {
        // Consider including a chart on this screen to demonstrate how absorption time affects prediction
        ChartsManager(colors: .primary, settings: .default, charts: [], traitCollection: traitCollection)
    }

    override func glucoseUnitDidChange() {
        // Consider including a chart on this screen to demonstrate how absorption time affects prediction
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 44
        tableView.register(DateAndDurationTableViewCell.nib(), forCellReuseIdentifier: DateAndDurationTableViewCell.className)
        tableView.register(DateAndDurationSteppableTableViewCell.nib(), forCellReuseIdentifier: DateAndDurationSteppableTableViewCell.className)

        if originalCarbEntry != nil {
            title = NSLocalizedString("carb-entry-title-edit", value: "Edit Carb Entry", comment: "The title of the view controller to edit an existing carb entry")
        } else {
            title = NSLocalizedString("carb-entry-title-add", value: "Add Carb Entry", comment: "The title of the view controller to create a new carb entry")
        }
        
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: footerView.primaryButton.titleLabel?.text, style: .plain, target: self, action: #selector(continueButtonPressed))
        navigationItem.rightBarButtonItem?.isEnabled = false

        // Sets text for back button on bolus screen
        navigationItem.backBarButtonItem = UIBarButtonItem(title: NSLocalizedString("Carb Entry", comment: "Back button text for bolus screen to return to carb entry screen"), style: .plain, target: nil, action: nil)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        if shouldBeginEditingQuantity, let cell = tableView.cellForRow(at: IndexPath(row: DetailsRow.value.rawValue, section: Sections.indexForDetailsSection(displayWarningSection: shouldDisplayWarning))) as? DecimalTextFieldTableViewCell {
            shouldBeginEditingQuantity = false
            cell.textField.becomeFirstResponder()
        }

        // check if either warning should be displayed
        updateDisplayAccurateCarbEntryWarning()
        updateDisplayOverrideEnabledWarning()
        
        // monitor loop updates
        notificationObservers += [
            NotificationCenter.default.addObserver(forName: .LoopDataUpdated, object: deviceManager.loopManager, queue: nil) { [weak self] _ in
                self?.updateDisplayAccurateCarbEntryWarning()
                self?.updateDisplayOverrideEnabledWarning()
            }
        ]
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        // Reposition footer view if necessary
        if tableView.contentSize.height != lastContentHeight {
            lastContentHeight = tableView.contentSize.height
            tableView.tableFooterView = nil

            let footerSize = footerView.systemLayoutSizeFitting(CGSize(width: tableView.frame.size.width, height: UIView.layoutFittingCompressedSize.height))
            footerView.frame.size = footerSize
            tableView.tableFooterView = footerView
        }
    }

    private var foodKeyboard: EmojiInputController!
    
    private func updateDisplayAccurateCarbEntryWarning() {
        let now = Date()
        let startDate = now.addingTimeInterval(-LoopConstants.missedMealWarningGlucoseRecencyWindow)

        deviceManager.glucoseStore.getGlucoseSamples(start: startDate, end: nil) { [weak self] (result) -> Void in
            DispatchQueue.main.async {
                switch result {
                case .failure:
                    self?.shouldDisplayAccurateCarbEntryWarning = false
                case .success(let samples):
                    let filteredSamples = samples.filterDateRange(startDate, now)
                    guard let startSample = filteredSamples.first, let endSample = filteredSamples.last else {
                        self?.shouldDisplayAccurateCarbEntryWarning = false
                        return
                    }
                    let duration = endSample.startDate.timeIntervalSince(startSample.startDate)
                    guard duration >= LoopConstants.missedMealWarningVelocitySampleMinDuration else {
                        self?.shouldDisplayAccurateCarbEntryWarning = false
                        return
                    }
                    let delta = endSample.quantity.doubleValue(for: .milligramsPerDeciliter) - startSample.quantity.doubleValue(for: .milligramsPerDeciliter)
                    let velocity = delta / duration.minutes // Unit = mg/dL/m
                    self?.shouldDisplayAccurateCarbEntryWarning = velocity > LoopConstants.missedMealWarningGlucoseRiseThreshold
                }
            }
        }
    }
    
    private func updateDisplayOverrideEnabledWarning() {
        DispatchQueue.main.async {
            if let managerSettings = self.deviceManager?.settings {
                if !managerSettings.scheduleOverrideEnabled(at: Date()) {
                    self.shouldDisplayOverrideEnabledWarning = false
                } else if let overrideSettings = managerSettings.scheduleOverride?.settings {
                    self.shouldDisplayOverrideEnabledWarning = overrideSettings.effectiveInsulinNeedsScaleFactor != 1.0
                }
            }
        }
    }
    
    private func displayWarning() {
        tableView.beginUpdates()

        if shouldDisplayWarning {
            tableView.insertSections([Sections.warning.rawValue], with: .top)
        } else {
            tableView.deleteSections([Sections.warning.rawValue], with: .top)
        }
        
        tableView.endUpdates()
    }
    
    private func displayWarningRow(rowType: WarningRow, isAddingRow: Bool = true ) {
        if shouldDisplayWarning {
            tableView.beginUpdates()
            
            // If the accurate carb entry warning is shown, use the positional index of the given row type.
            let rowIndex = shouldDisplayAccurateCarbEntryWarning ? rowType.rawValue : 0
            
            if isAddingRow {
                tableView.insertRows(at: [IndexPath(row: rowIndex, section: Sections.warning.rawValue)], with: UITableView.RowAnimation.top)
            } else {
                tableView.deleteRows(at: [IndexPath(row: rowIndex, section: Sections.warning.rawValue)], with: UITableView.RowAnimation.top)
            }
            
            tableView.endUpdates()
        }
    }

    // MARK: - Table view data source
    fileprivate enum Sections: Int, CaseIterable {
        case warning
        case details
        
        static func indexForDetailsSection(displayWarningSection: Bool) -> Int {
            return displayWarningSection ? Sections.details.rawValue : Sections.details.rawValue - 1
        }
        
        static func numberOfSections(displayWarningSection: Bool) -> Int {
            return displayWarningSection ? Sections.allCases.count : Sections.allCases.count - 1
        }
        
        static func section(for indexPath: IndexPath, displayWarningSection: Bool) -> Int {
            return displayWarningSection ? indexPath.section : indexPath.section + 1
        }
        
        static func numberOfRows(for section: Int, displayCarbEntryWarning: Bool, displayOverrideWarning: Bool) -> Int {
            if section == Sections.warning.rawValue && (displayCarbEntryWarning || displayOverrideWarning) {
                return displayCarbEntryWarning && displayOverrideWarning ? WarningRow.allCases.count : WarningRow.allCases.count - 1
            }

            return DetailsRow.allCases.count
        }
        
        static func footer(for section: Int, displayWarningSection: Bool) -> String? {
            if section == Sections.warning.rawValue && displayWarningSection {
                return nil
            }
                    
            return NSLocalizedString("Choose a longer absorption time for larger meals, or those containing fats and proteins. This is only guidance to the algorithm and need not be exact.", comment: "Carb entry section footer text explaining absorption time")
        }
        
        static func headerHeight(for section: Int, displayWarningSection: Bool) -> CGFloat {
            return 8
        }
        
        static func footerHeight(for section: Int, displayWarningSection: Bool) -> CGFloat {
            if section == Sections.warning.rawValue && displayWarningSection {
                return 1
            }
            
            return UITableView.automaticDimension
        }
    }
    
    fileprivate enum DetailsRow: Int, CaseIterable {
        case value
        case date
        case foodType
        case absorptionTime
    }
    
    fileprivate enum WarningRow: Int, CaseIterable {
        case carbEntry
        case override
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        return Sections.numberOfSections(displayWarningSection: shouldDisplayWarning)
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return Sections.numberOfRows(for: section, displayCarbEntryWarning: shouldDisplayAccurateCarbEntryWarning, displayOverrideWarning: shouldDisplayOverrideEnabledWarning)
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch Sections(rawValue: Sections.section(for: indexPath, displayWarningSection: shouldDisplayWarning))! {
        case .warning:
            let cell: UITableViewCell
            // if no accurate carb entry warning should be shown OR if the given indexPath is for the override warning row, return the override warning cell.
            if !shouldDisplayAccurateCarbEntryWarning || WarningRow(rawValue: indexPath.row)! == .override {
                if let existingCell = tableView.dequeueReusableCell(withIdentifier: "CarbEntryOverrideEnabledWarningCell") {
                    cell = existingCell
                } else {
                    cell = UITableViewCell(style: .default, reuseIdentifier: "CarbEntryOverrideEnabledWarningCell")
                }
                
                cell.imageView?.image = UIImage(systemName: "exclamationmark.triangle.fill")
                cell.imageView?.tintColor = .warning
                cell.textLabel?.numberOfLines = 0
                cell.textLabel?.text = NSLocalizedString("An active override is modifying your carb ratio and insulin sensitivity. If you don't want this to affect your bolus calculation and projected glucose, consider turning off the override.", comment: "Warning to ensure the carb entry is accurate during an override")
                cell.textLabel?.font = UIFont.preferredFont(forTextStyle: .caption1)
                cell.textLabel?.textColor = .secondaryLabel
                cell.isUserInteractionEnabled = false
            } else {
                if let existingCell = tableView.dequeueReusableCell(withIdentifier: "CarbEntryAccuracyWarningCell") {
                    cell = existingCell
                } else {
                    cell = UITableViewCell(style: .default, reuseIdentifier: "CarbEntryAccuracyWarningCell")
                }
                
                cell.imageView?.image = UIImage(systemName: "exclamationmark.triangle.fill")
                cell.imageView?.tintColor = .destructive
                cell.textLabel?.numberOfLines = 0
                cell.textLabel?.text = NSLocalizedString("Your glucose is rapidly rising. Check that any carbs you've eaten were logged. If you logged carbs, check that the time you entered lines up with when you started eating.", comment: "Warning to ensure the carb entry is accurate")
                cell.textLabel?.font = UIFont.preferredFont(forTextStyle: .caption1)
                cell.textLabel?.textColor = .secondaryLabel
                cell.isUserInteractionEnabled = false
            }
            return cell
        case .details:
            switch DetailsRow(rawValue: indexPath.row)! {
            case .value:
                let cell = tableView.dequeueReusableCell(withIdentifier: DecimalTextFieldTableViewCell.className) as! DecimalTextFieldTableViewCell
                
                if let quantity = quantity {
                    cell.number = NSNumber(value: quantity.doubleValue(for: preferredCarbUnit))
                }
                cell.textField.isEnabled = isSampleEditable
                cell.unitLabel?.text = String(describing: preferredCarbUnit)
                cell.delegate = self
                
                return cell
            case .date:
                let cell = tableView.dequeueReusableCell(withIdentifier: DateAndDurationSteppableTableViewCell.className) as! DateAndDurationSteppableTableViewCell
            
                cell.titleLabel.text = NSLocalizedString("Time", comment: "Title of the carb entry date picker cell")
                cell.datePicker.isEnabled = isSampleEditable
                cell.datePicker.datePickerMode = .dateAndTime
                #if swift(>=5.2)
                    if #available(iOS 14.0, *) {
                        cell.datePicker.preferredDatePickerStyle = .wheels
                    }
                #endif
                cell.datePicker.maximumDate = date.addingTimeInterval(.hours(1))
                cell.datePicker.minimumDate = date.addingTimeInterval(.hours(-12))
                cell.datePicker.minuteInterval = 1
                cell.date = date
                cell.delegate = self

                return cell
            case .foodType:
                if usesCustomFoodType {
                    let cell = tableView.dequeueReusableCell(withIdentifier: TextFieldTableViewCell.className, for: indexPath) as! TextFieldTableViewCell
                    
                    cell.textField.text = foodType
                    cell.delegate = self
                    
                    if let textField = cell.textField as? CustomInputTextField {
                        if foodKeyboard == nil {
                            foodKeyboard = CarbAbsorptionInputController()
                            foodKeyboard.delegate = self
                        }
                        
                        textField.customInput = foodKeyboard
                    }
                    
                    return cell
                } else {
                    let cell = tableView.dequeueReusableCell(withIdentifier: FoodTypeShortcutCell.className, for: indexPath) as! FoodTypeShortcutCell
                    
                    if absorptionTime == nil {
                        cell.selectionState = .medium
                    }
                    
                    selectedDefaultAbsorptionTimeEmoji = cell.selectedEmoji
                    cell.delegate = self
                    
                    return cell
                }
            case .absorptionTime:
                let cell = tableView.dequeueReusableCell(withIdentifier: DateAndDurationTableViewCell.className) as! DateAndDurationTableViewCell
                
                cell.titleLabel.text = NSLocalizedString("Absorption Time", comment: "Title of the carb entry absorption time cell")
                cell.datePicker.isEnabled = isSampleEditable
                cell.datePicker.datePickerMode = .countDownTimer
                cell.datePicker.minuteInterval = Int(absorptionTimePickerInterval.minutes)
                
                if let duration = absorptionTime ?? defaultAbsorptionTimes?.medium {
                    cell.duration = duration
                }
                
                cell.maximumDuration = maxAbsorptionTime
                cell.delegate = self
                
                return cell
            }
        }
    }

    override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        switch Sections(rawValue: Sections.section(for: indexPath, displayWarningSection: shouldDisplayWarning)) {
        case .details:
            switch DetailsRow(rawValue: indexPath.row)! {
            case .value, .date:
                break
            case .foodType:
                if usesCustomFoodType, shouldBeginEditingFoodType, let cell = cell as? TextFieldTableViewCell {
                    shouldBeginEditingFoodType = false
                    cell.textField.becomeFirstResponder()
                }
            case .absorptionTime:
                break
            }
        default:
            break
        }
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        return Sections.footer(for: section, displayWarningSection: shouldDisplayWarning)
    }
    
    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return Sections.headerHeight(for: section, displayWarningSection: shouldDisplayWarning)
    }
    
    override func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        return Sections.footerHeight(for: section, displayWarningSection: shouldDisplayWarning)
    }
    
    // MARK: - UITableViewDelegate

    override func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
        tableView.endEditing(false)
        tableView.beginUpdates()
        hideDatePickerCells(excluding: indexPath)
        return indexPath
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        switch tableView.cellForRow(at: indexPath) {
        case is FoodTypeShortcutCell:
            usesCustomFoodType = true
            shouldBeginEditingFoodType = true
            tableView.reloadRows(at: [IndexPath(row: DetailsRow.foodType.rawValue, section: Sections.indexForDetailsSection(displayWarningSection: shouldDisplayWarning))], with: .none)
        default:
            break
        }

        tableView.endUpdates()
        tableView.deselectRow(at: indexPath, animated: true)
    }

    // MARK: - Navigation

    override func restoreUserActivityState(_ activity: NSUserActivity) {
        if let entry = activity.newCarbEntry {
            lastEntryDate = entry.date
            quantity = entry.quantity
            date = entry.startDate

            if let foodType = entry.foodType {
                self.foodType = foodType
                usesCustomFoodType = true
            }

            if let absorptionTime = entry.absorptionTime {
                self.absorptionTime = absorptionTime
                absorptionTimeWasEdited = true
            }
        }
    }

    @objc private func continueButtonPressed() {
        tableView.endEditing(true)
        guard validateInput() else {
            return
        }
        continueToBolus()
    }

    private func continueToBolus() {

        guard let updatedEntry = updatedCarbEntry else {
            return
        }

        let viewModel = BolusEntryViewModel(
            delegate: deviceManager,
            screenWidth: UIScreen.main.bounds.width,
            originalCarbEntry: originalCarbEntry,
            potentialCarbEntry: updatedEntry,
            selectedCarbAbsorptionTimeEmoji: selectedDefaultAbsorptionTimeEmoji
        )
        Task {
            await viewModel.generateRecommendationAndStartObserving()
        }

        viewModel.analyticsServicesManager = deviceManager.analyticsServicesManager

        let bolusEntryView = BolusEntryView(viewModel: viewModel).environmentObject(deviceManager.displayGlucoseUnitObservable)

        // After confirming a bolus, pop back to this controller's predecessor, i.e. all the way back out of the carb flow.
        let predecessorViewControllerType = (navigationController?.viewControllers.dropLast().last).map { type(of: $0) } ?? UIViewController.self
        let hostingController = DismissibleHostingController(
            rootView: bolusEntryView,
            dismissalMode: originalCarbEntry == nil ? .modalDismiss : .pop(to: predecessorViewControllerType)
        )
        show(hostingController, sender: footerView.primaryButton)
        deviceManager.analyticsServicesManager.didDisplayBolusScreen()
    }

    private func validateInput() -> Bool {
        guard let absorptionTime = absorptionTime ?? defaultAbsorptionTimes?.medium else {
            return false
        }
        guard absorptionTime <= maxAbsorptionTime else {
            showAbsorptionTimeValidationWarning(for: self, maxAbsorptionTime: maxAbsorptionTime)
            return false
        }

        guard let quantity = quantity, quantity.doubleValue(for: preferredCarbUnit) > 0 else { return false }
        guard quantity.compare(maxCarbEntryQuantity) != .orderedDescending else {
            showMaxQuantityValidationWarning(for: self, maxQuantityGrams: maxCarbEntryQuantity.doubleValue(for: .gram()))
            return false
        }

        let enteredGrams = quantity.doubleValue(for: .gram())

        if (enteredGrams > warningCarbEntryQuantity.doubleValue(for: .gram())) {
            showWarningQuantityValidationWarning(for: self, enteredGrams: enteredGrams) {
                self.continueToBolus()
            }
            return false
        }
       return true
    }

    private func updateContinueButtonEnabled() {
        let hasValidQuantity = quantity != nil && quantity!.doubleValue(for: preferredCarbUnit) > 0
        let haveChangesBeenMade = updatedCarbEntry != nil
        
        let readyToContinue = hasValidQuantity && haveChangesBeenMade
        
        footerView.primaryButton.isEnabled = readyToContinue
        navigationItem.rightBarButtonItem?.isEnabled = readyToContinue
    }

    // Alerts
    private lazy var dismissActionTitle = NSLocalizedString("com.loudnate.LoopKit.errorAlertActionTitle", value: "OK", comment: "The title of the action used to dismiss an error alert")

    public func showAbsorptionTimeValidationWarning(for viewController: UIViewController, maxAbsorptionTime: TimeInterval) {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute]
        formatter.unitsStyle = .full

        let message = String(
            format: NSLocalizedString("The maximum absorption time is %@", comment: "Alert body displayed absorption time greater than max (1: maximum absorption time)"),
            formatter.string(from: maxAbsorptionTime) ?? String(describing: maxAbsorptionTime))
        let validationTitle = NSLocalizedString("Maximum Duration Exceeded", comment: "Alert title when maximum duration exceeded.")
        let alert = UIAlertController(title: validationTitle, message: message, preferredStyle: .alert)

        let action = UIAlertAction(title: dismissActionTitle, style: .default)
        alert.addAction(action)
        alert.preferredAction = action

        viewController.present(alert, animated: true)
    }

    public func showWarningQuantityValidationWarning(for viewController: UIViewController, enteredGrams: Double, didConfirm: @escaping () -> Void) {
        let warningTitle = NSLocalizedString("Large Meal Entered", comment: "Title of the warning shown when a large meal was entered")

        let message = String(
            format: NSLocalizedString("Did you intend to enter %1$@ grams as the amount of carbohydrates for this meal?", comment: "Alert body when entered carbohydrates is greater than threshold (1: entered quantity in grams)"),
            NumberFormatter.localizedString(from: NSNumber(value: enteredGrams), number: .none)
                )
        let alert = UIAlertController(title: warningTitle, message: message, preferredStyle: .alert)

        let editButtonText = NSLocalizedString("No, edit amount", comment: "The title of the action used when rejecting the the amount of carbohydrates entered.")
        let editAction = UIAlertAction(title: editButtonText, style: .default)
        alert.addAction(editAction)

        let confirmButtonText = NSLocalizedString("Yes", comment: "The title of the action used when confirming entered amount of carbohydrates.")
        let confirm = UIAlertAction(title: confirmButtonText, style: .default) {_ in
            didConfirm();
        }
        alert.addAction(confirm)
        alert.preferredAction = confirm

        viewController.present(alert, animated: true)
    }

    public func showMaxQuantityValidationWarning(for viewController: UIViewController, maxQuantityGrams: Double) {
        let errorTitle = NSLocalizedString("Input Maximum Exceeded", comment: "Title of the alert when carb input maximum was exceeded.")
        let message = String(
            format: NSLocalizedString("The maximum allowed amount is %@ grams.", comment: "Alert body displayed for quantity greater than max (1: maximum quantity in grams)"),
            NumberFormatter.localizedString(from: NSNumber(value: maxQuantityGrams), number: .none)
        )
        let alert = UIAlertController(title: errorTitle, message: message, preferredStyle: .alert)

        let action = UIAlertAction(title: dismissActionTitle, style: .default)
        alert.addAction(action)
        alert.preferredAction = action

        viewController.present(alert, animated: true)
    }
}


extension CarbEntryViewController: TextFieldTableViewCellDelegate {
    func textFieldTableViewCellDidBeginEditing(_ cell: TextFieldTableViewCell) {
        // Collapse any date picker cells to save space
        tableView.beginUpdates()
        hideDatePickerCells()
        tableView.endUpdates()
    }

    func textFieldTableViewCellDidChangeEditing(_ cell: TextFieldTableViewCell) {
        guard let row = tableView.indexPath(for: cell)?.row else { return }

        switch DetailsRow(rawValue: row) {
        case .value?:
            if let cell = cell as? DecimalTextFieldTableViewCell, let number = cell.number {
                quantity = HKQuantity(unit: preferredCarbUnit, doubleValue: number.doubleValue)
            } else {
                quantity = nil
            }
        case .foodType?:
            foodType = cell.textField.text
        default:
            break
        }
    }

    func textFieldTableViewCellDidEndEditing(_ cell: TextFieldTableViewCell) {
        textFieldTableViewCellDidChangeEditing(cell)
    }
}

extension CarbEntryViewController: DatePickerTableViewCellDelegate {
    func datePickerTableViewCellDidUpdateDate(_ cell: DatePickerTableViewCell) {
        guard let row = tableView.indexPath(for: cell)?.row else { return }

        switch DetailsRow(rawValue: row) {
        case .date?:
            date = cell.date
        case .absorptionTime?:
            absorptionTime = cell.duration
            absorptionTimeWasEdited = true
        default:
            break
        }
    }
}


extension CarbEntryViewController: FoodTypeShortcutCellDelegate {
    func foodTypeShortcutCellDidUpdateSelection(_ cell: FoodTypeShortcutCell) {
        var absorptionTime: TimeInterval?

        switch cell.selectionState {
        case .fast:
            absorptionTime = defaultAbsorptionTimes?.fast
        case .medium:
            absorptionTime = defaultAbsorptionTimes?.medium
        case .slow:
            absorptionTime = defaultAbsorptionTimes?.slow
        case .custom:
            tableView.beginUpdates()
            usesCustomFoodType = true
            shouldBeginEditingFoodType = true
            tableView.reloadRows(at: [IndexPath(row: DetailsRow.foodType.rawValue, section: Sections.indexForDetailsSection(displayWarningSection: shouldDisplayWarning))], with: .fade)
            tableView.endUpdates()
        }

        if let absorptionTime = absorptionTime {
            self.absorptionTime = absorptionTime

            if let cell = tableView.cellForRow(at: IndexPath(row: DetailsRow.absorptionTime.rawValue, section: Sections.indexForDetailsSection(displayWarningSection: shouldDisplayWarning))) as? DateAndDurationTableViewCell {
                cell.duration = absorptionTime
            }
        }

        selectedDefaultAbsorptionTimeEmoji = cell.selectedEmoji
    }
}


extension CarbEntryViewController: EmojiInputControllerDelegate {
    func emojiInputControllerDidAdvanceToStandardInputMode(_ controller: EmojiInputController) {
        if let cell = tableView.cellForRow(at: IndexPath(row: DetailsRow.foodType.rawValue, section: Sections.indexForDetailsSection(displayWarningSection: shouldDisplayWarning))) as? TextFieldTableViewCell, let textField = cell.textField as? CustomInputTextField, textField.customInput != nil {
            let customInput = textField.customInput
            textField.customInput = nil
            textField.resignFirstResponder()
            textField.becomeFirstResponder()
            textField.customInput = customInput
        }
    }

    func emojiInputControllerDidSelectItemInSection(_ section: Int) {
        guard !absorptionTimeWasEdited, section < orderedAbsorptionTimes.count else {
            return
        }

        if absorptionTime == nil {
            // only adjust the absorption time if it wasn't already set.
            absorptionTime = orderedAbsorptionTimes[section]
            
            if let cell = tableView.cellForRow(at: IndexPath(row: DetailsRow.absorptionTime.rawValue, section: Sections.indexForDetailsSection(displayWarningSection: shouldDisplayWarning))) as? DateAndDurationTableViewCell {
                cell.duration = orderedAbsorptionTimes[section]
            }
        }
    }
}

extension DateAndDurationTableViewCell: NibLoadable {}

extension DateAndDurationSteppableTableViewCell: NibLoadable {}
