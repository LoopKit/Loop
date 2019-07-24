//
//  RangeReplaceableCollection.swift
//  Loop
//
//  Created by Michael Pangburn on 3/6/19.
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

extension RangeReplaceableCollection where Element: Equatable {
    /// Returns `true` if the element was removed, or `false` if it is not present in the collection.
    @discardableResult
    mutating func remove(_ element: Element) -> Bool {
        guard let index = self.firstIndex(of: element) else {
            return false
        }

        remove(at: index)
        return true
    }
}
