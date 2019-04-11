//
//  DateIntervalFormatter.swift
//  Learn
//
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import Foundation


extension DateIntervalFormatter {
    convenience init(dateStyle: DateIntervalFormatter.Style, timeStyle: DateIntervalFormatter.Style) {
        self.init()
        self.dateStyle = dateStyle
        self.timeStyle = timeStyle
    }
}
