//
//  GlucoseRxMessage.swift
//  Loop
//
//  Created by Nathan Racklyeft on 5/30/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation
import xDripG5


extension GlucoseRxMessage: SensorDisplayable {
    var stateDescription: String {
        let status: String
        switch self.status {
        case .OK:
            status = ""
        case .LowBattery:
            status = NSLocalizedString("Low Battery", comment: "The description of a low G5 transmitter battery")
        case .Unknown(let value):
            status = String(format: "%02x", value)
        }

        return String(format: "%1$02x %2$@", state, status)
    }

    var trendType: GlucoseTrend? {
        guard trend < Int8.max else {
            return nil
        }

        switch trend {
        case let x where x <= -30:
            return .DownDownDown
        case let x where x <= -20:
            return .DownDown
        case let x where x <= -10:
            return .Down
        case let x where x < 10:
            return .Flat
        case let x where x < 20:
            return .Up
        case let x where x < 30:
            return .UpUp
        default:
            return .UpUpUp
        }
    }

    var trendDescription: String {
        guard let trendType = trendType else {
            return ""
        }

        return String(format: NSLocalizedString("%1$d %2$@", comment: "The format string describing the G5 sensor trend (1: The raw trend value)(2: The direction arrow)"), trend, trendType.description)
    }
}