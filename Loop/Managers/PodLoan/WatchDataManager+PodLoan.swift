//
//  WatchDataManager+PodLoan.swift
//  Loop
//
//  The phone side of the pod loan on WatchDataManager: controller startup, the loan's
//  WatchConnectivity channels, the reclaim background hold, and the link census.
//

import Combine
import HealthKit
import UIKit
import WatchConnectivity
import LoopAlgorithm
import LoopKit
import LoopCore

// MARK: - Loan protocol v2

extension WatchDataManager {

    /// Wires the Loop-Failure suppression gate to the loan state, once.
    func wireLoopFailureSuppressionGate() {
        guard FeatureFlags.sportModeEnabled else { return }
        deviceManager.alertManager?.loopNotRunningSuppressionGate = { [weak self] in
            self?.podLoanController.isLoanedOutForUI ?? false
        }
        Self.loanLadderSweep = { [weak self] in
            self?.deviceManager.alertManager?.sweepLoopNotRunningNotificationsDuringLoan()
        }
    }

    /// Written once on main at wiring; read from the census queue.
    nonisolated(unsafe) private static var loanLadderSweep: (() -> Void)?

    /// Brought up with WatchDataManager, after the session is activated.
    func podLoanStartup() {
        // With the flag off nothing of the loan starts: no controller, no census, no log.
        guard FeatureFlags.sportModeEnabled else { return }
        // The build as a commit and build time, matching the watch; build numbers do not name source.
        PhoneLog.event("session", "Loop phone ready — build \(BuildDetails.default.codeIdentity)")

        // Eager, so a relaunch mid-loan restores the state machine before any message.
        _ = podLoanController
        startLinkCensus()
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
    }

    // MARK: - Context

    private static var lastOnboardingKey = ""   // [onboarding-gate] dedupe

    /// The CGM's configuration, so a watch can read the sensor itself.
    func podLoanShareCGMConfiguration(_ context: WatchContext) {
        guard FeatureFlags.sportModeEnabled else { return }
        context.cgmConfiguration = (deviceManager.cgmManager as? DeviceConfigurationSharing)?.exportConfiguration().rawValue
    }

    func podLoanLogOnboardingContext(_ context: WatchContext) {
        guard FeatureFlags.sportModeEnabled else { return }
        // Logged on change; pairs with the watch's [onboarding-gate] lines.
        let onboardingKey = "\(context.isOnboardingCompleted == true)|\(deviceManager.cgmManager != nil)|\(deviceManager.pumpManager?.isOnboarded == true)"
        if onboardingKey != Self.lastOnboardingKey {
            Self.lastOnboardingKey = onboardingKey
            PhoneLog.event("link", "context to watch: onboardingCompleted=\(context.isOnboardingCompleted == true) — cgmManager \(deviceManager.cgmManager == nil ? "NIL" : "present"), pump onboarded=\(deviceManager.pumpManager?.isOnboarded == true) [onboarding-gate]")
        }
    }

    // MARK: - Watch bolus

