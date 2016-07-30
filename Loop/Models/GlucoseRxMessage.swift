//
//  GlucoseRxMessage.swift
//  Loop
//
//  Created by Nathan Racklyeft on 5/30/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation
import xDripG5


protocol SensorDisplayable {
    // Describes the state of the sensor in the current localization
    var stateDescription: String { get }

    // Describes the trend of the sensor values in the current localization
    var trendDescription: String { get }
}


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

    var trendDescription: String {
        guard trend < Int8.max else {
            return ""
        }

        let direction: String
        switch trend {
        case let x where x < -10:
            direction = "⇊"
        case let x where x < 0:
            direction = "↓"
        case let x where x > 10:
            direction = "⇈"
        case let x where x > 0:
            direction = "↑"
        default:
            direction = "→"
        }

        return String(format: NSLocalizedString("%1$d %2$@", comment: "The format string describing the G5 sensor trend (1: The raw trend value)(2: The direction arrow)"), trend, direction)
    }
}