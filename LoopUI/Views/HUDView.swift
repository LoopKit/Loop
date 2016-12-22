//
//  HUDView.swift
//  Loop
//
//  Created by Bharat Mediratta on 12/20/16.
//  Copyright © 2016 LoopKit Authors. All rights reserved.
//

import UIKit

public class HUDView: UIStackView {
    @IBOutlet public weak var loopCompletionHUD: LoopCompletionHUDView!
    @IBOutlet public weak var glucoseHUD: GlucoseHUDView!
    @IBOutlet public weak var basalRateHUD: BasalRateHUDView!
    @IBOutlet public weak var reservoirVolumeHUD: ReservoirVolumeHUDView!
    @IBOutlet public weak var batteryHUD: BatteryLevelHUDView!

    func setup() {
        let bundle = Bundle(for: type(of: self))
        let nib = bundle.loadNibNamed("HUDView", owner: self, options:nil)
        if let stackView = nib?[0] as? UIStackView {
            self.addSubview(stackView)
            self.autoresizesSubviews = true
            stackView.translatesAutoresizingMaskIntoConstraints = false
        }
    }

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    public required init(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setup()
    }
}
