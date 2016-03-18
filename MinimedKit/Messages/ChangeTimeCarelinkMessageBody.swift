//
//  ChangeTimeCarelinkMessageBody.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 3/17/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation


public class ChangeTimeCarelinkMessageBody: CarelinkLongMessageBody {

    public convenience init?(dateComponents: NSDateComponents) {

        guard dateComponents.isValidDateInCalendar(NSCalendar(calendarIdentifier: NSCalendarIdentifierGregorian)!) else {
            return nil
        }

        let length = 7
        let data = NSData(hexadecimalString: String(format: "%02x%02x%02x%02x%04x%02x%02x", length, dateComponents.hour, dateComponents.minute, dateComponents.second, dateComponents.year, dateComponents.month, dateComponents.day))!

        self.init(rxData: data)
    }

}