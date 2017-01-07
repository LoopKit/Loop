//
//  GlucoseHUDView.swift
//  Loop
//
//  Created by Nate Racklyeft on 8/3/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import UIKit
import HealthKit


public final class GlucoseHUDView: BaseHUDView {

    @IBOutlet private weak var unitLabel: UILabel! {
        didSet {
            unitLabel.text = "–"
            unitLabel.textColor = .glucoseTintColor
        }
    }

    @IBOutlet private weak var glucoseLabel: UILabel! {
        didSet {
            glucoseLabel.text = "–"
            glucoseLabel.textColor = .glucoseTintColor
        }
    }

    @IBOutlet private weak var alertLabel: UILabel! {
        didSet {
            alertLabel.alpha = 0
            alertLabel.backgroundColor = UIColor.agingColor
            alertLabel.textColor = UIColor.white
            alertLabel.layer.cornerRadius = 9
            alertLabel.clipsToBounds = true
        }
    }

    private enum SensorAlertState {
        case ok
        case missing
        case invalid
        case remote
    }

    private var sensorAlertState = SensorAlertState.ok {
        didSet {
            var alertLabelAlpha: CGFloat = 1

            switch sensorAlertState {
            case .ok:
                alertLabelAlpha = 0
            case .missing, .invalid:
                alertLabel.backgroundColor = UIColor.agingColor
                alertLabel.text = "!"
            case .remote:
                alertLabel.backgroundColor = UIColor.unknownColor
                alertLabel.text = "☁︎"
            }

            UIView.animate(withDuration: 0.25, animations: {
                self.alertLabel.alpha = alertLabelAlpha
            })
        }
    }

    public func set(glucoseQuantity: Double, at glucoseStartDate: Date, unitString: String, from sensor: SensorDisplayable?) {
        var accessibilityStrings = [String]()

        let time = timeFormatter.string(from: glucoseStartDate)
        caption?.text = time
        let unit = HKUnit(from: unitString)

        let numberFormatter = NumberFormatter.glucoseFormatter(for: unit)
        if let valueString = numberFormatter.string(from: NSNumber(value: glucoseQuantity)) {
            glucoseLabel.text = valueString
            accessibilityStrings.append(String(format: NSLocalizedString("%1$@ at %2$@", comment: "Accessbility format value describing glucose: (1: glucose number)(2: glucose time)"), valueString, time))
        }

        var unitStrings = [unit.glucoseUnitDisplayString]

        if let trend = sensor?.trendType {
            unitStrings.append(trend.symbol)
            accessibilityStrings.append(trend.localizedDescription)
        }

        if sensor == nil {
            sensorAlertState = .missing
        } else if sensor!.isStateValid == false {
            sensorAlertState = .invalid
            accessibilityStrings.append(NSLocalizedString("Needs attention", comment: "Accessibility label component for glucose HUD describing an invalid state"))
        } else if sensor!.isLocal == false {
            sensorAlertState = .remote
        } else {
            sensorAlertState = .ok
        }

        unitLabel.text = unitStrings.joined(separator: " ")
        accessibilityValue = accessibilityStrings.joined(separator: ", ")
    }

    private lazy var timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short

        return formatter
    }()

}
