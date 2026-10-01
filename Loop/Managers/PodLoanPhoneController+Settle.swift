//
//  PodLoanPhoneController+Settle.swift
//  Loop
//
//  The settle window: from the phone owning the pod again until a fresh pod read proves it.
//  No grant starts and no audit rules until then; a settle that never verifies opens the loop
//  where a verdict was owed.
//

import Foundation
import HealthKit
import LoopKit
import LoopCore
import UserNotifications
import os.log

extension PodLoanPhoneController {

    /// Ceiling on the settle; also bounds how long a grant can be refused as not-yet-ready.
    static let reclaimSettleTimeout: TimeInterval = .minutes(5)

    /// A typical settle; the progress bar is drawn against it.
    static let reclaimSettleExpectation: TimeInterval = 10

    /// Escalate to the pump manager's recovery when the link has not come up by then.
    static let reclaimEscalateAfter: TimeInterval = 12

    /// Called on every route back to `.owner`, before `.owner` is announced.
    func beginReclaimSettleWindow() {
        let started = deps.now()
        reclaimStartedAt = started
        reclaimEscalated = false
        reclaimVerifiedAt = nil
        syncUIMirror()
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
            os_log("Reclaim settle CEILING reached (%.0fs) without a verified round-trip — clearing anyway",
                   log: self.log, type: .error, Self.reclaimSettleTimeout)

            let ble = (self.deps.pumpManager() as? ExclusiveDeviceControl)?.connectionDiagnostics()
            self.handbackDiag(self.epoch, String(
                format: "settle CEILING at %.0fs — NO verified round-trip; clearing anyway · ble: %@",
                Self.reclaimSettleTimeout, ble ?? "no diagnostics from the pump manager"))
            self.reclaimStartedAt = nil
            self.syncUIMirror()
            self.reclaimDisplayAnchor = nil
            self.deps.endReclaimBackgroundTask()

            self.resolveOwedForceReclaimAudit(why: "pod unreachable through the settle window")
            self.deps.ownershipDidChange()
        }
        reclaimSettleWork = work

