//
//  DateIntervalFormatter.swift
//  Learn
//
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import Foundation


extension DateIntervalFormatter {
    convenience init(dateStyle: DateIntervalFormatter.Style = .none, timeStyle: DateIntervalFormatter.Style = .none) {
        self.init()
        self.dateStyle = dateStyle
        self.timeStyle = timeStyle
    }
}
