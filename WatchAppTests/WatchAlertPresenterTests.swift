//
//  WatchAlertPresenterTests.swift
//  WatchAppTests
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//
//  While the watch holds the pod it is the only device that can hear the pump, so a pod fault or
//  an occlusion has nowhere to go but the wrist. These tests pin that the alert reaches the
//  notification centre at all — for months it reached only the system log — and that the pieces a
//  user depends on survive the trip: the words, the urgency, and the ability to take it away again.
//

import XCTest
import LoopKit
import UserNotifications
@testable import WatchApp

final class WatchAlertPresenterTests: XCTestCase {

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

    private func alert(_ alertIdentifier: String = "podFault",
                       manager: String = "Omnipod",
                       title: String = "Pod Fault",
                       body: String = "Insulin delivery stopped. Change your pod now.",
                       level: LoopKit.Alert.InterruptionLevel = .critical,
                       trigger: LoopKit.Alert.Trigger = .immediate) -> LoopKit.Alert {
        let content = LoopKit.Alert.Content(title: title, body: body, acknowledgeActionButtonLabel: "OK")
        return LoopKit.Alert(identifier: .init(managerIdentifier: manager, alertIdentifier: alertIdentifier),
                             foregroundContent: content, backgroundContent: content,
                             trigger: trigger, interruptionLevel: level)
    }

    /// The whole point: an alert raised during a loan is presented, not merely logged.
    func testAPodAlertReachesTheWrist() {
        WatchAlertPresenter.present(alert())

        XCTAssertEqual(scheduler.pending.count, 1, "a pod fault during a loan must reach the wrist")
        let request = try? XCTUnwrap(scheduler.pending.first)
        XCTAssertEqual(request?.content.title, "Pod Fault", "the user is told what happened")
        XCTAssertEqual(request?.content.body, "Insulin delivery stopped. Change your pod now.",
                       "and what to do about it")
        XCTAssertNil(request?.trigger, "an immediate alert fires now, not on a timer")
    }

    /// A pod fault is not something to sleep through.
    func testUrgencySurvivesTheTrip() {
        WatchAlertPresenter.present(alert(level: .critical))
        XCTAssertEqual(scheduler.pending.first?.content.interruptionLevel, .critical)
        XCTAssertNotNil(scheduler.pending.first?.content.sound, "a critical alert makes a noise")

        scheduler = RecordingWristAlertScheduler(); WristAlerts.scheduler = scheduler
        WatchAlertPresenter.present(alert("reservoirLow", level: .timeSensitive))
        XCTAssertEqual(scheduler.pending.first?.content.interruptionLevel, .timeSensitive,
                       "a low reservoir is urgent, not critical — it must not cry wolf")
    }

    /// Retracting is how a driver says the condition cleared. An alarm left standing after the
    /// pod recovered costs the next one its weight.
    func testRetractingTakesItBack() {
        let fault = alert()
        WatchAlertPresenter.present(fault)
        XCTAssertEqual(scheduler.pending.count, 1)

        WatchAlertPresenter.retract(fault.identifier)
        XCTAssertTrue(scheduler.pending.isEmpty, "the pending alert is withdrawn")
        XCTAssertEqual(scheduler.deliveredRemovals.count, 1,
                       "and so is one already on the wrist — the user must not be left staring at a stale alarm")
    }

    /// Two alerts must not be able to cancel each other, and re-issuing one must replace its own
    /// copy rather than stack a second.
    func testIdentifiersAreIndependentAndReIssuingReplaces() {
        WatchAlertPresenter.present(alert("podFault"))
        WatchAlertPresenter.present(alert("occlusion", title: "Occlusion", body: "Delivery is blocked."))
        XCTAssertEqual(scheduler.pending.count, 2, "distinct conditions are distinct alerts")

        WatchAlertPresenter.present(alert("podFault", body: "Insulin delivery stopped. Change your pod now."))
        XCTAssertEqual(scheduler.pending.count, 2, "re-issuing replaces its own copy, never stacks")

        WatchAlertPresenter.retract(LoopKit.Alert.Identifier(managerIdentifier: "Omnipod", alertIdentifier: "podFault"))
        XCTAssertEqual(scheduler.pending.count, 1, "retracting one leaves the other standing")
        XCTAssertEqual(scheduler.pending.first?.content.title, "Occlusion")
    }

    /// The dead-man ladder owns its own identifiers. Retracting a pod alert must never reach them.
    func testAPodRetractionCannotCancelTheDeadManLadder() {
        LoopStallWatchdog.refresh()
        let ladder = scheduler.identifiers
        XCTAssertFalse(ladder.isEmpty, "the ladder is armed")

        WatchAlertPresenter.present(alert())
        WatchAlertPresenter.retract(LoopKit.Alert.Identifier(managerIdentifier: "Omnipod", alertIdentifier: "podFault"))

        XCTAssertTrue(ladder.isSubset(of: scheduler.identifiers),
                      "every dead-man rung survives a pod alert being taken back")
    }

    /// The notification centre silently drops a repeating trigger under a minute, so a driver
    /// asking for something shorter must still get an alarm.
    func testARepeatingAlertIsNeverLostToTooShortAnInterval() {
        WatchAlertPresenter.present(alert(trigger: .repeating(repeatInterval: 5)))

        let trigger = scheduler.pending.first?.trigger as? UNTimeIntervalNotificationTrigger
        XCTAssertEqual(trigger?.timeInterval ?? 0, 60, accuracy: 0.001,
                       "raised to the centre's floor rather than dropped")
        XCTAssertEqual(trigger?.repeats, true)
    }

    /// A delayed alert keeps its delay.
    func testADelayedAlertKeepsItsDelay() {
        WatchAlertPresenter.present(alert(trigger: .delayed(interval: 900)))

        let trigger = scheduler.pending.first?.trigger as? UNTimeIntervalNotificationTrigger
        XCTAssertEqual(trigger?.timeInterval ?? 0, 900, accuracy: 0.001)
        XCTAssertEqual(trigger?.repeats, false)
    }
}
