//
//  PotentialCarbEntryTableViewCell.swift
//  Loop
//
//  Created by Michael Pangburn on 12/27/19.
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import UIKit


class PotentialCarbEntryTableViewCell: UITableViewCell {
    @IBOutlet weak var valueLabel: UILabel!
    @IBOutlet weak var dateLabel: UILabel!

    override func layoutSubviews() {
        super.layoutSubviews()

        contentView.layoutMargins.left = separatorInset.left
        contentView.layoutMargins.right = separatorInset.left
    }

    override func awakeFromNib() {
        super.awakeFromNib()

        resetViews()
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        resetViews()
    }

    private func resetViews() {
        valueLabel.text = nil
        dateLabel.text = nil
    }
}
