//
//  BasalRateScheduleTableViewController.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 2/6/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import UIKit
import LoopKit


class BasalRateScheduleTableViewController: UITableViewController {

    private var keyboardWillShowNotificationObserver: AnyObject?

    override func viewDidLoad() {
        super.viewDidLoad()

        self.navigationItem.rightBarButtonItem = self.editButtonItem()

        keyboardWillShowNotificationObserver = NSNotificationCenter.defaultCenter().addObserverForName(UIKeyboardWillShowNotification, object: nil, queue: NSOperationQueue.mainQueue(), usingBlock: { [unowned self] (note) -> Void in

            guard note.userInfo?[UIKeyboardIsLocalUserInfoKey] as? Bool == true else {
                return
            }

            let animated = note.userInfo?[UIKeyboardAnimationDurationUserInfoKey] as? Double ?? 0 > 0

            if let indexPath = self.tableView.indexPathForSelectedRow {
                self.tableView.beginUpdates()
                self.tableView.deselectRowAtIndexPath(indexPath, animated: animated)
                self.tableView.endUpdates()
            }
        })
    }

    override func setEditing(editing: Bool, animated: Bool) {
        if let indexPath = tableView.indexPathForSelectedRow {
            tableView.beginUpdates()
            tableView.deselectRowAtIndexPath(indexPath, animated: animated)
            tableView.endUpdates()
        }

        tableView.endEditing(false)

        super.setEditing(editing, animated: animated)
    }

    deinit {
        if let observer = keyboardWillShowNotificationObserver {
            NSNotificationCenter.defaultCenter().removeObserver(observer)
        }
    }

    var scheduleItems: [RepeatingScheduleValue] = []

    var timeZone = NSTimeZone.localTimeZone() {
        didSet {
            calendar.timeZone = timeZone
        }
    }

    private var calendar = NSCalendar.currentCalendar()

    // MARK: - UITableViewDataSource

    override func numberOfSectionsInTableView(tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return scheduleItems.count
    }

    override func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCellWithIdentifier("RepeatingScheduleValueTableViewCell", forIndexPath: indexPath) as! RepeatingScheduleValueTableViewCell

        let item = scheduleItems[indexPath.row]
        let midnight = calendar.startOfDayForDate(NSDate(timeIntervalSinceReferenceDate: 0))
        let interval = NSTimeInterval(minutes: Double(cell.datePicker.minuteInterval))

        cell.value = item.value
        cell.date = midnight.dateByAddingTimeInterval(item.startTime)

        if indexPath.row > 0 {
            let lastItem = scheduleItems[indexPath.row - 1]

            cell.datePicker.minimumDate = midnight.dateByAddingTimeInterval(lastItem.startTime).dateByAddingTimeInterval(interval)
        }

        if indexPath.row < scheduleItems.count - 1 {
            let nextItem = scheduleItems[indexPath.row + 1]

            cell.datePicker.maximumDate = midnight.dateByAddingTimeInterval(nextItem.startTime).dateByAddingTimeInterval(-interval)
        } else {
            cell.datePicker.maximumDate = midnight.dateByAddingTimeInterval(NSTimeInterval(hours: 24) - interval)
        }

        return cell
    }

    override func tableView(tableView: UITableView, canEditRowAtIndexPath indexPath: NSIndexPath) -> Bool {
        return true
    }

    override func tableView(tableView: UITableView, commitEditingStyle editingStyle: UITableViewCellEditingStyle, forRowAtIndexPath indexPath: NSIndexPath) {
        if editingStyle == .Delete {
            // Delete the row from the data source
            tableView.deleteRowsAtIndexPaths([indexPath], withRowAnimation: .Automatic)
        }
    }

    // MARK: - UITableViewDelegate

    override func tableView(tableView: UITableView, heightForRowAtIndexPath indexPath: NSIndexPath) -> CGFloat {
        return tableView.indexPathForSelectedRow == indexPath ? 196 : 44
    }

    override func tableView(tableView: UITableView, shouldHighlightRowAtIndexPath indexPath: NSIndexPath) -> Bool {
        return indexPath.row > 0
    }

    override func tableView(tableView: UITableView, willSelectRowAtIndexPath indexPath: NSIndexPath) -> NSIndexPath? {
        if indexPath == tableView.indexPathForSelectedRow {
            tableView.beginUpdates()
            tableView.deselectRowAtIndexPath(indexPath, animated: false)
            tableView.endUpdates()

            return nil
        } else if indexPath.row == 0 {
            return nil
        }

        return indexPath
    }

    override func tableView(tableView: UITableView, didDeselectRowAtIndexPath indexPath: NSIndexPath) {
        tableView.beginUpdates()
        tableView.endUpdates()
    }

    override func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
        tableView.endEditing(false)
        tableView.beginUpdates()
        tableView.endUpdates()
    }
}
