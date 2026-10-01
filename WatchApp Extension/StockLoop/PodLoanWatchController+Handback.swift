//
//  PodLoanWatchController+Handback.swift
//  StockLoop
//
//  Giving the pod back, and every other way a loan ends. Two-phase: the watch keeps dosing
//  while interim offers drain the journal; the pod is released only after the final offer's
//  ack. Once released, the watch stays stopped.
//

import Foundation
import HealthKit
import LoopKit
import LoopAlgorithm
import LoopCore
import WatchKit
import os.log

extension PodLoanWatchController {

    /// The user's End: starts the drain; dosing continues until everything is acked. A phone
    /// without interim-offer support gets the single-phase path.
    func beginHandback() {
        #if targetEnvironment(simulator)
        if simFakeLoanFlow { simDriveHandback(); return }
        #endif
        queue.async {
            guard self.phase == .active, self.pumpManager != nil else { return }
            guard !self.handbackRequested else { return }
            self.reunionPromptActive = false
            self.handbackRequested = true
            self.handbackFailure = nil
            self.handbackResendCount = 0
            self.handbackSawUnreachable = false
            self.handbackSawUrgentSendError = false
            self.urgentSendWedged = false

            // One budget for the give-up deadline and the pre-scheduled stuck alert.
            self.handbackDeadline = self.now().addingTimeInterval(HandbackStuckAlert.interval)
            self.handbackStartedAt = self.now()
            HandbackStuckAlert.arm()
            guard self.phoneSupportsInterimHandback else {
                SportLog.event("loan", "HAND-BACK started (legacy single-phase — phone predates interim drains)")
                self.finalizeHandback()
                return
            }
            SportLog.event("loan", "HAND-BACK requested — draining \(self.journal.unackedEvents().count) events; still in control (WS1)")
            self.sendHandbackOffer(freshened: false, recovered: false)
        }
    }

    /// Cancellable until `finalizeHandback`.
    func cancelHandback() {
        queue.async {
            guard self.phase == .active, self.handbackRequested else { return }
            self.handbackRequested = false
            self.resendWorkItem?.cancel()
            self.handbackDeadline = nil
            self.handbackStartedAt = nil
            HandbackStuckAlert.disarm()
            SportLog.event("loan", "HAND-BACK cancelled — Sport Mode continues")
        }
    }

    /// No ack is coming. Before the final offer the loan simply continues; after it the watch
    /// stays stopped and becomes a parked drain.
    func handbackTimedOut(unreachable: Bool = false, refusal: String? = nil) {
        let why: String
        if let refusal { why = "REFUSED by the phone — \(refusal)" }
        else if unreachable { why = "not possible — iPhone not reachable, no offer sent" }
        else { why = "timed out (\(Int(HandbackStuckAlert.interval))s) — iPhone never acked" }
        handbackFailure = (now(), refusal ?? (unreachable
            ? NSLocalizedString("iPhone not reachable — still running", comment: "Glance transient: End failed, phone unreachable")
            : NSLocalizedString("iPhone didn't respond — still running", comment: "Glance transient: End failed, no ack")))
        resendWorkItem?.cancel()
        handbackDeadline = nil
        handbackStartedAt = nil
        // Read before the flags are unwound.
        let wasFinal = (phase == .handingBack)
        let wedge = HandbackWedge.classify(resendCount: handbackResendCount,
                                           sawUnreachable: handbackSawUnreachable,
                                           reachableNow: isPhoneReachable(),
                                           sendsErrored: handbackSawUrgentSendError)
        let wedgeSuffix: String
        switch wedge {
        case .sessionReestablishing:
            wedgeSuffix = " · ** \(handbackResendCount) offers, phone reachable, zero acks — but the sends themselves ERRORED: session re-establishing, usually self-heals in 1-2 min **"
        case .oneWay:
            wedgeSuffix = " · ** \(handbackResendCount) offers, phone REACHABLE throughout, zero acks — transport wedge; restarting the WATCH app is the known recovery **"
        case .none:
            wedgeSuffix = ""
        }
        handbackRequested = false
        finalOfferSent = false
        if wasFinal {
            SportLog.event("loan", "HAND-BACK \(why) (final); staying RELEASED — the pod is let go and the records keep offering; the phone resumes when the offer lands\(wedgeSuffix)")
            teardownPump()
            finalOfferSentAt = nil
            deliveredAtTakeover = nil
            onLoanActiveChanged?(false)

            phase = .recoveredDrain
            sendHandbackOffer(freshened: false, recovered: true)
            issueProtocolAlert(title: NSLocalizedString("End Not Confirmed", comment: "Watch alert title: the phone has not confirmed a hand-back"),
                               body: NSLocalizedString("The watch has stopped dosing and keeps sending its records. If your iPhone hasn't taken over in a minute or two, open Loop on the iPhone and tap the pod tile.", comment: "Watch alert body: released but unconfirmed hand-back"))
        } else {
            SportLog.event("loan", "HAND-BACK \(why) (interim); Sport Mode continues on the watch\(wedgeSuffix)")
        }
        switch wedge {
        case .sessionReestablishing:
            // Self-heals in a minute or two, so it is logged and never alerted.
            SportLog.event("loan", "hand-back wedge variant B (session re-establishing) — no alert; expected to clear on its own")
        case .oneWay:
            // Only while the loan is still live, so the watch is still dosing: a normal alert.
            if !wasFinal {
                issueProtocolAlert(title: "End Not Confirmed",
                                   body: "Your iPhone is reachable but hasn't confirmed. Reopening Loop on both devices usually clears this.",
                                   identifier: "handbackOneWay", interruptionLevel: .active)
            }
        case .none:
            break
        }

        HandbackStuckAlert.disarm()
    }

