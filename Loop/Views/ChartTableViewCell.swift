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

    @IBOutlet var titleLabel: UILabel?

    @IBOutlet var subtitleLabel: UILabel?

    override func prepareForReuse() {
        super.prepareForReuse()

        chartContentView.chartGenerator = nil
    }

    func reloadChart() {
        chartContentView.reloadChart()
    }
}