        // Wall deadline: a monotonic one stops while the app is suspended.
        queue.asyncAfter(wallDeadline: .now() + Self.reclaimSettleTimeout, execute: work)
        chaseReclaimVerification(started: started)
    }

    /// Ends the window early, for a phone that has stopped trying to hold the pod. Left open, the
    /// chase would escalate at +12 s and lift the release, the phone's dosing gate.
    func closeReclaimSettleWindow(reason: String) {
        guard reclaimStartedAt != nil else { return }
        handbackDiag(epoch, "settle window CLOSED early — \(reason)")

        reclaimSettleWork?.cancel()
        reclaimSettleWork = nil
        reclaimStartedAt = nil
        reclaimDisplayAnchor = nil
        reclaimVerifyInFlight = false
        deps.endReclaimBackgroundTask()

        // The ceiling would have resolved an owed verdict; closing early inherits that duty.
        resolveOwedForceReclaimAudit(why: reason)
        syncUIMirror()
    }

    /// A force-reclaim verdict the pod will never answer: lift the pause, open the loop, tell the user.
    func resolveOwedForceReclaimAudit(why: String) {
        guard let pending = pendingHandbackAudit, pending.flavor == .forceReclaim else { return }
        pendingHandbackAudit = nil
        handbackDiag(pending.epoch, "** force-reclaim audit NEVER RAN — \(why). Session UNVERIFIED, loop OPENS **")
        deps.setAutomaticDosingPaused(false)
        deps.openLoopForUncertainReconciliation()
        armOpenLoopReminder()
        deps.issueUrgentNotice("Watch Session Unverified", Self.sessionUnverifiedBody)
    }

    /// Polls every 2 s until the round-trip lands or the ceiling fires; `started` names the window.
    func chaseReclaimVerification(started: Date, attempt: Int = 0) {
        guard reclaimStartedAt == started, reclaimVerifiedAt == nil else { return }

        // Backstop: never chase, or escalate for, a pod this phone is not holding.
        guard state == .owner, !yieldingToInferredLoan else {
            handbackDiag(epoch, "settle chase STOOD DOWN at tick \(attempt) — the phone is not holding the pod (state \(state.rawValue)\(yieldingToInferredLoan ? ", yielded to an inferred loan" : ""))")
            return
        }

        if reclaimLinkUpAt == nil, deps.isConnectionReady() {
            let up = deps.now()
            reclaimLinkUpAt = up
            let waited = up.timeIntervalSince(started)

            handbackDiag(epoch, String(format: "settle: link up +%.1fs (tick %d)", waited, attempt))
        }

        // Once per settle, and only while the link has never come up.
        if reclaimLinkUpAt == nil, !reclaimEscalated,
           deps.now().timeIntervalSince(started) >= Self.reclaimEscalateAfter,
           let control = deps.pumpManager() as? ExclusiveDeviceControl {
            reclaimEscalated = true
            let bleBefore = control.connectionDiagnostics() ?? "none"
            let outcome = control.escalateTakeControl() ?? "the pump manager had nothing to escalate"
            handbackDiag(epoch, String(format: "settle: link still down at +%.0fs — escalating: %@ · ble before: %@",
                                       deps.now().timeIntervalSince(started), outcome, bleBefore))
        }

        attemptReclaimVerificationNow(started: started)
        // Always re-arm: the ceiling, not this loop, ends a settle.
        queue.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.chaseReclaimVerification(started: started, attempt: attempt + 1)
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
                    odometer.refreshDeliveredUnits { _ in pump.ensureCurrentPumpData { done($0) } }
                }
            } else {
                read = { done in pump.ensureCurrentPumpData { done($0) } }
            }
            read { [weak self] lastSync in
                guard let self = self else { return }
                self.queue.async {
                    self.reclaimVerifyInFlight = false
                    guard self.reclaimStartedAt == started, self.reclaimVerifiedAt == nil else { return }

                    if let sync = lastSync, sync > started {
                        let elapsed = self.deps.now().timeIntervalSince(started)
                        self.reclaimVerifiedAt = self.deps.now()
                        self.reclaimSettleWork?.cancel()
                        self.reclaimStartedAt = nil
                        self.syncUIMirror()
                        self.reclaimDisplayAnchor = nil
                        self.deps.endReclaimBackgroundTask()

                        let linkWait = self.reclaimLinkUpAt.map { $0.timeIntervalSince(started) } ?? elapsed
                        let readWait = max(elapsed - linkWait, 0)

                        // Log analysis parses this prefix: append fields, don't reword it.
                        self.handbackDiag(self.epoch,
                            String(format: "reclaim VERIFIED — pod round-trip complete +%.0fs (link +%.1fs, stale reads %d, read +%.1fs)",
                                   elapsed, linkWait, self.reclaimStaleReads, readWait))
                        self.deps.ownershipDidChange()

                        self.finishPendingHandbackAudit(elapsed: elapsed)
                    } else {
                        // Stale read: counted, to tell a caching failure from a radio one.
                        self.reclaimStaleReads += 1
                        os_log("Settle: status read %d did not advance lastSync — link %{public}@",
                               log: self.log, type: .default, self.reclaimStaleReads,
                               self.reclaimLinkUpAt == nil ? "still down" : "already up")

                        PhoneLog.event("loan", String(format: "e%d settle: read %d stale — link %@",
                                                      self.epoch, self.reclaimStaleReads,
                                                      self.reclaimLinkUpAt == nil ? "still down" : "already up"))
                    }
                }
            }
        }
    }

    /// At the verified round-trip: read the pod's total, rule on the loan, then cancel the
    /// watch's temp. The audit consumes its anchors either way.
    func finishPendingHandbackAudit(elapsed: TimeInterval) {
        defer { clearAuditAnchors() }
        guard let pending = pendingHandbackAudit else { return }
        pendingHandbackAudit = nil

        if let latest = (deps.pumpManager() as? PumpDeliveryOdometer)?.deliveredUnits?.units {
            let delivered = latest - pending.deliveredAtStart
            // Milli-units, so the band comparison is not decided by float error.
            let residual = ((delivered - pending.expected) * 1000).rounded() / 1000

            // Whole-loan figure, for the log only; the verdict uses the window above.
            let loanDelivered = pending.takeoverUnits.map { latest - $0 }
            let loanResidual: Double? = {
                guard let d = loanDelivered, let e = pending.wholeLoanExpected else { return nil }
                return d - e
            }()

            let drift = pending.watchLatest.map { latest - $0 }
            handbackDiag(pending.epoch, String(format:
                "reconcile[%@]: delivered=%.3f expected=%.3f residual=%+.3f (band ±0.20) · loan total %@ resid %@ · %d checkpoint(s) · loanMin=%.0f cycles=%d · odometer read by PHONE +%.0fs after reclaim · vs watch endpoint %@ (watch fresh=%@)",
                pending.flavor == .forceReclaim ? "FORCE-RECLAIM" : "AUTHORITATIVE",
                delivered, pending.expected, residual,
                loanDelivered.map { String(format: "%.3f", $0) } ?? "n/a",
                loanResidual.map { String(format: "%+.3f", $0) } ?? "n/a",
                checkpointsThisLoan,
                pending.loanMinutes, pending.cycles, elapsed,
                drift.map { String(format: "%+.3f", $0) } ?? "n/a",
                pending.watchFreshened ? "Y" : "N"))

            // Diagnostic only: windows reconciled but the loan total drifted.
            if let lr = loanResidual, abs(lr) > 0.5, abs(residual) <= Self.checkpointBand {
                handbackDiag(pending.epoch, String(format:
                    "** [checkpoint] loan-total residual %+.3f U exceeds ±0.5 while every window reconciled — possible systematic drip; diagnostic only **", lr))
            }
            switch pending.flavor {
            case .handback:
                applyReconciliationVerdict(residual: residual, epoch: pending.epoch)
            case .forceReclaim:
                applyForceReclaimVerdict(residual: residual, epoch: pending.epoch)
            }
        } else if pending.flavor == .forceReclaim {
            // No delivery total: a force reclaim is still unverified.
            handbackDiag(pending.epoch, "** force-reclaim round-trip landed but no odometer — session UNVERIFIED, loop OPENS **")
            deps.setAutomaticDosingPaused(false)
            deps.openLoopForUncertainReconciliation()
            armOpenLoopReminder()
            deps.issueUrgentNotice("Watch Session Unverified", Self.sessionUnverifiedBody)
        } else {
            // A clean hand-back keeps its committed records; nothing opens.
            handbackDiag(pending.epoch, "reconcile[AUTHORITATIVE]: pod reachable but reported no odometer — keeping the provisional line")
        }

        // The watch's temp ends here, after the reading. On failure it runs until the next cycle.
        deps.cancelTempBasalAfterPodReturn { [weak self] error in
            guard let self = self else { return }
            self.queue.async {
                if let error = error {
                    self.handbackDiag(pending.epoch, "temp cancel FAILED — pod keeps the watch's temp until the next cycle · \(String(describing: error))")
                } else {
                    self.handbackDiag(pending.epoch, "temp cancelled — pod reverts to the user's schedule until the phone's next reading")
                }
            }
        }
    }
}
