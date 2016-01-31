//
//  ReservoirTableViewController.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 1/30/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import UIKit
import LoopKit

private let ReuseIdentifier = "Reservoir"


public class ReservoirTableViewController: UITableViewController {

    @IBOutlet var needsConfigurationMessageView: UIView!

    public var doseStore: DoseStore? {
        didSet {
            if isViewLoaded() {
                if let doseStore = doseStore {
                    state = .Display(doseStore)
                } else {
                    state = .Unavailable
                }
            }
        }
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        if let doseStore = doseStore {
            state = .Display(doseStore)
        } else {
            state = .Unavailable
        }
    }

    public override func viewDidDisappear(animated: Bool) {
        super.viewDidDisappear(animated)

        if tableView.editing {
            tableView.endEditing(true)
        }
    }

    // MARK: - Data

    private var reservoirValues: [ReservoirValue] = []

    private enum State {
        case Unknown
        case Unavailable
        case Display(DoseStore)
    }

    private var state = State.Unknown {
        didSet {
            switch state {
            case .Unknown:
                break
            case .Unavailable:
                tableView.backgroundView = needsConfigurationMessageView
            case .Display(let doseStore):
                doseStoreObserver = NSNotificationCenter.defaultCenter().addObserverForName(DoseStore.ReservoirValuesDidUpdateNotification, object: doseStore, queue: NSOperationQueue.mainQueue(), usingBlock: { [unowned self] (_) -> Void in

                    dispatch_async(dispatch_get_main_queue()) {
                        self.reloadData()
                    }
                })

                self.tableView.backgroundView = nil
                self.tableView.tableHeaderView?.hidden = false
                self.tableView.tableFooterView = nil

                reloadData()
            }
        }
    }

    private func reloadData() {
        if case .Display(let doseStore) = state {
            doseStore.getRecentReservoirValues({ [unowned self] (reservoirValues) -> Void in
                self.reservoirValues = reservoirValues

                if reservoirValues.count > 0 {
                    self.navigationItem.rightBarButtonItem = self.editButtonItem()
                }

                self.tableView.reloadData()
            })
        }
    }

    private var doseStoreObserver: AnyObject? {
        willSet {
            if let observer = doseStoreObserver {
                NSNotificationCenter.defaultCenter().removeObserver(observer)
            }
        }
    }

    // MARK: - Table view data source

    public override func numberOfSectionsInTableView(tableView: UITableView) -> Int {
        switch state {
        case .Unknown, .Unavailable:
            return 0
        case .Display:
            return 1
        }
    }

    public override func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return reservoirValues.count
    }

    public override func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCellWithIdentifier(ReuseIdentifier, forIndexPath: indexPath)

        if case .Display = state {
            let entry = reservoirValues[indexPath.row]
            let volume = NSNumberFormatter.localizedStringFromNumber(entry.unitVolume, numberStyle: .DecimalStyle)
            let time = NSDateFormatter.localizedStringFromDate(entry.startDate, dateStyle: .NoStyle, timeStyle: .ShortStyle)

            cell.textLabel?.text = "\(volume) U"
            cell.detailTextLabel?.text = time
        }

        return cell
    }

    public override func tableView(tableView: UITableView, canEditRowAtIndexPath indexPath: NSIndexPath) -> Bool {
        return true
    }

    public override func tableView(tableView: UITableView, commitEditingStyle editingStyle: UITableViewCellEditingStyle, forRowAtIndexPath indexPath: NSIndexPath) {
        if editingStyle == .Delete, case .Display(let doseStore) = state {

            let value = reservoirValues.removeAtIndex(indexPath.row)

            tableView.deleteRowsAtIndexPaths([indexPath], withRowAnimation: .Automatic)

            do {
                try doseStore.deleteReservoirValue(value)
            } catch let error {
                presentAlertControllerWithError(error)
            }
        }
    }

}
