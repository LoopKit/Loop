//
//  GlucoseHUDView.swift
//  Loop
//
//  Created by Nate Racklyeft on 8/3/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import UIKit
import LoopKit
import HealthKit


final class GlucoseHUDView: HUDView {

    @IBOutlet private var unitLabel: UILabel! {
        didSet {
            unitLabel?.text = "–"
            unitLabel?.textColor = .glucoseTintColor
        }
    }

    @IBOutlet private var glucoseLabel: UILabel! {
        didSet {
            glucoseLabel?.text = "–"
            glucoseLabel?.textColor = .glucoseTintColor
        }
    }

    func set(glucoseValue: GlucoseValue, for unit: HKUnit, from sensor: SensorDisplayable?) {
        caption?.text = timeFormatter.stringFromDate(glucoseValue.startDate)

        let numberFormatter = NSNumberFormatter()
        numberFormatter.numberStyle = .DecimalStyle
        numberFormatter.minimumFractionDigits = unit.preferredMinimumFractionDigits
        glucoseLabel.text = numberFormatter.stringFromNumber(glucoseValue.quantity.doubleValueForUnit(unit))

        var unitStrings = [unit.glucoseUnitDisplayString]

        if let trend = sensor?.trendType {
            unitStrings.append(trend.description)
        }

        unitLabel.text = unitStrings.joinWithSeparator(" ")
    }

    private lazy var timeFormatter: NSDateFormatter = {
        let formatter = NSDateFormatter()
        formatter.dateStyle = .NoStyle
        formatter.timeStyle = .ShortStyle

        return formatter
    }()

}
