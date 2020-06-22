//
//  GlucoseTrendHUDView.swift
//  LoopUI
//
//  Created by Nathaniel Hamming on 2020-06-05.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import UIKit
import HealthKit
import LoopKit
import LoopKitUI

public final class GlucoseTrendHUDView: BaseHUDView {
    
    override public var orderPriority: HUDViewOrderPriority {
        return 2
    }

    @IBOutlet private weak var trendLabel: UILabel! {
        didSet {
            trendLabel.text = "–"
            trendLabel.textColor = .secondaryLabel
        }
    }

    public override func tintColorDidChange() {
        super.tintColorDidChange()

        trendLabel.textColor = tintColor
    }

    public func setTrend(_ trend: GlucoseTrend) {
        trendLabel.text = trend.symbol
    }
}
