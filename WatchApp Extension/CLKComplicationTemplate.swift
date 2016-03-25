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

    convenience init?(context: WatchContext) {
        guard let value = context.glucoseValue, date = context.glucoseDate else {
            return nil
        }

        self.init()

        line1TextProvider = CLKSimpleTextProvider(text: "\(value)")
        line2TextProvider = CLKTimeTextProvider(date: date)
    }

}