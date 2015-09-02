//
//  PumpIDTableViewController.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 8/30/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

import UIKit

protocol PumpIDTableViewControllerDelegate: class {
    func pumpIDTableViewControllerDidEndEditing(controller: PumpIDTableViewController)
}

class PumpIDTableViewController: UITableViewController, UITextFieldDelegate {

    @IBOutlet weak var pumpIDTextField: UITextField!

    var pumpID: String? {
        didSet {
            delegate?.pumpIDTableViewControllerDidEndEditing(self)
        }
    }

    weak var delegate: PumpIDTableViewControllerDelegate?

    override func viewDidLoad() {
        super.viewDidLoad()

        pumpIDTextField.text = pumpID
    }

    override func viewWillAppear(animated: Bool) {
        super.viewWillAppear(animated)

        pumpIDTextField.becomeFirstResponder()
    }

    // MARK: - UITextFieldDelegate

    func textFieldShouldEndEditing(textField: UITextField) -> Bool {
        pumpID = textField.text

        return true
    }

    func textFieldShouldReturn(textField: UITextField) -> Bool {
        pumpID = textField.text

        textField.delegate = nil

        navigationController?.popViewControllerAnimated(true)

        return false
    }
}