    /// Dosing stops and the released offer goes out. The interim resend is cancelled first. The
    /// running temp is left for the phone to cancel at its verified reclaim.
    func finalizeHandback() {
        resendWorkItem?.cancel()
        finalOfferSent = false
        // No pump manager left: send the released offer straight away.
        guard let manager = pumpManager else {
            handbackRequested = false
            phase = .handingBack
            finalOfferSent = true
            sendHandbackOffer(freshened: false, recovered: false)
            return
        }
        handbackRequested = false
        phase = .handingBack

        loopManager.dumpIOBDecomp("HAND-BACK", at: self.now())
        SportLog.event("loan", "drain complete — finalizing hand-back (loop dosing stops now)")

        let runningTemp: DoseEntry? = {
            if case .tempBasal(let dose) = manager.status.basalDeliveryState { return dose }
            return nil
        }()
        // Dosing stops here: from this line the loop has no pump, whatever becomes of the offer.
        loopManager.pumpManager = nil

        if runningTemp != nil {
            SportLog.event("loan", String(format: "hand-back: our temp (%.2f U/hr until %@) stays live until the phone cancels it on reclaim (phone-enforced)",
                                          runningTemp?.unitsPerHour ?? 0,
                                          runningTemp.map { ISO8601DateFormatter().string(from: $0.endDate) } ?? "—"))
        }

        do {
            let finalize: (Bool) -> Void = { freshened in
                self.queue.async {
                    self.finalOfferSent = true
                    self.sendHandbackOffer(freshened: freshened, recovered: false)
                }
            }
            // Read the odometer only over a link already up; otherwise a read dials the pod.
            if let odometer = manager as? PumpDeliveryOdometer, (manager as? ExclusiveDeviceControl)?.isControlReady == true {
                odometer.refreshDeliveredUnits { first in
                    let delivered = odometer.deliveredUnits?.units
                    // A total equal to the takeover reading is probably stale: read once more.
                    if first, delivered != nil, delivered == self.deliveredAtTakeover {
                        odometer.refreshDeliveredUnits { second in finalize(second) }
                    } else {
                        finalize(first)
                    }
                }
            } else {
                SportLog.event("loan", "hand-back: freshen SKIPPED — no live pod link; the phone's reclaim read is authoritative")
                finalize(false)
            }
        }
    }

    /// Sends one offer and arms the next. A live offer is never queued: accepted late it would
    /// split the pod. Drains from a loan that is already over may queue.
    func sendHandbackOffer(freshened: Bool, recovered: Bool) {
        guard let epoch = epoch ?? journal.activeEpoch else { return }
        // After a revoke's teardown, use the total captured before it.
        var odometer: LoanOdometerSnapshot?
        if let start = deliveredAtTakeover,
           let latest = pumpOdometer?.deliveredUnits?.units ?? revokeCapturedDelivered {
            odometer = LoanOdometerSnapshot(deliveredAtStart: start, deliveredLatest: latest, freshenSucceeded: freshened,
                                            asOf: pumpOdometer?.deliveredUnits?.at ?? revokeCapturedDeliveredAt)
        }
        let offerEvents = journal.unackedEvents()
        let offer = HandbackOffer(
            epoch: epoch,
            handedBackAt: self.now(),
            finalStatus: pumpManager.map { _ in currentPodStatus() },
            odometer: odometer,
            events: offerEvents,
            tombstones: journal.pendingTombstones(),
            recovered: recovered,
            released: phase != .active,

            // From the non-blocking mirror. A recovered offer sends nil: a rebooted flag is not the user's.
            watchClosedLoopEnabled: recovered ? nil : loopManager.closedLoopEnabledNonBlocking,

            // Lets the phone retro-acknowledge a loan it never granted.
            seizeToken: persisted.seizeToken,

            lastLoopCompleted: loopManager.lastLoopCompleted)
        if offer.released == true, finalOfferSentAt == nil { finalOfferSentAt = self.now() }
        handbackResendCount += 1

        // First attempt and every fourth after it: a drain can run for twenty.
        if handbackResendCount == 1 || handbackResendCount % 4 == 0 {
            SportLog.event("loan", "hand-back offer attempt \(handbackResendCount) — waiting for iPhone ack")
        }

        // Live: this watch still holds the pod (interim or final offer).
        let live = !recovered && phase != .revoked && phase != .recoveredDrain
        let reachableNow = isPhoneReachable()
        if !reachableNow { handbackSawUnreachable = true }
        if live, !reachableNow {
            handbackTimedOut(unreachable: true)
            return
        }
        if lastHandbackReachable != reachableNow {
            SportLog.event("loan", reachableNow
                ? "hand-back: iPhone reachable — offer should ack shortly"
                : "drain: iPhone UNREACHABLE — offer queued, will land when it returns")
            lastHandbackReachable = reachableNow
        }
        sendMessage(.handbackOffer(offer), urgentOnly: live)

        resendWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }

