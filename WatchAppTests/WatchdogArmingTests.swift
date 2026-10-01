//
//  WatchdogArmingTests.swift
//  WatchAppTests
//
//  The three pre-scheduled dead-man alerts, tested for the first time. TEST_COVERAGE_PLAN.md
//  listed "pre-scheduled notification delivery" as field-only, which was true while every test
//  ran in an iOS host. This target runs in the watch extension itself, so ARMING is now
//  observable — delivery still is not, and still needs the wrist.
//
//  Why arming is worth testing at all: these alerts work by replacement. Each refresh() adds a
//  request under the SAME identifier, which watchOS treats as replacing the pending one, so a
//  loop that keeps completing perpetually defers its own alarm. If an identifier ever varied,
//  refresh would STACK requests instead of deferring, and the watchdog would fire during a
//  perfectly healthy loop. If two alerts ever shared an identifier, disarming one would
//  silently cancel the other. Neither failure is visible from reading the call sites, and both
//  produce a dead-man's switch that is wrong in the dangerous direction.
//

import XCTest
import UserNotifications
@testable import WatchApp

final class WatchdogArmingTests: XCTestCase {

    private var scheduler: RecordingWristAlertScheduler!

    override func setUp() {
        super.setUp()
        scheduler = RecordingWristAlertScheduler()
        WristAlerts.scheduler = scheduler
    }

    override func tearDown() {
        WristAlerts.scheduler = UNUserNotificationCenter.current()
        scheduler = nil
        super.tearDown()
    }

    /// The requests the alerts have asked for. Synchronous: the double records inline, so the
    /// polling the old suite needed against a separate daemon process is gone, and with it the
    /// class of failure where a premature read returned ONE request and looked like correct
    /// replacement.
    private func pending() -> [UNNotificationRequest] { scheduler.pending }
    private func settledPending(timeout: TimeInterval = 3) -> [UNNotificationRequest] { scheduler.pending }

    private func interval(of request: UNNotificationRequest) -> TimeInterval? {
        (request.trigger as? UNTimeIntervalNotificationTrigger)?.timeInterval
    }

    // MARK: - Arming

    func testLoopStallLadderArmsStockRungs() {
        LoopStallWatchdog.refresh()
        let reqs = pending()
        XCTAssertEqual(reqs.count, 4, "stock parity: 20/40m + 1/2h, one request per rung")
        let intervals: Set<TimeInterval> = Set(reqs.compactMap { interval(of: $0) })
        let expected: Set<TimeInterval> = [1200, 2400, 3600, 7200]
        XCTAssertEqual(intervals, expected, "the phone's exact ladder (ruling 2026-08-24)")
    }

    func testHandbackStuckArmsAtTwoMinutes() {
        HandbackStuckAlert.arm()
        let reqs = pending()
        XCTAssertEqual(reqs.count, 1)
        XCTAssertEqual(interval(of: reqs[0]), 2 * 60, "this times a COMMIT acknowledgement, not presence — 5 s split the pod on 2026-09-19")
    }

    // MARK: - Replacement, which is the whole mechanism

    /// The load-bearing property. Every completed loop cycle calls refresh(); if that STACKED
    /// requests instead of replacing, the first one armed would still fire on schedule and the
    /// watchdog would alarm during a perfectly healthy loop.
    func testRefreshReplacesRatherThanStacking() {
        for _ in 0..<5 { LoopStallWatchdog.refresh() }
        XCTAssertEqual(pending().count, 4, "same identifiers replace — five refreshes still leave one ladder")
    }

    func testDisarmClearsTheWholeLadderButNotOtherAlerts() {
        LoopStallWatchdog.refresh()
        HandbackStuckAlert.arm()
        XCTAssertEqual(pending().count, 5)
        LoopStallWatchdog.disarm()
        let left = pending()
        XCTAssertEqual(left.count, 1, "disarm removes exactly the ladder's four rungs")
        XCTAssertEqual(interval(of: left[0]), HandbackStuckAlert.interval)
        HandbackStuckAlert.disarm()
    }

    func testHandbackAlertFiresLongBeforeTheLoopWatchdog() {
        XCTAssertLessThan(HandbackStuckAlert.interval, LoopStallWatchdog.interval)
    }
}
