//
//  SegmentedControlTableViewCell.swift
//  Loop
//
//  Created by Nathan Racklyeft on 6/10/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import UIKit


final class SegmentedControlTableViewCell: UITableViewCell {

    @IBOutlet weak var titleLabel: UILabel!

    @IBOutlet weak var segmentedControl: UISegmentedControl!

    override func awakeFromNib() {
        super.awakeFromNib()

        segmentedControl.selectedSegmentIndex = 0
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        segmentedControl.removeTarget(nil, action: nil, forControlEvents: .ValueChanged)
    }

}
