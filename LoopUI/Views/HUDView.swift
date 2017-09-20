//
//  HUDView.swift
//  Loop
//
//  Created by Bharat Mediratta on 12/20/16.
//  Copyright © 2016 LoopKit Authors. All rights reserved.
//

import UIKit

public class HUDView: UIView, NibLoadable {
    @IBOutlet public weak var loopCompletionHUD: LoopCompletionHUDView!
    @IBOutlet public weak var glucoseHUD: GlucoseHUDView!
    @IBOutlet public weak var basalRateHUD: BasalRateHUDView!
    @IBOutlet public weak var reservoirVolumeHUD: ReservoirVolumeHUDView!
    @IBOutlet public weak var batteryHUD: BatteryLevelHUDView!

    func setup() {
        let stackView = HUDView.nib().instantiate(withOwner: self, options: nil)[0] as! UIStackView
        self.addSubview(stackView)

        // Use AutoLayout to have the stack view fill its entire container.
        let horizontalConstraint = NSLayoutConstraint(item: stackView, attribute: .centerX, relatedBy: .equal, toItem: self, attribute: .centerX, multiplier: 1, constant: 0)
        let verticalConstraint = NSLayoutConstraint(item: stackView, attribute: .centerY, relatedBy: .equal, toItem: self, attribute: .centerY, multiplier: 1, constant: 0)
        let widthConstraint = NSLayoutConstraint(item: stackView, attribute: .width, relatedBy: .equal, toItem: self, attribute: .width, multiplier: 1, constant: 0)
        let heightConstraint = NSLayoutConstraint(item: stackView, attribute: .height, relatedBy: .equal, toItem: self, attribute: .height, multiplier: 1, constant: 0)
        self.addConstraints([horizontalConstraint, verticalConstraint, widthConstraint, heightConstraint])
    }

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    public required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setup()
    }
}
