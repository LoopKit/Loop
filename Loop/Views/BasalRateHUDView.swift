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

    func setNetBasalRate(_ rate: Double, percent: Double, atDate date: Date) {
        caption?.text = timeFormatter.string(from: date)
        basalRateLabel?.text = String(format: basalRateFormatString, decimalFormatter.string(from: NSNumber(value: rate)) ?? "–")
        basalStateView.netBasalPercent = percent
    }

    private lazy var decimalFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 1
        formatter.minimumIntegerDigits = 1
        formatter.positiveFormat = "+0.0##"
        formatter.negativeFormat = "-0.0##"

        return formatter
    }()

    private lazy var timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short

        return formatter
    }()

}
