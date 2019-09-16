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

        updateColors()
        gradient.frame = bounds
    }

    private lazy var gradient = CAGradientLayer()

    override func awakeFromNib() {
        super.awakeFromNib()

        gradient.frame = bounds
        backgroundView?.layer.insertSublayer(gradient, at: 0)

        updateColors()
    }

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        updateColors()
    }

    private func updateColors() {
        gradient.colors = [
            UIColor.cellBackgroundColor.withAlphaComponent(0).cgColor,
            UIColor.cellBackgroundColor.cgColor
        ]
    }
}
