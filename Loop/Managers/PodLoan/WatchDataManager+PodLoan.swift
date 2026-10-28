//
//  WatchDataManager+PodLoan.swift
//  Loop
//
//  The phone side of the pod loan on WatchDataManager: controller startup, the loan's
//  WatchConnectivity channels, the reclaim background hold, the link census, and the notice
//  for a watch bolus refused during a loan.
//

import Combine
import HealthKit
import UIKit
import UserNotifications
import WatchConnectivity
import LoopAlgorithm
import LoopKit
import LoopCore

// MARK: - Loan protocol v2

extension WatchDataManager {

    /// Wires the Loop-Failure suppression gate to the pump's release flag, once.
    func wireLoopFailureSuppressionGate() {
        guard FeatureFlags.sportModeEnabled else { return }
        deviceManager.alertManager?.loopNotRunningSuppressionGate = { [weak self] in
            (self?.deviceManager.pumpManager as? ExclusiveDeviceControl)?.isControlReleased ?? false
        }
    }

    /// Brought up with WatchDataManager, after the session is activated.
    func podLoanStartup() {
        // With the flag off nothing of the loan starts.
        guard FeatureFlags.sportModeEnabled else { return }
        // The build as a commit and build time, matching the watch; build numbers do not name source.
        PhoneLog.event("session", "Loop phone ready — build \(BuildDetails.default.codeIdentity)")

        // Eager, so a relaunch mid-loan restores the state machine before any message.
        _ = podLoanController
        followGlucoseAlertSettings()
    }

    /// A glucose alert change reaches the watch's standing copy now, not at the periodic refresh.
    private func followGlucoseAlertSettings() {
        let manager = deviceManager.glucoseAlertManager
        podLoanController.noteGlucoseAlertSettings(manager.sharedSettings)
        // Fires before the change; the main-actor hop reads it after.
        Self.glucoseAlertSettingsChanges = manager.objectWillChange.sink { [weak self, weak manager] _ in
            Task { @MainActor in
                guard let self, let manager else { return }
                self.podLoanController.noteGlucoseAlertSettings(manager.sharedSettings)
            }
        }
    }

    /// Written once on main at startup.
    nonisolated(unsafe) private static var glucoseAlertSettingsChanges: AnyCancellable?

    // MARK: - Background task

    func beginReclaimBackgroundTask() {
        endReclaimBackgroundTask()
        reclaimBackgroundTask = UIApplication.shared.beginBackgroundTask(withName: "PodLoanReclaim") { [weak self] in
            // Expired: release the hold; overdue rungs fire at the next resume.
            self?.endReclaimBackgroundTask()
        }
    }

    func endReclaimBackgroundTask() {
        if reclaimBackgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(reclaimBackgroundTask)
            reclaimBackgroundTask = .invalid
        }
    }

    // MARK: - Loop pulse

    func podLoanConsiderRefresh(for updateContext: LoopUpdateContext) {
        guard FeatureFlags.sportModeEnabled else { return }
        // Every loop update pings the refresher; its gating is inside.
        podLoanController.considerDormantRefresh(bookChanged: updateContext == .insulin || updateContext == .carbs)
        // The watch's hold on the pod lapses by itself when its renewals stop — same pulse.
        podLoanController.considerHoldLapse()
        podLoanController.considerOwedForceReclaimAudit()
    }

    // MARK: - Watch bolus

    /// Whether the watch's bolus must be refused because the pod is not this phone's to command.
    func podLoanRefusesWatchBolus(_ bolus: SetBolusUserInfo) -> Bool {
        guard FeatureFlags.sportModeEnabled else { return false }
        // The pod is on the watch: refuse delivery loudly. An attached carb entry is still stored.
        let deliveryRefusedForLoan = bolus.value > 0 && podLoanController.isPodLoanedOut
        if deliveryRefusedForLoan {
            log.error("refused a %.2f U bolus sent from the watch: the pod is on loan", bolus.value)
            NotificationManager.sendBolusFailureNotificationForPodLoan(units: bolus.value)
        }
        return deliveryRefusedForLoan
    }

    // MARK: - WatchConnectivity channels

    /// The urgent channel without a reply handler, which the watch's Start uses. Without this
    /// method WatchConnectivity drops the message silently.
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            guard FeatureFlags.sportModeEnabled, (try? LoanMessage.decode(fromTransport: message)) != nil else {
                log.default("ignored a message from the watch that is not a loan message: %{public}@",
                            String(describing: Array(message.keys)))
                return
            }
            podLoanController.handleIncoming(userInfo: message)
        }
    }

    /// Loan handshake messages, handled before the stock message handling; false for anything else.
    func podLoanHandlesMessage(_ message: [String: Any], replyHandler: ([String: Any]) -> Void) -> Bool {
        guard FeatureFlags.sportModeEnabled, (try? LoanMessage.decode(fromTransport: message)) != nil else { return false }
        podLoanController.handleIncoming(userInfo: message)
        replyHandler([:])
        return true
    }

    /// The QUEUED channel, `session(_:didReceiveUserInfo:)`'s whole body.
    nonisolated func podLoanHandleReceivedUserInfo(_ userInfo: [String: Any]) {
        // Loan traffic arrives on the queued channel. Route ours, log anything else; never drop
        // silently.
        Task { @MainActor in
            guard FeatureFlags.sportModeEnabled else {
                log.default("ignored userInfo from the watch: %{public}@", String(describing: Array(userInfo.keys)))
                return
            }
            do {
                if try LoanMessage.decode(fromTransport: userInfo) != nil {
                            podLoanController.handleIncoming(userInfo: userInfo)
                    return
                }
                log.default("ignored userInfo from the watch: %{public}@", String(describing: Array(userInfo.keys)))
            } catch {
                log.error("could not read a loan message from the watch: %{public}@", String(describing: error))
            }
        }
    }

    /// A loan's history, read at once (the system deletes the file on return) for the stores.
    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        guard FeatureFlags.sportModeEnabled, file.metadata?["kind"] as? String == LoanHistory.fileKind else { return }
        do {
            let transfer = try LoanHistory.decode(Data(contentsOf: file.fileURL))
            Task { @MainActor in self.podLoanController.handleWatchLoanHistory(transfer) }
        } catch {
            PhoneLog.event("loan", "could not read the loan history file from the watch: \(error)")
        }
    }

    // MARK: - Watch state transitions

    /// Logs the moment isWatchAppInstalled or pairing changes; when false, WatchConnectivity
    /// queues every message, which can strand a hand-back ack.
    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        guard FeatureFlags.sportModeEnabled else { return }
        PhoneLog.event("link", "watch state changed: paired \(session.isPaired), app installed \(session.isWatchAppInstalled), "
            + "reachable \(session.isReachable)")
    }
}

extension NotificationManager {
    /// A watch bolus request arrived while the pod is on loan; the phone refused delivery.
    static func sendBolusFailureNotificationForPodLoan(units: Double) {
        let notification = UNMutableNotificationContent()
        notification.title = NSLocalizedString("Bolus Not Delivered", comment: "Notification title when a bolus is refused because the pod is on loan")
        notification.body = String(
            format: NSLocalizedString("%1$@ U wasn't delivered because the pod is on the watch. Bolus on the watch instead.", comment: "Notification body when a bolus is refused because the pod is on loan (1: units)"),
            NumberFormatter.localizedString(from: NSNumber(value: units), number: .decimal))
        notification.sound = .default
        // No bolusFailure category: its Retry would be a no-op. Own identifier, so it replaces nothing.
        let request = UNNotificationRequest(
            identifier: "podloan.bolusRefused",
            content: notification,
            trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
