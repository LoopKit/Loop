//
//  GlucoseTrend.swift
//  Loop
//
//  Created by Nate Racklyeft on 8/2/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation


public enum GlucoseTrend: Int {
    case upUpUp       = 1
    case upUp         = 2
    case up           = 3
    case flat         = 4
    case down         = 5
    case downDown     = 6
    case downDownDown = 7

    var symbol: String {
        switch self {
        case .upUpUp:
            return "⇈"
        case .upUp:
            return "↑"
        case .up:
            return "↗︎"
        case .flat:
            return "→"
        case .down:
            return "↘︎"
        case .downDown:
            return "↓"
        case .downDownDown:
            return "⇊"
        }
    }

    var localizedDescription: String {
        switch self {
        case .upUpUp:
            return NSLocalizedString("Rising very fast", comment: "Glucose trend up-up-up")
        case .upUp:
            return NSLocalizedString("Rising fast", comment: "Glucose trend up-up")
        case .up:
            return NSLocalizedString("Rising", comment: "Glucose trend up")
        case .flat:
            return NSLocalizedString("Flat", comment: "Glucose trend flat")
        case .down:
            return NSLocalizedString("Falling", comment: "Glucose trend down")
        case .downDown:
            return NSLocalizedString("Falling fast", comment: "Glucose trend down-down")
        case .downDownDown:
            return NSLocalizedString("Falling very fast", comment: "Glucose trend down-down-down")
        }
    }
}
