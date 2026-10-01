//
//  PodLoanPhoneController+Settle.swift
//  Loop
//
//  Part of PodLoanPhoneController (see PodLoanPhoneController.swift). Split by concern; stored
//  properties live in the core class.
//
//  The window between the phone becoming owner again and the pod proving it. Being back at
//  .owner is a claim about authority, not about radio: the link still has to come up and a
//  fresh read still has to come back. Until that round-trip lands no grant may start and no
//  audit can rule.
//
//  A settle that never verifies is never treated as fine. It reaches its ceiling, says so, and
//  where a verdict was owed the loop opens.
//
//  Two failure shapes are worth telling apart in the log, and the chase reports both: the link
//  never came up at all, or the link came up and the reads kept returning the same stale sync
//  stamp. The first is a radio problem, the second a pump-manager caching one.
//

import Foundation
import HealthKit
import LoopKit
import LoopCore
import UserNotifications
import os.log

extension PodLoanPhoneController {

    /// Hard ceiling on the whole settle. Past it the phone stops waiting and states plainly that
    /// the round-trip never happened; it also bounds how long a grant can be refused as
    /// not-yet-ready.
    static let reclaimSettleTimeout: TimeInterval = .minutes(5)

    /// What a settle normally costs, and the only expectation the progress bar is drawn
    /// against — there is one stage, not a fast/slow split.
    static let reclaimSettleExpectation: TimeInterval = 10

    /// When to escalate to the pump manager's own recovery. Elapsed time is the trigger because
    /// this exists solely for the case where the link never came up at all, and there absence is
    /// the only evidence there is.
    static let reclaimEscalateAfter: TimeInterval = 12

    /// Opens the window. Called from every route back into `.owner`, and always BEFORE `.owner`
    /// is announced — an observer that sees ownership without a baseline draws a pod that is
    /// home when the phone has not reached it yet.
    func beginReclaimSettleWindow() {
        let started = deps.now()
        reclaimStartedAt = started
        reclaimEscalated = false
        reclaimVerifiedAt = nil
        syncUIMirror()
        reclaimVerifyInFlight = false
        reclaimLinkUpAt = nil
        reclaimStaleReads = 0

        // The display anchor is separate from the settle's own start so that a second window
        // opening moments after the first (a reclaim that immediately re-arms) keeps one
        // continuous elapsed count on screen instead of restarting the bar.
        if let anchor = reclaimDisplayAnchor, started.timeIntervalSince(anchor) < 60 {
        } else {
            reclaimDisplayAnchor = started
        }

        // Hold background execution for the whole settle. Without it a user who taps and pockets
        // the phone freezes this mid-flight, and the pod sits orphaned: released by the watch,
        // not yet taken by the phone, nobody dosing.
        deps.beginReclaimBackgroundTask()
        reclaimSettleWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, self.reclaimStartedAt == started else { return }
            os_log("Reclaim settle CEILING reached (%.0fs) without a verified round-trip — clearing anyway",
                   log: self.log, type: .error, Self.reclaimSettleTimeout)

            let ble = (self.deps.pumpManager() as? PumpConnectionLendable)?.connectionDiagnostics()
            self.handbackDiag(self.epoch, String(
                format: "settle CEILING at %.0fs — NO verified round-trip; clearing anyway · ble: %@",
                Self.reclaimSettleTimeout, ble ?? "no diagnostics from the pump manager"))
            self.reclaimStartedAt = nil
            self.syncUIMirror()
            self.reclaimDisplayAnchor = nil
            self.deps.endReclaimBackgroundTask()

            // "Cannot verify" is not "assume fine". A force reclaim was owed a verdict and the
            // pod never answered, so dosing resumes only in the sense that the pause is lifted —
            // the loop itself is opened and the user is told.
            if let pending = self.pendingHandbackAudit, pending.flavor == .forceReclaim {
                self.pendingHandbackAudit = nil
                self.handbackDiag(pending.epoch, "** R37: audit NEVER RAN — pod unreachable through the settle window. Session UNVERIFIED, loop OPENS **")
                self.deps.setAutomaticDosingPaused(false)
                self.deps.openLoopForUncertainReconciliation()
                self.armOpenLoopReminder()

                self.deps.issueUrgentNotice("Watch Session Unverified", Self.sessionUnverifiedBody)
            }
            self.deps.ownershipDidChange()
        }
        reclaimSettleWork = work

