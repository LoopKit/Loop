//
//  MySentryPumpStatusMessageBody.swift
//  Loop
//
//  Created by Nate Racklyeft on 7/28/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import LoopKit
import MinimedKit


extension MySentryPumpStatusMessageBody: SensorDisplayable {
    var stateDescription: String {
        switch glucose {
        case .Active:
            return "✓"
        case .Off:
            return ""
        default:
            return String(glucose)
        }
    }

    var trendDescription: String {
        guard case .Active = glucose else {
            return ""
        }

        switch glucoseTrend {
        case .Flat:
            return "→"
        case .Up:
            return "⇈"
        case .UpUp:
            return "↑"
        case .Down:
            return "↓"
        case .DownDown:
            return "⇊"
        }
    }
}