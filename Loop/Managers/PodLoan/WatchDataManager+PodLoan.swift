//
//  WatchDataManager+PodLoan.swift
//  Loop
//
//  Everything the phone side of the pod loan hangs off WatchDataManager: the controller's
//  startup, the WatchConnectivity channels the loan protocol rides on, the background-task
//  hold that keeps a reclaim alive, and the link census that records whether this phone can
//  see the watch at all.
//
//  Only stored properties stayed behind in WatchDataManager.swift. Their rationale, verbatim
//  from where it was written:
//
//  reclaimBackgroundTask —
//  The reclaim ladder runs on wall-clock rungs; hold the app awake across them so a
//  backgrounded phone still finishes taking the pod back.
//
//  `lockedLastWatchContact` stays in the stock file because an extension cannot hold a stored
//  property: it is when the watch was last heard from, which is the loan's liveness signal.
//

import HealthKit
import UIKit
import WatchConnectivity
import LoopAlgorithm
import LoopKit
import LoopCore

// MARK: - Loan protocol v2 (M5)

extension WatchDataManager {

    /// One-time wiring of the alert manager's Loop-Failure suppression gate to the loan
    /// state. Lazy-adjacent to the controller so neither can exist without the other.
    func wireLoopFailureSuppressionGate() {
        deviceManager.alertManager?.loopNotRunningSuppressionGate = { [weak self] in
            self?.podLoanController.isLoanedOutForUI ?? false
        }
        Self.loanLadderSweep = { [weak self] in
            self?.deviceManager.alertManager?.sweepLoopNotRunningNotificationsDuringLoan()
        }
    }

    /// Called from the link-census tick (its own queue) — the sweep itself gates on loan state.
    /// nonisolated(unsafe): written once at wiring time on main, read from the census queue;
    /// the closure hops back through Task-per-call inside the sweep itself.
    nonisolated(unsafe) private static var loanLadderSweep: (() -> Void)?

    /// Brought up with WatchDataManager, after the session is activated.
    func podLoanStartup() {
        // Which build this is, in the same words the watch uses: a commit and a build time.
        // The two apps install separately, so a phone and a watch running different code is
        // routine — and the App Store build number names the upload, not the source, so two
        // lines of development can both be "255". Without a commit here, telling a real problem
        // from a version skew means inferring it from behaviour, which has cost hours.
        PhoneLog.event("session", "Loop phone ready — build \(BuildDetails.default.codeIdentity)")

        // Constructed eagerly so a relaunch mid-loan restores the persisted state machine —
        // dosing stays paused, reminders re-arm — before any message arrives.
        _ = podLoanController
        startLinkCensus()
    }

    // MARK: - Background task

