//
//  DatesAndNumberCell.swift
//  Learn
//
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import UIKit


class DatesAndNumberCell: LessonCellProviding {
    static let cellIdentifier = "DatesAndNumberCell"

    let date: DateInterval
    let value: NSNumber
    let dateFormatter: DateIntervalFormatter
    let numberFormatter: NumberFormatter

    init(date: DateInterval, value: NSNumber, dateFormatter: DateIntervalFormatter, numberFormatter: NumberFormatter) {
        self.date = date
        self.value = value
        self.dateFormatter = dateFormatter
        self.numberFormatter = numberFormatter
    }

    func registerCell(for tableView: UITableView) {
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell: UITableViewCell

        if let existingCell = tableView.dequeueReusableCell(withIdentifier: DatesAndNumberCell.cellIdentifier) {
            cell = existingCell
        } else {
            cell = UITableViewCell(style: .value1, reuseIdentifier: DatesAndNumberCell.cellIdentifier)
        }

        cell.textLabel?.text = dateFormatter.string(from: date)
        cell.detailTextLabel?.text = numberFormatter.string(from: value)

        return cell
    }
}
