//
//  NumberEntry.swift
//  Learn
//
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKitUI


class TextEntry: TextFieldTableViewCellDelegate {

    func registerCell(for tableView: UITableView) {
        tableView.register(TextFieldTableViewCell.nib(), forCellReuseIdentifier: TextFieldTableViewCell.className)
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> TextFieldTableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: TextFieldTableViewCell.className, for: indexPath) as! TextFieldTableViewCell
        cell.delegate = self
        return cell
    }

    // MARK: - TextFieldTableViewCellDelegate

    func textFieldTableViewCellDidBeginEditing(_ cell: TextFieldTableViewCell) {

    }

    func textFieldTableViewCellDidEndEditing(_ cell: TextFieldTableViewCell) {

    }
}


class NumberEntry: TextEntry, LessonCellProviding {

    let formatter: NumberFormatter
    private(set) var number: NSNumber?
    let keyboardType: UIKeyboardType
    let placeholder: String?
    let unitString: String?

    init(number: NSNumber?, formatter: NumberFormatter, placeholder: String?, unitString: String?, keyboardType: UIKeyboardType) {
        self.number = number
        self.formatter = formatter
        self.placeholder = placeholder
        self.unitString = unitString
        self.keyboardType = keyboardType
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = super.tableView(tableView, cellForRowAt: indexPath)
        cell.textField.placeholder = placeholder
        cell.unitLabel?.text = unitString
        cell.textField.keyboardType = keyboardType
        updateText(for: cell)
        return cell
    }

    override func textFieldTableViewCellDidEndEditing(_ cell: TextFieldTableViewCell) {
        if let text = cell.textField.text {
            number = formatter.number(from: text)
        } else {
            number = nil
        }

        updateText(for: cell)
    }

    private func updateText(for cell: TextFieldTableViewCell) {
        if let number = number {
            cell.textField.text = formatter.string(from: number)
        } else {
            cell.textField.text = nil
        }
    }
}


extension NumberEntry {
    class func decimalEntry(value: Double?, unitString: String?) -> NumberEntry {
        let number: NSNumber?
        if let value = value {
            number = NSNumber(value: value)
        } else {
            number = nil
        }

        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal

        return NumberEntry(number: number, formatter: formatter, placeholder: nil, unitString: unitString, keyboardType: .decimalPad)
    }

    class func integerEntry(value: Int?, unitString: String?) -> NumberEntry {
        let number: NSNumber?
        if let value = value {
            number = NSNumber(value: value)
        } else {
            number = nil
        }


        let formatter = NumberFormatter()
        formatter.numberStyle = .none

        return NumberEntry(number: number, formatter: formatter, placeholder: nil, unitString: unitString, keyboardType: .decimalPad)
    }
}
