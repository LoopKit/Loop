//
//  NSDateComponents.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 9/13/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

import Foundation


extension NSDateComponents {
    convenience init(mySentryBytes: [UInt8]) {
        self.init()

        hour = Int(mySentryBytes[0])
        minute = Int(mySentryBytes[1])
        second = Int(mySentryBytes[2])
        year = Int(mySentryBytes[3]) + 2000
        month = Int(mySentryBytes[4])
        day = Int(mySentryBytes[5])

        calendar = NSCalendar(calendarIdentifier: NSCalendarIdentifierGregorian)
    }
}