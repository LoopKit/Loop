//
//  CarbEntryEditViewController.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 1/15/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import UIKit

class CarbEntryEditViewController: UITableViewController, DatePickerTableViewCellDelegate {

    var originalCarbEntry: CarbEntry? {
        didSet {
            if let entry = originalCarbEntry {
                amount = entry.amount
                date = entry.startDate
                foodType = entry.foodType
                absorptionTime = entry.absorptionTime
            }
        }
    }

    private var amount: Double?

    private var date = NSDate()

    private var foodType: String?

    private var absorptionTime: NSTimeInterval?

    var updatedCarbEntry: CarbEntry? {
        if let  amount = amount,
                absorptionTime = absorptionTime
        {
            return NewCarbEntry(amount: amount, startDate: date, foodType: foodType, absorptionTime: absorptionTime)
        } else {
            return nil
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        tableView.estimatedRowHeight = 44

        if originalCarbEntry != nil {
            title = NSLocalizedString("carb-entry-title-edit", tableName: "CarbKit", value: "Add Carb Entry", comment: "The title of the view controller to edit an existing carb entry")
        } else {
            title = NSLocalizedString("carb-entry-title-add", tableName: "CarbKit", value: "Add Carb Entry", comment: "The title of the view controller to create a new carb entry")
        }
    }

    // MARK: - Table view data source

    private enum Row: Int {
        case Amount
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
        case .Amount:
            let cell = tableView.dequeueReusableCellWithIdentifier(TextFieldTableViewCell.defaultIdentifier) as! TextFieldTableViewCell

            return cell
        case .Date:
            let cell = tableView.dequeueReusableCellWithIdentifier(DatePickerTableViewCell.defaultIdentifier) as! DatePickerTableViewCell

            cell.date = date
            cell.delegate = self

            return cell
        case .AbsorptionTime:
            let cell = tableView.dequeueReusableCellWithIdentifier(SegmentedControlTableViewCell.defaultIdentifier) as! SegmentedControlTableViewCell

            return cell
        }
    }

    // MARK: - UITableViewDelegate

    override func tableView(tableView: UITableView, willSelectRowAtIndexPath indexPath: NSIndexPath) -> NSIndexPath? {

        // Don't allow selection of rows we can't edit
        guard originalCarbEntry?.createdByCurrentApp != false else {
            return nil
        }

        let currentSelection = Row(rawValue: tableView.indexPathForSelectedRow?.row ?? -1)
        let newSelection = Row(rawValue: indexPath.row)!

        switch (currentSelection, newSelection)  {
        case (_, .AbsorptionTime):
            return nil
        case (let x, let y) where x == y:
            tableView.beginUpdates()
            tableView.deselectRowAtIndexPath(indexPath, animated: true)
            tableView.endUpdates()

            return nil
        default:
            tableView.beginUpdates()

            return indexPath
        }
    }

    override func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
        tableView.endUpdates()

        if case .Amount? = Row(rawValue: indexPath.row) {
            tableView.deselectRowAtIndexPath(indexPath, animated: true)
        }
    }

    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
        // Get the new view controller using segue.destinationViewController.
        // Pass the selected object to the new view controller.
    }
    */

    // MARK: - DatePickerTableViewCellDelegate

    func datePickerTableViewCellDidUpdateDate(cell: DatePickerTableViewCell) {
        date = cell.date
    }
}
