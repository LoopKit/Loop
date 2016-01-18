//
//  NSDateFormatter.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 11/25/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

import Foundation


public extension NSDateFormatter {
    static func ISO8601StrictDateFormatter() -> Self {
        let dateFormatter = self.init()

        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        dateFormatter.locale = NSLocale(localeIdentifier: "en_US_POSIX")

        return dateFormatter
    }

    static func ISO8601LocalTimeDateFormatter() -> Self {
        let dateFormatter = self.init()

        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        dateFormatter.locale = NSLocale(localeIdentifier: "en_US_POSIX")

        return dateFormatter
    }

    static func localTimeFormatter() -> Self {
        let timeFormatter = self.init()

        timeFormatter.dateFormat = "HH:mm:ss"
        timeFormatter.locale = NSLocale(localeIdentifier: "en_US_POSIX")

        return timeFormatter
    }
}