//
//  GlucoseRxMessage.swift
//  Loop
//
//  Created by Nathan Racklyeft on 5/30/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation
import LoopUI
import xDripG5


extension Glucose: SensorDisplayable {
    public var isStateValid: Bool {
        return state == .ok && status == .ok
    }

    public var stateDescription: String {
        let status: String
        switch self.status {
        case .ok:
            status = ""
        case .lowBattery:
            status = NSLocalizedString(" Low Battery", comment: "The description of a low G5 transmitter battery with a leading space")
        case .unknown(let value):
            status = String(format: "%02x", value)
        }

        return String(format: "%1$@ %2$@", String(describing: state), status)
    }

    public var trendType: GlucoseTrend? {
        guard trend < Int(Int8.max) else {
            return nil
        }

        switch trend {
        case let x where x <= -30:
            return .downDownDown
        case let x where x <= -20:
            return .downDown
        case let x where x <= -10:
            return .down
        case let x where x < 10:
            return .flat
        case let x where x < 20:
            return .up
        case let x where x < 30:
            return .upUp
        default:
            return .upUpUp
        }
    }

    public var isLocal: Bool {
        return true
    }
}
