//
//  MealReminderManagerTests.swift
//  LoopTests
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import LoopKit
import UserNotifications
import XCTest
@testable import Loop

@MainActor
final class MealReminderManagerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func entry(after interval: TimeInterval, id: String = "meal", grams: Double = 45) -> StoredCarbEntry {
        StoredCarbEntry(startDate: now.addingTimeInterval(interval), quantity: LoopQuantity(unit: .gram, doubleValue: grams), uuid: UUID(), syncIdentifier: id)
    }

    func testTimeSensitiveReminderAndIndependentMeals() async throws {
        let center = MockUserNotificationCenter()
        let manager = MealReminderManager(notificationCenter: center, now: { self.now }, authorize: { true }, isMuted: { _ in false })
        let first = entry(after: 2700)
        try await manager.scheduleReminder(for: first)
        try await manager.scheduleReminder(for: entry(after: 3000, id: "another-meal"))
        XCTAssertEqual(center.pendingRequests.count, 2)
        let request = try XCTUnwrap(center.pendingRequests.first { $0.identifier == MealReminderManager.requestIdentifier(for: first) })
        XCTAssertEqual(request.content.interruptionLevel, .timeSensitive)
        XCTAssertEqual(request.content.sound, .default)
        XCTAssertEqual(request.content.categoryIdentifier, MealReminderManager.categoryIdentifier)
        XCTAssertEqual((request.trigger as? UNTimeIntervalNotificationTrigger)?.timeInterval, 2700)
        XCTAssertEqual((request.trigger as? UNTimeIntervalNotificationTrigger)?.repeats, false)
        XCTAssertTrue(request.content.body.contains("45"))
    }

    func testEditMovesExistingReminderAndUpdatesQuantity() async throws {
        let center = MockUserNotificationCenter()
        let manager = MealReminderManager(notificationCenter: center, now: { self.now }, authorize: { true }, isMuted: { _ in false })
        let original = entry(after: 2700)
        let updated = entry(after: 3300, grams: 60)
        XCTAssertNotEqual(original.uuid, updated.uuid)
        try await manager.scheduleReminder(for: original)
        try await manager.scheduleReminder(for: updated, replacing: original)
        XCTAssertEqual(center.pendingRequests.count, 1)
        let request = try XCTUnwrap(center.pendingRequests.first)
        XCTAssertEqual((request.trigger as? UNTimeIntervalNotificationTrigger)?.timeInterval, 3300)
        XCTAssertTrue(request.content.body.contains("60"))
    }

    func testReplacingEntryWithDifferentIdentifierRemovesOldRequest() async throws {
        let center = MockUserNotificationCenter()
        let manager = MealReminderManager(notificationCenter: center, now: { self.now }, authorize: { true })
        let original = entry(after: 2700)
        let updated = entry(after: 3300, id: "updated-meal")
        try await manager.scheduleReminder(for: original)
        try await manager.scheduleReminder(for: updated, replacing: original)
        XCTAssertEqual(center.pendingRequests.map(\.identifier), [MealReminderManager.requestIdentifier(for: updated)!])
    }

    func testCancelAndMovingMealToPastRemoveReminder() async throws {
        let center = MockUserNotificationCenter()
        let manager = MealReminderManager(notificationCenter: center, now: { self.now }, authorize: { true })
        let original = entry(after: 2700)
        try await manager.scheduleReminder(for: original)
        try await manager.scheduleReminder(for: entry(after: -60), replacing: original)
        XCTAssertTrue(center.pendingRequests.isEmpty)

        try await manager.scheduleReminder(for: original)
        center.deliverAll()
        XCTAssertEqual(center.deliveredRequests.count, 1)
        manager.cancelReminder(for: original)
        XCTAssertTrue(center.deliveredRequests.isEmpty)
    }

    func testMuteChangesPreserveReminderTime() async throws {
        let center = MockUserNotificationCenter()
        var currentTime = now
        let muted = AlertMuter.Configuration(startTime: now, duration: .hours(1))
        let manager = MealReminderManager(notificationCenter: center, now: { currentTime }, authorize: { true }, isMuted: { delay in
            muted.shouldMuteAlert(scheduledAt: delay, now: currentTime)
        })
        try await manager.scheduleReminder(for: entry(after: .minutes(45)))
        let initial = try XCTUnwrap(center.pendingRequests.first)
        XCTAssertNil(initial.content.sound)
        XCTAssertEqual((initial.trigger as? UNTimeIntervalNotificationTrigger)?.timeInterval, .minutes(45))

        currentTime = now.addingTimeInterval(.minutes(5))
        try await manager.updatePendingReminderSounds(AlertMuter.Configuration())
        let unmuted = try XCTUnwrap(center.pendingRequests.first)
        XCTAssertEqual(unmuted.content.sound, .default)
        XCTAssertEqual((unmuted.trigger as? UNTimeIntervalNotificationTrigger)?.timeInterval, .minutes(40))

        currentTime = now.addingTimeInterval(.minutes(10))
        try await manager.updatePendingReminderSounds(muted)
        let mutedAgain = try XCTUnwrap(center.pendingRequests.first)
        XCTAssertNil(mutedAgain.content.sound)
        XCTAssertEqual((mutedAgain.trigger as? UNTimeIntervalNotificationTrigger)?.timeInterval, .minutes(35))
    }

    func testAuthorizationAndSchedulingFailuresAreReported() async {
        let center = MockUserNotificationCenter()
        let denied = MealReminderManager(notificationCenter: center, now: { self.now }, authorize: { false })
        do {
            try await denied.scheduleReminder(for: entry(after: 2700))
            XCTFail("Expected authorization failure")
        } catch {
            XCTAssertTrue(error is MealReminderManager.SchedulingError)
        }
        XCTAssertTrue(center.pendingRequests.isEmpty)
        center.addError = NSError(domain: "test", code: 1)
        let manager = MealReminderManager(notificationCenter: center, now: { self.now }, authorize: { true })
        do {
            try await manager.scheduleReminder(for: entry(after: 2700))
            XCTFail("Expected scheduling failure")
        } catch {
            XCTAssertEqual((error as NSError).domain, "test")
        }
    }

    func testMealTimePassingDuringAuthorizationDoesNotSendLateReminder() async throws {
        let center = MockUserNotificationCenter()
        var currentTime = now
        let manager = MealReminderManager(notificationCenter: center, now: { currentTime }, authorize: {
            currentTime = currentTime.addingTimeInterval(3000)
            return true
        })
        try await manager.scheduleReminder(for: entry(after: 2700))
        XCTAssertTrue(center.pendingRequests.isEmpty)
    }
}
