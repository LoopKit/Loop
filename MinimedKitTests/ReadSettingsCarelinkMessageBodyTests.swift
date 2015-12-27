//
//  ReadSettingsCarelinkMessageBodyTests.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 12/26/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

import XCTest
@testable import MinimedKit

class ReadSettingsCarelinkMessageBodyTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func testValidSettings() {
        let message = PumpMessage(rxData: NSData(hexadecimalString: "a7594040c01900010001010096008c00000000000064010400140019010101000000000000000000000000000000000000000000000000000000000000000000000000000000e9")!)

        if let message = message {
            XCTAssertTrue(message.messageBody is ReadSettingsCarelinkMessageBody)

            if let body = message.messageBody as? ReadSettingsCarelinkMessageBody {
                XCTAssertEqual(3.5, body.maxBasal)
                XCTAssertEqual(15, body.maxBolus)
                XCTAssertEqual(BasalProfile.Standard, body.selectedBasalProfile)
                XCTAssertEqual(4, body.insulinActionCurveHours)
            }

        } else {
            XCTFail("Message is nil")
        }
    }

}
