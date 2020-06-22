//
//  GlucoseValueHUDView.swift
//  LoopUI
//
//  Created by Nathaniel Hamming on 2020-06-05.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import UIKit
import HealthKit
import LoopKit
import LoopKitUI

public final class GlucoseValueHUDView: BaseHUDView {

    override public var orderPriority: HUDViewOrderPriority {
        return 1
    }

    static let staleGlucoseRepresentation: String = "---"
    
    @IBOutlet public weak var unitLabel: UILabel! {
        didSet {
            unitLabel.text = "–"
            unitLabel.textColor = .secondaryLabel
        }
    }

    @IBOutlet public weak var glucoseLabel: UILabel! {
        didSet {
            glucoseLabel.text = GlucoseHUDView.staleGlucoseRepresentation
            glucoseLabel.textColor = .label
        }
    }

    public override func tintColorDidChange() {
        super.tintColorDidChange()

        switch self.tintColor {
        case UIColor.label:
            glucoseLabel.textColor = tintColor
            unitLabel.textColor = .secondaryLabel
        default:
            glucoseLabel.textColor = tintColor
            unitLabel.textColor = tintColor
        }
    }
}
