//
//  AuthenticationViewController.swift
//  Loop
//
//  Created by Nate Racklyeft on 7/2/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import UIKit


final class AuthenticationViewController<T: ServiceAuthentication>: UITableViewController, IdentifiableClass, UITextFieldDelegate {

    typealias AuthenticationObserver = (_ authentication: T) -> Void

    var authenticationObserver: AuthenticationObserver?

    var authentication: T

    private var state: AuthenticationState = .empty {
        didSet {
            switch (oldValue, state) {
            case let (x, y) where x == y:
                break
            case (_, .verifying):
                let titleView = ValidatingIndicatorView(frame: CGRect.zero)
                UIView.animate(withDuration: 0.25, animations: {
                    self.navigationItem.hidesBackButton = true
                    self.navigationItem.titleView = titleView
                }) 

                tableView.reloadSections(IndexSet(integersIn: 0...1), with: .automatic)
                authentication.verify { (success, error) in
                    DispatchQueue.main.async {
                        UIView.animate(withDuration: 0.25, animations: {
                            self.navigationItem.titleView = nil
                            self.navigationItem.hidesBackButton = false
                        }) 

                        if let error = error {
                            self.presentAlertController(with: error)
                        }

                        if success {
                            self.state = .authorized
                        } else {
                            self.state = .unauthorized
                        }
                    }
                }
            case (_, .authorized), (_, .unauthorized):
                authentication.isAuthorized = (state == .authorized)

                authenticationObserver?(authentication)
                tableView.reloadSections(IndexSet(integersIn: 0...1), with: .automatic)
            default:
                break
            }
        }
    }

    var credentials: [ServiceCredential] {
        switch state {
        case .authorized:
            return authentication.credentials.filter({ !$0.isSecret })
        default:
            return authentication.credentials
        }
    }

    init(authentication: T) {
        self.authentication = authentication

        state = authentication.isAuthorized ? .authorized : .unauthorized

        super.init(style: .grouped)

        title = authentication.title
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        tableView.register(AuthenticationTableViewCell.nib(), forCellReuseIdentifier: AuthenticationTableViewCell.className)
        tableView.register(ButtonTableViewCell.nib(), forCellReuseIdentifier: ButtonTableViewCell.className)
    }

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        return Section.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .credentials:
            return credentials.count
        case .button:
            return 1
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch Section(rawValue: indexPath.section)! {
        case .button:
            let cell = tableView.dequeueReusableCell(withIdentifier: ButtonTableViewCell.className, for: indexPath) as! ButtonTableViewCell

            switch state {
            case .authorized:
                cell.button.setTitle(NSLocalizedString("Delete Account", comment: "The title of the button to remove the credentials for a service"), for: UIControlState())
                cell.button.setTitleColor(UIColor.deleteColor, for: UIControlState())
            case .empty, .unauthorized, .verifying:
                cell.button.setTitle(NSLocalizedString("Add Account", comment: "The title of the button to add the credentials for a service"), for: UIControlState())
                cell.button.setTitleColor(nil, for: UIControlState())
            }

            if case .verifying = state {
                cell.button.isEnabled = false
            } else {
                cell.button.isEnabled = true
            }

            cell.button.addTarget(self, action: #selector(buttonPressed(_:)), for: .touchUpInside)
            
            return cell
        case .credentials:
            let cell = tableView.dequeueReusableCell(withIdentifier: AuthenticationTableViewCell.className, for: indexPath) as! AuthenticationTableViewCell

            let credentials = self.credentials
            let credential = credentials[indexPath.row]

            cell.titleLabel.text = credential.title
            cell.textField.keyboardType = credential.keyboardType
            cell.textField.isSecureTextEntry = credential.isSecret
            cell.textField.returnKeyType = (indexPath.row < credentials.count - 1) ? .next : .done
            cell.textField.text = credential.value
            cell.textField.placeholder = credential.placeholder ?? NSLocalizedString("Required", comment: "The default placeholder string for a credential")

            if let options = credential.options {
                let picker = CredentialOptionPicker(options: options)
                picker.value = credential.value

                cell.credentialOptionPicker = picker
            }

            cell.textField.delegate = self

            switch state {
            case .authorized, .verifying, .empty:
                cell.textField.isEnabled = false
            case .unauthorized:
                cell.textField.isEnabled = true
            }

            return cell
        }
    }

    fileprivate func validate() {
        state = .verifying
    }

    // MARK: - Actions

    @objc private func buttonPressed(_: Any) {
        tableView.endEditing(false)

        switch state {
        case .authorized:
            authentication.reset()
            state = .unauthorized
        case .unauthorized:
            validate()
        default:
            break
        }

    }

    // MARK: - UITextFieldDelegate

    func textFieldDidEndEditing(_ textField: UITextField) {
        let point = tableView.convert(textField.frame.origin, from: textField.superview)

        guard case .unauthorized = state,
            let indexPath = tableView.indexPathForRow(at: point),
            let cell = tableView.cellForRow(at: IndexPath(row: indexPath.row, section: indexPath.section)) as? AuthenticationTableViewCell
        else {
            return
        }

        authentication.credentials[indexPath.row].value = cell.value
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if textField.returnKeyType == .done {
            textField.resignFirstResponder()
            validate()
        } else {
            let point = tableView.convert(textField.frame.origin, from: textField.superview)
            if let indexPath = tableView.indexPathForRow(at: point),
                let cell = tableView.cellForRow(at: IndexPath(row: indexPath.row + 1, section: indexPath.section)) as? AuthenticationTableViewCell
            {
                cell.textField.becomeFirstResponder()
            }
        }

        return true
    }

    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        return textField.inputView == nil
    }
}


private enum Section: Int {
    case credentials
    case button

    static let count = 2
}


enum AuthenticationState {
    case empty
    case authorized
    case verifying
    case unauthorized
}
