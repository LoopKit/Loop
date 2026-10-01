//
//  PodLoanPhoneController+Notifications.swift
//  Loop
//
//  Part of PodLoanPhoneController (see PodLoanPhoneController.swift). Split by concern; stored
//  properties live in the core class.
//
//  The scheduled half of what the phone tells the user about a loan: the reminders that outlive
//  the moment they were armed in. Anything that has to be seen immediately goes out through
//  `deps.issueNotice` / `issueUrgentNotice` at its own call site instead.
//
//  Each rung owns one identifier, so re-arming replaces rather than stacks and cancelling one
//  ladder cannot silence another.
//

import Foundation
import HealthKit
import LoopKit
import LoopCore
import UserNotifications
import os.log

extension PodLoanPhoneController {
    func scheduleNotification(id: String, title: String, body: String, delay: TimeInterval, repeats: Bool) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: repeats)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    /// Clears the pending request AND anything already delivered: a reminder about a condition
    /// that has cleared is worse than no reminder, because it is still sitting on the lock
    /// screen describing a state the phone has left.
    func cancelNotification(id: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [id])
    }

    /// One notice per stretch of skew. The flag is cleared by the first message that decodes, so
    /// a build mismatch is announced once and again if it recurs, rather than on every message.
    func warnProtocolMismatch() {
        os_log("Loan protocol skew — payload undecodable in this build", log: log, type: .error)
        guard !hasWarnedProtocolMismatch else { return }
        hasWarnedProtocolMismatch = true
        deps.issueNotice(
            NSLocalizedString("Watch Message Unreadable", comment: "Phone notice title when a loan message cannot be decoded"),
            NSLocalizedString("Loop can't read a message from the watch. The apps may be on different builds — check both are current.", comment: "Phone notice body when a loan message cannot be decoded"))
    }

    /// One wording for every way the audit can fail to reach a verdict — no baseline, no
    /// odometer, or a settle that ran out of time. The user's situation is identical in all
    /// three: the session's insulin is unknown and dosing has stopped.
    static let sessionUnverifiedBody = NSLocalizedString(
        "Loop couldn't verify the watch's insulin delivery. Automatic dosing is off until you turn it back on.",
        comment: "Phone notice when a watch session's insulin could not be verified after reclaim")

    /// Reminds the user that the unexplained-insulin placeholder is a pod total booked at the
    /// reclaim instant, not real timing, so they can correct it while it still matters. The
    /// rungs stop inside the insulin action duration — past that the placeholder has decayed
    /// out of IOB and re-timing it changes nothing.
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

    /// Fires ONCE, and does not repeat. The loop being open is a decision the phone already
    /// announced; a recurring nag about it only teaches the user to swipe these away.
    func armOpenLoopReminder() {
        scheduleNotification(
            id: NotificationID.openLoop,
            title: NSLocalizedString("Closed Loop Is Off", comment: "Phone reminder title after an audit opened the loop"),
            body: NSLocalizedString("Loop couldn't verify the watch session's insulin, so it stopped dosing. Turn Closed Loop back on when you're ready.", comment: "Phone reminder body after an audit opened the loop"),
            delay: ReminderLadder.openLoopDelay, repeats: false)
    }

    /// Run at launch: the user may have closed the loop again in a previous session, and the
    /// pending reminder would then arrive telling them to do what they have already done.
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
