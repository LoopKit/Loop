//
//  BasalRateHUDView.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 5/1/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import UIKit


public final class BasalRateHUDView: BaseHUDView {

    @IBOutlet private weak var basalStateView: BasalStateView!

    @IBOutlet private weak var basalRateLabel: UILabel! {
        didSet {
            basalRateLabel?.text = String(format: basalRateFormatString, "–")
            basalRateLabel?.textColor = .doseTintColor

            accessibilityValue = NSLocalizedString("Unknown", comment: "Accessibility value for an unknown value")
        }
    }

    private lazy var basalRateFormatString = NSLocalizedString("%@ U", comment: "The format string describing the basal rate.")

    public func setNetBasalRate(_ rate: Double, percent: Double, at date: Date) {
        let time = timeFormatter.string(from: date)
        caption?.text = time

        if let rateString = decimalFormatter.string(from: NSNumber(value: rate)) {
            basalRateLabel?.text = String(format: basalRateFormatString, rateString)
            accessibilityValue = String(format: NSLocalizedString("%1$@ units per hour at %2$@", comment: "Accessibility format string describing the basal rate. (1: localized basal rate value)(2: last updated time)"), rateString, time)
        } else {
            basalRateLabel?.text = nil
            accessibilityValue = nil
        }

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
