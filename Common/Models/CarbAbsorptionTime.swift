//
//  CarbAbsorptionTime.swift
//  WatchApp Extension
//
//  Created by Michael Pangburn on 4/1/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

enum CarbAbsorptionTime: Int, CaseIterable {
    case fast = 0
    case medium
    case slow

    var emoji: String {
        switch self {
        case .fast:
            return "🍭"
        case .medium:
            return "🌮"
        case .slow:
            return "🍕"
        }
    }
}
