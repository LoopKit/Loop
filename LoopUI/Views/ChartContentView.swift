//
//  ChartContentView.swift
//  Loop
//
//  Created by Nate Racklyeft on 9/14/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import UIKit

public class ChartContentView: UIView {

    override public func layoutSubviews() {
        super.layoutSubviews()

        if chartView == nil || chartView!.frame != bounds {
            // 50 is the smallest height in which we should attempt to redraw a chart.
            // Smaller sizes might be requested mid-animation, so ignore them.
            if bounds.height > 50 {
                chartView = chartGenerator?(bounds)
            }
        } else if chartView!.superview == nil {
            addSubview(chartView!)
        }
    }

    public func reloadChart() {
        chartView = nil
        setNeedsLayout()
    }

    public var chartGenerator: ((CGRect) -> UIView?)? {
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
