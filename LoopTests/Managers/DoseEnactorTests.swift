//
//  DoseEnactorTests.swift
//  LoopTests
//
//  Created by Pete Schwamb on 7/30/21.
//  Copyright © 2021 LoopKit Authors. All rights reserved.
//

import XCTest
import Foundation
import LoopKit
import HealthKit
import LoopAlgorithm

@testable import Loop

enum MockPumpManagerError: Error {
    case failed
}

extension MockPumpManagerError: LocalizedError {
    
}


class DoseEnactorTests: XCTestCase {
    func testBasalAndBolusDosedSerially() async throws {
        let enactor = DoseEnactor()
        let tempBasalRecommendation = TempBasalRecommendation(unitsPerHour: 0, duration: 0) // Cancel
        let recommendation = AutomaticDoseRecommendation(basalAdjustment: tempBasalRecommendation, bolusUnits: 1.5)
        let pumpManager = MockPumpManager()
        
        let tempBasalExpectation = expectation(description: "enactTempBasal called")
        pumpManager.enactTempBasalCalled = { (rate, duration) in
            tempBasalExpectation.fulfill()
        }

        let bolusExpectation = expectation(description: "enactBolus called")
        pumpManager.enactBolusCalled = { (amount, automatic) in
            bolusExpectation.fulfill()
        }

        try await enactor.enact(recommendation: recommendation, with: pumpManager)

        await fulfillment(of: [tempBasalExpectation, bolusExpectation], timeout: 5, enforceOrder: true)
    }
    
    func testBolusDoesNotIssueIfTempBasalAdjustmentFailed() async throws {
        let enactor = DoseEnactor()
        let tempBasalRecommendation = TempBasalRecommendation(unitsPerHour: 0, duration: 0) // Cancel
        let recommendation = AutomaticDoseRecommendation(basalAdjustment: tempBasalRecommendation, bolusUnits: 1.5)
        let pumpManager = MockPumpManager()
        
        let tempBasalExpectation = expectation(description: "enactTempBasal called")
        pumpManager.enactTempBasalCalled = { (rate, duration) in
            tempBasalExpectation.fulfill()
        }

        pumpManager.enactBolusCalled = { (amount, automatic) in
            XCTFail("Should not enact bolus")
        }
        
        pumpManager.enactTempBasalError = .configuration(MockPumpManagerError.failed)

        do {
            try await enactor.enact(recommendation: recommendation, with: pumpManager)
            XCTFail("Expected enact to throw error on failure.")
        } catch {
        }

        await fulfillment(of: [tempBasalExpectation])
    }
    
    func testTempBasalOnly() async throws {
        let enactor = DoseEnactor()
        let tempBasalRecommendation = TempBasalRecommendation(unitsPerHour: 1.2, duration: .minutes(30)) // Cancel
        let recommendation = AutomaticDoseRecommendation(basalAdjustment: tempBasalRecommendation, bolusUnits: 0)
        let pumpManager = MockPumpManager()
        
        let tempBasalExpectation = expectation(description: "enactTempBasal called")
        pumpManager.enactTempBasalCalled = { (rate, duration) in
            XCTAssertEqual(1.2, rate)
            XCTAssertEqual(.minutes(30), duration)
            tempBasalExpectation.fulfill()
        }

        pumpManager.enactBolusCalled = { (amount, automatic) in
            XCTFail("Should not enact bolus")
        }

        try await enactor.enact(recommendation: recommendation, with: pumpManager)

        await fulfillment(of: [tempBasalExpectation])
    }


}
