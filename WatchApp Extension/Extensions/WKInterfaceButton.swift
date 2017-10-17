//
//  WKInterfaceButton.swift
//  WatchApp Extension
//
//  Created by Michael Pangburn on 10/16/17.
//  Copyright © 2017 LoopKit Authors. All rights reserved.
//

import WatchKit


extension WKInterfaceButton {
    func setTitleWithColor(title: String, color: UIColor) {
        let attributedString = NSMutableAttributedString(string: title)
        attributedString.setAttributes([NSAttributedStringKey.foregroundColor: color], range: NSMakeRange(0, attributedString.length))
        self.setAttributedTitle(attributedString)
    }
}
