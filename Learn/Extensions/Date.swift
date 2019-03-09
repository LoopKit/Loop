//
//  Date.swift
//  Learn
//
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import Foundation


extension Date: Strideable {
    public typealias Stride = TimeInterval

    public func distance(to other: Date) -> TimeInterval {
        return other.timeIntervalSince(self)
    }

    public func advanced(by n: TimeInterval) -> Date {
        return addingTimeInterval(n)
    }
}
