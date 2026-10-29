//
//  AnalyticsServicesManagerTests.swift
//  LoopTests
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import XCTest
import LoopCore
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
        XCTAssertEqual(usage.foreground.count, 4)
        XCTAssertEqual(usage.foreground.duration, 769)
        XCTAssertEqual(usage.foreground.maxDuration, 600)
        XCTAssertEqual(usage.touchCount, 106)
        XCTAssertEqual(usage.foreground.under10sCount, 1)
        XCTAssertEqual(usage.foreground.from10To60sCount, 1)
        XCTAssertEqual(usage.foreground.from1To5MinCount, 1)
        XCTAssertEqual(usage.foreground.over5MinCount, 1)
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
        XCTAssertEqual(usage.foreground.count, 1)
        XCTAssertEqual(usage.foreground.duration, 30)
        XCTAssertEqual(usage.touchCount, 3)
        XCTAssertEqual(usage.foreground.from10To60sCount, 1)
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

    func testWatchActionsAreCounted() throws {
        let manager = AnalyticsServicesManager()
        manager.didRequestWatchContext()
        manager.didRequestWatchContext()
        manager.didAcknowledgeAlertOnWatch()
        manager.didStartPresetOnWatch()

        let summary = try XCTUnwrap(UserDefaults.standard.analyticsDailySummary)
        XCTAssertEqual(summary.properties["watchContextRequestCount"] as? Int, 2)
        XCTAssertEqual(summary.properties["watchAlertAcknowledgementCount"] as? Int, 1)
        XCTAssertEqual(summary.properties["watchPresetCount"] as? Int, 1)
    }
}

@MainActor
final class WatchUsageRecorderTests: XCTestCase {

    private var defaults: UserDefaults!
    private var sent: [WatchUsageSummary] = []
    private var canSend = true

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "WatchUsageRecorderTests")
        defaults.removePersistentDomain(forName: "WatchUsageRecorderTests")
        sent = []
        canSend = true
    }

    private func makeRecorder() -> WatchUsageRecorder {
        WatchUsageRecorder(defaults: defaults) { [unowned self] summary in
            guard canSend else {
                return false
            }
            sent.append(summary)
            return true
        }
    }

    func testCompletedDayIsSentWhenTheNextDayStarts() throws {
        let recorder = makeRecorder()
        let today = Calendar.current.startOfDay(for: Date())
        let yesterdayNoon = Calendar.current.date(byAdding: .hour, value: -12, to: today)!

        recorder.didBecomeActive(at: yesterdayNoon)
        recorder.willResignActive(at: yesterdayNoon.addingTimeInterval(8))
        XCTAssertTrue(sent.isEmpty)

        recorder.didBecomeActive(at: today.addingTimeInterval(3600))
        recorder.didDisplayScreen("chart")

        let summary = try XCTUnwrap(sent.first)
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(summary.day, Calendar.current.startOfDay(for: yesterdayNoon))
        XCTAssertEqual(summary.foreground.count, 1)
        XCTAssertEqual(summary.foreground.under10sCount, 1)
        XCTAssertEqual(recorder.currentSummary?.day, today)
        XCTAssertEqual(recorder.currentSummary?.screenCounts, ["chart": 1])
        XCTAssertTrue(recorder.pendingSummaries.isEmpty)
    }

    func testUnsentDaysAreKeptUntilTheSessionIsAvailable() {
        canSend = false
        let recorder = makeRecorder()
        let today = Calendar.current.startOfDay(for: Date())
        let twoDaysAgo = Calendar.current.date(byAdding: .day, value: -2, to: today)!.addingTimeInterval(3600)
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!.addingTimeInterval(3600)

        recorder.didBecomeActive(at: twoDaysAgo)
        recorder.didBecomeActive(at: yesterday)
        recorder.didBecomeActive(at: today.addingTimeInterval(3600))
        XCTAssertEqual(recorder.pendingSummaries.count, 2)

        canSend = true
        recorder.sendCompletedDays()
        XCTAssertEqual(sent.map(\.day), [Calendar.current.startOfDay(for: twoDaysAgo), Calendar.current.startOfDay(for: yesterday)])
        XCTAssertTrue(recorder.pendingSummaries.isEmpty)
    }

    func testUserInfoRoundTrips() throws {
        var summary = WatchUsageSummary(day: Calendar.current.startOfDay(for: Date()))
        summary.foreground.add(duration: 75)
        summary.complicationLaunchCount = 3
        summary.screenCounts = ["bolus": 2]

        let decoded = try XCTUnwrap(WatchUsageSummaryUserInfo(rawValue: WatchUsageSummaryUserInfo(summary: summary).rawValue))
        XCTAssertEqual(decoded.summary, summary)
        XCTAssertEqual(summary.properties["watchForeground1To5MinCount"] as? Int, 1)
        XCTAssertEqual(summary.properties["maxWatchForegroundSeconds"] as? Int, 75)
    }
}
