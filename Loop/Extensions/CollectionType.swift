//
//  CollectionType.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 2/21/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation


extension CollectionType where Index: RandomAccessIndexType, Generator.Element: Comparable {

    /**
     Returns the insertion index of a new value in a sorted collection

     Based on some helpful responses found at [StackOverflow](http://stackoverflow.com/a/33674192)
     
     - parameter value: The value to insert

     - returns: The appropriate insertion index, between `startIndex` and `endIndex`
     */
    func findInsertionIndexForValue(value: Generator.Element) -> Index {
        var low = startIndex
        var high = endIndex

        while low != high {
            let mid = low.advancedBy(low.distanceTo(high) / 2)

            if self[mid] < value {
                low = mid.advancedBy(1)
            } else {
                high = mid
            }
        }

        return low
    }
}


extension CollectionType where Index: RandomAccessIndexType, Generator.Element: Strideable {
    /**
     Returns the index of the closest element to a specified value in a sorted collection

     - parameter value: The value to match

     - returns: The index of the closest element, or nil if the collection is empty
     */
    func findClosestElementIndexToValue(value: Generator.Element) -> Index? {
        let upperBound = findInsertionIndexForValue(value)

        if upperBound == startIndex {
            if upperBound == endIndex {
                return nil
            }
            return upperBound
        }

        let lowerBound = upperBound.advancedBy(-1)

        if upperBound == endIndex {
            return lowerBound
        }

        if value.distanceTo(self[upperBound]) < self[lowerBound].distanceTo(value) {
            return upperBound
        }
        
        return lowerBound
    }
}