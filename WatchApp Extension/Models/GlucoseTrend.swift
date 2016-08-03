//
//  GlucoseTrend.swift
//  Loop
//
//  Created by Nate Racklyeft on 8/2/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//


enum GlucoseTrend: Int {
    case UpUpUp       = 1
    case UpUp         = 2
    case Up           = 3
    case Flat         = 4
    case Down         = 5
    case DownDown     = 6
    case DownDownDown = 7

    var description: String {
        switch self {
        case UpUpUp:
            return "⇈"
        case UpUp:
            return "↑"
        case Up:
            return "↗"
        case Flat:
            return "→"
        case Down:
            return "↘"
        case DownDown:
            return "↓"
        case DownDownDown:
            return "⇊"
        }
    }
}
