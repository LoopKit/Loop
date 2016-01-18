//
//  CarbEntryEditViewController.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 1/15/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import UIKit

class CarbEntryEditViewController: UITableViewController, DatePickerTableViewCellDelegate, TextFieldTableViewCellDelegate {

    var defaultAbsorptionTimes: [NSTimeInterval] = [] {
        didSet {
            if defaultAbsorptionTimes.count > 0 && originalCarbEntry == nil {
                absorptionTime = defaultAbsorptionTimes[defaultAbsorptionTimes.count / 2]
            }
        }
    }

    var originalCarbEntry: CarbEntry? {
        didSet {
            if let entry = originalCarbEntry {
                value = entry.value
                date = entry.startDate
                foodType = entry.foodType
                absorptionTime = entry.absorptionTime
            }
        }
    }

    private var value: Double?

    private var date = NSDate()

    private var foodType: String?

    private var absorptionTime: NSTimeInterval?

    var updatedCarbEntry: CarbEntry? {
        if let  value = value,
                absorptionTime = absorptionTime
        {
            if let o = originalCarbEntry where o.value == value && o.startDate == date && o.foodType == foodType && o.absorptionTime == absorptionTime {
                return nil  // No changes were made
            }

            return NewCarbEntry(value: value, startDate: date, foodType: foodType, absorptionTime: absorptionTime)
        } else {
            return nil
        }
    }

    private var isSampleEditable: Bool {
        return originalCarbEntry?.createdByCurrentApp != false
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        tableView.estimatedRowHeight = 44

        if originalCarbEntry != nil {
            title = NSLocalizedString("carb-entry-title-edit", tableName: "CarbKit", value: "Edit Carb Entry", comment: "The title of the view controller to edit an existing carb entry")
        } else {
            title = NSLocalizedString("carb-entry-title-add", tableName: "CarbKit", value: "Add Carb Entry", comment: "The title of the view controller to create a new carb entry")
        }
    }

    @IBOutlet var segmentedControlInputAccessoryView: SegmentedControlInputAccessoryView!

    // MARK: - Table view data source

    private enum Row: Int {
        case Value
        case Date
        case AbsorptionTime
    }

    override func numberOfSectionsInTableView(tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return 3
    }

    override func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        switch Row(rawValue: indexPath.row)! {
        case .Value:
            let cell = tableView.dequeueReusableCellWithIdentifier(DecimalTextFieldTableViewCell.defaultIdentifier) as! DecimalTextFieldTableViewCell

            if let value = value {
                cell.number = NSNumber(double: value)
            }
            cell.textField.enabled = isSampleEditable
            cell.delegate = self

            return cell
        case .Date:
            let cell = tableView.dequeueReusableCellWithIdentifier(DatePickerTableViewCell.defaultIdentifier) as! DatePickerTableViewCell

            cell.date = date
            cell.datePicker.enabled = isSampleEditable
            cell.delegate = self

            return cell
        case .AbsorptionTime:
            let cell = tableView.dequeueReusableCellWithIdentifier(AbsorptionTimeTextFieldTableViewCell.defaultIdentifier) as! AbsorptionTimeTextFieldTableViewCell

            if let absorptionTime = absorptionTime {
                cell.number = NSNumber(double: absorptionTime.minutes)
            }
            cell.segmentValues = defaultAbsorptionTimes.map { $0.minutes }
            cell.segmentedControlInputAccessoryView = segmentedControlInputAccessoryView
            cell.delegate = self

            return cell
        }
    }

    // MARK: - UITableViewDelegate

    override func tableView(tableView: UITableView, willSelectRowAtIndexPath indexPath: NSIndexPath) -> NSIndexPath? {

        tableView.endEditing(false)
        tableView.beginUpdates()
        return indexPath
    }

    override func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
        tableView.endUpdates()
        tableView.deselectRowAtIndexPath(indexPath, animated: true)
    }

    // MARK: - Navigation

    override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
        self.tableView.endEditing(true)
    }

    // MARK: - DatePickerTableViewCellDelegate

    func datePickerTableViewCellDidUpdateDate(cell: DatePickerTableViewCell) {
        date = cell.date
    }

    // MARK: - TextFieldTableViewCellDelegate

    func textFieldTableViewCellDidUpdateText(cell: DecimalTextFieldTableViewCell) {
        switch Row(rawValue: tableView.indexPathForCell(cell)?.row ?? -1) {
        case .Value?:
            if let number = cell.number {
                value = number.doubleValue
            } else {
                value = nil
            }
        case .AbsorptionTime?:
            if let number = cell.number {
                absorptionTime = NSTimeInterval(minutes: number.doubleValue)
            } else {
                absorptionTime = nil
            }
        default:
            break
        }
    }
}
