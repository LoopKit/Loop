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

    var trendType: GlucoseTrend? {
        guard case .Active = glucose else {
            return nil
        }

        switch glucoseTrend {
        case .Down:
            return .Down
        case .DownDown:
            return .DownDown
        case .Up:
            return .Up
        case .UpUp:
            return .UpUp
        case .Flat:
            return .Flat
        }
    }
}
