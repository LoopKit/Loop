//
//  CLKComplicationTemplate.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 11/26/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

import ClockKit
import Foundation


extension CLKComplicationTemplateModularSmallStackText {

    convenience init?(line1: String?, date: Date?) {
        guard let line1 = line1, let date = date else {
            return nil
        }

        self.init()

        line1TextProvider = CLKSimpleTextProvider(text: line1)
        line2TextProvider = CLKTimeTextProvider(date: date)
    }

}
