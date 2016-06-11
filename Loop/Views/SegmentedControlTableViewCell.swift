//
//  SegmentedControlTableViewCell.swift
//  Loop
//
//  Created by Nathan Racklyeft on 6/10/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import UIKit

class SegmentedControlTableViewCell: UITableViewCell {

    @IBOutlet weak var titleLabel: UILabel!

    @IBOutlet weak var segmentedControl: UISegmentedControl!

    var selectedIndex = 0 {
        didSet {
            segmentedControl.selectedSegmentIndex = selectedIndex
        }
    }

    override func awakeFromNib() {
        super.awakeFromNib()

        segmentedControl.selectedSegmentIndex = selectedIndex
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        segmentedControl.removeTarget(nil, action: nil, forControlEvents: .ValueChanged)
    }

}
