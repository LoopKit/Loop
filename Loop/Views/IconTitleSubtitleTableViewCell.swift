//
//  IconTitleSubtitleTableViewCell.swift
//  Loop
//
//  Created by Darin Krauss on 8/19/21.
//  Copyright © 2021 LoopKit Authors. All rights reserved.
//

import UIKit

class IconTitleSubtitleTableViewCell: UITableViewCell {

    @IBOutlet weak var iconImageView: UIImageView!
    
    @IBOutlet weak var titleLabel: UILabel!

    @IBOutlet weak var subtitleLabel: UILabel! {
        didSet {
            subtitleLabel.textColor = UIColor.secondaryLabel
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
