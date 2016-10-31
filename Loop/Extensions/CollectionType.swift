//
//  CollectionType.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 2/21/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation
import LoopKit


extension BidirectionalCollection where Index: Strideable, Iterator.Element: Comparable, Index.Stride == Int {

    /**
     Returns the insertion index of a new value in a sorted collection

     Based on some helpful responses found at [StackOverflow](http://stackoverflow.com/a/33674192)
     
     - parameter value: The value to insert

     - returns: The appropriate insertion index, between `startIndex` and `endIndex`
     */
    func findInsertionIndex(for value: Iterator.Element) -> Index {
        var low = startIndex
        var high = endIndex

        while low != high {
            let mid = low.advanced(by: low.distance(to: high) / 2)

            if self[mid] < value {
                low = mid.advanced(by: 1)
            } else {
                high = mid
            }
        }

        return low
    }
}


extension BidirectionalCollection where Index: Strideable, Iterator.Element: Strideable, Index.Stride == Int {
    /**
     Returns the index of the closest element to a specified value in a sorted collection

     - parameter value: The value to match

     - returns: The index of the closest element, or nil if the collection is empty
     */
    func findClosestElementIndex(matching value: Iterator.Element) -> Index? {
        let upperBound = findInsertionIndex(for: value)

        if upperBound == startIndex {
            if upperBound == endIndex {
                return nil
            }
            return upperBound
        }

        let lowerBound = upperBound.advanced(by: -1)

        if upperBound == endIndex {
            return lowerBound
        }

        if value.distance(to: self[upperBound]) < self[lowerBound].distance(to: value) {
            return upperBound
        }
        
        return lowerBound
    }
}


public extension Sequence where Iterator.Element: TimelineValue {
    /// Returns the closest element index in the sorted sequence prior to the specified date
    ///
    /// - parameter date: The date to use in the search
    ///
    /// - returns: The closest index, if any exist before the specified date
    func closestIndexPriorToDate(_ date: Date) -> Int? {
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
