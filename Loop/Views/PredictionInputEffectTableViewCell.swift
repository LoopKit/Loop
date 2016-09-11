//
//  PredictionInputEffectTableViewCell.swift
//  Loop
//
//  Created by Nate Racklyeft on 9/4/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import UIKit

class PredictionInputEffectTableViewCell: UITableViewCell {

    @IBOutlet weak var titleLabel: UILabel!

    @IBOutlet weak var subtitleLabel: UILabel!

    var enabled: Bool = true {
        didSet {
            if enabled {
                titleLabel.textColor = UIColor.darkTextColor()
                subtitleLabel.textColor = UIColor.darkTextColor()
            } else {
                titleLabel.textColor = UIColor.secondaryLabelColor
                subtitleLabel.textColor = UIColor.secondaryLabelColor
            }
        }
    }

}
