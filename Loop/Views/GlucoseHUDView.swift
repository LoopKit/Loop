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
            unitLabel.text = "–"
            unitLabel.textColor = .glucoseTintColor
        }
    }

    @IBOutlet private var glucoseLabel: UILabel! {
        didSet {
            glucoseLabel.text = "–"
            glucoseLabel.textColor = .glucoseTintColor
        }
    }

    @IBOutlet private var alertLabel: UILabel! {
        didSet {
            alertLabel.alpha = 0
            alertLabel.backgroundColor = UIColor.agingColor
            alertLabel.textColor = UIColor.whiteColor()
            alertLabel.layer.cornerRadius = 9
            alertLabel.clipsToBounds = true
        }
    }

    func set(glucoseValue: GlucoseValue, for unit: HKUnit, from sensor: SensorDisplayable?) {
        caption?.text = timeFormatter.stringFromDate(glucoseValue.startDate)

        let numberFormatter = NSNumberFormatter.glucoseFormatter(for: unit)
        glucoseLabel.text = numberFormatter.stringFromNumber(glucoseValue.quantity.doubleValueForUnit(unit))

        var unitStrings = [unit.glucoseUnitDisplayString]

        if let trend = sensor?.trendType {
            unitStrings.append(trend.description)
        }

        unitLabel.text = unitStrings.joinWithSeparator(" ")

        UIView.animateWithDuration(0.25) { 
            self.alertLabel.alpha = sensor?.isStateValid == true ? 0 : 1
        }
    }

    private lazy var timeFormatter: NSDateFormatter = {
        let formatter = NSDateFormatter()
        formatter.dateStyle = .NoStyle
        formatter.timeStyle = .ShortStyle

        return formatter
    }()

}
