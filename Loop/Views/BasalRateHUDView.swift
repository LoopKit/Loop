//
//  BasalRateHUDView.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 5/1/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import UIKit


final class BasalRateHUDView: HUDView {

    @IBOutlet private var basalStateView: BasalStateView!

    @IBOutlet private var basalRateLabel: UILabel! {
        didSet {
            basalRateLabel?.text = String(format: basalRateFormatString, "–")
            basalRateLabel?.textColor = .doseTintColor
        }
    }

    private lazy var basalRateFormatString = NSLocalizedString("%@ U", comment: "The format string describing the basal rate. ")

    func setNetBasalRate(rate: Double, percent: Double, atDate date: NSDate) {
        caption?.text = timeFormatter.stringFromDate(date)
        basalRateLabel?.text = String(format: basalRateFormatString, decimalFormatter.stringFromNumber(rate) ?? "–")
        basalStateView.netBasalPercent = percent
    }

    private lazy var decimalFormatter: NSNumberFormatter = {
        let formatter = NSNumberFormatter()
        formatter.numberStyle = .DecimalStyle
        formatter.minimumFractionDigits = 1
        formatter.minimumIntegerDigits = 1
        formatter.positiveFormat = "+0.0##"
        formatter.negativeFormat = "-0.0##"

        return formatter
    }()

    private lazy var timeFormatter: NSDateFormatter = {
        let formatter = NSDateFormatter()
        formatter.dateStyle = .NoStyle
        formatter.timeStyle = .ShortStyle

        return formatter
    }()

}
