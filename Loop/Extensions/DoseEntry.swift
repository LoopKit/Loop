//
//  DoseEntry.swift
//  Loop
//
//  Created by Pete Schwamb on 2/13/24.
//  Copyright © 2024 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit

public extension Array where Element == DoseEntry {
    func trimmed(from start: Date? = nil, to end: Date? = nil, onlyTrimTempBasals: Bool = false) -> [DoseEntry] {
        return self.compactMap { (dose) -> DoseEntry? in
            if let start, dose.endDate < start {
                return nil
            }
            if let end, dose.startDate > end {
                return nil
            }
            if onlyTrimTempBasals && dose.type == .bolus {
                return dose
            }
            return dose.trimmed(from: start, to: end)
        }
    }
}
