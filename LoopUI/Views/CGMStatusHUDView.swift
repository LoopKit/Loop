//
//  CGMStatusHUDView.swift
//  LoopUI
//
//  Created by Nathaniel Hamming on 2020-06-05.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import UIKit
import HealthKit
import LoopKit
import LoopKitUI

public final class CGMStatusHUDView: DeviceStatusHUDView, NibLoadable {
    
    @IBOutlet public weak var glucoseValueHUD: GlucoseValueHUDView!
    
    @IBOutlet public weak var glucoseTrendHUD: GlucoseTrendHUDView!
    
    override public var orderPriority: HUDViewOrderPriority {
        return 1
    }
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    public required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setup()
        
    }
    
    override func setup() {
        super.setup()
        alertStatusView.setIconPosition(.right)
    }
    
    public override func tintColorDidChange() {
        super.tintColorDidChange()
        
        glucoseValueHUD.tintColor = tintColor
        glucoseTrendHUD.tintColor = tintColor
    }
    
    public func presentAddCGMAlert() {
        alertStatusView.alertMessageLabel.text = LocalizedString("Add CGM", comment: "Title text for button to set up a CGM")
        alertStatusView.alertMessageLabel.tintColor = .label
        alertStatusView.alertIcon.image = UIImage(systemName: "plus.circle")
        alertStatusView.alertIcon.tintColor = .systemBlue
        presentAlert()
    }
    
    override public func presentAlert() {
        guard !statusStackView.arrangedSubviews.contains(alertStatusView) else {
            return
        }
        
        // need to also hide these view, since they will be added back to the stack at some point
        glucoseValueHUD.isHidden = true
        glucoseTrendHUD.isHidden = true
        statusStackView.removeArrangedSubview(glucoseValueHUD)
        statusStackView.removeArrangedSubview(glucoseTrendHUD)
        
        super.presentAlert()
    }
    
    override public func dismissAlert() {
        guard statusStackView.arrangedSubviews.contains(alertStatusView) else {
            return
        }
        
        super.dismissAlert()
        
        statusStackView.addArrangedSubview(glucoseValueHUD)
        statusStackView.addArrangedSubview(glucoseTrendHUD)
        glucoseValueHUD.isHidden = false
        glucoseTrendHUD.isHidden = false
    }
    
    public func setGlucoseQuantity(_ glucoseQuantity: Double,
                                   at glucoseStartDate: Date,
                                   unit: HKUnit,
                                   staleGlucoseAge: TimeInterval,
                                   sensor: SensorDisplayable?)
    {
        // TODO refactor this function with LOOP-1293. Suggestion is to make a view model. Need to check with design about the display of stale glucose values.
        var accessibilityStrings = [String]()
        
        let time = timeFormatter.string(from: glucoseStartDate)
        caption?.text = time
        
        isStaleAt = glucoseStartDate.addingTimeInterval(staleGlucoseAge)
        let glucoseValueCurrent = Date() < isStaleAt!
        
        let numberFormatter = NumberFormatter.glucoseFormatter(for: unit)
        if let valueString = numberFormatter.string(from: glucoseQuantity) {
            if glucoseValueCurrent {
                glucoseValueHUD.glucoseLabel.text = valueString
                startStalenessTimerIfNeeded()
            } else {
                glucoseValueHUD.glucoseLabel.text = GlucoseValueHUDView.staleGlucoseRepresentation
            }
            accessibilityStrings.append(String(format: LocalizedString("%1$@ at %2$@", comment: "Accessbility format value describing glucose: (1: glucose number)(2: glucose time)"), valueString, time))
        }
        
        if let trend = sensor?.trendType, glucoseValueCurrent {
            glucoseTrendHUD.setTrend(trend)
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
        glucoseValueHUD.unitLabel.text = unit.localizedShortUnitString
        accessibilityValue = accessibilityStrings.joined(separator: ", ")
    }
    
    private lazy var timeFormatter = DateFormatter(timeStyle: .short)
    
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
        if let fireDate = isStaleAt,
            isVisible,
            stalenessTimer == nil
        {
            stalenessTimer = Timer(fire: fireDate, interval: 0, repeats: false) { (_) in
                self.glucoseValueHUD.glucoseLabel.text = GlucoseValueHUDView.staleGlucoseRepresentation
            }
            RunLoop.main.add(stalenessTimer!, forMode: .default)
        }
    }
    
    private enum SensorAlertState {
        case ok
        case missing
        case invalid
        case remote
    }
    
    override public func stateColorsDidUpdate() {
        super.stateColorsDidUpdate()
    }
    
    private var sensorAlertState = SensorAlertState.ok
    
}
