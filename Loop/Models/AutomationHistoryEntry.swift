//
//  AutomationHistoryEntry.swift
//  Loop
//
//  Created by Pete Schwamb on 9/19/24.
//  Copyright © 2024 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit

public struct AutomationHistoryEntry: Codable, Hashable {
    var startDate: Date
    var enabled: Bool
}

extension Array where Element == AutomationHistoryEntry {
    func toTimeline(from start: Date, to end: Date = .now) -> [AbsoluteScheduleValue<Bool>] {
        guard !isEmpty else {
            return []
        }

        var out = [AbsoluteScheduleValue<Bool>]()

        var iter = makeIterator()

        var prev = iter.next()!

        if prev.startDate > start {
            let gapEnd = Swift.min(prev.startDate, end)
            out.append(AbsoluteScheduleValue(startDate: start, endDate: gapEnd, value: !prev.enabled))
        }

        while let cur = iter.next() {
            guard cur.enabled != prev.enabled else {
                continue
            }
            if cur.startDate > start {
                let segmentStart = Swift.max(prev.startDate, start)
                let segmentEnd = Swift.min(cur.startDate, end)
                out.append(AbsoluteScheduleValue(startDate: segmentStart, endDate: segmentEnd, value: prev.enabled))
            }
            prev = cur
        }

        if prev.startDate < end {
            let segmentStart = Swift.max(prev.startDate, start)
            out.append(AbsoluteScheduleValue(startDate: segmentStart, endDate: end, value: prev.enabled))
        }

        return out
    }
    
    func automationEnabled(at date: Date) -> Bool? {
        let clampedValues = toTimeline(from: date)
        guard let first = clampedValues.first else {
            return nil
        }
        
        if date < first.startDate {
            return !first.value
        } else if let enabled = clampedValues.last(where: { $0.startDate <= date })?.value {
            return enabled
        } else {
            return nil
        }
    }
}
