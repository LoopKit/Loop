//
//  PodLoanPhoneController+Settle.swift
//  Loop
//
//  The settle window: from the phone owning the pod again until a fresh pod read proves it.
//  No grant starts and no audit rules until then; a verdict still owed when the window closes
//  waits, with dosing held, for the pod to answer.
//

import Foundation
import HealthKit
import LoopKit
import LoopCore
import UserNotifications

extension PodLoanPhoneController {

    /// Ceiling on the settle, and when the looper is told the pod has not answered.
    static let reclaimSettleTimeout: TimeInterval = .minutes(5)

    static let podUnreachedTitle = NSLocalizedString("iPhone Can't Reach the Pod", comment: "Phone notice title: the phone has the pod again after Sport Mode and has not reached it for five minutes")
    static let podUnreachedBody = NSLocalizedString("Nobody is looping. Start Sport Mode again to resume looping.", comment: "Phone notice body: the phone has the pod again after Sport Mode and has not reached it for five minutes")

    /// The phone has the pod again, by the looper's End or any other route, and may be out of its reach
    /// (control row 31): the watch reaches this phone over Wi-Fi where the pod's radio does not. Nobody
    /// loops then, and the looper is told when the settle gives up. Scheduled now and withdrawn at the
    /// pod's answer, so it needs no run time on a phone iOS has suspended.
    func schedulePodUnreachedNotice() {
        scheduleNotification(id: NotificationID.podUnreached, title: Self.podUnreachedTitle, body: Self.podUnreachedBody,
                             delay: Self.reclaimSettleTimeout, repeats: false, interruptionLevel: .timeSensitive)
    }

    /// A typical settle; the progress bar is drawn against it.
    static let reclaimSettleExpectation: TimeInterval = 10

    /// Called on every route back to `.owner`, before `.owner` is announced.
    func beginReclaimSettleWindow() {
        // No pod to reach: it was deactivated on the watch and forgotten.
        if reclaimForgotPod {
            reclaimDisplayAnchor = nil
            deps.endReclaimBackgroundTask()
            return
        }
        let started = deps.now()
        reclaimStartedAt = started
        reclaimVerifiedAt = nil
        reclaimVerifyInFlight = false
        reclaimLinkUpAt = nil
        reclaimStaleReads = 0

        // A window reopened within a minute keeps the on-screen elapsed count running.
        if let anchor = reclaimDisplayAnchor, started.timeIntervalSince(anchor) < 60 {
        } else {
            reclaimDisplayAnchor = started
        }

        schedulePodUnreachedNotice()

        // Background time for the whole settle, so pocketing the phone cannot orphan the pod.
        deps.beginReclaimBackgroundTask()
        reclaimSettleWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, self.reclaimStartedAt == started else { return }
            self.handbackDiag(self.epoch, String(
                format: "gave up reconnecting to the pod after %.0f s without a verified round-trip, %d stale reads",
                Self.reclaimSettleTimeout, self.reclaimStaleReads))
            self.reclaimStartedAt = nil
            self.reclaimDisplayAnchor = nil
            self.deps.endReclaimBackgroundTask()

            self.noteAuditStillOwed(why: "the pod did not answer while reconnecting")
            self.deps.ownershipDidChange()
        }
        reclaimSettleWork = work

