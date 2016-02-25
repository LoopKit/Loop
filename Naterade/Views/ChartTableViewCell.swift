//
//  ChartTableViewCell.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 2/19/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import UIKit

class ChartTableViewCell: UITableViewCell {

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
