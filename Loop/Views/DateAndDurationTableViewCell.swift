//
//  DateAndDurationTableViewCell.swift
//  LoopKitUI
//
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import UIKit

class DateAndDurationTableViewCell: DatePickerTableViewCell, NibLoadable {

    weak var delegate: DatePickerTableViewCellDelegate?

    @IBOutlet weak var titleLabel: UILabel!

    @IBOutlet weak var dateLabel: UILabel!

    private lazy var durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()

        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .short

        return formatter
    }()

    override func updateDateLabel() {
        switch datePicker.datePickerMode {
        case .countDownTimer:
            dateLabel.text = durationFormatter.string(from: duration)
        case .date, .dateAndTime:
            dateLabel.text = DateFormatter.localizedString(from: date, dateStyle: .short, timeStyle: .short)
        case .time:
            dateLabel.text = DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .short)
        }
    }

    override func dateChanged(_ sender: UIDatePicker) {
        super.dateChanged(sender)

        delegate?.datePickerTableViewCellDidUpdateDate(self)
    }
}
