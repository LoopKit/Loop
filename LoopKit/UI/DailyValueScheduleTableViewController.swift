//
//  DailyValueScheduleTableViewController.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 2/6/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import UIKit


public protocol DailyValueScheduleTableViewControllerDelegate: class {
    func dailyValueScheduleTableViewControllerWillFinishUpdating(controller: DailyValueScheduleTableViewController)
}


func insertableIndicesForScheduleItems<T>(scheduleItems: [RepeatingScheduleValue<T>], byRemovingRow row: Int, withInterval interval: NSTimeInterval) -> [Bool] {

    let insertableIndices = scheduleItems.enumerate().map { (index, item) -> Bool in
        if row == index {
            return true
        } else if index == 0 {
            return false
        } else if index == scheduleItems.endIndex - 1 {
            return item.startTime < NSTimeInterval(hours: 24) - interval
        } else if index > row {
            return scheduleItems[index + 1].startTime - item.startTime > interval
        } else {
            return item.startTime - scheduleItems[index - 1].startTime > interval
        }
    }

    return insertableIndices
}


public class DailyValueScheduleTableViewController: UITableViewController, IdentifiableClass {

    private var keyboardWillShowNotificationObserver: AnyObject?

    public init() {
        super.init(style: .Plain)
    }

    public required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.rightBarButtonItems = [insertButtonItem(), editButtonItem()]

        tableView.keyboardDismissMode = .OnDrag

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

    public override func setEditing(editing: Bool, animated: Bool) {
        if let indexPath = tableView.indexPathForSelectedRow {
            tableView.beginUpdates()
            tableView.deselectRowAtIndexPath(indexPath, animated: animated)
            tableView.endUpdates()
        }

        tableView.endEditing(false)

        navigationItem.rightBarButtonItems?[0].enabled = !editing

        super.setEditing(editing, animated: animated)
    }

    deinit {
        if let observer = keyboardWillShowNotificationObserver {
            NSNotificationCenter.defaultCenter().removeObserver(observer)
        }
    }

    public override func viewWillDisappear(animated: Bool) {
        super.viewWillDisappear(animated)

        tableView.endEditing(true)

        if isMovingFromParentViewController() {
            delegate?.dailyValueScheduleTableViewControllerWillFinishUpdating(self)
        }
    }

    public weak var delegate: DailyValueScheduleTableViewControllerDelegate?

    public func insertButtonItem() -> UIBarButtonItem {
        return UIBarButtonItem(barButtonSystemItem: .Add, target: self, action: "addScheduleItem:")
    }

    // MARK: - State

    public var timeZone = NSTimeZone.localTimeZone() {
        didSet {
            calendar.timeZone = timeZone
        }
    }

    public var unitString: String = "U/hour"

    private var calendar = NSCalendar.currentCalendar()

    var midnight: NSDate {
        return calendar.startOfDayForDate(NSDate(timeIntervalSinceReferenceDate: 0))
    }

    func addScheduleItem(sender: AnyObject?) {
        // Updates the table view state. Subclasses should update their data model before calling super

        tableView.insertRowsAtIndexPaths([NSIndexPath(forRow: tableView.numberOfRowsInSection(0), inSection: 0)], withRowAnimation: .Automatic)
    }

    func insertableIndiciesByRemovingRow(row: Int, withInterval timeInterval: NSTimeInterval) -> [Bool] {
        fatalError("Subclasses must override __FUNCTION__")
    }

    // MARK: - UITableViewDataSource

    public override func numberOfSectionsInTableView(tableView: UITableView) -> Int {
        return 1
    }

    public override func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        fatalError("Subclasses must override __FUNCTION__")
    }

    public override func tableView(tableView: UITableView, canEditRowAtIndexPath indexPath: NSIndexPath) -> Bool {
        return true
    }

    public override func tableView(tableView: UITableView, canMoveRowAtIndexPath indexPath: NSIndexPath) -> Bool {
        return indexPath.row > 0
    }

    public override func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        fatalError("Subclasses must override __FUNCTION__")
    }

    public override func tableView(tableView: UITableView, commitEditingStyle editingStyle: UITableViewCellEditingStyle, forRowAtIndexPath indexPath: NSIndexPath) {
        if editingStyle == .Delete {
            // Updates the table view state. Subclasses should update their data model before calling super

            tableView.deleteRowsAtIndexPaths([indexPath], withRowAnimation: .Automatic)
        }
    }

    // MARK: - UITableViewDelegate

    public override func tableView(tableView: UITableView, heightForRowAtIndexPath indexPath: NSIndexPath) -> CGFloat {
        return tableView.indexPathForSelectedRow == indexPath ? 196 : 44
    }

    public override func tableView(tableView: UITableView, shouldHighlightRowAtIndexPath indexPath: NSIndexPath) -> Bool {
        return indexPath.row > 0
    }

    public override func tableView(tableView: UITableView, willSelectRowAtIndexPath indexPath: NSIndexPath) -> NSIndexPath? {
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

    public override func tableView(tableView: UITableView, didDeselectRowAtIndexPath indexPath: NSIndexPath) {
        tableView.beginUpdates()
        tableView.endUpdates()
    }

    public override func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
        tableView.endEditing(false)
        tableView.beginUpdates()
        tableView.endUpdates()
    }

    public override func tableView(tableView: UITableView, targetIndexPathForMoveFromRowAtIndexPath sourceIndexPath: NSIndexPath, toProposedIndexPath proposedDestinationIndexPath: NSIndexPath) -> NSIndexPath {

        guard sourceIndexPath != proposedDestinationIndexPath, let cell = tableView.cellForRowAtIndexPath(sourceIndexPath) as? RepeatingScheduleValueTableViewCell else {
            return proposedDestinationIndexPath
        }

        let interval = cell.datePickerInterval
        let insertableIndices = insertableIndiciesByRemovingRow(sourceIndexPath.row, withInterval: interval)

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

    func repeatingScheduleValueTableViewCellDidUpdateDate(cell: RepeatingScheduleValueTableViewCell) {

        // Updates the TableView state. Subclasses should update their data model
        if let indexPath = tableView.indexPathForCell(cell) {

            var indexPaths: [NSIndexPath] = []

            if indexPath.row > 0 {
                indexPaths.append(NSIndexPath(forRow: indexPath.row - 1, inSection: indexPath.section))
            }

            if indexPath.row < tableView.numberOfRowsInSection(0) - 1 {
                indexPaths.append(NSIndexPath(forRow: indexPath.row + 1, inSection: indexPath.section))
            }

            dispatch_async(dispatch_get_main_queue()) {
                self.tableView.reloadRowsAtIndexPaths(indexPaths, withRowAnimation: .None)
            }
        }
    }

}
