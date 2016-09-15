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
            alertLabel.textColor = UIColor.white
            alertLabel.layer.cornerRadius = 9
            alertLabel.clipsToBounds = true
        }
    }

    func set(_ glucoseValue: GlucoseValue, for unit: HKUnit, from sensor: SensorDisplayable?) {
        caption?.text = timeFormatter.string(from: glucoseValue.startDate)

        let numberFormatter = NumberFormatter.glucoseFormatter(for: unit)
        glucoseLabel.text = numberFormatter.string(from: NSNumber(value: glucoseValue.quantity.doubleValue(for: unit)))

        var unitStrings = [unit.glucoseUnitDisplayString]

        if let trend = sensor?.trendType {
            unitStrings.append(trend.description)
        }

        unitLabel.text = unitStrings.joined(separator: " ")

        UIView.animate(withDuration: 0.25, animations: { 
            self.alertLabel.alpha = sensor?.isStateValid == true ? 0 : 1
        }) 
    }

    private lazy var timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short

        return formatter
    }()

}
