//
//  ReadTimeCarelinkMessageBodyTests.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 3/17/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import XCTest
@testable import MinimedKit

class ReadTimeCarelinkMessageBodyTests: XCTestCase {
    
    func testReadTime() {
        let message = PumpMessage(rxData: NSData(hexadecimalString: "a71234567007161B2007E00311000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000ff")!)!

        let body = message.messageBody as! ReadTimeCarelinkMessageBody

        let components = NSDateComponents()
        components.calendar = NSCalendar(calendarIdentifier: NSCalendarIdentifierGregorian)
        components.year = 2016
        components.month = 03
        components.day = 17
        components.hour = 22
        components.minute = 27
        components.second = 32

        XCTAssertEqual(components, body.dateComponents)
    }
    
}
