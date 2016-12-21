//
//  HUDView.swift
//  Loop
//
//  Created by Bharat Mediratta on 12/20/16.
//  Copyright © 2016 LoopKit Authors. All rights reserved.
//

import UIKit

public class HUDStackView: UIStackView {
    @IBOutlet public weak var loopCompletionHUD: LoopCompletionHUDView!
    @IBOutlet public weak var glucoseHUD: GlucoseHUDView!
    @IBOutlet public weak var basalRateHUD: BasalRateHUDView!
    @IBOutlet public weak var reservoirVolumeHUD: ReservoirVolumeHUDView!
    @IBOutlet public weak var batteryHUD: BatteryLevelHUDView!
}
