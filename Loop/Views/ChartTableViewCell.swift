//
//  ChartTableViewCell.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 2/19/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import UIKit


final class ChartTableViewCell: UITableViewCell {

    @IBOutlet var placeholderView: UIView?

    @IBOutlet var subtitleLabel: UILabel? {
        didSet {
            subtitleLabel?.textColor = UIColor.secondaryLabelColor
        }
    }

    var chartView: UIView? {
        didSet {
            if let view = oldValue {
                view.removeFromSuperview()
            }

            if let view = chartView {
                contentView.addSubview(view)
            }
        }
    }

}
