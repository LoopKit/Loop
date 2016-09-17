//
//  ChartTableViewCell.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 2/19/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import UIKit


final class ChartTableViewCell: UITableViewCell {

    @IBOutlet var chartContentView: ChartContentView!

    @IBOutlet var subtitleLabel: UILabel? {
        didSet {
            subtitleLabel?.textColor = UIColor.secondaryLabelColor
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        chartContentView.chartGenerator = nil
    }
}
