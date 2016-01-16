//
//  CarbEntryTableViewController.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 1/10/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import UIKit

private let ReuseIdentifier = "CarbEntry"

public class CarbEntryTableViewController: UITableViewController {

    @IBOutlet var unavailableMessageView: UIView!

    @IBOutlet var authorizationRequiredMessageView: UIView!

    var carbStore: CarbStore?

    override public func viewDidLoad() {
        super.viewDidLoad()

        if let carbStore = carbStore {
            if carbStore.authorizationRequired {
                state = .AuthorizationRequired(carbStore)
            } else {
                state = .Display(carbStore)
            }
        } else {
            state = .Unavailable
        }

        self.navigationItem.leftBarButtonItem = self.editButtonItem()
    }

    override public func viewWillAppear(animated: Bool) {
        super.viewWillAppear(animated)

        reloadData()
    }

    deinit {
        carbStoreObserver = nil
    }

    // MARK: - Data

    private var carbEntries: [CarbEntry] = []

    private enum State {
        case Unknown
        case Unavailable
        case AuthorizationRequired(CarbStore)
        case Display(CarbStore)
    }

    private var state = State.Unknown {
        didSet {
            switch state {
            case .Unknown:
                break
            case .Unavailable:
                tableView.backgroundView = unavailableMessageView
            case .AuthorizationRequired:
                tableView.backgroundView = authorizationRequiredMessageView
                carbStoreObserver = nil
            case .Display(let carbStore):
                carbStoreObserver = NSNotificationCenter.defaultCenter().addObserverForName(nil, object: carbStore, queue: NSOperationQueue.mainQueue(), usingBlock: { [unowned self] (note) -> Void in

                    self.reloadData()
                })

                tableView.backgroundView = nil
                reloadData()
            }
        }
    }

    private func reloadData() {
        if case .Display(let carbStore) = state {
            carbStore.getRecentCarbEntries { (entries, error) -> Void in
                dispatch_async(dispatch_get_main_queue()) {
                    if let error = error {
                        let alert = UIAlertController(
                            title: error.userInfo[NSLocalizedDescriptionKey] as? String ?? "Error",
                            message: error.userInfo[NSLocalizedRecoverySuggestionErrorKey] as? String ?? "",
                            preferredStyle: .Alert
                        )

                        self.showViewController(alert, sender: nil)
                    } else {
                        self.carbEntries = entries
                        self.tableView.reloadData()
                    }
                }
            }
        }
    }

    private var carbStoreObserver: AnyObject? {
        willSet {
            if let observer = carbStoreObserver {
                NSNotificationCenter.defaultCenter().removeObserver(observer)
            }
        }
    }

    // MARK: - Table view data source

    override public func numberOfSectionsInTableView(tableView: UITableView) -> Int {
        switch state {
        case .Unknown, .Unavailable, .AuthorizationRequired:
            return 0
        case .Display:
            return 1
        }
    }

    override public func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return carbEntries.count
    }

    override public func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCellWithIdentifier(ReuseIdentifier, forIndexPath: indexPath)

        let entry = carbEntries[indexPath.row]

        var titleText = "\(entry.amount) g"

        if let foodType = entry.foodType {
            titleText += ": \(foodType)"
        }

        cell.textLabel?.text = titleText

        if let absorptionTime = entry.absorptionTime {
            cell.detailTextLabel?.text = "\(absorptionTime) min"
        } else {
            cell.detailTextLabel?.text = nil
        }

        return cell
    }

    override public func tableView(tableView: UITableView, canEditRowAtIndexPath indexPath: NSIndexPath) -> Bool {
        // Return false if you do not want the specified item to be editable.
        return carbEntries[indexPath.row].createdByCurrentApp
    }

    override public func tableView(tableView: UITableView, commitEditingStyle editingStyle: UITableViewCellEditingStyle, forRowAtIndexPath indexPath: NSIndexPath) {
        if editingStyle == .Delete {
            // Delete the row from the data source
//            tableView.deleteRowsAtIndexPaths([indexPath], withRowAnimation: .Fade)
        }
    }

    // MARK: - Navigation

    @IBAction func unwindFromEditing(segue: UIStoryboardSegue) {
        
    }

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override public func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
        print(segue)
    }

    @IBAction func addCarbItem(sender: AnyObject) {

    }

    @IBAction func authorizeHealth(sender: AnyObject) {
        if case .AuthorizationRequired(let carbStore) = state {
            carbStore.authorize { (success, error) in
                dispatch_async(dispatch_get_main_queue()) {
                    if success {
                        self.state = .Display(carbStore)
                    } else if let error = error {

                        let alert = UIAlertController(
                            title: error.userInfo[NSLocalizedDescriptionKey] as? String ?? "Error",
                            message: error.userInfo[NSLocalizedRecoverySuggestionErrorKey] as? String ?? "",
                            preferredStyle: .Alert
                        )

                        self.presentViewController(alert, animated: true, completion: nil)
                    }
                }
            }
        }
    }

}
