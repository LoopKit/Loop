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

    /// Ceiling on the settle; also bounds how long a grant can be refused as not-yet-ready.
    static let reclaimSettleTimeout: TimeInterval = .minutes(5)

    /// A typical settle; the progress bar is drawn against it.
    static let reclaimSettleExpectation: TimeInterval = 10

    /// Called on every route back to `.owner`, before `.owner` is announced.
    func beginReclaimSettleWindow() {
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

            self.noteForceReclaimAuditStillOwed(why: "the pod did not answer while reconnecting")
            self.deps.ownershipDidChange()
        }
        reclaimSettleWork = work

        // Wall deadline: a monotonic one stops while the app is suspended.
        DispatchQueue.main.asyncAfter(wallDeadline: .now() + Self.reclaimSettleTimeout, execute: work)
        chaseReclaimVerification(started: started)
    }

    /// Ends the window early, for a phone that has stopped trying to hold the pod.
    func closeReclaimSettleWindow(reason: String) {
        guard reclaimStartedAt != nil else { return }
        handbackDiag(epoch, "stopped reconnecting to the pod: \(reason)")

        reclaimSettleWork?.cancel()
        reclaimSettleWork = nil
        reclaimStartedAt = nil
        reclaimDisplayAnchor = nil
        reclaimVerifyInFlight = false
        deps.endReclaimBackgroundTask()

        noteForceReclaimAuditStillOwed(why: reason)
    }

    /// The window closed without the pod answering, its link lost after the take-back. The check
    /// stays owed and dosing stays held: a phone that cannot reach the pod cannot dose it.
    /// `considerOwedForceReclaimAudit` runs it later.
    func noteForceReclaimAuditStillOwed(why: String) {
        guard let pending = pendingHandbackAudit, pending.flavor == .forceReclaim else { return }
        handbackDiag(pending.epoch, "take-back check still owed: \(why); dosing stays paused until the pod answers")
    }

    /// Called every phone cycle. Reopens the settle for a check still owed once the pod is reachable.
    func considerOwedForceReclaimAudit() {
        guard let pending = self.pendingHandbackAudit, pending.flavor == .forceReclaim,
              self.reclaimStartedAt == nil, self.state == .owner, !self.yieldingToInferredLoan,
              self.deps.isConnectionReady() else { return }
        self.handbackDiag(pending.epoch, "take-back check owed and the pod is reachable: reading it now")
        self.beginReclaimSettleWindow()
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
        // Always re-arm: the ceiling, not this loop, ends a settle.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.chaseReclaimVerification(started: started)
        }
    }

    /// Verified means a reading newer than the window's start.
    func attemptReclaimVerificationNow(started: Date) {
        guard reclaimStartedAt == started, reclaimVerifiedAt == nil else { return }
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
                        self.reclaimVerifiedAt = self.deps.now()
                        self.reclaimSettleWork?.cancel()
                        self.reclaimStartedAt = nil
                        self.reclaimDisplayAnchor = nil
                        self.deps.endReclaimBackgroundTask()

                        let linkWait = self.reclaimLinkUpAt.map { $0.timeIntervalSince(started) } ?? elapsed
                        self.handbackDiag(self.epoch,
                            String(format: "back in control of the pod after %.0f s: link up at %.1f s, %d stale reads",
                                   elapsed, linkWait, self.reclaimStaleReads))
                        self.deps.ownershipDidChange()

                        self.finishPendingHandbackAudit()
                    } else {
                        // Stale read: counted, to tell a caching failure from a radio one.
                        self.reclaimStaleReads += 1
                    }
                }
            }
        }
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
