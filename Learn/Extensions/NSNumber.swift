//
//  NSNumber.swift
//  Learn
//
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import Foundation


extension NSNumber: Comparable {
    public static func < (lhs: NSNumber, rhs: NSNumber) -> Bool {
        return lhs.compare(rhs) == .orderedAscending
    }
}


extension NSNumber {
    convenience init?(value: Double?) {
        if let value = value {
            self.init(value: value)
        } else {
            return nil
        }
    }
}
