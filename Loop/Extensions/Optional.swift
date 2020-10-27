//
//  Optional.swift
//  Loop
//
//  Created by Michael Pangburn on 5/19/19.
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

extension Optional {
    /// Returns `nil` if the value is `nil` or if it fails the predicate.
    func filter(_ shouldKeep: (Wrapped) throws -> Bool) rethrows -> Optional {
        return try flatMap { try shouldKeep($0) ? $0 : nil }
    }
}
