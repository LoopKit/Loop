//
//  MySentryPumpStatusMessageBodyTests.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 9/6/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

import XCTest
@testable import MinimedKit

class MySentryPumpStatusMessageBodyTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }

    func testValidPumpStatusMessage() {
        let message = PumpMessage(rxData: NSData(hexadecimalString: "a2594040042f511727070f09050184850000cd010105b03e0a0a1a009d030000711726000f09050000d0")!)

        if let message = message {
            XCTAssertTrue(message.messageBody is MySentryPumpStatusMessageBody)
        } else {
            XCTFail("\(message) is nil")
        }
    }

    func testGlucoseTrendFlat() {
        XCTAssertEqual(GlucoseTrend.Flat, GlucoseTrend(byte: 0b00000000))
        XCTAssertEqual(GlucoseTrend.Flat, GlucoseTrend(byte: 0b11110001))
        XCTAssertEqual(GlucoseTrend.Flat, GlucoseTrend(byte: 0b11110001))
        XCTAssertEqual(GlucoseTrend.Flat, GlucoseTrend(byte: 0b000))
        XCTAssertEqual(GlucoseTrend.Flat, GlucoseTrend(byte: 0x51))
    }

    func testMidnightSensor() {
        let message = PumpMessage(rxData: NSData(hexadecimalString: "a2594040049c510003310f090501393700025b0101068d262208150034000000700003000f0905000067")!)!

        let body = message.messageBody as! MySentryPumpStatusMessageBody

        switch body.glucose {
        case .Active(glucose: let glucose):
            XCTAssertEqual(114, glucose)
        default:
            XCTFail("\(body.glucose) is not .Active")
        }

        switch body.previousGlucose {
        case .Active(glucose: let glucose):
            XCTAssertEqual(110, glucose)
        default:
            XCTFail("\(body.previousGlucose) is not .Active")
        }

        let dateComponents = NSDateComponents()
        dateComponents.calendar = NSCalendar(calendarIdentifier: NSCalendarIdentifierGregorian)
        dateComponents.year = 2015
        dateComponents.month = 9
        dateComponents.day = 5
        dateComponents.hour = 0
        dateComponents.minute = 3
        dateComponents.second = 49

        XCTAssertEqual(dateComponents, body.pumpDateComponents)

        dateComponents.second = 0

        XCTAssertEqual(dateComponents, body.glucoseDateComponents)

        XCTAssertEqual(GlucoseTrend.Flat, body.glucoseTrend)
    }

    func testActiveSensor() {
        let message = PumpMessage(rxData: NSData(hexadecimalString: "a2594040042f511727070f09050184850000cd010105b03e0a0a1a009d030000711726000f09050000d0")!)!

        let body = message.messageBody as! MySentryPumpStatusMessageBody

        switch body.glucose {
        case .Active(glucose: let glucose):
            XCTAssertEqual(265, glucose)
        default:
            XCTFail("\(body.glucose) is not .Active")
        }

        switch body.previousGlucose {
        case .Active(glucose: let glucose):
            XCTAssertEqual(267, glucose)
        default:
            XCTFail("\(body.previousGlucose) is not .Active")
        }

        let dateComponents = NSDateComponents()
        dateComponents.calendar = NSCalendar(calendarIdentifier: NSCalendarIdentifierGregorian)
        dateComponents.year = 2015
        dateComponents.month = 9
        dateComponents.day = 5
        dateComponents.hour = 23
        dateComponents.minute = 39
        dateComponents.second = 7

        XCTAssertEqual(dateComponents, body.pumpDateComponents)

        dateComponents.minute = 38
        dateComponents.second = 0

        XCTAssertEqual(dateComponents, body.glucoseDateComponents)

        XCTAssertEqual(GlucoseTrend.Flat, body.glucoseTrend)
    }

    func testSensorEndEmptyReservoir() {
        let message = PumpMessage(rxData: NSData(hexadecimalString: "a259404004fb511205000f090601050502000004000000ff00ffff0040000000711205000f090600002b")!)!

        let body = message.messageBody as! MySentryPumpStatusMessageBody

        switch body.glucose {
        case .Ended:
            break
        default:
            XCTFail("\(body.glucose) is not .Ended")
        }

        switch body.previousGlucose {
        case .Ended:
            break
        default:
            XCTFail("\(body.previousGlucose) is not .Ended")
        }

        let dateComponents = NSDateComponents()
        dateComponents.calendar = NSCalendar(calendarIdentifier: NSCalendarIdentifierGregorian)
        dateComponents.year = 2015
        dateComponents.month = 9
        dateComponents.day = 6
        dateComponents.hour = 18
        dateComponents.minute = 5
        dateComponents.second = 0

        XCTAssertEqual(dateComponents, body.pumpDateComponents)
        XCTAssertEqual(dateComponents, body.glucoseDateComponents)

        XCTAssertEqual(GlucoseTrend.Flat, body.glucoseTrend)
    }

    func testSensorOffEmptyReservoir() {
        let message = PumpMessage(rxData: NSData(hexadecimalString: "a259404004ff501219000f09060100000000000400000000000000005e0000007200000000000000008b")!)!

        let body = message.messageBody as! MySentryPumpStatusMessageBody

        switch body.glucose {
        case .Off:
            break
        default:
            XCTFail("\(body.glucose) is not .Off")
        }

        switch body.previousGlucose {
        case .Off:
            break
        default:
            XCTFail("\(body.previousGlucose) is not .Off")
        }

        let dateComponents = NSDateComponents()
        dateComponents.calendar = NSCalendar(calendarIdentifier: NSCalendarIdentifierGregorian)
        dateComponents.year = 2015
        dateComponents.month = 9
        dateComponents.day = 6
        dateComponents.hour = 18
        dateComponents.minute = 25
        dateComponents.second = 0

        XCTAssertEqual(dateComponents, body.pumpDateComponents)
        XCTAssertNil(body.glucoseDateComponents)

        XCTAssertEqual(GlucoseTrend.Flat, body.glucoseTrend)
    }

    func testSensorOffEmptyReservoirSuspended() {
        let message = PumpMessage(rxData: NSData(hexadecimalString: "a25940400401501223000f0906010000000000040000000000000000590000007200000000000000009f")!)!

        let body = message.messageBody as! MySentryPumpStatusMessageBody

        switch body.glucose {
        case .Off:
            break
        default:
            XCTFail("\(body.glucose) is not .Off")
        }

        switch body.previousGlucose {
        case .Off:
            break
        default:
            XCTFail("\(body.previousGlucose) is not .Off")
        }

        let dateComponents = NSDateComponents()
        dateComponents.calendar = NSCalendar(calendarIdentifier: NSCalendarIdentifierGregorian)
        dateComponents.year = 2015
        dateComponents.month = 9
        dateComponents.day = 6
        dateComponents.hour = 18
        dateComponents.minute = 35
        dateComponents.second = 0

        XCTAssertEqual(dateComponents, body.pumpDateComponents)
        XCTAssertNil(body.glucoseDateComponents)

        XCTAssertEqual(GlucoseTrend.Flat, body.glucoseTrend)
    }

}
