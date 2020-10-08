//
//  Collection.swift
//  WatchApp Extension
//
//  Created by Michael Pangburn on 6/30/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

extension Collection {
    /// Returns a sequence containing adjacent pairs of elements in the ordered collection.
    func adjacentPairs() -> Zip2Sequence<Self, SubSequence> {
        return zip(self, dropFirst())
    }
}
