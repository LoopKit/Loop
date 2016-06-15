//
//  GlucoseRxMessage.swift
//  Loop
//
//  Created by Nathan Racklyeft on 5/30/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation
import xDripG5


extension GlucoseRxMessage {
    var trendDescription: String {
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
            direction = ""
        }

        return direction
    }
}