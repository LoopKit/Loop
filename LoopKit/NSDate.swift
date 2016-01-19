//
//  NSDate.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 1/17/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation


public extension NSDate {
    func dateFlooredToTimeInterval(interval: NSTimeInterval) -> NSDate {
        if interval == 0 {
            return self.copy() as! NSDate
        }

        return NSDate(timeIntervalSinceReferenceDate: floor(self.timeIntervalSinceReferenceDate / interval) * interval)
    }

    func dateCeiledToTimeInterval(interval: NSTimeInterval) -> NSDate {
        if interval == 0 {
            return self.copy() as! NSDate
        }

        return NSDate(timeIntervalSinceReferenceDate: ceil(self.timeIntervalSinceReferenceDate / interval) * interval)
    }
}

extension NSDate: Comparable { }

public func <(lhs: NSDate, rhs: NSDate) -> Bool {
    return lhs.compare(rhs) == .OrderedAscending
}
