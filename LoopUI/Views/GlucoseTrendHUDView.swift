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

    @IBOutlet private weak var trendIcon: UIImageView! {
        didSet {
            trendIcon.image = UIImage(systemName: "questionmark.circle")
            trendIcon.tintColor = .systemPurple
        }
    }

    public override func tintColorDidChange() {
        super.tintColorDidChange()
        
        trendIcon.tintColor = tintColor
    }

    public func setTrend(_ trend: GlucoseTrend?) {
        guard let trend = trend else {
            trendIcon.image = UIImage(systemName: "questionmark.circle")
            return
        }
        
        switch trend {
        case .upUpUp:
            // TODO this is a placeholder until I get the correct icon from design
            trendIcon.image = UIImage(systemName: "arrow.up.circle")
        case .upUp:
            trendIcon.image = UIImage(systemName: "arrow.up.circle")
        case .up:
            trendIcon.image = UIImage(systemName: "arrow.up.right.circle")
        case .flat:
            trendIcon.image = UIImage(systemName: "arrow.right.circle")
        case .down:
            trendIcon.image = UIImage(systemName: "arrow.down.right.circle")
        case .downDown:
            trendIcon.image = UIImage(systemName: "arrow.down.circle")
        case .downDownDown:
            // TODO this is a placeholder until I get the correct icon from design
            trendIcon.image = UIImage(systemName: "arrow.down.circle")
        }
    }
}
