//
//  BasalRateHUDView.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 5/1/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import UIKit

class BasalRateHUDView: HUDView {

    @IBOutlet private var basalStateView: BasalStateView!

    func setNetBasalRate(rate: Double, percent: Double, atDate date: NSDate) {
        caption?.text = timeFormatter.stringFromDate(date)

        basalStateView.netBasalPercent = percent
    }

    private lazy var timeFormatter: NSDateFormatter = {
        let formatter = NSDateFormatter()
        formatter.dateStyle = .NoStyle
        formatter.timeStyle = .ShortStyle

        return formatter
    }()

}
