//
//  GlucoseG4.swift
//  Loop
//
//  Created by Mark Wilson on 7/21/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation
import G4ShareSpy


let TREND_TO_DESCRIPTION: [UInt8: String] = [
    1: "⇈",
    2: "↑",
    3: "↗",
    4: "→",
    5: "↘",
    6: "↓",
    7: "⇊",
]

extension GlucoseG4 {
    var trendDescription: String {
        if let direction = TREND_TO_DESCRIPTION[trend] {
            return direction
        } else {
            return ""
        }
    }
}