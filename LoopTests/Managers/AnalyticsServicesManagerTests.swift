//
//  AnalyticsServicesManagerTests.swift
//  LoopTests
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import XCTest
@testable import Loop

@MainActor
final class AnalyticsServicesManagerTests: XCTestCase {

    override func setUp() {
        super.setUp()
        UserDefaults.standard.analyticsDailySummary = nil
    }

    override func tearDown() {
        UserDefaults.standard.analyticsDailySummary = nil
        super.tearDown()
    }

    func testForegroundSessionsAreBucketedByLength() {
        var summary = AnalyticsDailySummary(day: Date())
        summary.addForegroundSession(duration: 4, touchCount: 0)
        summary.addForegroundSession(duration: 45, touchCount: 6)
        summary.addForegroundSession(duration: 120, touchCount: 20)
        summary.addForegroundSession(duration: 600, touchCount: 80)

        let usage = summary.usage
        XCTAssertEqual(usage.foregroundCount, 4)
        XCTAssertEqual(usage.foregroundDuration, 769)
        XCTAssertEqual(usage.maxForegroundDuration, 600)
        XCTAssertEqual(usage.touchCount, 106)
        XCTAssertEqual(usage.foregroundUnder10sCount, 1)
        XCTAssertEqual(usage.foreground10To60sCount, 1)
        XCTAssertEqual(usage.foreground1To5MinCount, 1)
        XCTAssertEqual(usage.foregroundOver5MinCount, 1)
        XCTAssertEqual(summary.properties["foregroundSeconds"] as? Int, 769)
        XCTAssertEqual(summary.properties["touchCount"] as? Int, 106)
    }

    func testSummaryStoredBeforeUsageCountsStillDecodes() throws {
        let day = Calendar.current.startOfDay(for: Date())
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(AnalyticsDailySummary(day: day))) as? [String: Any])
        legacy["loopSuccessCount"] = 12
        legacy.removeValue(forKey: "storedUsage")
        let data = try JSONSerialization.data(withJSONObject: legacy)

        let summary = try JSONDecoder().decode(AnalyticsDailySummary.self, from: data)
        XCTAssertEqual(summary.loopSuccessCount, 12)
        XCTAssertEqual(summary.usage, AnalyticsUsage())
    }

    func testForegroundSessionRecordsDurationAndTouches() throws {
        let manager = AnalyticsServicesManager()
        let end = Date()
        manager.didEnterForeground(at: end.addingTimeInterval(-30))
        manager.didReceiveTouch()
        manager.didReceiveTouch()
        manager.didReceiveTouch()
        manager.didEnterBackground(at: end)

        let usage = try XCTUnwrap(UserDefaults.standard.analyticsDailySummary).usage
        XCTAssertEqual(usage.foregroundCount, 1)
        XCTAssertEqual(usage.foregroundDuration, 30)
        XCTAssertEqual(usage.touchCount, 3)
        XCTAssertEqual(usage.foreground10To60sCount, 1)
    }

    func testBackgroundWithoutForegroundIsIgnored() {
        let manager = AnalyticsServicesManager()
        manager.didEnterBackground()
        XCTAssertNil(UserDefaults.standard.analyticsDailySummary)
    }

    func testActionsAreCountedBySource() throws {
        let manager = AnalyticsServicesManager()
        manager.didBolus(source: "Phone")
        manager.didBolus(source: "Watch")
        manager.didBolus(source: "Phone")
        manager.didAddCarbs(source: "Phone")
        manager.didDisplayBolusScreen()
        manager.didOpenFromNotification()
        manager.didAcknowledgeAlert()

        let summary = try XCTUnwrap(UserDefaults.standard.analyticsDailySummary)
        XCTAssertEqual(summary.usage.bolusCounts, ["Phone": 2, "Watch": 1])
        XCTAssertEqual(summary.usage.carbEntryCounts, ["Phone": 1])
        XCTAssertEqual(summary.usage.screenCounts, ["bolus": 1])
        XCTAssertEqual(summary.usage.notificationOpenCount, 1)
        XCTAssertEqual(summary.usage.alertAcknowledgementCount, 1)
        XCTAssertEqual(summary.properties["bolusCount"] as? Int, 3)
    }
}
