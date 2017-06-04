//
//  MySentryPumpStatusMessageBody.swift
//  Loop
//
//  Created by Nate Racklyeft on 7/28/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import LoopKit
import LoopUI
import MinimedKit


extension MySentryPumpStatusMessageBody: SensorDisplayable {
    public var isStateValid: Bool {
        switch glucose {
        case .active:
            return true
        default:
            return false
        }
    }

    public var trendType: LoopUI.GlucoseTrend? {
        guard case .active = glucose else {
            return nil
        }

        switch glucoseTrend {
        case .down:
            return .down
        case .downDown:
            return .downDown
        case .up:
            return .up
        case .upUp:
            return .upUp
        case .flat:
            return .flat
        }
    }

    public var isLocal: Bool {
        return true
    }

    var batteryPercentage: Int {
        return batteryRemainingPercent
    }
}
