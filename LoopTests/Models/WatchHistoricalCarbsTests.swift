//
//  WatchHistoricalCarbs.swift
//  LoopTests
//
//  Created by Darin Krauss on 8/21/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import XCTest
import LoopKit

@testable import Loop

class WatchHistoricalCarbsTests: XCTestCase {
    private lazy var objects: [SyncCarbObject] = {
        return [SyncCarbObject(absorptionTime: .hours(5),
                               createdByCurrentApp: true,
                               foodType: "Pizza",
                               grams: 45,
                               startDate: Date(timeIntervalSinceReferenceDate: .hours(100)),
                               uuid: UUID(),
                               provenanceIdentifier: "com.loopkit.Loop",
                               syncIdentifier: UUID().uuidString,
                               syncVersion: 4,
                               userCreatedDate: Date(timeIntervalSinceReferenceDate: .hours(98)),
                               userUpdatedDate: Date(timeIntervalSinceReferenceDate: .hours(99)),
                               userDeletedDate: nil,
                               operation: .update,
                               addedDate: Date(timeIntervalSinceReferenceDate: .hours(97)),
                               supercededDate: nil),
                SyncCarbObject(absorptionTime: .hours(3),
                               createdByCurrentApp: false,
                               foodType: "Pasta",
                               grams: 25,
                               startDate: Date(timeIntervalSinceReferenceDate: .hours(110)),
                               uuid: UUID(),
                               provenanceIdentifier: "com.abc.Example",
                               syncIdentifier: UUID().uuidString,
                               syncVersion: 1,
                               userCreatedDate: Date(timeIntervalSinceReferenceDate: .hours(108)),
                               userUpdatedDate: nil,
                               userDeletedDate: nil,
                               operation: .create,
                               addedDate: Date(timeIntervalSinceReferenceDate: .hours(107)),
                               supercededDate: nil),
                SyncCarbObject(absorptionTime: .minutes(30),
                               createdByCurrentApp: true,
                               foodType: "Sugar",
                               grams: 15,
                               startDate: Date(timeIntervalSinceReferenceDate: .hours(120)),
                               uuid: UUID(),
                               provenanceIdentifier: "com.loopkit.Loop",
                               syncIdentifier: UUID().uuidString,
                               syncVersion: 1,
                               userCreatedDate: Date(timeIntervalSinceReferenceDate: .hours(118)),
                               userUpdatedDate: nil,
                               userDeletedDate: nil,
                               operation: .create,
                               addedDate: Date(timeIntervalSinceReferenceDate: .hours(117)),
                               supercededDate: nil)
        ]
    }()
    private lazy var objectsEncoded: Data = {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return try! encoder.encode(self.objects)
    }()
    private lazy var rawValue: WatchHistoricalCarbs.RawValue = {
        return [
            "o": objectsEncoded
        ]
    }()

    func testDefaultInitializer() {
        let carbs = WatchHistoricalCarbs(objects: self.objects)
        XCTAssertEqual(carbs.objects, self.objects)
    }

    func testRawValueInitializer() {
        let carbs = WatchHistoricalCarbs(rawValue: self.rawValue)
        XCTAssertEqual(carbs?.objects, self.objects)
    }

    func testRawValueInitializerMissingObjects() {
        var rawValue = self.rawValue
        rawValue["o"] = nil
        XCTAssertNil(WatchHistoricalCarbs(rawValue: rawValue))
    }

    func testRawValueInitializerInvalidObjects() {
        var rawValue = self.rawValue
        rawValue["o"] = Data()
        XCTAssertNil(WatchHistoricalCarbs(rawValue: rawValue))
    }

    func testRawValue() {
        let rawValue = WatchHistoricalCarbs(objects: self.objects).rawValue
        XCTAssertEqual(rawValue.count, 1)
        XCTAssertEqual(rawValue["o"] as? Data, self.objectsEncoded)
    }
}
