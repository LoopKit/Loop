//
//  PodLoanWatchController+Handback.swift
//  StockLoop
//
//  Part of PodLoanWatchController (see PodLoanWatchController.swift). Split by concern; stored properties live in the core class.
//
//  Giving the pod back — and every other way a loan ends.
//
//  Hand-back is two-phase. The watch keeps dosing while it drains its journal through interim
//  offers, and only a fully-acked drain reaches `finalizeHandback`; until then End is cancellable.
//  The pod is released ONLY after the phone acknowledges the final offer.
//
//  Released means released. Once that offer has gone out the watch stays stopped whatever happens
//  next: it cannot know whether the phone took the pod, and a watch that resumed on a timer would
//  be the second controller on one pod.
//

import Foundation
import HealthKit
import LoopKit
import LoopAlgorithm
import LoopCore
import OmnipodKit
import WatchKit
import os.log

extension PodLoanWatchController {

    /// The user's End. Starts the drain and arms the stuck alert, but changes nothing about
    /// dosing: the watch keeps looping until every record is acked.
    ///
    /// A phone that does not understand interim offers takes the single-phase path instead — its
    /// decoder drops the `released` key and would read the first interim offer as a completed
    /// hand-back, reclaiming the pod while this watch is still dosing.
    func beginHandback() {
        #if targetEnvironment(simulator)
        if defaults.bool(forKey: "sim.fakeLoanFlow") { simDriveHandback(); return }
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

            // One budget for both: the deadline this code gives up at, and the pre-scheduled
            // alert that fires if the app is not running to give up for itself.
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

    /// Cancellable right up to `finalizeHandback`. The stuck alert goes with it — that alert is
    /// about an End the user is still waiting on.
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

    /// A hand-back that will not get its acknowledgement: the budget expired, the phone refused,
    /// or a live offer found no phone to send to.
    ///
    /// What happens next turns entirely on whether the FINAL offer had already gone out. Before
    /// it, the loan simply continues and the watch keeps dosing. After it, the watch has already
    /// told the phone it is released: it stays stopped, tears the pod down, and becomes a parked
    /// drain that keeps offering its records until somebody takes them.
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
        // Both are read before the phase and the hand-back flags are unwound below — after that
        // nothing here still describes this hand-back.
        let wasFinal = (phase == .handingBack)
        let wedge = HandbackWedge.classify(resendCount: handbackResendCount,
                                           sawUnreachable: handbackSawUnreachable,
                                           reachableNow: isPhoneReachable(),
                                           sendsErrored: handbackSawUrgentSendError)
        let wedgeSuffix: String
        switch wedge {
        case .sessionReestablishing:
            wedgeSuffix = " · ** \(handbackResendCount) offers, phone reachable, zero acks — but the sends themselves ERRORED: session re-establishing (#113 variant B), usually self-heals in 1-2 min **"
        case .oneWay:
            wedgeSuffix = " · ** \(handbackResendCount) offers, phone REACHABLE throughout, zero acks — transport wedge (#113 variant A); restarting the WATCH app is the known recovery **"
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
            // Only while the loan is still live. A released drain raised its own alert above, and
            // protocol alerts share one identifier, so a second would merely replace it.
            if !wasFinal {
                issueProtocolAlert(title: "End Not Confirmed",
                                   body: "Your iPhone is reachable but hasn't confirmed. Reopening Loop on both devices usually clears this.")
            }
        case .none:
            break
        }

        HandbackStuckAlert.disarm()
    }

