//
//  ChangeTimeCarelinMessageBodyTests.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 3/17/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import XCTest
@testable import MinimedKit


class ChangeTimeCarelinMessageBodyTests: XCTestCase {
    
    func testChangeTime() {
        let components = NSDateComponents()
        components.calendar = NSCalendar(calendarIdentifier: NSCalendarIdentifierGregorian)

        components.year = 2017
        components.month = 12
        components.day = 29
        components.hour = 9
        components.minute = 22
        components.second = 59

        let message = PumpMessage(packetType: .Carelink, address: "123456", messageType: .ChangeTime, messageBody: ChangeTimeCarelinkMessageBody(dateComponents: components)!)

        XCTAssertEqual(NSData(hexadecimalString: "a7123456400709163B07E10C1D000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"), message.txData)
    }
    
}