        // A WALL deadline, not a monotonic one: Dispatch's `.now() + delay` freezes while iOS
        // suspends the app and then appends the suspension, so a locked phone turns a
        // five-minute ceiling into an unbounded one.
        queue.asyncAfter(wallDeadline: .now() + Self.reclaimSettleTimeout, execute: work)
        chaseReclaimVerification(started: started)
    }

    /// Polls every couple of seconds until the round-trip lands or the ceiling fires. `started`
    /// identifies the window: a later settle replaces `reclaimStartedAt`, and every rung of the
    /// older chase then retires itself.
    func chaseReclaimVerification(started: Date, attempt: Int = 0) {
        guard reclaimStartedAt == started, reclaimVerifiedAt == nil else { return }

        if reclaimLinkUpAt == nil, deps.isConnectionReady() {
            let up = deps.now()
            reclaimLinkUpAt = up
            let waited = up.timeIntervalSince(started)

            handbackDiag(epoch, String(format: "settle: link up +%.1fs (tick %d)", waited, attempt))
        }

        // Escalate once per settle, and only while the link has NEVER come up. Once it is up
        // there is nothing for an escalation to find.
        if reclaimLinkUpAt == nil, !reclaimEscalated,
           deps.now().timeIntervalSince(started) >= Self.reclaimEscalateAfter,
           let lendable = deps.pumpManager() as? PumpConnectionLendable {
            reclaimEscalated = true
            let bleBefore = lendable.connectionDiagnostics() ?? "none"
            let outcome = lendable.escalateConnectionReclaim() ?? "the pump manager had nothing to escalate"
            handbackDiag(epoch, String(format: "settle: link still down at +%.0fs — escalating: %@ · ble before: %@",
                                       deps.now().timeIntervalSince(started), outcome, bleBefore))
        }

        attemptReclaimVerificationNow(started: started)
        // Re-arm unconditionally. The ceiling, not this loop, is what ends a settle: a chase
        // that stopped on its own would leave the window open with nothing driving it.
        queue.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.chaseReclaimVerification(started: started, attempt: attempt + 1)
        }
    }

    /// One verification attempt. Verified means a reading that came back AFTER this window
    /// opened — nothing weaker counts, because the phone is trying to prove it can reach the pod
    /// now, not that it could at some point in the past.
    func attemptReclaimVerificationNow(started: Date) {
        guard reclaimStartedAt == started, reclaimVerifiedAt == nil else { return }
        if deps.isConnectionReady(), !reclaimVerifyInFlight, let pump = deps.pumpManager() {
            reclaimVerifyInFlight = true
            let read: (@escaping (Date?) -> Void) -> Void
            // A FORCED read first where the pump manager offers one: `ensureCurrentPumpData`
            // skips the radio when its data is recent and hands back the same old `lastSync`,
            // which this window rejects — forever, on every tick, while the pod sits reachable.
            if let lendable = pump as? PumpConnectionLendable {
                read = { done in
                    lendable.refreshLentDeviceStatus { _ in pump.ensureCurrentPumpData { done($0) } }
                }
            } else {
                read = { done in pump.ensureCurrentPumpData { done($0) } }
            }
            read { [weak self] lastSync in
                guard let self = self else { return }
                self.queue.async {
                    self.reclaimVerifyInFlight = false
                    guard self.reclaimStartedAt == started, self.reclaimVerifiedAt == nil else { return }

                    // The proof: a sync stamp from AFTER this window opened. Anything earlier is
                    // the pump manager returning what it already had.
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

                        // Keep the leading phrase of this line as it is. A long series of
                        // captured settles is parsed off it, so new fields append rather than
                        // replace.
                        self.handbackDiag(self.epoch,
                            String(format: "reclaim VERIFIED — pod round-trip complete +%.0fs (link +%.1fs, stale reads %d, read +%.1fs)",
                                   elapsed, linkWait, self.reclaimStaleReads, readWait))
                        self.deps.ownershipDidChange()

                        self.finishPendingHandbackAudit(elapsed: elapsed)
                    } else {
                        // A read that came back without advancing the sync stamp. Counted and
                        // reported, because a settle that ends at its ceiling with a high count
                        // failed differently from one where the link never came up at all.
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

    /// The end of a loan: read the pod's delivery total, rule on it, and only then cancel the
    /// temp the watch left running.
    ///
    /// This runs at the verified round-trip because that is the one instant in the whole
    /// hand-back where the pod is provably reachable. Order matters — the reading has to
    /// describe the loan, not the cancel this method is about to issue.
    ///
    /// An audit CONSUMES its anchors, hence the unconditional clear: anchors describe exactly
    /// one loan, and any left behind make the next take-back audit a session that already
    /// closed and report its insulin as unexplained.
    func finishPendingHandbackAudit(elapsed: TimeInterval) {
        defer { clearAuditAnchors() }
        guard let pending = pendingHandbackAudit else { return }
        pendingHandbackAudit = nil

        if let latest = (deps.pumpManager() as? PumpConnectionLendable)?.lentDeviceInsulinDelivered {
            let delivered = latest - pending.deliveredAtStart
            // Quantize to milli-units BEFORE any band comparison. Binary arithmetic turns
            // 2.400 − 2.200 into 0.20000000000000018, and the verdict must turn on the pulse
            // grid rather than on float dust one ulp outside the band.
            let residual = ((delivered - pending.expected) * 1000).rounded() / 1000

            // Two figures: the residual above is the VERDICT window, which accepted checkpoints
            // may have narrowed to the last unreconciled stretch; this one spans the whole loan
            // and is reported for context only.
            let loanDelivered = pending.takeoverUnits.map { latest - $0 }
            let loanResidual: Double? = {
                guard let d = loanDelivered, let e = pending.wholeLoanExpected else { return nil }
                return d - e
            }()

            let drift = pending.watchLatest.map { latest - $0 }
            handbackDiag(pending.epoch, String(format:
                "reconcile[%@]: delivered=%.3f expected=%.3f residual=%+.3f (tol 0.05) · loan total %@ resid %@ · %d checkpoint(s) · loanMin=%.0f cycles=%d · odometer read by PHONE +%.0fs after reclaim · vs watch endpoint %@ (watch fresh=%@)",
                pending.flavor == .forceReclaim ? "FORCE-RECLAIM" : "AUTHORITATIVE",
                delivered, pending.expected, residual,
                loanDelivered.map { String(format: "%.3f", $0) } ?? "n/a",
                loanResidual.map { String(format: "%+.3f", $0) } ?? "n/a",
                checkpointsThisLoan,
                pending.loanMinutes, pending.cycles, elapsed,
                drift.map { String(format: "%+.3f", $0) } ?? "n/a",
                pending.watchFreshened ? "Y" : "N"))
            UserDefaults.standard.set(loanDelivered ?? delivered, forKey: Keys.deliveredAuthoritative)

            // Drift tripwire: every window reconciled, yet the loan total did not. Diagnostic
            // only and never an action — quantization drift is same-signed too, so this pattern
            // does not distinguish a real leak from arithmetic.
            if let lr = loanResidual, abs(lr) > 0.5, abs(residual) <= Self.checkpointBand {
                handbackDiag(pending.epoch, String(format:
                    "** [checkpoint] loan-total residual %+.3f U exceeds ±0.5 while every window reconciled — possible systematic drip; diagnostic only **", lr))
            }
            switch pending.flavor {
            case .handback:

                // Bank ONLY on a clean hand-back. A force reclaim's residual measures a watch
                // whose records never arrived, and banking those poisons the statistics the
                // threshold review reads.
                bankResidual(loanResidual ?? residual,
                             worstWindow: max(worstWindowThisLoan, abs(residual)),
                             epoch: pending.epoch)
                applyReconciliationVerdict(residual: residual, epoch: pending.epoch)
            case .forceReclaim:
                applyForceReclaimVerdict(residual: residual, epoch: pending.epoch)
            }
        } else if pending.flavor == .forceReclaim {
            // Reachable, but no delivery total came back. For a force reclaim that is still
            // "cannot verify", and it gets the same treatment as the ceiling above.
            handbackDiag(pending.epoch, "** R37: reclaim round-trip landed but no odometer — session UNVERIFIED, loop OPENS **")
            deps.setAutomaticDosingPaused(false)
            deps.openLoopForUncertainReconciliation()
            armOpenLoopReminder()
            deps.issueUrgentNotice("Watch Session Unverified", Self.sessionUnverifiedBody)
        } else {
            // A clean hand-back with no reading is different: the watch's records are already
            // committed and its own provisional figures stand. Nothing is opened over it.
            handbackDiag(pending.epoch, "reconcile[AUTHORITATIVE]: pod reachable but reported no odometer — keeping the provisional line")
        }

        // Now the cancel. No automatic program outlives the controller that set it — but the
        // watch has no link by this point, so the phone is the device that enforces it, and it
        // does so only after the reading above has described the loan. A failure here is not
        // fatal: the pod keeps the watch's last rate, which is therapy rather than a gap, until
        // the phone's next cycle.
        deps.cancelTempBasalAfterPodReturn { [weak self] error in
            guard let self = self else { return }
            self.queue.async {
                if let error = error {
                    self.handbackDiag(pending.epoch, "R33 temp cancel FAILED — pod keeps the watch's temp until the next cycle · \(String(describing: error))")
                } else {
                    self.handbackDiag(pending.epoch, "R33 temp cancelled — pod reverts to the user's schedule until the phone's next reading")
                }
            }
        }
    }
}