    /// The point of no return: dosing stops here and the released offer goes out.
    ///
    /// The interim resend is cancelled FIRST. A stale interim firing after the phase flip would
    /// send `released = true` early, and the phone would reclaim while this watch was still
    /// commanding the pod.
    ///
    /// The watch does NOT cancel its running temp. It is about to have no link to cancel over; the
    /// pod keeps delivering the last automatic rate, which is continuous therapy rather than a
    /// gap, and the phone issues the cancel at its verified reclaim. No automatic program outlives
    /// the controller that set it — only the device that enforces that moved.
    func finalizeHandback() {
        resendWorkItem?.cancel()
        finalOfferSent = false
        // No pump manager left — a revoke or a teardown got here first — so there is nothing to
        // read and the released offer goes straight out.
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
            SportLog.event("loan", String(format: "hand-back: our temp (%.2f U/hr until %@) stays live until the phone cancels it on reclaim (R33, phone-enforced)",
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
            // Freshen the odometer only over a link that is ALREADY up. Under connect-on-demand a
            // read DIALS — scan, connect, the pod hangs up on the idle link — and burns its whole
            // timeout for a reading the phone discards anyway, since its own reclaim round-trip is
            // the authoritative one.
            if manager.isConnectionReady {
                manager.podLoanReadStatus { first in
                    let delivered = manager.podLoanInsulinDelivered
                    // A total identical to the takeover reading is far more likely a stale answer
                    // than a loan that delivered nothing at all; read once more before committing.
                    if first, delivered != nil, delivered == self.deliveredAtTakeover {
                        manager.podLoanReadStatus { second in finalize(second) }
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

    /// Send one offer and arm the next. Four situations come through here — an interim drain, the
    /// final released offer, a revoke's drain and a relaunch-recovered drain — and `live` below is
    /// what separates them.
    ///
    /// A LIVE offer is NEVER queued. If the phone is unreachable the hand-back fails now and the
    /// loan continues, because a queued offer is accepted whenever the link returns — possibly
    /// hours later, with the phone nowhere near the pod and the loan long since moved on. Drains
    /// from a loan that is already over do queue: the pod has changed hands either way.
    func sendHandbackOffer(freshened: Bool, recovered: Bool) {
        guard let epoch = epoch ?? journal.activeEpoch else { return }
        // The revoke path has already torn the pump down, so it falls back to the total captured
        // before that teardown: an offer without an odometer skips the phone's reconcile entirely.
        var odometer: LoanOdometerSnapshot?
        if let start = deliveredAtTakeover,
           let latest = pumpManager?.podLoanInsulinDelivered ?? revokeCapturedDelivered {
            odometer = LoanOdometerSnapshot(deliveredAtStart: start, deliveredLatest: latest, freshenSucceeded: freshened,
                                            asOf: pumpManager?.podLoanInsulinDeliveredAt ?? revokeCapturedDeliveredAt)
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

            // Built from the NON-BLOCKING mirror: reading the real flag syncs onto the loop's
            // queue from this one, which is the deadlock direction. A RECOVERED offer sends nil
            // instead — a relaunch reads a freshly booted manager whose flag is a boot default,
            // and overwriting the user's captured mode with it leaves the phone resuming in the
            // wrong one.
            watchClosedLoopEnabled: recovered ? nil : loopManager.closedLoopEnabledNonBlocking,

            // Echoed on every offer: it is how the phone retro-acknowledges a loan it never
            // granted.
            seizeToken: defaults.string(forKey: DormantKeys.activeToken).flatMap(UUID.init(uuidString:)),

            lastLoopCompleted: loopManager.lastLoopCompleted)
        if offer.released == true, finalOfferSentAt == nil { finalOfferSentAt = self.now() }
        handbackResendCount += 1

        // First attempt and every fourth after it: a drain can run for twenty.
        if handbackResendCount == 1 || handbackResendCount % 4 == 0 {
            SportLog.event("loan", "hand-back offer attempt \(handbackResendCount) — waiting for iPhone ack")
        }

        // "Live" means this watch still holds the pod and the loan can still be kept: an interim
        // drain or the final offer. A revoked or recovered drain is not live — the pod has already
        // changed hands — so those may queue and wait for the link.
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

            // The budget is checked HERE rather than by a timer of its own, so a suspended app
            // discovers the expiry on its next resend instead of firing it long after the fact.
            if let deadline = self.handbackDeadline, self.now() >= deadline,
               self.phase == .handingBack || (self.phase == .active && self.handbackRequested) {
                self.handbackTimedOut()
                return
            }

            // The drain's ceiling. Giving up loses nothing: the phone owns the pod and has
            // already committed these records, whereas a one-way session otherwise leaves the
            // watch resending across relaunches indefinitely.
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
                self.phase = .idle
                self.epoch = nil
                self.deliveredAtTakeover = nil
                self.handbackDeadline = nil
                self.handbackStartedAt = nil
                self.finalOfferSentAt = nil
                self.handbackRequested = false
                self.finalOfferSent = false
                // Everything this session accumulated goes with it. The resend count and the two
                // wedge flags are per-session: carried into the next one they start it already
                // spent, so the NEXT drain gives up after a single offer and its wedge verdict
                // describes a session that is over. Only `beginHandback` used to clear them,
                // which a drain never runs through.
                self.handbackResendCount = 0
                self.handbackSawUnreachable = false
                self.handbackSawUrgentSendError = false
                self.urgentSendWedged = false
                // Same reason the ordinary close clears it: left set, the next ordinary loan is
                // mistaken for one grown from the standing copy.
                self.defaults.removeObject(forKey: DormantKeys.activeToken)
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

    /// The phone's commit acknowledgement. It advances the journal's cursor always, and moves the
    /// loan along only once nothing is left unacked.
    ///
    /// The pod is released only from here, after the FINAL offer's ack. The `finalOfferSent` gate
    /// is what stops a duplicate interim ack, arriving in the window before that offer goes out,
    /// from closing a loan the phone still believes it has lent — which would strand it there.
    func handleAck(_ ack: HandbackAck) {
        // The journal's epoch is the fallback because a parked drain has no controller epoch left
        // — it was cleared when its loan ended — and its records still need acking.
        guard let current = epoch ?? journal.activeEpoch, ack.epoch == current else {
            SportLog.event("loan", "ack IGNORED ev=\(ack.epoch) — ours ev=\(epoch.map(String.init) ?? "nil") journal ev=\(journal.activeEpoch.map(String.init) ?? "nil"); stale redelivery or epoch mismatch")
            return
        }
        // The cursor moves on every ack, and an empty backlog is the finalize gate. The phone
        // ACKS the still-open temp without committing it for exactly this reason: the gate can
        // clear while that temp is still running, and it comes home clamped on the final drain.
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
        // Timed, because this is the moment the pod starts advertising again and the phone's
        // standing connect can land on it.
        let releaseBegan = self.now()
        teardownPump()
        SportLog.event("loan", String(format: "pod BLE teardown returned in %.2fs — the phone's standing connect can land from here",
                                      self.now().timeIntervalSince(releaseBegan)))
        // CLOSED: the epoch, the journal, the takeover odometer and the seize token all go. The
        // high-water epoch deliberately does not.
        finalOfferSentAt = nil
        journal.end()
        phase = .idle
        epoch = nil
        deliveredAtTakeover = nil
        handbackDeadline = nil
        handbackStartedAt = nil
        HandbackStuckAlert.disarm()
        onLoanActiveChanged?(false)
        defaults.removeObject(forKey: DormantKeys.activeToken)
        reunionPromptActive = false
        SportLog.event("loan", "CLOSED — records drained, pod released, cursor \(ack.committedCursor)")
    }

    /// The phone asking for the pod back.
    ///
    /// `lastRevokedEpoch` is recorded BEFORE the epoch is matched, so even a revoke that names no
    /// live session closes the split-brain hole: any grant at or below it is refused from here on.
    /// A revoke for a stale epoch is answered with what this watch holds rather than with silence
    /// — silence reads to the phone as a dead watch, and its ladder then force-steals a live
    /// loan's pod.
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

        // Capture the odometer BEFORE the teardown. Teardown comes first on purpose — it frees
        // the pod's BLE for the reclaiming phone — but it leaves no pump to ask, and an offer
        // without an odometer skips the phone's authoritative reconcile of this loan entirely.
        revokeCapturedDelivered = pumpManager?.podLoanInsulinDelivered
        revokeCapturedDeliveredAt = pumpManager?.podLoanInsulinDeliveredAt
        loopManager.pumpManager = nil
        teardownPump()
        phase = .revoked
        onLoanActiveChanged?(false)
        SportLog.event("loan", "REVOKED — phone reclaimed the pod, draining records")
        sendHandbackOffer(freshened: false, recovered: true)
    }

    /// Run once the transport is up after a launch. It tells the phone about a takeover that was
    /// in flight when the app died — otherwise the phone waits out its own dead-man for a loan
    /// that never started — and re-kicks a parked drain's resend chain, which is what makes a
    /// parked drain startable ground rather than a wall.
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

    /// Answer the phone's probe about a specific epoch. Two guards before claiming ignorance:
    /// never while `.active`, and only when our epoch is BEHIND the one being asked about. A phone
    /// probing for a grant that never arrived, against a watch running a newer loan, got silence
    /// and parked its hand-over until somebody forced it by hand.
    func handleStatusQuery(_ query: StatusQuery) {
        guard let current = epoch, query.epoch == current else {
            if phase != .active, (epoch ?? Int.min) < query.epoch {
                // An explicit "we never heard of this grant" is what lets the phone give up
                // early. Silence is not "no": an unreachable watch mid-takeover looks identical.
                SportLog.event("loan", "status query for epoch \(query.epoch) — we have \(epoch.map(String.init) ?? "none") and hold no pod: the grant never reached us (#108)")
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
            podFault: pumpManager?.podLoanFaultDescription,
            holdsPod: phase == .active,
            knowsGrant: true)
        sendMessage(.statusReport(report))
    }

    /// Always `.closedDirect` today — the other cases of `LoanDosingMode` are unimplemented.
    func currentMode() -> LoanDosingMode {
        return .closedDirect
    }

    /// What the phone is told about the pod. Reservoir level is not read and suspension is not
    /// tracked on the wrist; the phone establishes both from its own reclaim round-trip.
    func currentPodStatus() -> LoanPodStatus {
        LoanPodStatus(
            timestamp: self.now(),
            deliveredUnits: pumpManager?.podLoanInsulinDelivered,
            reservoirLevel: nil,
            isSuspended: false,
            faultCode: pumpManager?.podLoanFaultDescription)
    }

}
