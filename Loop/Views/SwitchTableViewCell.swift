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

    @IBOutlet var `switch`: UISwitch?

    override func prepareForReuse() {
        super.prepareForReuse()

        `switch`?.removeTarget(nil, action: nil, forControlEvents: .ValueChanged)
    }

}
