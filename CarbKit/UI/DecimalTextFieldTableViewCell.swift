//
//  DecimalTextFieldTableViewCell.swift
//  CarbKit
//
//  Created by Nathan Racklyeft on 1/15/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import UIKit


protocol TextFieldTableViewCellDelegate: class {
    func textFieldTableViewCellDidUpdateText(cell: DecimalTextFieldTableViewCell)
}


class DecimalTextFieldTableViewCell: UITableViewCell, UITextFieldDelegate {

    @IBOutlet weak var textField: UITextField! {
        didSet {
            textField.delegate = self
        }
    }

    override func setSelected(selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: true)

        if selected {
            if textField.isFirstResponder() {
                textField.resignFirstResponder()
            } else {
                textField.becomeFirstResponder()
            }
        }
    }

    weak var delegate: TextFieldTableViewCellDelegate?

    var numberFormatter: NSNumberFormatter = {
        let formatter = NSNumberFormatter()
        formatter.numberStyle = .DecimalStyle

        return formatter
    }()

    var number: NSNumber? {
        get {
            return numberFormatter.numberFromString(textField.text ?? "")
        }
        set {
            if let value = newValue {
                textField.text = numberFormatter.stringFromNumber(value)
            } else {
                textField.text = nil
            }
        }
    }

    // MARK: - UITextFieldDelegate

    func textFieldDidEndEditing(textField: UITextField) {
        if let number = number {
            textField.text = numberFormatter.stringFromNumber(number)
        } else {
            textField.text = nil
        }

        delegate?.textFieldTableViewCellDidUpdateText(self)
    }
}

