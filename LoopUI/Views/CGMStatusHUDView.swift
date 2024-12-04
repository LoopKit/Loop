//
//  CGMStatusHUDView.swift
//  LoopUI
//
//  Created by Nathaniel Hamming on 2020-06-05.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import UIKit
import LoopAlgorithm
import LoopKit
import LoopKitUI

public final class CGMStatusHUDView: DeviceStatusHUDView, NibLoadable {
    
    private var viewModel: CGMStatusHUDViewModel!
    
    @IBOutlet public weak var glucoseValueHUD: GlucoseValueHUDView!
    
    @IBOutlet public weak var glucoseTrendHUD: GlucoseTrendHUDView!
    
    override public var orderPriority: HUDViewOrderPriority {
        return 1
    }
    
    public var isGlucoseValueStale: Bool {
        get {
            viewModel.isGlucoseValueStale
        }
        set {
            viewModel.isGlucoseValueStale = newValue
        }
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
    
    override public init(frame: CGRect) {
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
        viewModel = CGMStatusHUDViewModel()
    }
    
    override public func tintColorDidChange() {
        super.tintColorDidChange()
        
        glucoseValueHUD.tintColor = viewModel.glucoseValueTintColor
        glucoseTrendHUD.tintColor = viewModel.glucoseTrendTintColor
    }

    override public func presentStatusHighlight(_ statusHighlight: DeviceStatusHighlight?) {
        viewModel.statusHighlight = statusHighlight
        super.presentStatusHighlight(viewModel.statusHighlight)
    }
    
    override func presentStatusHighlight() {
        defer {
            // when the status highlight is updated, the trend icon may also need to be updated
            updateTrendIcon()
            // when the status highlight is updated, the accessibility string is updated
            accessibilityValue = viewModel.accessibilityString
        }
        
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
        defer {
            // when the status highlight is updated, the trend icon may also need to be updated
            updateTrendIcon()
            // when the status highlight is updated, the accessibility string is updated
            accessibilityValue = viewModel.accessibilityString
        }
        
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
                                   unit: LoopUnit,
                                   glucoseDisplay: GlucoseDisplayable?,
                                   wasUserEntered: Bool,
                                   isDisplayOnly: Bool,
                                   isGlucoseValueStale: Bool)
    {
        viewModel.setGlucoseQuantity(glucoseQuantity,
                                     at: glucoseStartDate,
                                     unit: unit,
                                     glucoseDisplay: glucoseDisplay,
                                     wasUserEntered: wasUserEntered,
                                     isDisplayOnly: isDisplayOnly,
                                     isGlucoseValueStale: isGlucoseValueStale)
        
        updateDisplay()
    }

    func updateDisplay() {
        glucoseValueHUD.glucoseLabel.text = viewModel.glucoseValueString
        glucoseValueHUD.unitLabel.text = viewModel.unitsString
        glucoseValueHUD.tintColor = viewModel.glucoseValueTintColor
        presentStatusHighlight(viewModel.statusHighlight)
        
        accessibilityValue = viewModel.accessibilityString
    }
    
    func updateTrendIcon() {
        glucoseTrendHUD.setIcon(viewModel.glucoseTrendIcon)
        glucoseTrendHUD.tintColor = viewModel.glucoseTrendTintColor
    }
}
