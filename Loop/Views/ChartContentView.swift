//
//  ChartContentView.swift
//  Loop
//
//  Created by Nate Racklyeft on 9/14/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import UIKit

class ChartContentView: UIView {

    override func layoutSubviews() {
        super.layoutSubviews()

        if chartView == nil || chartView!.frame != bounds {
            chartView = chartGenerator?(bounds)
        } else if chartView!.superview == nil {
            addSubview(chartView!)
        }
    }

    func reloadChart() {
        chartView = nil
        setNeedsLayout()
    }

    var chartGenerator: ((CGRect) -> UIView?)? {
        didSet {
            chartView = nil
            setNeedsLayout()
        }
    }

    private var chartView: UIView? {
        didSet {
            if let view = oldValue {
                view.removeFromSuperview()
            }

            if let view = chartView {
                self.addSubview(view)
            }
        }
    }

}
