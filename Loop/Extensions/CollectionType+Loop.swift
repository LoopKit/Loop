//
//  CollectionType.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 2/21/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation
import LoopKit


public extension Sequence where Element: TimelineValue {
    /// Returns the closest element index in the sorted sequence prior to the specified date
    ///
    /// - parameter date: The date to use in the search
    ///
    /// - returns: The closest index, if any exist before the specified date
    func closestIndex(priorTo date: Date) -> Int? {
        var closestIndex: Int?

        for (index, value) in self.enumerated() {
            if value.startDate <= date {
                closestIndex = index
            } else {
                break
            }
        }

        return closestIndex
    }
}
