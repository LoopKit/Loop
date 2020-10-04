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


final class CarbEntryViewController: ChartsTableViewController, IdentifiableClass {

    var navigationDelegate = CarbEntryNavigationDelegate()

    var defaultAbsorptionTimes: CarbStore.DefaultAbsorptionTimes? {
        didSet {
            if let times = defaultAbsorptionTimes {
                orderedAbsorptionTimes = [times.fast, times.medium, times.slow]
            }
        }
    }

    fileprivate var orderedAbsorptionTimes = [TimeInterval]()

    var preferredUnit = HKUnit.gram()

    var maxQuantity = HKQuantity(unit: .gram(), doubleValue: 250)

    /// Entry configuration values. Must be set before presenting.
    var absorptionTimePickerInterval = TimeInterval(minutes: 30)

    var maxAbsorptionTime = TimeInterval(hours: 8)

    var maximumDateFutureInterval = TimeInterval(hours: 4)

    var glucoseUnit: HKUnit = .milligramsPerDeciliter

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

    fileprivate var quantity: HKQuantity? {
        didSet {
            updateContinueButtonEnabled()
        }
    }

    fileprivate var date = Date() {
        didSet {
            updateContinueButtonEnabled()
        }
    }

    fileprivate var foodType: String? {
        didSet {
            updateContinueButtonEnabled()
        }
    }

    fileprivate var absorptionTime: TimeInterval? {
        didSet {
            updateContinueButtonEnabled()
        }
    }

    private var selectedDefaultAbsorptionTimeEmoji: String?

    fileprivate var absorptionTimeWasEdited = false

    fileprivate var usesCustomFoodType = false

    private var shouldBeginEditingQuantity = true

    private var shouldBeginEditingFoodType = false

