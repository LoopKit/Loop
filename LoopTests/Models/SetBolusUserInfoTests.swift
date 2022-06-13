//
//  SetBolusUserInfoTests.swift
//  LoopTests
//
//  Created by Darin Krauss on 10/6/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import XCTest
import HealthKit
import LoopKit
@testable import Loop

class SetBolusUserInfoTests: XCTestCase {
    private var value = 4.56
    private var startDate = dateFormatter.date(from: "2020-05-14T22:45:00Z")!
    private var contextDate = dateFormatter.date(from: "2020-05-14T22:38:14Z")!
    private var carbEntry = NewCarbEntry(date: dateFormatter.date(from: "2020-05-14T22:39:34Z")!,
                                         quantity: HKQuantity(unit: .gram(), doubleValue: 17),
                                         startDate: dateFormatter.date(from: "2020-05-14T22:00:00Z")!,
                                         foodType: "Pizza",
                                         absorptionTime: .hours(5))
    private var activationType = BolusActivationType.manualRecommendationAccepted

    private lazy var rawValue: SetBolusUserInfo.RawValue = {
        return [
            "v": 1,
            "name": "SetBolusUserInfo",
            "bv": value,
            "sd": startDate,
            "cd": contextDate,
            "ce": carbEntry.rawValue,
            "at": activationType.rawValue,
        ]
    }()

    func testDefaultInitializer() {
        let info = SetBolusUserInfo(value: value, startDate: startDate, contextDate: contextDate, carbEntry: carbEntry, activationType: activationType)
        XCTAssertEqual(info.value, value)
        XCTAssertEqual(info.startDate, startDate)
        XCTAssertEqual(info.contextDate, contextDate)
        XCTAssertEqual(info.carbEntry, carbEntry)
        XCTAssertEqual(info.activationType, activationType)
    }

    func testRawValueInitializer() {
        let info = SetBolusUserInfo(rawValue: rawValue)
        XCTAssertEqual(info?.value, value)
        XCTAssertEqual(info?.startDate, startDate)
        XCTAssertEqual(info?.contextDate, contextDate)
        XCTAssertEqual(info?.carbEntry, carbEntry)
    }

    func testRawValueInitializerMissingVersion() {
        var rawValue = self.rawValue
        rawValue["v"] = nil
        XCTAssertNil(SetBolusUserInfo(rawValue: rawValue))
    }

    func testRawValueInitializerInvalidVersion() {
        var rawValue = self.rawValue
        rawValue["v"] = 2
        XCTAssertNil(SetBolusUserInfo(rawValue: rawValue))
    }

    func testRawValueInitializerMissingName() {
        var rawValue = self.rawValue
        rawValue["name"] = nil
        XCTAssertNil(SetBolusUserInfo(rawValue: rawValue))
    }

    func testRawValueInitializerInvalidName() {
        var rawValue = self.rawValue
        rawValue["name"] = "Invalid"
        XCTAssertNil(SetBolusUserInfo(rawValue: rawValue))
    }

    func testRawValueInitializerMissingValue() {
        var rawValue = self.rawValue
        rawValue["bv"] = nil
        XCTAssertNil(SetBolusUserInfo(rawValue: rawValue))
    }

    func testRawValueInitializerMissingStartDate() {
        var rawValue = self.rawValue
        rawValue["sd"] = nil
        XCTAssertNil(SetBolusUserInfo(rawValue: rawValue))
    }

    func testRawValue() {
        let info = SetBolusUserInfo(value: value, startDate: startDate, contextDate: contextDate, carbEntry: carbEntry, activationType: activationType)
        let rawValue = info.rawValue
        XCTAssertEqual(rawValue.count, 7)
        XCTAssertEqual(rawValue["v"] as? Int, 1)
        XCTAssertEqual(rawValue["name"] as? String, "SetBolusUserInfo")
        XCTAssertEqual(rawValue["bv"] as? Double, value)
        XCTAssertEqual(rawValue["sd"] as? Date, startDate)
        XCTAssertEqual(rawValue["cd"] as? Date, contextDate)
        XCTAssertEqual(rawValue["at"] as? BolusActivationType.RawValue, activationType.rawValue)
        let carbEntryRawValue = rawValue["ce"] as? NewCarbEntry.RawValue
        XCTAssertEqual(carbEntryRawValue?["date"] as? Date, carbEntry.date)
        XCTAssertEqual(carbEntryRawValue?["grams"] as? Double, carbEntry.quantity.doubleValue(for: .gram()))
        XCTAssertEqual(carbEntryRawValue?["startDate"] as? Date, carbEntry.startDate)
        XCTAssertEqual(carbEntryRawValue?["foodType"] as? String, carbEntry.foodType)
        XCTAssertEqual(carbEntryRawValue?["absorptionTime"] as? TimeInterval, carbEntry.absorptionTime)
    }

    private static let dateFormatter = ISO8601DateFormatter()
}
