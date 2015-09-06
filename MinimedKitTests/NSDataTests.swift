//
//  NSDataTests.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 9/5/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

import XCTest
@testable import MinimedKit

class NSDataTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }

    func testInitWithHexadecimalStringEmpty() {
        let data = NSData(hexadecimalString: "")
        XCTAssertEqual(0, data!.length)
    }

    func testInitWithHexadecimalStringOdd() {
        let data = NSData(hexadecimalString: "a")
        XCTAssertNil(data)
    }

    func testInitWithHexadecimalStringZeros() {
        let data = NSData(hexadecimalString: "00")
        XCTAssertEqual(1, data!.length)

        var bytes = [UInt8](count: 1, repeatedValue: 1)
        data?.getBytes(&bytes, length: 1)
        XCTAssertEqual(0, bytes[0])
    }

    func testInitWithHexadecimalStringShortData() {
        let data = NSData(hexadecimalString: "a2594040")

        XCTAssertEqual(4, data!.length)

        var bytes = [UInt8](count: 4, repeatedValue: 0)
        data?.getBytes(&bytes, length: 4)
        XCTAssertEqual([0xa2, 0x59, 0x40, 0x40], bytes)
    }
}
