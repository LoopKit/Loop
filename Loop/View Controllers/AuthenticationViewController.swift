//
//  AuthenticationViewController.swift
//  Loop
//
//  Created by Nate Racklyeft on 7/2/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import UIKit


class AuthenticationViewController<T: ServiceAuthentication>: UITableViewController, IdentifiableClass, UITextFieldDelegate {

    typealias AuthenticationObserver = (authentication: T) -> Void

    var authenticationObserver: AuthenticationObserver?

    var authentication: T

    private var state: AuthenticationState = .Empty {
        didSet {
            switch (oldValue, state) {
            case let (x, y) where x == y:
                break
            case (_, .Verifying):
                let titleView = ValidatingIndicatorView(frame: CGRect.zero)
                UIView.animateWithDuration(0.25) {
                    self.navigationItem.hidesBackButton = true
                    self.navigationItem.titleView = titleView
                }

                tableView.reloadSections(NSIndexSet(indexesInRange: NSRange(0...1)), withRowAnimation: .Automatic)
                authentication.verify { [unowned self] (success, error) in
                    dispatch_async(dispatch_get_main_queue()) {
                        UIView.animateWithDuration(0.25) {
                            self.navigationItem.titleView = nil
                            self.navigationItem.hidesBackButton = false
                        }

                        if success {
                            self.state = .Authorized
                        } else {
                            if let error = error {
                                self.presentAlertControllerWithError(error)
                            }

                            self.state = .Unauthorized
                        }
                    }
                }
            case (_, .Authorized), (_, .Unauthorized):
                authenticationObserver?(authentication: authentication)
                tableView.reloadSections(NSIndexSet(indexesInRange: NSRange(0...1)), withRowAnimation: .Automatic)
            default:
                break
            }
        }
    }

    init(authentication: T) {
        self.authentication = authentication

        state = authentication.isAuthorized ? .Authorized : .Unauthorized

        super.init(style: .Grouped)

        title = authentication.title
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        tableView.registerNib(AuthenticationTableViewCell.nib(), forCellReuseIdentifier: AuthenticationTableViewCell.className)
        tableView.registerNib(ButtonTableViewCell.nib(), forCellReuseIdentifier: ButtonTableViewCell.className)
    }

    // MARK: - Table view data source

    override func numberOfSectionsInTableView(tableView: UITableView) -> Int {
        return Section.count
    }

    override func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .Credentials:
            switch state {
            case .Authorized:
                return authentication.credentials.filter({ !$0.isSecret }).count
            default:
                return authentication.credentials.count
            }
        case .Button:
            return 1
        }
    }

    override func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        switch Section(rawValue: indexPath.section)! {
        case .Button:
            let cell = tableView.dequeueReusableCellWithIdentifier(ButtonTableViewCell.className, forIndexPath: indexPath) as! ButtonTableViewCell

            switch state {
            case .Authorized:
                cell.button.setTitle(NSLocalizedString("Delete Account", comment: "The title of the button to remove the credentials for a service"), forState: .Normal)
                cell.button.setTitleColor(UIColor.deleteColor, forState: .Normal)
            case .Empty, .Unauthorized, .Verifying:
                cell.button.setTitle(NSLocalizedString("Add Account", comment: "The title of the button to add the credentials for a service"), forState: .Normal)
                cell.button.setTitleColor(nil, forState: .Normal)
            }

            if case .Verifying = state {
                cell.button.enabled = false
            } else {
                cell.button.enabled = true
            }

            cell.button.addTarget(self, action: #selector(buttonPressed(_:)), forControlEvents: .TouchUpInside)
            
            return cell
        case .Credentials:
            let cell = tableView.dequeueReusableCellWithIdentifier(AuthenticationTableViewCell.className, forIndexPath: indexPath) as! AuthenticationTableViewCell

            let credential = authentication.credentials[indexPath.row]

            cell.titleLabel.text = credential.title
            cell.textField.tag = indexPath.row
            cell.textField.keyboardType = credential.keyboardType
            cell.textField.secureTextEntry = credential.isSecret
            cell.textField.returnKeyType = (indexPath.row < authentication.credentials.count - 1) ? .Next : .Done
            cell.textField.text = credential.value
            cell.textField.placeholder = credential.placeholder ?? NSLocalizedString("Required", comment: "The default placeholder string for a credential")

            cell.textField.delegate = self

            switch state {
            case .Authorized, .Verifying, .Empty:
                cell.textField.enabled = false
            case .Unauthorized:
                cell.textField.enabled = true
            }

            return cell
        }
    }

    private func validate() {
        state = .Verifying
    }

    // MARK: - Actions

    @objc private func buttonPressed(_: AnyObject) {
        tableView.endEditing(false)

        switch state {
        case .Authorized:
            authentication.reset()
            state = .Unauthorized
        case .Unauthorized:
            validate()
        default:
            break
        }

    }

    // MARK: - UITextFieldDelegate

    func textFieldDidEndEditing(textField: UITextField) {
        authentication.credentials[textField.tag].value = textField.text
    }

    func textFieldShouldReturn(textField: UITextField) -> Bool {
        if textField.returnKeyType == .Done {
            textField.resignFirstResponder()
        } else {
            let point = tableView.convertPoint(textField.frame.origin, fromView: textField.superview)
            if let indexPath = tableView.indexPathForRowAtPoint(point),
                cell = tableView.cellForRowAtIndexPath(NSIndexPath(forRow: indexPath.row + 1, inSection: indexPath.section)) as? AuthenticationTableViewCell
            {
                cell.textField.becomeFirstResponder()

                validate()
            }
        }

        return true
    }
}


private enum Section: Int {
    case Credentials
    case Button

    static let count = 2
}


enum AuthenticationState {
    case Empty
    case Authorized
    case Verifying
    case Unauthorized
}
