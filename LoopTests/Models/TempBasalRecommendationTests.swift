//
//  TempBasalRecommendationTests.swift
//  LoopTests
//
//  Created by Pete Schwamb on 2/21/24.
//  Copyright © 2024 LoopKit Authors. All rights reserved.
//

import XCTest
import LoopAlgorithm
@testable import Loop

class TempBasalRecommendationTests: XCTestCase {

    func testCancel() {
        let cancel = TempBasalRecommendation.cancel
        XCTAssertEqual(cancel.unitsPerHour, 0)
        XCTAssertEqual(cancel.duration, 0)
    }

    func testInitializer() {
        let tempBasalRecommendation = TempBasalRecommendation(unitsPerHour: 1.23, duration: 4.56)
        XCTAssertEqual(tempBasalRecommendation.unitsPerHour, 1.23)
        XCTAssertEqual(tempBasalRecommendation.duration, 4.56)
    }
}
