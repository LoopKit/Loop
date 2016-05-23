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

    private weak var textField: UITextField?

    var indexPath: NSIndexPath?

    var placeholder: String?

    var value: String? {
        didSet {
            delegate?.textFieldTableViewControllerDidEndEditing(self)
        }
    }

    var keyboardType = UIKeyboardType.Default

    weak var delegate: TextFieldTableViewControllerDelegate?

    convenience init() {
        self.init(style: .Grouped)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        tableView.registerNib(TextFieldTableViewCell.nib(), forCellReuseIdentifier: TextFieldTableViewCell.className)
    }

    override func viewDidAppear(animated: Bool) {
        super.viewDidAppear(animated)

        textField?.becomeFirstResponder()
    }

    // MARK: - UITableViewDataSource

    override func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return 1
    }

    override func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCellWithIdentifier(TextFieldTableViewCell.className, forIndexPath: indexPath) as! TextFieldTableViewCell

        textField = cell.textField

        cell.textField.delegate = self
        cell.textField.text = value
        cell.textField.keyboardType = keyboardType
        cell.textField.placeholder = placeholder

        return cell
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
