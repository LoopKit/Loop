//
//  SingleValueScheduleTableViewController.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 2/13/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import UIKit

public class SingleValueScheduleTableViewController: DailyValueScheduleTableViewController, RepeatingScheduleValueTableViewCellDelegate {

    public override func viewDidLoad() {
        super.viewDidLoad()

        tableView.registerNib(UINib(nibName: RepeatingScheduleValueTableViewCell.className, bundle: NSBundle(forClass: self.dynamicType)), forCellReuseIdentifier: RepeatingScheduleValueTableViewCell.className)
    }

    // MARK: - State

    public var scheduleItems: [RepeatingScheduleValue<Double>] = []

    override func addScheduleItem(sender: AnyObject?) {
        tableView.endEditing(false)

        var startTime = NSTimeInterval(0)
        var value = 0.0

        if scheduleItems.count > 0, let cell = tableView.cellForRowAtIndexPath(NSIndexPath(forRow: scheduleItems.count - 1, inSection: 0)) as? RepeatingScheduleValueTableViewCell {
            let lastItem = scheduleItems.last!
            let interval = cell.datePickerInterval

            startTime = lastItem.startTime + interval
            value = lastItem.value

            if startTime >= NSTimeInterval(hours: 24) {
                return
            }
        }

        scheduleItems.append(
            RepeatingScheduleValue(
                startTime: min(NSTimeInterval(hours: 23.5), startTime),
                value: value
            )
        )

        super.addScheduleItem(sender)
    }

    override func insertableIndiciesByRemovingRow(row: Int, withInterval timeInterval: NSTimeInterval) -> [Bool] {
        return insertableIndicesForScheduleItems(scheduleItems, byRemovingRow: row, withInterval: timeInterval)
    }

    func preferredValueMinimumFractionDigits() -> Int {
        return 1
    }

    // MARK: - UITableViewDataSource

    public override func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return scheduleItems.count
    }

    public override func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCellWithIdentifier(RepeatingScheduleValueTableViewCell.className, forIndexPath: indexPath) as! RepeatingScheduleValueTableViewCell

        let item = scheduleItems[indexPath.row]
        let interval = cell.datePickerInterval

        cell.date = midnight.dateByAddingTimeInterval(item.startTime)

        cell.valueNumberFormatter.minimumFractionDigits = preferredValueMinimumFractionDigits()

        cell.value = item.value
        cell.unitString = unitString
        cell.delegate = self

        if indexPath.row > 0 {
            let lastItem = scheduleItems[indexPath.row - 1]

            cell.datePicker.minimumDate = midnight.dateByAddingTimeInterval(lastItem.startTime).dateByAddingTimeInterval(interval)
        }

        if indexPath.row < scheduleItems.endIndex - 1 {
            let nextItem = scheduleItems[indexPath.row + 1]

            cell.datePicker.maximumDate = midnight.dateByAddingTimeInterval(nextItem.startTime).dateByAddingTimeInterval(-interval)
        } else {
            cell.datePicker.maximumDate = midnight.dateByAddingTimeInterval(NSTimeInterval(hours: 24) - interval)
            
        }
        
        return cell
    }

    public override func tableView(tableView: UITableView, commitEditingStyle editingStyle: UITableViewCellEditingStyle, forRowAtIndexPath indexPath: NSIndexPath) {
        if editingStyle == .Delete {
            scheduleItems.removeAtIndex(indexPath.row)

            super.tableView(tableView, commitEditingStyle: editingStyle, forRowAtIndexPath: indexPath)
        }
    }

    public override func tableView(tableView: UITableView, moveRowAtIndexPath sourceIndexPath: NSIndexPath, toIndexPath destinationIndexPath: NSIndexPath) {

        if sourceIndexPath != destinationIndexPath {
            let item = scheduleItems.removeAtIndex(sourceIndexPath.row)
            scheduleItems.insert(item, atIndex: destinationIndexPath.row)

            guard destinationIndexPath.row > 0, let cell = tableView.cellForRowAtIndexPath(destinationIndexPath) as? RepeatingScheduleValueTableViewCell else {
                return
            }

            let interval = cell.datePickerInterval
            let startTime = scheduleItems[destinationIndexPath.row - 1].startTime + interval

            scheduleItems[destinationIndexPath.row] = RepeatingScheduleValue(startTime: startTime, value: scheduleItems[destinationIndexPath.row].value)

            // Since the valid date ranges of neighboring cells are affected, the lazy solution is to just reload the entire table view
            dispatch_async(dispatch_get_main_queue()) {
                tableView.reloadData()
            }
        }
    }

    // MARK: - UITableViewDelegate

    public override func tableView(tableView: UITableView, targetIndexPathForMoveFromRowAtIndexPath sourceIndexPath: NSIndexPath, toProposedIndexPath proposedDestinationIndexPath: NSIndexPath) -> NSIndexPath {

        guard sourceIndexPath != proposedDestinationIndexPath, let cell = tableView.cellForRowAtIndexPath(sourceIndexPath) as? RepeatingScheduleValueTableViewCell else {
            return proposedDestinationIndexPath
        }

        let interval = cell.datePickerInterval
        let insertableIndices = insertableIndicesForScheduleItems(scheduleItems, byRemovingRow: sourceIndexPath.row, withInterval: interval)

        if insertableIndices[proposedDestinationIndexPath.row] {
            return proposedDestinationIndexPath
        } else {
            var closestRow = sourceIndexPath.row

            for (index, valid) in insertableIndices.enumerate() where valid {
                if abs(proposedDestinationIndexPath.row - index) < closestRow {
                    closestRow = index
                }
            }

            return NSIndexPath(forRow: closestRow, inSection: proposedDestinationIndexPath.section)
        }
    }

    // MARK: - RepeatingScheduleValueTableViewCellDelegate

    override func repeatingScheduleValueTableViewCellDidUpdateDate(cell: RepeatingScheduleValueTableViewCell) {
        if let indexPath = tableView.indexPathForCell(cell) {
            let currentItem = scheduleItems[indexPath.row]

            scheduleItems[indexPath.row] = RepeatingScheduleValue(
                startTime: cell.date.timeIntervalSinceDate(midnight),
                value: currentItem.value
            )
        }

        super.repeatingScheduleValueTableViewCellDidUpdateDate(cell)
    }

    func repeatingScheduleValueTableViewCellDidUpdateValue(cell: RepeatingScheduleValueTableViewCell) {
        if let indexPath = tableView.indexPathForCell(cell) {
            let currentItem = scheduleItems[indexPath.row]

            scheduleItems[indexPath.row] = RepeatingScheduleValue(startTime: currentItem.startTime, value: cell.value)
        }
    }

}