        // Wall deadline: a monotonic one stops while the app is suspended.
        DispatchQueue.main.asyncAfter(wallDeadline: .now() + Self.reclaimSettleTimeout, execute: work)
        chaseReclaimVerification(started: started)
    }

    /// Ends the window early, for a phone that has stopped trying to hold the pod.
    func closeReclaimSettleWindow(reason: String) {
        // Pending or already shown: this phone no longer means to hold the pod.
        cancelNotification(id: NotificationID.podUnreached)
        guard reclaimStartedAt != nil else { return }
        handbackDiag(epoch, "stopped reconnecting to the pod: \(reason)")

        reclaimSettleWork?.cancel()
        reclaimSettleWork = nil
        reclaimStartedAt = nil
        reclaimDisplayAnchor = nil
        reclaimVerifyInFlight = false
        deps.endReclaimBackgroundTask()

        noteAuditStillOwed(why: reason)
    }

    /// The window closed without the pod answering. The loan's insulin check stays owed, after a
    /// hand-back as after a take-back, and `considerOwedAudit` runs it once the pod is reachable. A
    /// take-back's also holds dosing: the watch's records may be incomplete. A hand-back brought them all.
    func noteAuditStillOwed(why: String) {
        guard let pending = pendingHandbackAudit else { return }
        handbackDiag(pending.epoch, pending.flavor == .forceReclaim
            ? "take-back check still owed: \(why); dosing stays paused until the pod answers"
            : "hand-back check still owed: \(why); it is made when the pod answers")
    }

    /// Called every phone cycle. Reopens the settle for a check still owed once the pod is reachable.
    func considerOwedAudit() {
        guard let pending = self.pendingHandbackAudit,
              self.reclaimStartedAt == nil, self.state == .owner, !self.yieldingToInferredLoan,
              self.deps.isConnectionReady() else { return }
        self.handbackDiag(pending.epoch, "\(pending.flavor == .forceReclaim ? "take-back" : "hand-back") check owed and the pod is reachable: reading it now")
        self.beginReclaimSettleWindow()
    }

    /// A new loan starts before this phone has read the pod after the last one, so the next reading of
    /// the pod is the watch's: by this phone's grant, or by adopting a loan the watch started without it.
    /// An open settle ends. A hand-back's check still owed is made on the watch's own last reading, which
    /// came with the hand-back; a take-back's stays owed, as when its window closes.
    func closeLastLoansCheckBeforeANewLoan() {
        if let pending = pendingHandbackAudit, pending.flavor == .handback {
            ruleOnWatchReading(pending, because: "a new loan starts before this phone read the pod")
        }
        closeReclaimSettleWindow(reason: "a new loan starts")
    }

    /// Polls every 2 s until the round-trip lands or the ceiling fires; `started` names the window.
    func chaseReclaimVerification(started: Date) {
        guard reclaimStartedAt == started, reclaimVerifiedAt == nil else { return }

        // Backstop: never chase a pod this phone is not holding.
        guard state == .owner, !yieldingToInferredLoan else {
            handbackDiag(epoch, "reconnect stopped: this phone is \(yieldingToInferredLoan ? "standing aside" : "in state \(state.rawValue)")")
            return
        }

        if reclaimLinkUpAt == nil, deps.isConnectionReady() {
            reclaimLinkUpAt = deps.now()
        }

        attemptReclaimVerificationNow(started: started)
        // Always re-arm: the ceiling, not this loop, ends a settle. A timer is safe here: it runs inside
        // the take-back's background time, and the ceiling is a wall-clock deadline checked on each run.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.chaseReclaimVerification(started: started)
        }
    }

    /// Verified means a reading newer than the window's start, or a final one.
    func attemptReclaimVerificationNow(started: Date) {
        guard reclaimStartedAt == started, reclaimVerifiedAt == nil else { return }
        // A failed pump refuses reads, and its last total, however early, is final.
        if let odometer = deps.pumpManager() as? PumpDeliveryOdometer, odometer.deliveredUnitsAreFinal,
           odometer.deliveredUnits != nil {
            noteReclaimVerified(started: started, how: "the pump has stopped for good, so its last total is final")
            return
        }
        if deps.isConnectionReady(), !reclaimVerifyInFlight, let pump = deps.pumpManager() {
            reclaimVerifyInFlight = true
            let read: (@escaping (Date?) -> Void) -> Void
            // Force a real read where offered: `ensureCurrentPumpData` alone can return a cached `lastSync`.
            if let odometer = pump as? PumpDeliveryOdometer {
                read = { done in
                    Task {
                        _ = await odometer.refreshDeliveredUnits()
                        pump.ensureCurrentPumpData { done($0) }
                    }
                }
            } else {
                read = { done in pump.ensureCurrentPumpData { done($0) } }
            }
            read { [weak self] lastSync in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    self.reclaimVerifyInFlight = false
                    guard self.reclaimStartedAt == started, self.reclaimVerifiedAt == nil else { return }

                    if let sync = lastSync, sync > started {
                        let elapsed = self.deps.now().timeIntervalSince(started)
                        let linkWait = self.reclaimLinkUpAt.map { $0.timeIntervalSince(started) } ?? elapsed
                        self.noteReclaimVerified(started: started, how: String(format: "link up at %.1f s, %d stale reads",
                                                                               linkWait, self.reclaimStaleReads))
                    } else {
                        // Stale read: counted, to tell a caching failure from a radio one.
                        self.reclaimStaleReads += 1
                    }
                }
            }
        }
    }

    private func noteReclaimVerified(started: Date, how: String) {
        let elapsed = deps.now().timeIntervalSince(started)
        reclaimVerifiedAt = deps.now()
        cancelNotification(id: NotificationID.podUnreached)
        reclaimSettleWork?.cancel()
        reclaimStartedAt = nil
        reclaimDisplayAnchor = nil
        deps.endReclaimBackgroundTask()

        handbackDiag(epoch, String(format: "back in control of the pod after %.0f s: %@", elapsed, how))
        deps.ownershipDidChange()

        finishPendingHandbackAudit()
    }

    /// At the verified round-trip: read the pod's total, rule on the loan, then cancel the watch's
    /// temp. The reading ends the watch's window and starts this phone's, verdict or not.
    func finishPendingHandbackAudit() {
        let reading = (deps.pumpManager() as? PumpDeliveryOdometer)?.deliveredUnits
        defer {
            if let reading { noteReading(units: reading.units, at: reading.at) }
            loanStartedAt = nil
        }
        guard let pending = pendingHandbackAudit else {
            // No audit (a hand-back that came without a pod reading): the watch's temp still ends here.
            cancelWatchTemp(epoch: epoch)
            return
        }
        // The dosing hold lifts last, after the verdict is dispatched.
        defer { pendingHandbackAudit = nil }

        if let reading {
            let latest = reading.units
            let delivered = latest - pending.deliveredAtStart
            // Milli-units, so the band comparison is not decided by float error.
            let residual = ((delivered - pending.expected) * 1000).rounded() / 1000

            let drift = pending.watchLatest.map { latest - $0 }
            handbackDiag(pending.epoch, String(format:
                "%@ check: delivered %.3f U, expected %.3f U, residual %+.3f U over %.0f min%@",
                pending.flavor == .forceReclaim ? "take-back" : "hand-back",
                delivered, pending.expected, residual, pending.loanMinutes,
                drift.map { String(format: "; %+.3f U since the watch's last reading", $0) } ?? ""))

            switch pending.flavor {
            case .handback:
                applyReconciliationVerdict(residual: residual, epoch: pending.epoch)
            case .forceReclaim:
                applyForceReclaimVerdict(residual: residual, epoch: pending.epoch,
                                         window: DateInterval(start: pending.windowStart, end: max(reading.at, pending.windowStart)))
            }
        } else if pending.flavor == .forceReclaim {
            // A pump that gives no delivered total: nothing to check against.
            handbackDiag(pending.epoch, "insulin not verified after take-back: the pod gave no total")
            deps.issueUrgentNotice(Self.sessionUnverifiedTitle, Self.sessionUnverifiedBody)
        } else {
            // A clean hand-back keeps its committed records; nothing opens.
            handbackDiag(pending.epoch, "hand-back check: the pod gave no total; the watch's count stands")
        }

        // The watch's temp ends here, after the reading.
        cancelWatchTemp(epoch: pending.epoch)
    }

    /// The phone will not read the pod for this loan (it was deactivated on the watch, or a new loan
    /// starts first): the watch's last reading, which came with the hand-back, stands in. A take-back has
    /// none, and nothing is ruled.
    func ruleOnWatchReading(_ pending: PendingHandbackAudit, because why: String = "the pod was deactivated on the watch") {
        defer {
            pendingHandbackAudit = nil
            loanStartedAt = nil
        }
        guard pending.flavor == .handback, let latest = pending.watchLatest else {
            handbackDiag(pending.epoch, "no insulin check: \(why), and no reading of the pod came home")
            return
        }
        let delivered = latest - pending.deliveredAtStart
        let residual = ((delivered - pending.expected) * 1000).rounded() / 1000
        handbackDiag(pending.epoch, String(format:
            "hand-back check on the watch's last reading (%@): delivered %.3f U, expected %.3f U, residual %+.3f U over %.0f min",
            why, delivered, pending.expected, residual, pending.loanMinutes))
        applyReconciliationVerdict(residual: residual, epoch: pending.epoch)
    }

    /// On failure the watch's temp runs until the phone's next cycle.
    private func cancelWatchTemp(epoch: Int) {
        deps.cancelTempBasalAfterPodReturn { [weak self] error in
            guard let self = self else { return }
            DispatchQueue.main.async {
                if let error = error {
                    self.handbackDiag(epoch, "could not cancel the watch's temp; it runs until the next loop cycle: \(String(describing: error))")
                } else {
                    self.handbackDiag(epoch, "temp cancelled: the pod runs the scheduled basal until the phone's next cycle")
                }
            }
        }
    }
}