    /// Whether the watch's bolus must be refused because the pod is not this phone's to command.
    func podLoanRefusesWatchBolus(_ bolus: SetBolusUserInfo, message: [String: Any]) -> Bool {
        guard FeatureFlags.sportModeEnabled else { return false }
        // The pod is on the watch: refuse delivery loudly. An attached carb entry is still stored.
        let deliveryRefusedForLoan = bolus.value > 0 && podLoanController.isPodLoanedOut
        if deliveryRefusedForLoan {
            log.error("Refusing watch bolus while the pod is on loan: %{public}@", String(describing: message))
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
                log.default("Ignoring unexpected sendMessage from the watch: %{public}@",
                            String(describing: Array(message.keys)))
                return
            }
            lockedLastWatchContact.value = Date()
            log.default("Loan sendMessage delivered (urgent path)")
            podLoanController.handleIncoming(userInfo: message)
        }
    }

    /// The QUEUED channel, `session(_:didReceiveUserInfo:)`'s whole body.
    nonisolated func podLoanHandleReceivedUserInfo(_ userInfo: [String: Any]) {
        // Loan traffic arrives on the queued channel. Route ours, log anything else; never drop
        // silently.
        Task { @MainActor in
            guard FeatureFlags.sportModeEnabled else {
                log.default("Unexpected userInfo from the watch: %{public}@", String(describing: Array(userInfo.keys)))
                return
            }
            do {
                if let message = try LoanMessage.decode(fromTransport: userInfo) {
                    lockedLastWatchContact.value = Date()
                    podLoanController.handleIncoming(userInfo: userInfo)
                    return
                }
                log.default("Unexpected userInfo from the watch: %{public}@", String(describing: Array(userInfo.keys)))
            } catch {
                log.error("Undecodable pod loan payload from the watch: %{public}@", String(describing: error))
            }
        }
    }

    /// The loan's half of `sessionReachabilityDidChange`.
    func podLoanSessionReachabilityDidChange(_ session: WCSession) {
        guard FeatureFlags.sportModeEnabled else { return }
        if session.isReachable {
            lockedLastWatchContact.value = Date()
            podLoanController.watchDidBecomeReachable()
        }
    }

    /// The watch's log files, copied at once (the system deletes the file on return) to Documents
    /// for AirDrop from the phone; and a loan's history, read at once for the stores.
    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        guard FeatureFlags.sportModeEnabled else { return }
        lockedLastWatchContact.value = Date()   // the log pulse is the loan's heartbeat
        if file.metadata?["kind"] as? String == LoanHistory.fileKind {
            do {
                let transfer = try LoanHistory.decode(Data(contentsOf: file.fileURL))
                Task { @MainActor in self.podLoanController.handleWatchLoanHistory(transfer) }
            } catch {
                PhoneLog.event("loan", "loan history file from the watch UNREADABLE — \(error)")
            }
            return
        }
        guard file.metadata?["kind"] as? String == "g7watch.log" else { return }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamped = docs.appendingPathComponent("g7watch-\(formatter.string(from: Date())).log")
        try? FileManager.default.copyItem(at: file.fileURL, to: stamped)
        let latest = docs.appendingPathComponent("g7watch-latest.log")
        try? FileManager.default.removeItem(at: latest)
        try? FileManager.default.copyItem(at: file.fileURL, to: latest)
        // Keep the newest 20 stamped copies, plus latest.
        if let entries = try? FileManager.default.contentsOfDirectory(at: docs, includingPropertiesForKeys: nil) {
            let stampedLogs = entries
                .filter { $0.pathExtension == "log" && $0.lastPathComponent.hasPrefix("g7watch-") && $0.lastPathComponent != "g7watch-latest.log" }
                .sorted { $0.lastPathComponent > $1.lastPathComponent }
            for old in stampedLogs.dropFirst(20) {
                try? FileManager.default.removeItem(at: old)
            }
        }
        log.default("Watch log received: %{public}@", stamped.lastPathComponent)
    }

    /// Link census: one line a minute on whether this phone can see the watch. Serial.
    nonisolated private static let linkCensusQueue = DispatchQueue(label: "com.loopkit.Loop.linkCensus", qos: .utility)
    nonisolated(unsafe) private static var linkCensusTimer: DispatchSourceTimer?

    /// The phone's pod link during a loan, for the census.
    nonisolated(unsafe) static var podLinkCensus: (() -> String)?

    nonisolated private func startLinkCensus() {
        let t = DispatchSource.makeTimerSource(queue: Self.linkCensusQueue)
        t.schedule(deadline: .now() + 60, repeating: 60, leeway: .seconds(5))
        t.setEventHandler {
            guard WCSession.isSupported() else { return }
            let s = WCSession.default
            let pod = Self.podLinkCensus.map { " · pod: \($0())" } ?? ""
            Self.loanLadderSweep?()
            PhoneLog.event("link", "watch reachable=\(s.isReachable) activation=\(s.activationState.rawValue) paired=\(s.isPaired) appInstalled=\(s.isWatchAppInstalled)\(pod)")
        }
        t.resume()
        Self.linkCensusTimer = t
    }

    // MARK: - Watch state transitions

    /// Logs the moment isWatchAppInstalled or pairing changes; when false, WatchConnectivity
    /// queues every message, which can strand a hand-back ack.
    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        guard FeatureFlags.sportModeEnabled else { return }
        PhoneLog.event("link", "** WATCH STATE CHANGED ** paired=\(session.isPaired) "
            + "appInstalled=\(session.isWatchAppInstalled) reachable=\(session.isReachable) "
            + "activation=\(session.activationState.rawValue) "
            + "complication=\(session.isComplicationEnabled)")
    }
}