            // Checked on each resend, so a suspended app still notices.
            if let deadline = self.handbackDeadline, self.now() >= deadline,
               self.phase == .handingBack || (self.phase == .active && self.handbackRequested) {
                self.handbackTimedOut()
                return
            }

            // The drain's ceiling; the phone already has the records.
            let drain = self.phase == .revoked || self.phase == .recoveredDrain
            if drain, self.handbackResendCount >= Self.maxDrainResends {
                let wedge = HandbackWedge.classify(resendCount: self.handbackResendCount,
                                                   sawUnreachable: self.handbackSawUnreachable,
                                                   reachableNow: self.isPhoneReachable(),
                                                   sendsErrored: self.handbackSawUrgentSendError)
                SportLog.event("loan", "drain GIVING UP after \(self.handbackResendCount) unacked offer(s) [\(wedge)] — the phone owns the pod and has already committed these records; closing to idle")
                self.resendWorkItem?.cancel()
                self.teardownPump()
                self.journal.end()
                // Closed in one save; the token goes too, or the next loan is mistaken for a seized one.
                self.updateState {
                    $0.phase = .idle
                    $0.epoch = nil
                    $0.deliveredAtTakeover = nil
                    $0.seizeToken = nil
                }
                self.handbackDeadline = nil
                self.handbackStartedAt = nil
                self.finalOfferSentAt = nil
                self.handbackRequested = false
                self.finalOfferSent = false
                // Per-session counters and wedge flags reset with the session.
                self.handbackResendCount = 0
                self.handbackSawUnreachable = false
                self.handbackSawUrgentSendError = false
                self.urgentSendWedged = false
                HandbackStuckAlert.disarm()
                self.onLoanActiveChanged?(false)
                SportLog.event("loan", "CLOSED — drain abandoned, pod already the phone's")
                return
            }
            if self.phase == .handingBack || drain
                || (self.phase == .active && self.handbackRequested) {
                self.sendHandbackOffer(freshened: freshened, recovered: recovered)
            }
        }
        resendWorkItem = work
        schedule(after: 15, label: "handback-resend", execute: work)
    }

    /// Advances the cursor on every ack; only the final offer's ack releases the pod.
    func handleAck(_ ack: HandbackAck) {
        // A parked drain has no controller epoch; use the journal's.
        guard let current = epoch ?? journal.activeEpoch, ack.epoch == current else {
            SportLog.event("loan", "ack IGNORED ev=\(ack.epoch) — ours ev=\(epoch.map(String.init) ?? "nil") journal ev=\(journal.activeEpoch.map(String.init) ?? "nil"); stale redelivery or epoch mismatch")
            return
        }
        // An empty backlog is the finalize gate.
        journal.applyAck(committedCursor: ack.committedCursor)
        guard journal.unackedEvents().isEmpty else { return }

        // Fully drained while the user is still waiting: that is what triggers finalize.
        if phase == .active && handbackRequested {
            finalizeHandback()
            return
        }
        guard phase == .handingBack || phase == .revoked || phase == .recoveredDrain else { return }

        if phase == .handingBack && !finalOfferSent { return }

        resendWorkItem?.cancel()

        let ackWait = finalOfferSentAt.map { self.now().timeIntervalSince($0) }
        SportLog.event("loan", String(format: "ack RECEIVED %@ after the final offer — releasing the pod now",
                                      ackWait.map { String(format: "+%.1fs", $0) } ?? "(no offer stamp)"))
        // Timed: the pod advertises again from here.
        let releaseBegan = self.now()
        teardownPump()
        SportLog.event("loan", String(format: "pod BLE teardown returned in %.2fs — the phone's standing connect can land from here",
                                      self.now().timeIntervalSince(releaseBegan)))
        // Closed: epoch, journal, takeover odometer and seize token go; the high-water epoch stays.
        finalOfferSentAt = nil
        journal.end()
        updateState {
            $0.phase = .idle
            $0.epoch = nil
            $0.deliveredAtTakeover = nil
            $0.seizeToken = nil
        }
        handbackDeadline = nil
        handbackStartedAt = nil
        HandbackStuckAlert.disarm()
        onLoanActiveChanged?(false)
        reunionPromptActive = false
        SportLog.event("loan", "CLOSED — records drained, pod released, cursor \(ack.committedCursor)")
    }

    /// The phone asking for the pod back. `lastRevokedEpoch` is recorded first, closing the
    /// split-brain hole; a stale revoke is answered with what this watch holds.
    func handleRevoke(_ revoke: Revoke) {
        if revoke.epoch > (lastRevokedEpoch ?? Int.min) {
            lastRevokedEpoch = revoke.epoch
        }
        guard let current = epoch ?? journal.activeEpoch, revoke.epoch == current else {
            SportLog.event("loan", "revoke ev=\(revoke.epoch) matched no live session (epoch \(epoch.map(String.init) ?? "nil"), phase \(phase.rawValue)) — RECORDED; any grant at or below ev=\(revoke.epoch) will now be refused")

            if phase == .active, (epoch ?? Int.min) > revoke.epoch {
                sendHoldsPodStatusReport(reason: "stale revoke e\(revoke.epoch) refused")
            }
            return
        }
        guard phase != .idle else { return }

        handbackRequested = false
        handbackDeadline = nil
        handbackStartedAt = nil
        HandbackStuckAlert.disarm()

        // Capture the odometer before the teardown frees the pod for the phone.
        revokeCapturedDelivered = pumpOdometer?.deliveredUnits?.units
        revokeCapturedDeliveredAt = pumpOdometer?.deliveredUnits?.at
        loopManager.pumpManager = nil
        teardownPump()
        phase = .revoked
        onLoanActiveChanged?(false)
        SportLog.event("loan", "REVOKED — phone reclaimed the pod, draining records")
        sendHandbackOffer(freshened: false, recovered: true)
    }

    /// After launch: report a takeover that died mid-flight, and restart a parked drain's resends.
    func drainRecoveredIfNeeded() {
        queue.async {
            if let epoch = self.pendingInterruptedTakeoverEpoch {
                self.pendingInterruptedTakeoverEpoch = nil
                SportLog.event("loan", "START INTERRUPTED — takeover was in flight at relaunch; failing it to the phone, epoch \(epoch)")
                self.sendMessage(.takeoverFailed(TakeoverFailed(epoch: epoch, reason: "watch relaunched during takeover")))
            }
            guard self.phase == .recoveredDrain else { return }
            self.sendHandbackOffer(freshened: false, recovered: true)
        }
    }

    /// Claims ignorance of an epoch only when not active and behind it.
    func handleStatusQuery(_ query: StatusQuery) {
        guard let current = epoch, query.epoch == current else {
            if phase != .active, (epoch ?? Int.min) < query.epoch {
                // An explicit no lets the phone give up early.
                SportLog.event("loan", "status query for epoch \(query.epoch) — we have \(epoch.map(String.init) ?? "none") and hold no pod: the grant never reached us")
                sendMessage(.statusReport(StatusReport(
                    epoch: query.epoch,
                    mode: currentMode(),
                    lastDirectGlucoseAge: nil,
                    lastEventSeq: 0,
                    podFault: nil,
                    holdsPod: false,
                    knowsGrant: false)))
            } else if phase == .active, (epoch ?? Int.min) > query.epoch {
                sendHoldsPodStatusReport(reason: "status query for stale e\(query.epoch)")
            }
            return
        }
        // The query names our own live loan, so it is answered in full.
        let report = StatusReport(
            epoch: current,
            mode: currentMode(),
            lastDirectGlucoseAge: loopManager.latestGlucoseAge,
            lastEventSeq: journal.lastEventSeq,
            podFault: pumpFaultDescription,
            holdsPod: phase == .active,
            knowsGrant: true)
        sendMessage(.statusReport(report))
    }

    /// Always `.closedDirect` today — the other cases of `LoanDosingMode` are unimplemented.
    func currentMode() -> LoanDosingMode {
        return .closedDirect
    }

    /// The phone reads reservoir and suspension itself at reclaim.
    func currentPodStatus() -> LoanPodStatus {
        LoanPodStatus(
            timestamp: self.now(),
            deliveredUnits: pumpOdometer?.deliveredUnits?.units,
            reservoirLevel: nil,
            isSuspended: false,
            faultCode: pumpFaultDescription)
    }

}
