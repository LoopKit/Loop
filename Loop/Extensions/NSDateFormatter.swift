//
//  NSDateFormatter.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 11/25/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

import Foundation


extension DateFormatter {
    static func ISO8601StrictDateFormatter() -> Self {
        let dateFormatter = self.init()

        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")

        return dateFormatter
    }
}
