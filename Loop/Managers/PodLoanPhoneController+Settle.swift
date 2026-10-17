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

            self.noteForceReclaimAuditStillOwed(why: "pod unreachable through the settle window")
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

        noteForceReclaimAuditStillOwed(why: reason)
        syncUIMirror()
    }

    /// The window closed without the pod answering, its link lost after the take-back. The check
    /// stays owed and dosing stays held: a phone that cannot reach the pod cannot dose it.
    /// `considerOwedForceReclaimAudit` runs it later.
    func noteForceReclaimAuditStillOwed(why: String) {
        guard let pending = pendingHandbackAudit, pending.flavor == .forceReclaim else { return }
        handbackDiag(pending.epoch, "force-reclaim audit still OWED — \(why). It runs when the pod next answers; dosing stays held until then")
    }

    /// Called every phone cycle. Reopens the settle for a check still owed once the pod is reachable.
    func considerOwedForceReclaimAudit() {
        queue.async {
            guard let pending = self.pendingHandbackAudit, pending.flavor == .forceReclaim,
                  self.reclaimStartedAt == nil, self.state == .owner, !self.yieldingToInferredLoan,
                  self.deps.isConnectionReady() else { return }
            self.handbackDiag(pending.epoch, "force-reclaim audit owed and the pod is reachable — reading it now")
            self.beginReclaimSettleWindow()
        }
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

    /// At the verified round-trip: read the pod's total, rule on the loan, then cancel the watch's
    /// temp. The reading ends the watch's window and starts this phone's, verdict or not.
    func finishPendingHandbackAudit(elapsed: TimeInterval) {
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
                "reconcile[%@]: delivered=%.3f expected=%.3f residual=%+.3f (band ±0.20) · loanMin=%.0f cycles=%d · odometer read by PHONE +%.0fs after reclaim · vs watch endpoint %@ (watch fresh=%@)",
                pending.flavor == .forceReclaim ? "FORCE-RECLAIM" : "AUTHORITATIVE",
                delivered, pending.expected, residual,
                pending.loanMinutes, pending.cycles, elapsed,
                drift.map { String(format: "%+.3f", $0) } ?? "n/a",
                pending.watchFreshened ? "Y" : "N"))

            switch pending.flavor {
            case .handback:
                applyReconciliationVerdict(residual: residual, epoch: pending.epoch)
            case .forceReclaim:
                applyForceReclaimVerdict(residual: residual, epoch: pending.epoch,
                                         window: DateInterval(start: pending.windowStart, end: max(reading.at, pending.windowStart)))
            }
        } else if pending.flavor == .forceReclaim {
            // A pump that gives no delivered total: nothing to check against.
            handbackDiag(pending.epoch, "** force-reclaim round-trip landed but no odometer — session UNVERIFIED **")
            deps.issueUrgentNotice("Watch Session Unverified", Self.sessionUnverifiedBody)
        } else {
            // A clean hand-back keeps its committed records; nothing opens.
            handbackDiag(pending.epoch, "reconcile[AUTHORITATIVE]: pod reachable but reported no odometer — keeping the provisional line")
        }

        // The watch's temp ends here, after the reading.
        cancelWatchTemp(epoch: pending.epoch)
    }

    /// On failure the watch's temp runs until the phone's next cycle.
    private func cancelWatchTemp(epoch: Int) {
        deps.cancelTempBasalAfterPodReturn { [weak self] error in
            guard let self = self else { return }
            self.queue.async {
                if let error = error {
                    self.handbackDiag(epoch, "temp cancel FAILED — pod keeps the watch's temp until the next cycle · \(String(describing: error))")
                } else {
                    self.handbackDiag(epoch, "temp cancelled — pod reverts to the user's schedule until the phone's next reading")
                }
            }
        }
    }
}
