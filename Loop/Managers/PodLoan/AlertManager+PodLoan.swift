//
//  AlertManager+PodLoan.swift
//  Loop
//
//  The Loop-Failure ladder during a pod loan: clearing it when the watch takes the pod, and
//  sweeping up the rungs that escape the clear.
//
//  The gate itself — `loopNotRunningSuppressionGate` — is a stored property and so stays on
//  AlertManager. Its rationale, verbatim from where it was written:
//
//  True while a pod loan is active. Set by WatchDataManager at wiring time. The
//  grant-time clear (clearLoopNotRunningNotificationsForLoanGrant) removes the QUEUED
//  rungs, but .LoopCycleCompleted kept firing — the phone completes open-loop cycles all
//  through a loan — and each completion re-armed the whole ladder ungated, so a
//  "Loop Failure" about the phone's deliberately-idle loop fired mid-loan (field
//  2026-08-24: 20-minute rung on the wrist while the WATCH held the pod; also the earlier
//  sightings the grant-time clear was believed to have fixed). The clear handles the past;
//  this gate handles the future; the reclaim-instant re-arm restores coverage at loan end.
//

import Foundation
import LoopKit
import UserNotifications

extension AlertManager {

    /// Belt-and-braces for the ladder's escape artists. A 1-hour rung fired mid-loan on
    /// 2026-08-25 having survived BOTH the grant-time clear and the completion gate — anchored
    /// pre-loan, mechanism unidentified. Rather than guess the escape path, sweep: once a
    /// minute during a loan (riding the link census tick) any pending Loop-Failure rung is
    /// removed and LOGGED with its count, so whatever queued it dies within a minute and the
    /// log line convicts the original path.
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

    /// Clear the Loop Failure ladder because the WATCH has taken the pod.
    ///
    /// Phone-side silence is the normal state during a loan — leaving the phone behind is the
    /// point of the feature — so the pre-scheduled ladder would fire on a healthy session.
    /// Clears the persisted list too, so a relaunch mid-loan does not re-arm what was cleared.
    func clearLoopNotRunningNotificationsForLoanGrant() {
        UserDefaults.appGroup?.loopNotRunningNotifications = []
        Task { await clearLoopNotRunningNotifications() }
    }
}
