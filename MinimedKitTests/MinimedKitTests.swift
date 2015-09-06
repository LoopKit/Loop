//
//  MinimedKitTests.swift
//  MinimedKitTests
//
//  Created by Nathan Racklyeft on 9/2/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

import XCTest
@testable import MinimedKit

class MinimedKitTests: XCTestCase {
    
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

        XCTAssertNotNil(message)
    }
    
}
