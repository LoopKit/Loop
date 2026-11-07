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
        let center = MealReminderTestNotificationCenter()
        let manager = MealReminderManager(notificationCenter: center, now: { self.now }, authorize: { true }, isMuted: { _ in false })
        let first = entry(after: 2700)
        try await manager.scheduleReminder(for: first)
        try await manager.scheduleReminder(for: entry(after: 3000, id: "another-meal"))
        XCTAssertEqual(center.requests.count, 2)
        let request = try XCTUnwrap(center.requests[MealReminderManager.requestIdentifier(for: first)!])
        XCTAssertEqual(request.content.interruptionLevel, .timeSensitive)
        XCTAssertEqual(request.content.sound, .default)
        XCTAssertEqual(request.content.categoryIdentifier, MealReminderManager.categoryIdentifier)
        XCTAssertEqual((request.trigger as? UNTimeIntervalNotificationTrigger)?.timeInterval, 2700)
        XCTAssertEqual((request.trigger as? UNTimeIntervalNotificationTrigger)?.repeats, false)
        XCTAssertTrue(request.content.body.contains("45"))
    }

    func testEditMovesExistingReminderAndUpdatesQuantity() async throws {
        let center = MealReminderTestNotificationCenter()
        let manager = MealReminderManager(notificationCenter: center, now: { self.now }, authorize: { true }, isMuted: { _ in false })
        let original = entry(after: 2700)
        let updated = entry(after: 3300, grams: 60)
        XCTAssertNotEqual(original.uuid, updated.uuid)
        try await manager.scheduleReminder(for: original)
        try await manager.updateReminder(from: original, to: updated)
        XCTAssertEqual(center.requests.count, 1)
        let request = try XCTUnwrap(center.requests.values.first)
        XCTAssertEqual((request.trigger as? UNTimeIntervalNotificationTrigger)?.timeInterval, 3300)
        XCTAssertTrue(request.content.body.contains("60"))
    }

    func testEditsDoNotCreateUnrequestedReminders() async throws {
        let center = MealReminderTestNotificationCenter()
        let manager = MealReminderManager(notificationCenter: center, now: { self.now }, authorize: { true })
        try await manager.updateReminder(from: entry(after: 2700), to: entry(after: 3300))
        XCTAssertTrue(center.requests.isEmpty)
    }

    func testCancelAndMovingMealToPastRemoveReminder() async throws {
        let center = MealReminderTestNotificationCenter()
        let manager = MealReminderManager(notificationCenter: center, now: { self.now }, authorize: { true })
        let original = entry(after: 2700)
        try await manager.scheduleReminder(for: original)
        try await manager.updateReminder(from: original, to: entry(after: -60))
        XCTAssertTrue(center.requests.isEmpty)

        try await manager.scheduleReminder(for: original)
        center.removedDelivered.removeAll()
        manager.cancelReminder(for: original)
        XCTAssertTrue(center.requests.isEmpty)
        let identifier = try XCTUnwrap(MealReminderManager.requestIdentifier(for: original))
        XCTAssertEqual(center.removedDelivered, [identifier])
    }

    func testMuteChangesPreserveReminderTime() async throws {
        let center = MealReminderTestNotificationCenter()
        var currentTime = now
        let muted = AlertMuter.Configuration(startTime: now, duration: .hours(1))
        let manager = MealReminderManager(notificationCenter: center, now: { currentTime }, authorize: { true }, isMuted: { delay in
            muted.shouldMuteAlert(scheduledAt: delay, now: currentTime)
        })
        try await manager.scheduleReminder(for: entry(after: .minutes(45)))
        let initial = try XCTUnwrap(center.requests.values.first)
        XCTAssertNil(initial.content.sound)
        XCTAssertEqual((initial.trigger as? UNTimeIntervalNotificationTrigger)?.timeInterval, .minutes(45))

        currentTime = now.addingTimeInterval(.minutes(5))
        try await manager.updatePendingReminderSounds(AlertMuter.Configuration())
        let unmuted = try XCTUnwrap(center.requests.values.first)
        XCTAssertEqual(unmuted.content.sound, .default)
        XCTAssertEqual((unmuted.trigger as? UNTimeIntervalNotificationTrigger)?.timeInterval, .minutes(40))

        currentTime = now.addingTimeInterval(.minutes(10))
        try await manager.updatePendingReminderSounds(muted)
        let mutedAgain = try XCTUnwrap(center.requests.values.first)
        XCTAssertNil(mutedAgain.content.sound)
        XCTAssertEqual((mutedAgain.trigger as? UNTimeIntervalNotificationTrigger)?.timeInterval, .minutes(35))
    }

    func testAuthorizationAndSchedulingFailuresAreReported() async {
        let center = MealReminderTestNotificationCenter()
        let denied = MealReminderManager(notificationCenter: center, now: { self.now }, authorize: { false })
        do {
            try await denied.scheduleReminder(for: entry(after: 2700))
            XCTFail("Expected authorization failure")
        } catch {
            XCTAssertTrue(error is MealReminderManager.SchedulingError)
        }
        XCTAssertTrue(center.requests.isEmpty)
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
        let center = MealReminderTestNotificationCenter()
        var currentTime = now
        let manager = MealReminderManager(notificationCenter: center, now: { currentTime }, authorize: {
            currentTime = currentTime.addingTimeInterval(3000)
            return true
        })
        try await manager.scheduleReminder(for: entry(after: 2700))
        XCTAssertTrue(center.requests.isEmpty)
    }
}

private final class MealReminderTestNotificationCenter: UserNotificationCenter {
    var requests: [String: UNNotificationRequest] = [:]
    var removedDelivered: [String] = []
    var addError: Error?

    func add(_ request: UNNotificationRequest, withCompletionHandler completionHandler: ((Error?) -> Void)?) {
        if addError == nil { requests[request.identifier] = request }
        completionHandler?(addError)
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        for identifier in identifiers { requests.removeValue(forKey: identifier) }
    }

    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {
        removedDelivered.append(contentsOf: identifiers)
    }

    func getPendingNotificationRequests(completionHandler: @escaping ([UNNotificationRequest]) -> Void) {
        completionHandler(Array(requests.values))
    }

    func getDeliveredNotifications(completionHandler: @escaping ([UNNotification]) -> Void) {
        completionHandler([])
    }
}
