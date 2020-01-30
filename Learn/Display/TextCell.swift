//
//  TextCell.swift
//  Learn
//
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import UIKit


class TextCell: LessonCellProviding {
    static let cellIdentifier = "TextCell"

    let text: String
    let detailText: String?
    let textColor: UIColor?
    let detailTextColor: UIColor?

    init(text: String, detailText: String? = nil, textColor: UIColor? = nil, detailTextColor: UIColor? = nil) {
        self.text = text
        self.detailText = detailText
        self.textColor = textColor
        self.detailTextColor = detailTextColor
    }

    func registerCell(for tableView: UITableView) {
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell: UITableViewCell

        if let existingCell = tableView.dequeueReusableCell(withIdentifier: TextCell.cellIdentifier) {
            cell = existingCell
        } else {
            cell = UITableViewCell(style: .value1, reuseIdentifier: TextCell.cellIdentifier)
        }

        cell.textLabel?.text = text
        cell.detailTextLabel?.text = detailText

        if let color = textColor {
            cell.textLabel?.textColor = color
        }

        if let color = detailTextColor {
            cell.detailTextLabel?.textColor = color
        }

        return cell
    }
}
