//
//  ChartTableViewCell.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 2/19/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import UIKit
import LoopUI


final class ChartTableViewCell: UITableViewCell {

    @IBOutlet weak var chartContentView: ChartContentView!

    @IBOutlet weak var titleLabel: UILabel?

    @IBOutlet weak var subtitleLabel: UILabel?

    override func prepareForReuse() {
        super.prepareForReuse()

        chartContentView.chartGenerator = nil
    }

    func reloadChart() {
        chartContentView.reloadChart()
    }
}
