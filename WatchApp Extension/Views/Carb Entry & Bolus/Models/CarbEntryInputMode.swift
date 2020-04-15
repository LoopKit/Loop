//
//  CarbEntryInputMode.swift
//  WatchApp Extension
//
//  Created by Michael Pangburn on 4/1/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

enum CarbEntryInputMode {
    case carbs
    case date

    mutating func toggle() {
        switch self {
        case .carbs:
            self = .date
        case .date:
            self = .carbs
        }
    }
}
