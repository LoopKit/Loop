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

        }
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        if let doseStore = doseStore {
            
        }

        self.navigationItem.rightBarButtonItem = self.editButtonItem()
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
                // Add a notification?

                navigationItem.rightBarButtonItem?.enabled = true

                tableView.backgroundView = nil
                tableView.tableHeaderView?.hidden = false
                tableView.tableFooterView = nil
                reloadData()
            }
        }
    }

    private func reloadData() {
        if case .Display(let doseStore) = state {
            // Load reservoir data
        }
    }

    // MARK: - Table view data source

    public override func numberOfSectionsInTableView(tableView: UITableView) -> Int {
        // #warning Incomplete implementation, return the number of sections
        return 0
    }

    public override func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        // #warning Incomplete implementation, return the number of rows
        return 0
    }

    public override func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCellWithIdentifier(ReuseIdentifier, forIndexPath: indexPath)

        return cell
    }

    public override func tableView(tableView: UITableView, canEditRowAtIndexPath indexPath: NSIndexPath) -> Bool {

        return true
    }

    public override func tableView(tableView: UITableView, commitEditingStyle editingStyle: UITableViewCellEditingStyle, forRowAtIndexPath indexPath: NSIndexPath) {
        if editingStyle == .Delete, case .Display(let doseStore) = state {

            let value = reservoirValues[indexPath.row]

            do {
                try doseStore.deleteReservoirValue(value)

                tableView.deleteRowsAtIndexPaths([indexPath], withRowAnimation: .Fade)
            } catch let error {
                presentAlertControllerWithError(error)
            }
        }
    }

}