    func beginReclaimBackgroundTask() {
        endReclaimBackgroundTask()
        reclaimBackgroundTask = UIApplication.shared.beginBackgroundTask(withName: "PodLoanReclaim") { [weak self] in
            // Expiration: iOS is done waiting — release the hold or be killed. The wall-clock
            // rungs then fire whatever is overdue at the next resume.
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
        // R40: every loop update pings the dormant-grant refresher — all gating (owner
        // state, watch capability, settings fingerprint, 30-min floor) lives inside it,
        // so this is one enqueued no-op almost always.
        podLoanController.considerDormantRefresh(bookChanged: updateContext == .insulin || updateContext == .carbs)
        // The watch's hold on the pod lapses by itself when its renewals stop — same pulse.
        podLoanController.considerHoldLapse()
    }

    // MARK: - Context

    private static var lastOnboardingKey = ""   // [onboarding-gate] dedupe

    func podLoanLogOnboardingContext(_ context: WatchContext) {
        // Bench 2026-09-18: the watch kept showing "Please complete onboarding" and neither log
        // said what this phone had told it. Logged on change only; pairs with the watch's
        // "[onboarding-gate]" lines.
        let onboardingKey = "\(context.isOnboardingCompleted == true)|\(deviceManager.cgmManager != nil)|\(deviceManager.pumpManager?.isOnboarded == true)"
        if onboardingKey != Self.lastOnboardingKey {
            Self.lastOnboardingKey = onboardingKey
            PhoneLog.event("link", "context to watch: onboardingCompleted=\(context.isOnboardingCompleted == true) — cgmManager \(deviceManager.cgmManager == nil ? "NIL" : "present"), pump onboarded=\(deviceManager.pumpManager?.isOnboarded == true) [onboarding-gate]")
        }
    }

    // MARK: - Watch bolus

    /// Whether the watch's bolus must be refused because the pod is not this phone's to command.
    func podLoanRefusesWatchBolus(_ bolus: SetBolusUserInfo, message: [String: Any]) -> Bool {
        // While the pod is loaned to the watch this phone cannot deliver — its pod link is
        // deliberately released. Refuse loudly rather than letting the request die in a BLE
        // timeout. Delivery only is refused: an attached carb entry still stores below, because
        // dropping it would lose the meal from the record entirely.
        // (Reconciled from the dev line. This line had NO guard here: a watch
        // bolus during a loan went straight to enactBolus against a released pod link.)
        let deliveryRefusedForLoan = bolus.value > 0 && podLoanController.isPodLoanedOut
        if deliveryRefusedForLoan {
            log.error("Refusing watch bolus while the pod is on loan: %{public}@", String(describing: message))
            NotificationManager.sendBolusFailureNotificationForPodLoan(units: bolus.value)
        }
        return deliveryRefusedForLoan
    }

    // MARK: - WatchConnectivity channels

    /// The URGENT channel with no reply handler — and the one the watch's Start actually uses.
    ///
    /// `sendMessage(_:replyHandler:nil)` is delivered HERE, not to the `replyHandler:` variant
    /// above, which WatchConnectivity only calls when the sender supplied a reply handler. Without
    /// this method the request is dropped by the framework with no error on either side: the watch
    /// logs a successful send, the phone logs nothing at all, and the watch sits until its 25 s
    /// timeout and reports "No response from iPhone". That is exactly what it looked like on the
    /// wrist, and it is indistinguishable from a phone that is refusing or asleep.
    ///
    /// The queued path below is not a substitute. The watch only falls back to it when the phone
    /// is UNREACHABLE, so this gap hides whenever the phone is present — the case that matters.
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            guard (try? LoanMessage.decode(fromTransport: message)) != nil else {
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
        // The pod loan protocol's QUEUED channel carries watch→phone traffic — streamed dose
        // records, status reports, hand-back offers — so this is no longer an impossible
        // callback. It previously asserted, which would take the app down on the first such
        // message, and during a loan that is the worst possible moment: the watch is holding
        // the pump and the phone is the side that has to commit its records.
        //
        // Three outcomes, none of them a silent drop (loan protocol: never ack-and-drop).
        // Ours → route it. Not ours → log, because stock genuinely sends nothing here and a
        // new sender is worth seeing. Undecodable-but-ours → log loudly; the sender's own
        // nack path handles recovery.
        Task { @MainActor in
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
        if session.isReachable {
            lockedLastWatchContact.value = Date()
            podLoanController.watchDidBecomeReachable()
        }
    }

    /// The watch's diagnostics log, transferred file-by-file.
    ///
    /// Without this method the transfers still SUCCEED on the watch side and are then dropped
    /// here, so the wrist reports a healthy log pipeline while nothing is ever written — which is
    /// the worst shape a diagnostics gap can take, because it looks like silence from the device
    /// rather than a missing receiver.
    ///
    /// Two destinations, deliberately. Documents makes the file visible in Files (On My iPhone →
    /// Loop) so it can be AirDropped from the PHONE — watchOS has no AirDrop, and the logs were
    /// otherwise being texted. The iCloud mirror syncs it to the Mac with no Shortcuts step, and
    /// works on cellular. The copy has to happen NOW: the system deletes `file.fileURL` as soon
    /// as this method returns.
    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        lockedLastWatchContact.value = Date()   // the log pulse is the loan's heartbeat
        guard file.metadata?["kind"] as? String == "g7watch.log" else { return }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamped = docs.appendingPathComponent("g7watch-\(formatter.string(from: Date())).log")
        try? FileManager.default.copyItem(at: file.fileURL, to: stamped)
        let latest = docs.appendingPathComponent("g7watch-latest.log")
        try? FileManager.default.removeItem(at: latest)
        try? FileManager.default.copyItem(at: file.fileURL, to: latest)
        // Retention: transfers arrive every reading (~5 min), so stamped copies accumulate fast.
        // Keep the newest 20; the stamp is lexicographically sortable. latest is exempt.
        if let entries = try? FileManager.default.contentsOfDirectory(at: docs, includingPropertiesForKeys: nil) {
            let stampedLogs = entries
                .filter { $0.pathExtension == "log" && $0.lastPathComponent.hasPrefix("g7watch-") && $0.lastPathComponent != "g7watch-latest.log" }
                .sorted { $0.lastPathComponent > $1.lastPathComponent }
            for old in stampedLogs.dropFirst(20) {
                try? FileManager.default.removeItem(at: old)
            }
        }
        // Mirrored from the durable local copy, not from file.fileURL, which is gone by the time
        // the background queue runs.
        Self.mirrorLogToICloud(from: stamped)
        log.default("Watch log received: %{public}@", stamped.lastPathComponent)
    }

    /// SERIAL, not a global queue: a queued-transfer flush delivers several files back-to-back,
    /// and concurrent mirrors interleave their remove/copy/prune steps — which is how
    /// g7watch-latest.log ends up stale or missing in iCloud while newer sends exist. One mirror
    /// at a time, in arrival order.
    /// LINK CENSUS — one line a minute saying whether this PHONE can see the watch.
    ///
    /// The mirror of the watch's census. Reachability otherwise appears only as a side effect of
    /// a send, so the record is silent precisely when nothing is being sent — and a phone that
    /// could not reach the watch looks identical to a phone with nothing to say. Both directions
    /// are logged because they are not the same question and have disagreed in the field: the
    /// watch has reported `reachable true` while the phone logged `reachable=false` acking the
    /// same hand-back.
    nonisolated private static let linkCensusQueue = DispatchQueue(label: "com.loopkit.Loop.linkCensus", qos: .utility)
    nonisolated(unsafe) private static var linkCensusTimer: DispatchSourceTimer?

    /// Set by `PodLoanPhoneController` so the 60 s census can also report what the PHONE's pod link is
    /// doing DURING a loan. Filling a hole, not adding detail: on 2026-08-19 the phone logged NOTHING
    /// about its pod between `released=true linkUp=false` and, 110 s later, `link up +0.0s` — a link it
    /// should not have had, with no record of how it got one. A loan is exactly the window in which the
    /// phone is supposed to be silent on the radio, so silence in the log is indistinguishable from
    /// correct behaviour. Now it is not.
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

    nonisolated private static let mirrorQueue = DispatchQueue(label: "com.loopkit.Loop.logMirror", qos: .utility)

    nonisolated private static func mirrorLogToICloud(from localStamped: URL) {
        mirrorQueue.async {
            let fm = FileManager.default
            guard let container = fm.url(forUbiquityContainerIdentifier: nil) else { return }   // iCloud off / not signed in
            let dir = container.appendingPathComponent("Documents", isDirectory: true)
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            try? fm.copyItem(at: localStamped, to: dir.appendingPathComponent(localStamped.lastPathComponent))
            let cloudLatest = dir.appendingPathComponent("g7watch-latest.log")
            // Atomic replace, never remove-then-copy: a crash or race between those two steps is
            // exactly how latest.log goes MISSING rather than merely stale.
            let tmp = dir.appendingPathComponent(".g7watch-latest.tmp")
            try? fm.removeItem(at: tmp)
            if (try? fm.copyItem(at: localStamped, to: tmp)) != nil {
                _ = try? fm.replaceItemAt(cloudLatest, withItemAt: tmp)
            }
            if let entries = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
                let stampedLogs = entries
                    .filter { $0.pathExtension == "log" && $0.lastPathComponent.hasPrefix("g7watch-") && $0.lastPathComponent != "g7watch-latest.log" }
                    .sorted { $0.lastPathComponent > $1.lastPathComponent }
                for old in stampedLogs.dropFirst(20) {
                    try? fm.removeItem(at: old)
                }
            }
        }
    }

    // MARK: - Watch state transitions

    /// The exact instant `isWatchAppInstalled` (or paired/complication) changes — the one thing the
    /// 60 s census cannot give us.
    ///
    /// WHY THIS MATTERS MORE THAN IT LOOKS. `WCSession.isWatchAppInstalled == false` makes WCSession
    /// QUEUE every message instead of delivering it, which silently breaks the loan's hand-back ACK:
    /// the phone commits, takes the pod back in a second, and the watch spins on "returning records"
    /// forever because the ack never lands. On 2026-08-19 that flag flapped five times in ninety
    /// minutes around install churn, and because we only sampled it every 60 s we could never say
    /// which install flipped it. A sampled level cannot be attributed to an event; a transition can.
    ///
    /// This also answers the open question directly: does installing the WATCH first and the phone
    /// workspace second leave the registration healthy, where the other order does not? Do each
    /// ordering once and read the transition lines.
    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        PhoneLog.event("link", "** WATCH STATE CHANGED ** paired=\(session.isPaired) "
            + "appInstalled=\(session.isWatchAppInstalled) reachable=\(session.isReachable) "
            + "activation=\(session.activationState.rawValue) "
            + "complication=\(session.isComplicationEnabled)")
    }
}
