//
//  CarbBackfillRequestUserInfoTests.swift
//  LoopTests
//
//  Created by Darin Krauss on 8/21/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import XCTest

@testable import Loop

class CarbBackfillRequestUserInfoTests: XCTestCase {
    private lazy var startDate: Date = { Date(timeIntervalSinceReferenceDate: 0) }()
    private lazy var rawValue: CarbBackfillRequestUserInfo.RawValue = {
        return [
            "v": 1,
            "name": "CarbBackfillRequestUserInfo",
            "sd": startDate,
        ]
    }()

    func testDefaultInitializer() {
        let info = CarbBackfillRequestUserInfo(startDate: self.startDate)
        XCTAssertEqual(info.version, 1)
        XCTAssertEqual(info.startDate, self.startDate)
    }

    func testRawValueInitializer() {
        let info = CarbBackfillRequestUserInfo(rawValue: self.rawValue)
        XCTAssertEqual(info?.version, 1)
        XCTAssertEqual(info?.startDate, self.startDate)
    }

    func testRawValueInitializerMissingVersion() {
        var rawValue = self.rawValue
        rawValue["v"] = nil
        XCTAssertNil(CarbBackfillRequestUserInfo(rawValue: rawValue))
    }

    func testRawValueInitializerInvalidVersion() {
        var rawValue = self.rawValue
        rawValue["v"] = 2
        XCTAssertNil(CarbBackfillRequestUserInfo(rawValue: rawValue))
    }

    func testRawValueInitializerMissingName() {
        var rawValue = self.rawValue
        rawValue["name"] = nil
        XCTAssertNil(CarbBackfillRequestUserInfo(rawValue: rawValue))
    }

    func testRawValueInitializerInvalidName() {
        var rawValue = self.rawValue
        rawValue["name"] = "Invalid"
        XCTAssertNil(CarbBackfillRequestUserInfo(rawValue: rawValue))
    }

    func testRawValueInitializerMissingStartDate() {
        var rawValue = self.rawValue
        rawValue["sd"] = nil
        XCTAssertNil(CarbBackfillRequestUserInfo(rawValue: rawValue))
    }

    func testRawValue() {
        let rawValue = CarbBackfillRequestUserInfo(startDate: self.startDate).rawValue
        XCTAssertEqual(rawValue.count, 3)
        XCTAssertEqual(rawValue["v"] as? Int, 1)
        XCTAssertEqual(rawValue["name"] as? String, "CarbBackfillRequestUserInfo")
        XCTAssertEqual(rawValue["sd"] as? Date, self.startDate)
    }
}
