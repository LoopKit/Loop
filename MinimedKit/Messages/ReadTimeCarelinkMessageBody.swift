//
//  ReadTimeCarelinkMessageBody.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 3/17/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation


public class ReadTimeCarelinkMessageBody: CarelinkLongMessageBody {

    public let dateComponents = NSDateComponents()

    public required init?(rxData: NSData) {
        guard rxData.length == self.dynamicType.length else {
            super.init(rxData: rxData)
            return nil
        }

        dateComponents.calendar = NSCalendar(calendarIdentifier: NSCalendarIdentifierGregorian)
        dateComponents.hour   = Int(rxData[1] as UInt8)
        dateComponents.minute = Int(rxData[2] as UInt8)
        dateComponents.second = Int(rxData[3] as UInt8)
        dateComponents.year   = Int(bigEndianBytes: rxData[4...5])
        dateComponents.month  = Int(rxData[6] as UInt8)
        dateComponents.day    = Int(rxData[7] as UInt8)

        super.init(rxData: rxData)
    }

}