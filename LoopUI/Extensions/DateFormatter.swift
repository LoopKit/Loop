//
//  DateFormatter.swift
//  LoopUI
//
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import Foundation

extension DateFormatter {
    convenience init(dateStyle: Style = .none, timeStyle: Style = .none) {
        self.init()
        self.dateStyle = dateStyle
        self.timeStyle = timeStyle
    }
}
