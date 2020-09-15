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

// Source:  https://github.com/apple/swift/blob/master/stdlib/public/core/CollectionAlgorithms.swift#L476
extension Collection {
    /// Returns the index of the first element in the collection that matches
    /// the predicate.
    ///
    /// The collection must already be partitioned according to the predicate.
    /// That is, there should be an index `i` where for every element in
    /// `collection[..<i]` the predicate is `false`, and for every element
    /// in `collection[i...]` the predicate is `true`.
    ///
    /// - Parameter predicate: A predicate that partitions the collection.
    /// - Returns: The index of the first element in the collection for which
    ///   `predicate` returns `true`.
    ///
    /// - Complexity: O(log *n*), where *n* is the length of this collection if
    ///   the collection conforms to `RandomAccessCollection`, otherwise O(*n*).
    func partitioningIndex(
        where predicate: (Element) throws -> Bool
    ) rethrows -> Index {
        var n = count
        var l = startIndex

        while n > 0 {
            let half = n / 2
            let mid = index(l, offsetBy: half)
            if try predicate(self[mid]) {
                n = half
            } else {
                l = index(after: mid)
                n -= half + 1
            }
        }
        return l
    }
}
