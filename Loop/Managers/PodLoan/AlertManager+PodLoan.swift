//
//  AlertManager+PodLoan.swift
//  Loop
//
//  The Loop-Failure ladder during a loan: cleared at the grant, gated while the phone's loop
//  is idle (`loopNotRunningSuppressionGate`), swept each minute, re-armed at the reclaim.
//

import Foundation
import LoopKit
import UserNotifications

extension AlertManager {

    /// Removes and logs any Loop-Failure rung found pending during a loan, once a minute.
    func sweepLoopNotRunningNotificationsDuringLoan() {
        guard loopNotRunningSuppressionGate?() == true else { return }
        Task {
            let center = UNUserNotificationCenter.current()
            let prefix = LoopNotificationCategory.loopNotRunning.rawValue
            let ids = await center.pendingNotificationRequests()
                .filter { $0.identifier.hasPrefix(prefix) }
                .map(\.identifier)
            guard !ids.isEmpty else { return }
            center.removePendingNotificationRequests(withIdentifiers: ids)
            PhoneLog.event("deadman", "swept \(ids.count) stale phone Loop-Failure rung(s) mid-loan — these escaped the grant clear and the gate [deadman-sweep]")
        }
    }

    /// The watch has the pod, so the phone's silence is expected; clears the persisted list too.
    func clearLoopNotRunningNotificationsForLoanGrant() {
        UserDefaults.appGroup?.loopNotRunningNotifications = []
        Task { await clearLoopNotRunningNotifications() }
    }
}
