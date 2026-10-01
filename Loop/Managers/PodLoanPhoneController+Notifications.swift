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
            NSLocalizedString("Loop can't read a message from the watch. The apps may be on different builds — check both are current.", comment: "Phone notice body when a loan message cannot be decoded"))
    }

    /// Shared by every way an audit can fail to reach a verdict.
    static let sessionUnverifiedBody = NSLocalizedString(
        "Loop couldn't verify the watch's insulin delivery. Automatic dosing is off until you turn it back on.",
        comment: "Phone notice when a watch session's insulin could not be verified after reclaim")

    /// Reminders to re-time the unexplained-insulin placeholder, within the insulin duration.
    func armPlaceholderReminders(units: Double, bookedAt: Date) {
        let amount = String(format: "%.2f", units)
        let time = Self.reminderTimeFormatter.string(from: bookedAt)
        for (index, delay) in ReminderLadder.placeholderRungs.enumerated() {
            scheduleNotification(
                id: NotificationID.placeholder(index),
                title: NSLocalizedString("Estimated Insulin Still Booked", comment: "Phone reminder title while an unexplained gap bolus stands"),
                body: String(format: NSLocalizedString("%1$@ U is booked as a bolus at %2$@ — the pod's total, not real timing. If you remember the session, correct it in Insulin Delivery.", comment: "Phone reminder body while an unexplained gap bolus stands (1: units, 2: time booked)"), amount, time),
                delay: delay, repeats: false)
        }
    }

    func cancelPlaceholderReminders() {
        for index in ReminderLadder.placeholderRungs.indices {
            cancelNotification(id: NotificationID.placeholder(index))
        }
    }

    /// Fires once; the phone already announced the open loop. Time-sensitive: nothing doses
    /// automatically until the user acts.
    func armOpenLoopReminder() {
        scheduleNotification(
            id: NotificationID.openLoop,
            title: NSLocalizedString("Closed Loop Is Off", comment: "Phone reminder title after an audit opened the loop"),
            body: NSLocalizedString("Loop couldn't verify the watch session's insulin, so it stopped dosing. Turn Closed Loop back on when you're ready.", comment: "Phone reminder body after an audit opened the loop"),
            delay: ReminderLadder.openLoopDelay, repeats: false, interruptionLevel: .timeSensitive)
    }

    /// At launch, in case the user already closed the loop.
    func cancelOpenLoopReminderIfLoopClosed() {
        guard deps.settings().dosingEnabled else { return }
        cancelNotification(id: NotificationID.openLoop)
    }

    private static let reminderTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()

}
