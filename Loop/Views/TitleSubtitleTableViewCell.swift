//
//  TitleSubtitleTableViewCell.swift
//  Loop
//
//  Created by Nate Racklyeft on 9/28/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import UIKit

class TitleSubtitleTableViewCell: UITableViewCell {

    @IBOutlet weak var titleLabel: UILabel!

    @IBOutlet weak var subtitleLabel: UILabel! {
        didSet {
            subtitleLabel.textColor = UIColor.secondaryLabelColor
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        gradient.frame = bounds
    }

    private lazy var gradient = CAGradientLayer()

    override func awakeFromNib() {
        super.awakeFromNib()

        gradient.frame = bounds
        gradient.colors = [UIColor.white.cgColor, UIColor.cellBackgroundColor.cgColor]
        backgroundView?.layer.insertSublayer(gradient, at: 0)
    }

}
