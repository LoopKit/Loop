//
//  SwitchTableViewCell.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 3/13/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import UIKit


final class SwitchTableViewCell: UITableViewCell {

    @IBOutlet weak var titleLabel: UILabel!

    @IBOutlet weak var subtitleLabel: UILabel?

    @IBOutlet weak var `switch`: UISwitch?

    override func layoutSubviews() {
        super.layoutSubviews()

        contentView.layoutMargins.left = separatorInset.left
        contentView.layoutMargins.right = separatorInset.left
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        self.switch?.removeTarget(nil, action: nil, for: .valueChanged)
    }

}
