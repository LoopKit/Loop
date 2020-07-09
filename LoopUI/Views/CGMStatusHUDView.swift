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
    
    private var viewModel: CGMStatusHUDViewModel!
    
    @IBOutlet public weak var glucoseValueHUD: GlucoseValueHUDView!
    
    @IBOutlet public weak var glucoseTrendHUD: GlucoseTrendHUDView!
    
    override public var orderPriority: HUDViewOrderPriority {
        return 1
    }
    
    public var isVisible: Bool {
        get {
            viewModel.isVisible
        }
        set {
            if viewModel.isVisible != newValue {
                viewModel.isVisible = newValue
            }
        }
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
        statusHighlightView.setIconPosition(.right)
        viewModel = CGMStatusHUDViewModel(staleGlucoseValueHandler: { self.glucoseValueHUD.glucoseLabel.text = $0 })
    }
    
    public override func tintColorDidChange() {
        super.tintColorDidChange()
        
        glucoseValueHUD.tintColor = viewModel.glucoseValueTintColor
        glucoseTrendHUD.tintColor = viewModel.glucoseTrendTintColor
    }
    
    public func presentAddCGMHighlight() {
        resetProgress()
        presentStatusHighlight(withMessage: LocalizedString("Add CGM", comment: "Title text for button to set up a CGM"),
                               image: UIImage(systemName: "plus.circle")!,
                               color: .systemBlue)
    }
    
    override func presentStatusHighlight() {
        guard statusStackView.arrangedSubviews.contains(glucoseValueHUD),
            statusStackView.arrangedSubviews.contains(glucoseTrendHUD) else
        {
            return
        }
        
        // need to also hide these view, since they will be added back to the stack at some point
        glucoseValueHUD.isHidden = true
        glucoseTrendHUD.isHidden = true
        statusStackView.removeArrangedSubview(glucoseValueHUD)
        statusStackView.removeArrangedSubview(glucoseTrendHUD)
        
        super.presentStatusHighlight()
    }
    
    override public func dismissStatusHighlight() {
        guard statusStackView.arrangedSubviews.contains(statusHighlightView) else {
            return
        }
        
        super.dismissStatusHighlight()
        
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
        viewModel.setGlucoseQuantity(glucoseQuantity,
                                     at: glucoseStartDate,
                                     unit: unit,
                                     staleGlucoseAge: staleGlucoseAge,
                                     sensor: sensor)
        
        glucoseValueHUD.glucoseLabel.text = viewModel.glucoseValueString
        glucoseValueHUD.unitLabel.text = viewModel.unitsString
        glucoseValueHUD.tintColor = viewModel.glucoseValueTintColor
        
        glucoseTrendHUD.setTrend(viewModel.trend)
        glucoseTrendHUD.tintColor = viewModel.glucoseTrendTintColor
        
        accessibilityValue = viewModel.accessibilityString
    }
}
