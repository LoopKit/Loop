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

    private(set) var date: NSDate = NSDate()

    private(set) var value: Double = 0

    var datePickerInterval: NSTimeInterval {
        return NSTimeInterval(minutes: Double(datePicker.minuteInterval))
    }

    private lazy var decimalFormatter: NSNumberFormatter = {
        let formatter = NSNumberFormatter()
        formatter.numberStyle = .DecimalStyle
        formatter.minimumFractionDigits = 1

        return formatter
    }()

    @IBOutlet weak var dateLabel: UILabel!

    @IBOutlet weak var unitLabel: UILabel!

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

    func configureWithDate(date: NSDate, value: Double) {
        self.date = date
        self.value = value

        dateLabel.text = NSDateFormatter.localizedStringFromDate(date, dateStyle: .NoStyle, timeStyle: .ShortStyle)
        datePicker.date = date
        textField.text = decimalFormatter.stringFromNumber(value)
    }

    @IBAction func dateChanged(sender: UIDatePicker) {
        configureWithDate(sender.date, value: value)

        delegate?.repeatingScheduleValueTableViewCellDidUpdateDate(self)
    }

    // MARK: - UITextFieldDelegate

    func textFieldShouldBeginEditing(textField: UITextField) -> Bool {
        return !editing
    }

    func textFieldDidEndEditing(textField: UITextField) {
        configureWithDate(date, value: decimalFormatter.numberFromString(textField.text ?? "")?.doubleValue ?? 0)

        delegate?.repeatingScheduleValueTableViewCellDidUpdateValue(self)
    }
}
