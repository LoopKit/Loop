//
//  GlucoseHUDView.swift
//  Loop
//
//  Created by Nate Racklyeft on 8/3/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import UIKit
import HealthKit
import LoopKit
import LoopKitUI

public final class GlucoseHUDView: BaseHUDView {
    
    static let staleGlucoseRepresentation: String = NSLocalizedString("– – –", comment: "No glucose value representation (3 dashes for mg/dL)")
    
    private var stalenessTimer: Timer?
    
    private var isStaleAt: Date? {
        didSet {
            if oldValue != isStaleAt {
                stalenessTimer?.invalidate()
                stalenessTimer = nil
            }
        }
    }
    
    public var isVisible: Bool = true {
        didSet {
            if oldValue != isVisible {
                if !isVisible {
                    stalenessTimer?.invalidate()
                    stalenessTimer = nil
                } else {
                    startStalenessTimerIfNeeded()
                }
            }
        }
    }
    
    private func startStalenessTimerIfNeeded() {
        if let fireDate = isStaleAt, isVisible, stalenessTimer == nil {
            
            stalenessTimer = Timer(fire: fireDate, interval: 0, repeats: false) { (_) in
                self.glucoseLabel.text = GlucoseHUDView.staleGlucoseRepresentation
            }
            RunLoop.main.add(stalenessTimer!, forMode: .default)
        }
    }
    
    override public var orderPriority: HUDViewOrderPriority {
        return 2
    }

    @IBOutlet private weak var unitLabel: UILabel! {
        didSet {
            unitLabel.text = "–"
            unitLabel.textColor = tintColor
        }
    }

    @IBOutlet private weak var glucoseLabel: UILabel! {
        didSet {
            glucoseLabel.text = GlucoseHUDView.staleGlucoseRepresentation
            glucoseLabel.textColor = tintColor
        }
    }

    @IBOutlet private weak var alertLabel: UILabel! {
        didSet {
            alertLabel.alpha = 0
            alertLabel.textColor = UIColor.white
            alertLabel.layer.cornerRadius = 9
            alertLabel.clipsToBounds = true
        }
    }

    public override func tintColorDidChange() {
        super.tintColorDidChange()

        unitLabel.textColor = tintColor
        glucoseLabel.textColor = tintColor
    }

    override public func stateColorsDidUpdate() {
        super.stateColorsDidUpdate()
        updateColor()
    }

    private func updateColor() {
        switch sensorAlertState {
        case .missing, .invalid:
            alertLabel.backgroundColor = stateColors?.warning
        case .remote:
            alertLabel.backgroundColor = stateColors?.unknown
        case .ok:
            alertLabel.backgroundColor = stateColors?.normal
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
                alertLabel.text = "!"
            case .remote:
                alertLabel.text = "☁︎"
            }

            updateColor()

            UIView.animate(withDuration: 0.25, animations: {
                self.alertLabel.alpha = alertLabelAlpha
            })
        }
    }

    public func setGlucoseQuantity(_ glucoseQuantity: Double, at glucoseStartDate: Date, unit: HKUnit, staleGlucoseAge: TimeInterval, sensor: GlucoseDisplayable?) {
        var accessibilityStrings = [String]()

        let time = timeFormatter.string(from: glucoseStartDate)
        caption?.text = time
        
        isStaleAt = glucoseStartDate.addingTimeInterval(staleGlucoseAge)
        let glucoseValueCurrent = Date() < isStaleAt!

        let numberFormatter = NumberFormatter.glucoseFormatter(for: unit)
        if let valueString = numberFormatter.string(from: glucoseQuantity) {
            if glucoseValueCurrent {
                glucoseLabel.text = valueString
                startStalenessTimerIfNeeded()
            } else {
                glucoseLabel.text = GlucoseHUDView.staleGlucoseRepresentation
            }
            accessibilityStrings.append(String(format: LocalizedString("%1$@ at %2$@", comment: "Accessbility format value describing glucose: (1: glucose number)(2: glucose time)"), valueString, time))
        }

        var unitStrings = [unit.localizedShortUnitString]

        if let trend = sensor?.trendType, glucoseValueCurrent {
            unitStrings.append(trend.symbol)
            accessibilityStrings.append(trend.localizedDescription)
        }

        if sensor == nil {
            sensorAlertState = .missing
        } else if sensor!.isStateValid == false {
            sensorAlertState = .invalid
            accessibilityStrings.append(LocalizedString("Needs attention", comment: "Accessibility label component for glucose HUD describing an invalid state"))
        } else if sensor!.isLocal == false {
            sensorAlertState = .remote
        } else {
            sensorAlertState = .ok
        }

        unitLabel.text = unitStrings.joined(separator: " ")
        accessibilityValue = accessibilityStrings.joined(separator: ", ")
        
        
    }

    private lazy var timeFormatter = DateFormatter(timeStyle: .short)

}
