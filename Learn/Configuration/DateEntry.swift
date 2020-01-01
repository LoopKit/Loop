//
//  DateEntry.swift
//  Learn
//
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import LoopKitUI


class DateEntry {
    private(set) var date: Date
    let title: String
    let mode: UIDatePicker.Mode

    init(date: Date, title: String, mode: UIDatePicker.Mode) {
        self.date = date
        self.title = title
        self.mode = mode
    }
}

extension DateEntry: LessonCellProviding {
    func registerCell(for tableView: UITableView) {
        tableView.register(DateAndDurationTableViewCell.nib(), forCellReuseIdentifier: DateAndDurationTableViewCell.className)
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: DateAndDurationTableViewCell.className, for: indexPath) as! DateAndDurationTableViewCell
        cell.delegate = self
        cell.titleLabel.text = title
        cell.datePicker.isEnabled = true
        cell.datePicker.datePickerMode = mode
        cell.date = date
        return cell
    }
}

extension DateEntry: DatePickerTableViewCellDelegate {
    func datePickerTableViewCellDidUpdateDate(_ cell: DatePickerTableViewCell) {
        date = cell.datePicker.date
    }
}
