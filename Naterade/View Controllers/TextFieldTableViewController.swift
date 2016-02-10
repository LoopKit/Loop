//
//  TextFieldTableViewController.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 8/30/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

import UIKit
import LoopKit


protocol TextFieldTableViewControllerDelegate: class {
    func textFieldTableViewControllerDidEndEditing(controller: TextFieldTableViewController)
}


class TextFieldTableViewController: UITableViewController, IdentifiableClass, UITextFieldDelegate {

    @IBOutlet weak var textField: UITextField!

    var indexPath: NSIndexPath?

    var placeholder: String?

    var value: String? {
        didSet {
            delegate?.textFieldTableViewControllerDidEndEditing(self)
        }
    }

    weak var delegate: TextFieldTableViewControllerDelegate?

    override func viewDidLoad() {
        super.viewDidLoad()

        textField.text = value
        textField.placeholder = placeholder
    }

    override func viewWillAppear(animated: Bool) {
        super.viewWillAppear(animated)

        textField.becomeFirstResponder()
    }

    // MARK: - UITextFieldDelegate

    func textFieldShouldEndEditing(textField: UITextField) -> Bool {
        value = textField.text

        return true
    }

    func textFieldShouldReturn(textField: UITextField) -> Bool {
        value = textField.text

        textField.delegate = nil

        navigationController?.popViewControllerAnimated(true)

        return false
    }
}
