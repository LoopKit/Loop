//
//  PodLoanPhoneController+Notifications.swift
//  Loop
//
//  Scheduled loan reminders, one identifier per rung. Immediate notices go through
//  `deps.issueNotice` / `issueUrgentNotice` at their call sites.
//

import Foundation
import HealthKit
import LoopKit
import LoopCore
import UserNotifications
import os.log

extension PodLoanPhoneController {
    func scheduleNotification(id: String, title: String, body: String, delay: TimeInterval, repeats: Bool,
                              interruptionLevel: UNNotificationInterruptionLevel = .active) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.interruptionLevel = interruptionLevel
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: repeats)
        deps.addNotification(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    /// Removes pending and delivered: a reminder about a cleared condition is worse than none.
    func cancelNotification(id: String) {
        deps.removeNotifications([id])
    }

    /// Once per stretch of version skew; the first message that decodes re-arms it. Time-sensitive:
    /// a skewed loan can leave the pod with nobody dosing.
    func warnProtocolMismatch() {
        os_log("Loan protocol skew — payload undecodable in this build", log: log, type: .error)
        guard !hasWarnedProtocolMismatch else { return }
        hasWarnedProtocolMismatch = true
        deps.issueUrgentNotice(
            NSLocalizedString("Watch Message Unreadable", comment: "Phone notice title when a loan message cannot be decoded"),
            NSLocalizedString("Loop can't read a message from the watch. The iPhone and watch apps may be on different versions.", comment: "Phone notice body when a loan message cannot be decoded"))
    }

    /// For a pump that gave no delivered total to check against.
    static let sessionUnverifiedTitle = "Insulin Not Checked After Sport Mode"
    static let sessionUnverifiedBody = NSLocalizedString(
        "Unexpected: the iPhone couldn't check the watch's insulin against the pod. Insulin the watch gave may be missing from insulin on board. Consider reporting it with a Loop Report.",
        comment: "Phone notice when a watch session's insulin could not be verified after reclaim")

    /// Reminders to re-time the unexplained-insulin placeholder, within the insulin duration.
    func armPlaceholderReminders(units: Double, bookedAt: Date) {
        let amount = String(format: "%.2f", units)
        let time = Self.reminderTimeFormatter.string(from: bookedAt)
        for (index, delay) in ReminderLadder.placeholderRungs.enumerated() {
            scheduleNotification(
                id: NotificationID.placeholder(index),
                title: NSLocalizedString("Estimated Insulin Still Booked", comment: "Phone reminder title while an unexplained gap bolus stands"),
                body: String(format: NSLocalizedString("%1$@ U is still booked as a bolus at %2$@. The watch's records replace it when it's back.", comment: "Phone reminder body while an unexplained gap bolus stands (1: units, 2: time booked)"), amount, time),
                delay: delay, repeats: false, interruptionLevel: .timeSensitive)
        }
    }

    func cancelPlaceholderReminders() {
        for index in ReminderLadder.placeholderRungs.indices {
            cancelNotification(id: NotificationID.placeholder(index))
        }
    }

    private static let reminderTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()

}
