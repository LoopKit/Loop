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

    var navigationDelegate = CarbEntryNavigationDelegate()

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
        return deviceManager.glucoseStore.preferredUnit ?? .milligramsPerDeciliter
    }

    var maxQuantity = HKQuantity(unit: .gram(), doubleValue: 250)

    /// Entry configuration values. Must be set before presenting.
    var absorptionTimePickerInterval = TimeInterval(minutes: 30)

    var maxAbsorptionTime = TimeInterval(hours: 8)

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
                DispatchQueue.main.async {
                    self.displayAccuracyWarning()
                }
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
                foodType: foodType,
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

        if shouldBeginEditingQuantity, let cell = tableView.cellForRow(at: IndexPath(row: DetailsRow.value.rawValue, section: Sections.indexForDetailsSection(displayWarningSection: shouldDisplayAccurateCarbEntryWarning))) as? DecimalTextFieldTableViewCell {
            shouldBeginEditingQuantity = false
            cell.textField.becomeFirstResponder()
        }

        // check if the warning should be displayed
        updateDisplayAccurateCarbEntryWarning()
        
        // monitor loop updates
        notificationObservers += [
            NotificationCenter.default.addObserver(forName: .LoopDataUpdated, object: deviceManager.loopManager, queue: nil) { [weak self] _ in
                self?.updateDisplayAccurateCarbEntryWarning()
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
        deviceManager.loopManager.getLoopState { [weak self] (_, state) in
            let endDate = Date()
            let startDate = endDate.addingTimeInterval(.minutes(-20))
            let threshold = HKQuantity(unit: GlucoseEffectVelocity.unit, doubleValue: 3)

            let filteredInsulinCounteractionEffects = state.insulinCounteractionEffects.filterDateRange(startDate, endDate)

            // at least 3 insulin counteraction effects are required to calculate the average
            guard filteredInsulinCounteractionEffects.count >= 3,
                let averageInsulinCounteractionEffect = filteredInsulinCounteractionEffects.average(unit: GlucoseEffectVelocity.unit) else
            {
                self?.shouldDisplayAccurateCarbEntryWarning = false
                return
            }

            self?.shouldDisplayAccurateCarbEntryWarning = averageInsulinCounteractionEffect >= threshold
        }
    }
    
    private func displayAccuracyWarning() {
        tableView.beginUpdates()

        if shouldDisplayAccurateCarbEntryWarning {
            tableView.insertSections([Sections.warning.rawValue], with: .top)
        } else {
            tableView.deleteSections([Sections.warning.rawValue], with: .top)
        }
        
        tableView.endUpdates()
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
        
        static func numberOfRows(for section: Int, displayWarningSection: Bool) -> Int {
            if section == Sections.warning.rawValue && displayWarningSection {
                return 1
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

    override func numberOfSections(in tableView: UITableView) -> Int {
        return Sections.numberOfSections(displayWarningSection: shouldDisplayAccurateCarbEntryWarning)
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return Sections.numberOfRows(for: section, displayWarningSection: shouldDisplayAccurateCarbEntryWarning)
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch Sections(rawValue: Sections.section(for: indexPath, displayWarningSection: shouldDisplayAccurateCarbEntryWarning))! {
        case .warning:
            let cell: UITableViewCell
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
            
                cell.titleLabel.text = NSLocalizedString("Date", comment: "Title of the carb entry date picker cell")
                cell.datePicker.isEnabled = isSampleEditable
                cell.datePicker.datePickerMode = .dateAndTime
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
        switch Sections(rawValue: Sections.section(for: indexPath, displayWarningSection: shouldDisplayAccurateCarbEntryWarning)) {
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
        return Sections.footer(for: section, displayWarningSection: shouldDisplayAccurateCarbEntryWarning)
    }
    
    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return Sections.headerHeight(for: section, displayWarningSection: shouldDisplayAccurateCarbEntryWarning)
    }
    
    override func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        return Sections.footerHeight(for: section, displayWarningSection: shouldDisplayAccurateCarbEntryWarning)
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
            tableView.reloadRows(at: [IndexPath(row: DetailsRow.foodType.rawValue, section: Sections.indexForDetailsSection(displayWarningSection: shouldDisplayAccurateCarbEntryWarning))], with: .none)
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
        guard validateInput(), let updatedEntry = updatedCarbEntry else {
            return
        }

        let viewModel = BolusEntryViewModel(
            delegate: deviceManager,
            originalCarbEntry: originalCarbEntry,
            potentialCarbEntry: updatedEntry,
            selectedCarbAbsorptionTimeEmoji: selectedDefaultAbsorptionTimeEmoji
        )

        let bolusEntryView = BolusEntryView(viewModel: viewModel)

        // After confirming a bolus, pop back to this controller's predecessor, i.e. all the way back out of the carb flow.
        let predecessorViewControllerType = (navigationController?.viewControllers.dropLast().last).map { type(of: $0) } ?? UIViewController.self
        let hostingController = DismissibleHostingController(
            rootView: bolusEntryView,
            dismissalMode: originalCarbEntry == nil ? .modalDismiss : .pop(to: predecessorViewControllerType)
        )
        show(hostingController, sender: footerView.primaryButton)
    }

    private func validateInput() -> Bool {
        guard let absorptionTime = absorptionTime ?? defaultAbsorptionTimes?.medium else {
            return false
        }
        guard absorptionTime <= maxAbsorptionTime else {
            navigationDelegate.showAbsorptionTimeValidationWarning(for: self, maxAbsorptionTime: maxAbsorptionTime)
            return false
        }

        guard let quantity = quantity, quantity.doubleValue(for: preferredCarbUnit) > 0 else { return false }
        guard quantity.compare(maxQuantity) != .orderedDescending else {
            navigationDelegate.showMaxQuantityValidationWarning(for: self, maxQuantityGrams: maxQuantity.doubleValue(for: .gram()))
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
            tableView.reloadRows(at: [IndexPath(row: DetailsRow.foodType.rawValue, section: Sections.indexForDetailsSection(displayWarningSection: shouldDisplayAccurateCarbEntryWarning))], with: .fade)
            tableView.endUpdates()
        }

        if let absorptionTime = absorptionTime {
            self.absorptionTime = absorptionTime

            if let cell = tableView.cellForRow(at: IndexPath(row: DetailsRow.absorptionTime.rawValue, section: Sections.indexForDetailsSection(displayWarningSection: shouldDisplayAccurateCarbEntryWarning))) as? DateAndDurationTableViewCell {
                cell.duration = absorptionTime
            }
        }

        selectedDefaultAbsorptionTimeEmoji = cell.selectedEmoji
    }
}


extension CarbEntryViewController: EmojiInputControllerDelegate {
    func emojiInputControllerDidAdvanceToStandardInputMode(_ controller: EmojiInputController) {
        if let cell = tableView.cellForRow(at: IndexPath(row: DetailsRow.foodType.rawValue, section: Sections.indexForDetailsSection(displayWarningSection: shouldDisplayAccurateCarbEntryWarning))) as? TextFieldTableViewCell, let textField = cell.textField as? CustomInputTextField, textField.customInput != nil {
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
            
            if let cell = tableView.cellForRow(at: IndexPath(row: DetailsRow.absorptionTime.rawValue, section: Sections.indexForDetailsSection(displayWarningSection: shouldDisplayAccurateCarbEntryWarning))) as? DateAndDurationTableViewCell {
                cell.duration = orderedAbsorptionTimes[section]
            }
        }
    }
}

extension DateAndDurationTableViewCell: NibLoadable {}

extension DateAndDurationSteppableTableViewCell: NibLoadable {}
