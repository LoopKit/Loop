//
//  FoodTableViewController.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 1/10/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import UIKit
import CarbKit

class FoodTableViewController: UITableViewController {

    @IBOutlet var unavailableMessageView: UIView!

    @IBOutlet var authorizationRequiredMessageView: UIView!

    override func viewDidLoad() {
        super.viewDidLoad()

        if let carbStore = PumpDataManager.sharedManager.carbStore {
            if carbStore.authorizationRequired {
                state = .AuthorizationRequired(carbStore)
            } else {
                state = .Display(carbStore)
            }
        } else {
            state = .Unavailable
        }

        self.navigationItem.rightBarButtonItem = self.editButtonItem()
    }

    override func viewWillAppear(animated: Bool) {
        super.viewWillAppear(animated)

        reloadData()
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
            case .Display:
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

    // MARK: - Table view data source

    override func numberOfSectionsInTableView(tableView: UITableView) -> Int {
        switch state {
        case .Unknown, .Unavailable, .AuthorizationRequired:
            return 0
        case .Display:
            return 1
        }
    }

    override func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return carbEntries.count
    }

    override func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCellWithIdentifier("CarbEntry", forIndexPath: indexPath)

        let entry = carbEntries[indexPath.row]

        var titleText = "\(entry.amount) g"

        if let description = entry.description {
            titleText += ": \(description)"
        }

        cell.textLabel?.text = titleText

        if let absorptionTime = entry.absorptionTime {
            cell.detailTextLabel?.text = "\(absorptionTime) min"
        } else {
            cell.detailTextLabel?.text = nil
        }

        return cell
    }

    override func tableView(tableView: UITableView, canEditRowAtIndexPath indexPath: NSIndexPath) -> Bool {
        // Return false if you do not want the specified item to be editable.
        return true
    }

    override func tableView(tableView: UITableView, commitEditingStyle editingStyle: UITableViewCellEditingStyle, forRowAtIndexPath indexPath: NSIndexPath) {
        if editingStyle == .Delete {
            // Delete the row from the data source
//            tableView.deleteRowsAtIndexPaths([indexPath], withRowAnimation: .Fade)
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
