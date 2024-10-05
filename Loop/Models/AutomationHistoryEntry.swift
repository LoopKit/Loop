//
//  AutomationHistoryEntry.swift
//  Loop
//
//  Created by Pete Schwamb on 9/19/24.
//  Copyright © 2024 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopAlgorithm

struct AutomationHistoryEntry: Codable {
    var startDate: Date
    var enabled: Bool
}

extension Array where Element == AutomationHistoryEntry {
    func toTimeline(from start: Date, to end: Date) -> [AbsoluteScheduleValue<Bool>] {
        guard !isEmpty else {
            return []
        }

        var out = [AbsoluteScheduleValue<Bool>]()

        var iter = makeIterator()

        var prev = iter.next()!

        func addItem(start: Date, end: Date, enabled: Bool) {
            out.append(AbsoluteScheduleValue(startDate: start, endDate: end, value: enabled))
        }

        while let cur = iter.next() {
            guard cur.enabled != prev.enabled else {
                continue
            }
            if cur.startDate > start {
                addItem(start: Swift.max(prev.startDate, start), end: Swift.min(cur.startDate, end), enabled: prev.enabled)
            }
            prev = cur
        }

        if prev.startDate < end {
            addItem(start: prev.startDate, end: end, enabled: prev.enabled)
        }

        return out
    }
}
