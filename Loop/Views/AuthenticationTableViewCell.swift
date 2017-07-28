//
//  AuthenticationTableViewCell.swift
//  Loop
//
//  Created by Nate Racklyeft on 7/2/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import UIKit


final class AuthenticationTableViewCell: UITableViewCell, NibLoadable {

    @IBOutlet weak var titleLabel: UILabel!

    @IBOutlet weak var textField: UITextField!

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)

        if selected {
            textField.becomeFirstResponder()
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        textField.delegate = nil
        credentialOptionPicker = nil
    }

    var credentialOptionPicker: CredentialOptionPicker? {
        didSet {
            if let picker = credentialOptionPicker {
                picker.delegate = self

                textField.text = picker.selectedOption.title
                textField.inputView = picker.view
                textField.tintColor = .clear // Makes the cursor invisible
            } else {
                textField.inputView = nil
                textField.tintColor = nil
            }
        }
    }

    var value: String? {
        if let picker = credentialOptionPicker {
            return picker.value
        } else {
            return textField.text
        }
    }
}

extension AuthenticationTableViewCell: CredentialOptionPickerDelegate {
    func credentialOptionDataSourceDidUpdateValue(_ picker: CredentialOptionPicker) {
        textField.text = picker.selectedOption.title
        textField.delegate?.textFieldDidEndEditing?(textField)
    }
}


protocol CredentialOptionPickerDelegate: class {
    func credentialOptionDataSourceDidUpdateValue(_ picker: CredentialOptionPicker)
}


class CredentialOptionPicker: NSObject, UIPickerViewDataSource, UIPickerViewDelegate {
    let options: [(title: String, value: String)]

    weak var delegate: CredentialOptionPickerDelegate?

    let view = UIPickerView()

    var selectedOption: (title: String, value: String) {
        let index = view.selectedRow(inComponent: 0)
        guard index >= options.startIndex && index < options.endIndex else {
            return options[0]
        }

        return options[index]
    }

    var value: String? {
        get {
            return selectedOption.value
        }
        set {
            let index: Int

            if let value = newValue, let optionIndex = options.index(where: { $0.value == value }) {
                index = optionIndex
            } else {
                index = 0
            }

            view.selectRow(index, inComponent: 0, animated: view.superview != nil)
        }
    }

    init(options: [(title: String, value: String)]) {
        assert(options.count > 0, "At least one option must be specified")

        self.options = options

        super.init()

        view.dataSource = self
        view.delegate = self
    }

    // MARK: - UIPickerViewDataSource

    func numberOfComponents(in pickerView: UIPickerView) -> Int {
        return 1
    }

    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        return options.count
    }

    // MARK: - UIPickerViewDelegate

    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        return options[row].title
    }

    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
        delegate?.credentialOptionDataSourceDidUpdateValue(self)
    }
}