    var updatedCarbEntry: NewCarbEntry? {
        if  let quantity = quantity,
            let absorptionTime = absorptionTime ?? defaultAbsorptionTimes?.medium
        {
            if let o = originalCarbEntry, o.quantity == quantity && o.startDate == date && o.foodType == foodType && o.absorptionTime == absorptionTime {
                return nil  // No changes were made
            }

            return NewCarbEntry(
                quantity: quantity,
                startDate: date,
                foodType: foodType,
                absorptionTime: absorptionTime,
                externalID: originalCarbEntry?.externalID
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
        footerView.primaryButton.isEnabled = quantity != nil && quantity!.doubleValue(for: preferredUnit) > 0
        return footerView
    }()

    private var lastContentHeight: CGFloat = 0

    override func createChartsManager() -> ChartsManager {
        // Consider including a chart on this screen to demonstrate how absorption time affects prediction
        ChartsManager(colors: .default, settings: .default, charts: [], traitCollection: traitCollection)
    }

    override func glucoseUnitDidChange() {
        // Consider including a chart on this screen to demonstrate how absorption time affects prediction
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        // This gets rid of the empty space at the top.
        tableView.tableHeaderView = UIView(frame: CGRect(x: 0, y: 0, width: tableView.bounds.size.width, height: 0.01))

        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 44
        tableView.register(DateAndDurationTableViewCell.nib(), forCellReuseIdentifier: DateAndDurationTableViewCell.className)

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

        if shouldBeginEditingQuantity, let cell = tableView.cellForRow(at: IndexPath(row: Row.value.rawValue, section: 0)) as? DecimalTextFieldTableViewCell {
            shouldBeginEditingQuantity = false
            cell.textField.becomeFirstResponder()
        }
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

    // MARK: - Table view data source

    fileprivate enum Row: Int {
        case value
        case date
        case foodType
        case absorptionTime

        static let count = 4
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return Row.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch Row(rawValue: indexPath.row)! {
        case .value:
            let cell = tableView.dequeueReusableCell(withIdentifier: DecimalTextFieldTableViewCell.className) as! DecimalTextFieldTableViewCell

            if let quantity = quantity {
                cell.number = NSNumber(value: quantity.doubleValue(for: preferredUnit))
            }
            cell.textField.isEnabled = isSampleEditable
            cell.unitLabel?.text = String(describing: preferredUnit)
            cell.delegate = self

            return cell
        case .date:
            let cell = tableView.dequeueReusableCell(withIdentifier: DateAndDurationTableViewCell.className) as! DateAndDurationTableViewCell

            cell.titleLabel.text = NSLocalizedString("Date", comment: "Title of the carb entry date picker cell")
            cell.datePicker.isEnabled = isSampleEditable
            cell.datePicker.datePickerMode = .dateAndTime
            #if swift(>=5.2)
                if #available(iOS 14.0, *) {
                    cell.datePicker.preferredDatePickerStyle = .wheels
                }
            #endif
            cell.datePicker.maximumDate = Date(timeIntervalSinceNow: maximumDateFutureInterval)
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

    override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        switch Row(rawValue: indexPath.row)! {
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
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        return NSLocalizedString("Choose a longer absorption time for larger meals, or those containing fats and proteins. This is only guidance to the algorithm and need not be exact.", comment: "Carb entry section footer text explaining absorption time")
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
            tableView.reloadRows(at: [IndexPath(row: Row.foodType.rawValue, section: 0)], with: .none)
        default:
            break
        }

        tableView.endUpdates()
        tableView.deselectRow(at: indexPath, animated: true)
    }

    // MARK: - Navigation

    override func restoreUserActivityState(_ activity: NSUserActivity) {
        if let entry = activity.newCarbEntry {
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

        let bolusVC = BolusViewController.instance()
        bolusVC.deviceManager = deviceManager
        bolusVC.glucoseUnit = glucoseUnit
        if let originalEntry = originalCarbEntry {
            bolusVC.configuration = .updatedCarbEntry(from: originalEntry, to: updatedEntry)
        } else {
            bolusVC.configuration = .newCarbEntry(updatedEntry)
        }
        bolusVC.selectedDefaultAbsorptionTimeEmoji = selectedDefaultAbsorptionTimeEmoji

        show(bolusVC, sender: footerView.primaryButton)
    }

    private func validateInput() -> Bool {
        guard let absorptionTime = absorptionTime ?? defaultAbsorptionTimes?.medium else {
            return false
        }
        guard absorptionTime <= maxAbsorptionTime else {
            navigationDelegate.showAbsorptionTimeValidationWarning(for: self, maxAbsorptionTime: maxAbsorptionTime)
            return false
        }

        guard let quantity = quantity, quantity.doubleValue(for: preferredUnit) > 0 else { return false }
        guard quantity.compare(maxQuantity) != .orderedDescending else {
            navigationDelegate.showMaxQuantityValidationWarning(for: self, maxQuantityGrams: maxQuantity.doubleValue(for: .gram()))
            return false
        }

        return true
    }

    private func updateContinueButtonEnabled() {
        let hasValidQuantity = quantity != nil && quantity!.doubleValue(for: preferredUnit) > 0
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

    func textFieldTableViewCellDidEndEditing(_ cell: TextFieldTableViewCell) {
        guard let row = tableView.indexPath(for: cell)?.row else { return }

        switch Row(rawValue: row) {
        case .value?:
            if let cell = cell as? DecimalTextFieldTableViewCell, let number = cell.number {
                quantity = HKQuantity(unit: preferredUnit, doubleValue: number.doubleValue)
            } else {
                quantity = nil
            }
        case .foodType?:
            foodType = cell.textField.text
        default:
            break
        }
    }

    func textFieldTableViewCellDidChangeEditing(_ cell: TextFieldTableViewCell) {
        guard let row = tableView.indexPath(for: cell)?.row else { return }

        switch Row(rawValue: row) {
        case .value?:
            if let cell = cell as? DecimalTextFieldTableViewCell, let number = cell.number {
                quantity = HKQuantity(unit: preferredUnit, doubleValue: number.doubleValue)
            } else {
                quantity = nil
            }
        default:
            break
        }
    }
}


extension CarbEntryViewController: DatePickerTableViewCellDelegate {
    func datePickerTableViewCellDidUpdateDate(_ cell: DatePickerTableViewCell) {
        guard let row = tableView.indexPath(for: cell)?.row else { return }

        switch Row(rawValue: row) {
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
            tableView.reloadRows(at: [IndexPath(row: Row.foodType.rawValue, section: 0)], with: .fade)
            tableView.endUpdates()
        }

        if let absorptionTime = absorptionTime {
            self.absorptionTime = absorptionTime

            if let cell = tableView.cellForRow(at: IndexPath(row: Row.absorptionTime.rawValue, section: 0)) as? DateAndDurationTableViewCell {
                cell.duration = absorptionTime
            }
        }

        selectedDefaultAbsorptionTimeEmoji = cell.selectedEmoji
    }
}


extension CarbEntryViewController: EmojiInputControllerDelegate {
    func emojiInputControllerDidAdvanceToStandardInputMode(_ controller: EmojiInputController) {
        if let cell = tableView.cellForRow(at: IndexPath(row: Row.foodType.rawValue, section: 0)) as? TextFieldTableViewCell, let textField = cell.textField as? CustomInputTextField, textField.customInput != nil {
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

        let lastAbsorptionTime = self.absorptionTime
        self.absorptionTime = orderedAbsorptionTimes[section]

        if let cell = tableView.cellForRow(at: IndexPath(row: Row.absorptionTime.rawValue, section: 0)) as? DateAndDurationTableViewCell {
            cell.duration = max(lastAbsorptionTime ?? 0, orderedAbsorptionTimes[section])
        }
    }
}

extension DateAndDurationTableViewCell: NibLoadable {}
