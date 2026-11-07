//
//  MealReminderManager.swift
//  Loop
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit
import UserNotifications

@MainActor
protocol MealReminderScheduling {
    func hasPendingReminder(for entry: StoredCarbEntry) async -> Bool
    func scheduleReminder(for entry: StoredCarbEntry) async throws
    func cancelReminder(for entry: StoredCarbEntry)
}

/// The notification request persists across launches. Its identifier follows the carb
/// entry's sync identity, rather than the HealthKit UUID that changes on edits.
@MainActor
final class MealReminderManager: MealReminderScheduling {
    static let shared = MealReminderManager()
    nonisolated static let categoryIdentifier = "com.loopkit.Loop.MealReminder"
    private static let mealTimeKey = "mealTime"

    enum SchedulingError: Error {
        case notificationsDisabled
        case missingEntryIdentifier
    }

    private let notificationCenter: UserNotificationCenter
    private let now: () -> Date
    private let authorize: () async throws -> Bool
    private let isMuted: (TimeInterval) -> Bool

    init(
        notificationCenter: UserNotificationCenter = UNUserNotificationCenter.current(),
        now: @escaping () -> Date = Date.init,
        authorize: @escaping () async throws -> Bool = {
            let center = UNUserNotificationCenter.current()
            var settings = await center.notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                guard try await center.requestAuthorization(options: [.alert, .sound]) else { return false }
                settings = await center.notificationSettings()
            }
            return settings.authorizationStatus != .denied && settings.alertSetting == .enabled
        },
        isMuted: @escaping (TimeInterval) -> Bool = {
            UserDefaults.standard.alertMuterConfiguration.shouldMuteAlert(scheduledAt: $0)
        }
    ) {
        self.notificationCenter = notificationCenter
        self.now = now
        self.authorize = authorize
        self.isMuted = isMuted
    }

    nonisolated static func requestIdentifier(for entry: StoredCarbEntry) -> String? {
        guard let identifier = entry.syncIdentifier ?? entry.uuid?.uuidString else { return nil }
        return "\(categoryIdentifier).\(entry.provenanceIdentifier).\(identifier)"
    }

    func hasPendingReminder(for entry: StoredCarbEntry) async -> Bool {
        guard let identifier = Self.requestIdentifier(for: entry) else { return false }
        let requests = await withCheckedContinuation { continuation in
            notificationCenter.getPendingNotificationRequests { continuation.resume(returning: $0) }
        }
        return requests.contains { $0.identifier == identifier }
    }

    func scheduleReminder(for entry: StoredCarbEntry) async throws {
        guard entry.startDate > now() else {
            cancelReminder(for: entry)
            return
        }
        guard let identifier = Self.requestIdentifier(for: entry) else {
            throw SchedulingError.missingEntryIdentifier
        }
        guard try await authorize() else { throw SchedulingError.notificationsDisabled }

        // Authorization may have taken long enough for the meal time to pass.
        let delay = entry.startDate.timeIntervalSince(now())
        guard delay > 0 else {
            cancelReminder(for: entry)
            return
        }

        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString("Time to Eat", comment: "Title of a scheduled meal reminder")
        let quantity = QuantityFormatter(for: .gram).string(from: entry.quantity) ?? ""
        let time = DateFormatter.localizedString(from: entry.startDate, dateStyle: .none, timeStyle: .short)
        content.body = String(format: NSLocalizedString("You entered %1$@ for %2$@. If your plans have changed, update your carb entry.", comment: "Meal reminder body (1: carb quantity with unit, 2: meal time)"), quantity, time)
        content.categoryIdentifier = Self.categoryIdentifier
        content.userInfo = [Self.mealTimeKey: entry.startDate.timeIntervalSince1970]
        content.interruptionLevel = .timeSensitive
        content.sound = isMuted(delay) ? nil : .default

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
        )
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            notificationCenter.add(request) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
        notificationCenter.removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    func cancelReminder(for entry: StoredCarbEntry) {
        guard let identifier = Self.requestIdentifier(for: entry) else { return }
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [identifier])
        notificationCenter.removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    func updatePendingReminderSounds(_ configuration: AlertMuter.Configuration) async throws {
        let requests = await withCheckedContinuation { continuation in
            notificationCenter.getPendingNotificationRequests { continuation.resume(returning: $0) }
        }
        for request in requests where request.content.categoryIdentifier == Self.categoryIdentifier {
            guard let timestamp = request.content.userInfo[Self.mealTimeKey] as? TimeInterval,
                  let content = request.content.mutableCopy() as? UNMutableNotificationContent else { continue }
            let date = Date(timeIntervalSince1970: timestamp)
            let currentTime = now()
            let delay = date.timeIntervalSince(currentTime)
            guard delay > 0 else { continue }
            content.sound = configuration.shouldMuteAlert(scheduledAt: delay, now: currentTime) ? nil : .default
            // Reusing the original interval trigger would postpone the reminder.
            let updated = UNNotificationRequest(identifier: request.identifier, content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false))
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                notificationCenter.add(updated) { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
        }
    }

    /// Only carry forward a reminder the user already requested. Editing a carb
    /// entry must never silently opt someone into a new reminder.
    func updateReminder(from original: StoredCarbEntry, to updated: StoredCarbEntry) async throws {
        guard await hasPendingReminder(for: original) else { return }
        cancelReminder(for: original)
        try await scheduleReminder(for: updated)
    }
}
