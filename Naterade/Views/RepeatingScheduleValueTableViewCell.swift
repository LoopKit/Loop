//
//  RepeatingScheduleValueTableViewCell.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 2/6/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import UIKit


protocol RepeatingScheduleValueTableViewCellDelegate: class {
    func repeatingScheduleValueTableViewCellDidUpdateDate(cell: RepeatingScheduleValueTableViewCell)

    func repeatingScheduleValueTableViewCellDidUpdateValue(cell: RepeatingScheduleValueTableViewCell)
}


class RepeatingScheduleValueTableViewCell: UITableViewCell, UITextFieldDelegate {

    weak var delegate: RepeatingScheduleValueTableViewCellDelegate?

    var date: NSDate {
        get {
            return datePicker.date
        }
        set {
            datePicker.date = newValue
            dateChanged(datePicker)
        }
    }

    var value: Double {
        get {
            return decimalFormatter.numberFromString(textField.text ?? "")?.doubleValue ?? 0
        }
        set {
            textField.text = decimalFormatter.stringFromNumber(newValue)
            valueChanged()
        }
    }

    private lazy var decimalFormatter: NSNumberFormatter = {
        let formatter = NSNumberFormatter()
        formatter.numberStyle = .DecimalStyle
        formatter.minimumFractionDigits = 1

        return formatter
    }()

    @IBOutlet weak var dateLabel: UILabel!

    @IBOutlet weak var textField: UITextField!

    @IBOutlet weak var datePicker: UIDatePicker!

    @IBOutlet weak var datePickerHeightConstraint: NSLayoutConstraint!

    private var datePickerExpandedHeight: CGFloat = 0

    override func awakeFromNib() {
        super.awakeFromNib()

        datePickerExpandedHeight = datePickerHeightConstraint.constant

        dateChanged(datePicker)
    }

    override func setSelected(selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)

        datePicker.hidden = !selected
        datePickerHeightConstraint.constant = selected ? datePickerExpandedHeight : 0
    }

    @IBAction func dateChanged(sender: UIDatePicker) {
        dateLabel.text = NSDateFormatter.localizedStringFromDate(date, dateStyle: .NoStyle, timeStyle: .ShortStyle)
        
        delegate?.repeatingScheduleValueTableViewCellDidUpdateDate(self)
    }

    func valueChanged() {
        delegate?.repeatingScheduleValueTableViewCellDidUpdateValue(self)
    }

    // MARK: - UITextFieldDelegate

    func textFieldShouldBeginEditing(textField: UITextField) -> Bool {
        return !editing
    }

    func textFieldShouldEndEditing(textField: UITextField) -> Bool {
        let parsedValue = value
        value = parsedValue

        return true
    }
}
