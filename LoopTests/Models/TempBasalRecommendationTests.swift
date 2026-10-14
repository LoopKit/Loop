//
//  TempBasalRecommendationTests.swift
//  LoopTests
//
//  Created by Pete Schwamb on 2/21/24.
//  Copyright © 2024 LoopKit Authors. All rights reserved.
//

import XCTest
import LoopKit
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

    // MARK: - adjustForCurrentDelivery

    private let now = Date(timeIntervalSinceReferenceDate: 700_000_000)
    private let continuationInterval: TimeInterval = .minutes(11)

    private func activeTemp(rate: Double, startedAgo: TimeInterval = .minutes(5), endingIn: TimeInterval) -> DoseEntry {
        DoseEntry(
            type: .tempBasal,
            startDate: now.addingTimeInterval(-startedAgo),
            endDate: now.addingTimeInterval(endingIn),
            value: rate,
            unit: .unitsPerHour,
            decisionId: nil
        )
    }

    // No current temp basal

    func testAdjustForCurrentDelivery_NoCurrentTemp_RecMatchesSchedule_PumpMatches_ReturnsNil() {
        let rec = TempBasalRecommendation(unitsPerHour: 1.0, duration: .minutes(30))
        let result = rec.adjustForCurrentDelivery(
            at: now,
            neutralBasalRate: 1.0,
            currentTempBasal: nil,
            continuationInterval: continuationInterval,
            neutralBasalRateMatchesPump: true
        )
        XCTAssertNil(result)
    }

    func testAdjustForCurrentDelivery_NoCurrentTemp_RecMatchesSchedule_OverrideActive_ReturnsSelf() {
        let rec = TempBasalRecommendation(unitsPerHour: 1.0, duration: .minutes(30))
        let result = rec.adjustForCurrentDelivery(
            at: now,
            neutralBasalRate: 1.0,
            currentTempBasal: nil,
            continuationInterval: continuationInterval,
            neutralBasalRateMatchesPump: false
        )
        XCTAssertEqual(result, rec)
    }

    func testAdjustForCurrentDelivery_NoCurrentTemp_RecDiffersFromSchedule_ReturnsSelf() {
        let rec = TempBasalRecommendation(unitsPerHour: 1.5, duration: .minutes(30))
        let result = rec.adjustForCurrentDelivery(
            at: now,
            neutralBasalRate: 1.0,
            currentTempBasal: nil,
            continuationInterval: continuationInterval,
            neutralBasalRateMatchesPump: true
        )
        XCTAssertEqual(result, rec)
    }

    // Current dose is not an active temp basal

    func testAdjustForCurrentDelivery_CurrentDoseIsScheduledBasal_TreatedAsNoTemp() {
        let scheduled = DoseEntry(
            type: .basal,
            startDate: now.addingTimeInterval(-.minutes(5)),
            endDate: now.addingTimeInterval(.minutes(25)),
            value: 1.0,
            unit: .unitsPerHour,
            decisionId: nil
        )
        let rec = TempBasalRecommendation(unitsPerHour: 1.0, duration: .minutes(30))
        let result = rec.adjustForCurrentDelivery(
            at: now,
            neutralBasalRate: 1.0,
            currentTempBasal: scheduled,
            continuationInterval: continuationInterval,
            neutralBasalRateMatchesPump: true
        )
        XCTAssertNil(result)
    }

    func testAdjustForCurrentDelivery_ExpiredTempBasal_TreatedAsNoTemp() {
        let expired = activeTemp(rate: 1.5, startedAgo: .minutes(30), endingIn: -.minutes(1))
        let rec = TempBasalRecommendation(unitsPerHour: 1.0, duration: .minutes(30))
        let result = rec.adjustForCurrentDelivery(
            at: now,
            neutralBasalRate: 1.0,
            currentTempBasal: expired,
            continuationInterval: continuationInterval,
            neutralBasalRateMatchesPump: true
        )
        XCTAssertNil(result)
    }

    // Active temp basal

    func testAdjustForCurrentDelivery_ActiveTemp_SameRate_PlentyOfTimeLeft_ReturnsNil() {
        let active = activeTemp(rate: 1.5, endingIn: .minutes(25))
        let rec = TempBasalRecommendation(unitsPerHour: 1.5, duration: .minutes(30))
        let result = rec.adjustForCurrentDelivery(
            at: now,
            neutralBasalRate: 1.0,
            currentTempBasal: active,
            continuationInterval: continuationInterval,
            neutralBasalRateMatchesPump: true
        )
        XCTAssertNil(result)
    }

    func testAdjustForCurrentDelivery_ActiveTemp_SameRate_NearingExpiry_RecMatchesScheduleAndPump_ReturnsCancel() {
        // Temp running at the schedule rate (unusual but possible), about to expire — should cancel.
        let active = activeTemp(rate: 1.0, endingIn: .minutes(5))
        let rec = TempBasalRecommendation(unitsPerHour: 1.0, duration: .minutes(30))
        let result = rec.adjustForCurrentDelivery(
            at: now,
            neutralBasalRate: 1.0,
            currentTempBasal: active,
            continuationInterval: continuationInterval,
            neutralBasalRateMatchesPump: true
        )
        XCTAssertEqual(result, .cancel)
    }

    func testAdjustForCurrentDelivery_ActiveTemp_SameRate_NearingExpiry_RecDiffersFromSchedule_ReturnsSelf() {
        let active = activeTemp(rate: 1.5, endingIn: .minutes(5))
        let rec = TempBasalRecommendation(unitsPerHour: 1.5, duration: .minutes(30))
        let result = rec.adjustForCurrentDelivery(
            at: now,
            neutralBasalRate: 1.0,
            currentTempBasal: active,
            continuationInterval: continuationInterval,
            neutralBasalRateMatchesPump: true
        )
        XCTAssertEqual(result, rec)
    }

    func testAdjustForCurrentDelivery_ActiveTemp_DifferentRate_RecMatchesScheduleAndPump_ReturnsCancel() {
        let active = activeTemp(rate: 1.5, endingIn: .minutes(25))
        let rec = TempBasalRecommendation(unitsPerHour: 1.0, duration: .minutes(30))
        let result = rec.adjustForCurrentDelivery(
            at: now,
            neutralBasalRate: 1.0,
            currentTempBasal: active,
            continuationInterval: continuationInterval,
            neutralBasalRateMatchesPump: true
        )
        XCTAssertEqual(result, .cancel)
    }

    func testAdjustForCurrentDelivery_ActiveTemp_DifferentRate_RecMatchesSchedule_OverrideActive_ReturnsSelf() {
        // Override changes the pump's schedule, so even though the rec equals neutralBasalRate,
        // we can't trust that the pump's scheduled basal will deliver that rate — set a new temp.
        let active = activeTemp(rate: 1.5, endingIn: .minutes(25))
        let rec = TempBasalRecommendation(unitsPerHour: 1.0, duration: .minutes(30))
        let result = rec.adjustForCurrentDelivery(
            at: now,
            neutralBasalRate: 1.0,
            currentTempBasal: active,
            continuationInterval: continuationInterval,
            neutralBasalRateMatchesPump: false
        )
        XCTAssertEqual(result, rec)
    }

    func testAdjustForCurrentDelivery_ActiveTemp_DifferentRate_RecDiffersFromSchedule_ReturnsSelf() {
        let active = activeTemp(rate: 1.5, endingIn: .minutes(25))
        let rec = TempBasalRecommendation(unitsPerHour: 0.5, duration: .minutes(30))
        let result = rec.adjustForCurrentDelivery(
            at: now,
            neutralBasalRate: 1.0,
            currentTempBasal: active,
            continuationInterval: continuationInterval,
            neutralBasalRateMatchesPump: true
        )
        XCTAssertEqual(result, rec)
    }

    func testAdjustForCurrentDelivery_ActiveTemp_RemainingTimeAtBoundary_DoesNotContinue() {
        // continuationInterval is exclusive: remaining == continuationInterval should not continue.
        let active = activeTemp(rate: 1.5, endingIn: continuationInterval)
        let rec = TempBasalRecommendation(unitsPerHour: 1.5, duration: .minutes(30))
        let result = rec.adjustForCurrentDelivery(
            at: now,
            neutralBasalRate: 1.0,
            currentTempBasal: active,
            continuationInterval: continuationInterval,
            neutralBasalRateMatchesPump: true
        )
        XCTAssertEqual(result, rec)
    }
}
