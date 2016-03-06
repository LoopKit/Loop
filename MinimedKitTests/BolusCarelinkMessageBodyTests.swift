//
//  BolusCarelinkMessageBodyTests.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 3/5/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation
import XCTest
@testable import MinimedKit


class BolusCarelinkMessageBodyTests: XCTestCase {

    func testBolusMessageBody() {
        let message = PumpMessage(packetType: .Carelink, address: "123456", messageType: .Bolus, messageBody: BolusCarelinkMessageBody(units: 1.1, strokesPerUnit: 40))

        XCTAssertEqual(
            NSData(hexadecimalString: "a71234564202002C0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
            message.txData
        )
    }

    func testBolusMessageBody522() {
        let message = PumpMessage(packetType: .Carelink, address: "123456", messageType: .Bolus, messageBody: BolusCarelinkMessageBody(units: 1.1, strokesPerUnit: 10))

        XCTAssertEqual(
            NSData(hexadecimalString: "a712345642010B000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
            message.txData
        )
    }

    func testBolusMessageBodyRounding() {
        let message = PumpMessage(packetType: .Carelink, address: "123456", messageType: .Bolus, messageBody: BolusCarelinkMessageBody(units: 1.475, strokesPerUnit: 40))

        XCTAssertEqual(
            NSData(hexadecimalString: "a71234564202003A0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
            message.txData
        )
    }

    func testBolusMessageBodyTwoByte() {
        let message = PumpMessage(packetType: .Carelink, address: "123456", messageType: .Bolus, messageBody: BolusCarelinkMessageBody(units: 7.9, strokesPerUnit: 40))

        XCTAssertEqual(
            NSData(hexadecimalString: "a71234564202013C0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
            message.txData
        )
    }
}