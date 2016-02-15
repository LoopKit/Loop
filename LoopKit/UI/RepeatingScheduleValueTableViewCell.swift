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

    var date: NSDate = NSDate() {
        didSet {
            dateLabel.text = NSDateFormatter.localizedStringFromDate(date, dateStyle: .NoStyle, timeStyle: .ShortStyle)

            if datePicker.date != date {
                datePicker.date = date
            }
        }
    }

    var value: Double = 0 {
        didSet {
            textField.text = valueNumberFormatter.stringFromNumber(value)
        }
    }

    var datePickerInterval: NSTimeInterval {
        return NSTimeInterval(minutes: Double(datePicker.minuteInterval))
    }

    lazy var valueNumberFormatter: NSNumberFormatter = {
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
    }

    override func setSelected(selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)

        datePicker.hidden = !selected
        datePickerHeightConstraint.constant = selected ? datePickerExpandedHeight : 0
    }

    var unitString: String? {
        get {
            return unitLabel.text
        }
        set {
            unitLabel.text = newValue
        }
    }

    @IBAction func dateChanged(sender: UIDatePicker) {
        date = sender.date

        delegate?.repeatingScheduleValueTableViewCellDidUpdateDate(self)
    }

    // MARK: - UITextFieldDelegate

    func textFieldDidEndEditing(textField: UITextField) {
        value = valueNumberFormatter.numberFromString(textField.text ?? "")?.doubleValue ?? 0

        delegate?.repeatingScheduleValueTableViewCellDidUpdateValue(self)
    }
}
