//
//  NSDateFormatter.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 3/25/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation


extension NSDateFormatter {
    static func ISO8601StrictDateFormatter() -> Self {
        let dateFormatter = self.init()

        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSZ"
        dateFormatter.locale = NSLocale(localeIdentifier: "en_US_POSIX")

        return dateFormatter
    }
}
