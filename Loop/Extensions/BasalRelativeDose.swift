//
//  BasalRelativeDose.swift
//  Loop
//
//  Created by Pete Schwamb on 2/12/24.
//  Copyright © 2024 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopAlgorithm

public extension Array where Element == BasalRelativeDose {
    func trimmed(from start: Date? = nil, to end: Date? = nil) -> [BasalRelativeDose] {
        return self.compactMap { (dose) -> BasalRelativeDose? in
            if let start, dose.endDate < start {
                return nil
            }
            if let end, dose.startDate > end {
                return nil
            }
            if dose.type == .bolus {
                // Do not split boluses
                return dose
            }
            return dose.trimmed(from: start, to: end)
        }
    }
}

extension BasalRelativeDose {
    public func trimmed(from start: Date? = nil, to end: Date? = nil, syncIdentifier: String? = nil) -> BasalRelativeDose {

        let originalDuration = endDate.timeIntervalSince(startDate)

        let startDate = max(start ?? .distantPast, self.startDate)
        let endDate = max(startDate, min(end ?? .distantFuture, self.endDate))

        var trimmedVolume: Double = volume

        if originalDuration > .ulpOfOne && (startDate > self.startDate || endDate < self.endDate) {
            trimmedVolume = volume * (endDate.timeIntervalSince(startDate) / originalDuration)
        }

        return BasalRelativeDose(
            type: self.type,
            startDate: startDate,
            endDate: endDate,
            volume: trimmedVolume
        )
    }
}
