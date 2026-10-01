//
//  PodLoanPhoneController+Mirror.swift
//  Loop
//
//  Part of PodLoanPhoneController (see PodLoanPhoneController.swift). Split by concern; stored
//  properties live in the core class.
//
//  Keeping the phone's picture of a loan in step with the watch's: status reports, the takeover
//  dead-man, and standing aside for a loan this phone never granted.
//
//  The governing rule is that the phone stands aside on the watch's WORD — a message naming an
//  epoch the watch says it holds — never on the pod's own evidence. Inference has twice locked
//  the phone out of a pod nobody was using. Standing aside releases the pod radio as well as
//  dosing authority: the two travel together, or the watch cannot reach the pod it now owns.
//

import Foundation
import HealthKit
import LoopKit
import LoopCore
import UserNotifications
import os.log

extension PodLoanPhoneController {
    /// True when the watch has recently told us it holds a loan NEWER than the one named.
    /// Freshness matters as much as the epoch: a ten-minute-old sighting is evidence of a live
    /// session, an hour-old one is evidence of a session that has since ended.
    func supersededByLiveLoan(_ epochN: Int) -> Bool {
        guard let evidence = newestForeignLoanEvidence, evidence.epoch > epochN else { return false }
        return deps.now().timeIntervalSince(evidence.at) < 600
    }

    /// Stand aside for a loan this phone never granted — the watch started it from the standing
    /// dormant copy while the phone was away. Callers must already have the watch's word for it.
    ///
    /// Known gap: the phone's own temp basal may still be running at this moment, and it is not
    /// counted as expected insulin in the audit window opened here.
    func engageInferredLoanYield(evidence: String) {
        guard state == .owner, !yieldingToInferredLoan else { return }
        yieldingToInferredLoan = true
        // Treat this as first contact, so the silence watchdog starts counting from here rather
        // than from whenever this phone last heard anything.
        holdRenewedAt = deps.now()
        holdLapseNoticedAt = nil

        // Open an audit window from the pod's current total while the pod is still readable.
        // Without an anchor the eventual take-back has nothing to measure the session against.
        if let units = (deps.pumpManager() as? PumpConnectionLendable)?.lentDeviceInsulinDelivered {
            let asOf = deps.pumpManager()?.lastSync ?? deps.now()
            checkpointsThisLoan = 0
            auditBase = AuditBase(units: units, asOf: asOf)
            loanStartedAt = asOf
            UserDefaults.standard.set(asOf, forKey: Keys.loanStartedAt)
        }
        deps.setAutomaticDosingPaused(true)

        // Authority and radio travel together: a phone that stopped dosing but kept the pod link
        // would starve the watch that is now doing the dosing.
        (deps.pumpManager() as? PumpConnectionLendable)?.releaseConnection()
        syncUIMirror()
        deps.ownershipDidChange()

        deps.issueNotice(
            NSLocalizedString("Pod Looks Controlled by the Watch", comment: "Phone notice title when the phone yields to an inferred watch loan"),
            NSLocalizedString("This phone has paused automatic dosing because the pod appears to be in use by the watch. Tap the pod tile to take it back.", comment: "Phone notice body when the phone yields to an inferred watch loan"))
        PhoneLog.event("mirror", "YIELDING to an inferred loan — \(evidence); pill=Pod on Watch, dosing paused, pod BLE released, exits: pill tap / watch revival / R40(f) prompt (R40(a): on conflict the phone yields) [mirror]")
    }

    /// Take the pod radio back. The counterpart to the release at the grant, and it must run on
    /// every route back to ownership — a phone that believes it owns the pod but has not
    /// re-taken the link doses into a radio it is not holding.
    func reclaimPodConnection() {
        (deps.pumpManager() as? PumpConnectionLendable)?.reclaimConnection()
    }

    /// Stop standing aside. Deliberately does NOT re-take the radio or resume dosing by itself:
    /// the callers differ on both — a reclaim re-takes the link on its way to owning the pod, a
    /// retro-ack leaves it with the watch because the loan is now an adopted one.
    func clearInferredLoanYield(reason: String) {
        guard yieldingToInferredLoan else { return }
        yieldingToInferredLoan = false
        syncUIMirror()
        deps.ownershipDidChange()
        PhoneLog.event("mirror", "inferred-loan yield CLEARED — \(reason) [mirror]")
    }

    /// A grant that failed before the watch could have acted on it. The watch is told why, in
    /// words the glance can show, and the phone takes its pod straight back.
    func abortGrant(reason: String) {
        os_log("Grant aborted: %{public}@", log: log, type: .error, reason)
        sendMessage(.denied(LoanDenied(reason: "The loan could not start (\(reason)). The phone kept the pod.")))
        reclaimToOwner(alert: nil, reason: "grant ABORTED before it left the phone: \(reason)")
    }

    /// Comfortably past a normal takeover, which lands in well under half this.
    private static let grantLostProbeDelay: TimeInterval = 20

    /// Asks the watch whether the grant ever arrived. It only ASKS — no answer is not an answer,
    /// because a watch mid-takeover and a watch that heard nothing are equally silent. Acting on
    /// silence here would reclaim a pod the watch is in the middle of adopting.
    private func armGrantLostProbe(for grantEpoch: Int) {
        queue.asyncAfter(deadline: .now() + Self.grantLostProbeDelay) { [weak self] in
            guard let self = self, self.state == .grantOffered, self.epoch == grantEpoch else { return }
            self.handbackDiag(grantEpoch, String(format: "grant unconfirmed after %.0fs — asking the watch whether it arrived (#108)", Self.grantLostProbeDelay))

            if !self.deps.watchAppInstalled() {
                self.handbackDiag(grantEpoch, "grant unconfirmed AND isWatchAppInstalled=false — one-way wedge signature")
            }
            self.sendMessage(.statusQuery(StatusQuery(epoch: grantEpoch)))
        }
    }

    /// The five-minute dead-man on an unconfirmed takeover: if the watch never says it has the
    /// pod, the phone asks once more, waits briefly for that answer, and then takes the pod back
    /// rather than leaving it stranded between two devices.
    ///
    /// The stamp is per grant. Every path that abandons a loan clears it, so an elapsed figure
    /// can never be reported against the previous grant's clock.
    func armT1(for grantEpoch: Int) {
        if grantOfferedAt == nil { grantOfferedAt = deps.now() }
        armGrantLostProbe(for: grantEpoch)

        scheduleNotification(id: NotificationID.t1, title: "Watch Loan Not Confirmed",
                             body: "The watch hasn't confirmed taking the pod. The phone will take it back.",
                             delay: .minutes(5), repeats: false)
        t1WorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, self.state == .grantOffered, self.epoch == grantEpoch else { return }
            self.sendMessage(.statusQuery(StatusQuery(epoch: grantEpoch)))
            // Every guard is re-checked inside the rungs: a takeover that lands while these are
            // pending leaves the state no longer .grantOffered, and the rung does nothing.
            let confirm = DispatchWorkItem { [weak self] in
                guard let self = self, self.state == .grantOffered, self.epoch == grantEpoch else { return }

                self.reclaimToOwner(alert: nil, reason: "dead-man T1 expired — the watch never confirmed the takeover")
            }
            self.t1WorkItem = confirm
            self.queue.asyncAfter(deadline: .now() + 15, execute: confirm)
        }
        t1WorkItem = work
        queue.asyncAfter(deadline: .now() + .minutes(5), execute: work)
    }

    /// The watch has the pod. This is where the loan's audit origin is set, from the pod's own
    /// delivery total at the moment the watch first read it — everything the session is later
    /// judged against is measured from here.
    func handleTakeoverComplete(_ complete: TakeoverComplete) {
        guard complete.epoch == epoch, state == .grantOffered else { return }
        noteHoldRenewal(sentAt: complete.firstPodStatus.timestamp)
        grantOfferedAt = nil
        t1WorkItem?.cancel()
        cancelNotification(id: NotificationID.t1)

        if let atTakeover = complete.firstPodStatus.deliveredUnits {
            UserDefaults.standard.set(atTakeover, forKey: Keys.deliveredAtTakeover)

            auditBase = AuditBase(units: atTakeover, asOf: complete.firstPodStatus.timestamp)
        }
        state = .loaned

    }

    /// The watch says it could not take the pod. This is the fast path out of a failed grant —
    /// an explicit failure, unlike silence, is safe to act on immediately.
    func handleTakeoverFailed(_ failed: TakeoverFailed) {
        guard failed.epoch == epoch, state == .grantOffered else { return }
        t1WorkItem?.cancel()
        cancelNotification(id: NotificationID.t1)

        reclaimToOwner(alert: nil, reason: "watch reported takeover FAILED: \(failed.reason)")
    }

    /// The watch's answer to a status query, and the one place a loan this phone never granted
    /// can be recognised.
    ///
    /// `knowsGrant` is three-valued and must be read that way: nil is "no information" and only
    /// an explicit `false` may act. `holdsPod: false` is equally true of a watch that never
    /// received the grant and one thirty seconds into a takeover, and those want opposite
    /// responses.
    ///
    /// Known gap: a pod fault reported here during a loan is logged and goes no further. The
    /// watch holds the pod and owns surfacing its faults.
    func handleStatusReport(_ report: StatusReport) {
        // A newer epoch the watch says it HOLDS is the evidence a yield and a re-aimed revoke
        // both rest on.
        if report.holdsPod, report.epoch > epoch {
            if newestForeignLoanEvidence.map({ report.epoch >= $0.epoch }) ?? true {
                newestForeignLoanEvidence = (report.epoch, deps.now())
            }
            // Only yield to a watch that could plausibly have started a session: one this phone
            // has issued a standing seize credential to.
            let hasCredential = UserDefaults.standard.string(forKey: Keys.dormantSeizeToken) != nil
            switch state {
            case .owner where hasCredential:
                engageInferredLoanYield(evidence: "statusReport — watch holds the pod on e\(report.epoch)")
            // The watch is on a newer loan than the grant we are waiting to be confirmed, so
            // that grant is a ghost: no takeover can ever arrive for it. Abandon it and yield to
            // the loan that is actually running instead of waiting out the dead-man.
            case .grantOffered where hasCredential:

                t1WorkItem?.cancel()
                cancelNotification(id: NotificationID.t1)
                handbackDiag(epoch, "ghost grant e\(epoch) ABANDONED — the watch answered holdsPod e\(report.epoch); yielding instead of waiting on a takeover that cannot come [mirror]")
                state = .owner
                engageInferredLoanYield(evidence: "statusReport — watch holds e\(report.epoch), ghost grant abandoned")
            // Mid-reclaim, and the watch has just named a newer loan than the one this revoke
            // was addressed to. Re-aim it: the watch's own split-brain guard correctly refuses a
            // revoke at a stale epoch, and the ladder would read that refusal as death and steal
            // a pod that would have drained politely. Still bounded by the ladder's two attempts.
            case .reclaimPending:

                if var ladder = reclaimLadder, !ladder.forced, ladder.attempts < 2 {
                    sendMessage(.revoke(Revoke(epoch: report.epoch)))
                    ladder.attempts += 1
                    reclaimLadder = ladder
                    handbackDiag(epoch, "reclaim revoke RE-AIMED at e\(report.epoch) (attempt \(ladder.attempts) of 2) — the watch holds a newer loan than the one this reclaim named")
                }
            default:
                break
            }
        }
        guard report.epoch == epoch else { return }

        // The takeover landed but its completion message did not. The report is proof enough to
        // move on; it carries no odometer, so the audit keeps the reading taken at the grant as
        // its origin rather than inventing one.
        if state == .grantOffered, report.holdsPod {
            handleTakeoverComplete(TakeoverComplete(epoch: report.epoch, firstPodStatus: LoanPodStatus(timestamp: deps.now(), deliveredUnits: nil, reservoirLevel: nil, isSuspended: false, faultCode: report.podFault)))
        }

        if state == .grantOffered, report.knowsGrant == true, !report.holdsPod {
            let elapsed = grantOfferedAt.map { deps.now().timeIntervalSince($0) } ?? 0
            handbackDiag(report.epoch, String(format: "takeover IN PROGRESS on the watch at +%.0fs — the 5-minute dead-man runs unchanged", elapsed))
        }
        // The only answer that may cut the dead-man short: the watch says outright that it does
        // not know this grant, so waiting the full five minutes would only delay a retry the
        // user can make now.
        if state == .grantOffered, report.knowsGrant == false, !report.holdsPod {
            handbackDiag(report.epoch, "grant CONFIRMED LOST by the watch — reclaiming now instead of waiting out the 5-minute timer (#108)")
            t1WorkItem?.cancel()
            cancelNotification(id: NotificationID.t1)

            sendMessage(.denied(LoanDenied(reason: "The hand-over never reached the watch. The phone kept the pod. Tap Start again.")))
            reclaimToOwner(alert: nil, reason: "grant CONFIRMED LOST by the watch")
        }
        if report.podFault != nil {
            handbackDiag(report.epoch, "pod fault reported in a status report — logged only; the watch owns pod-fault surfacing during a loan")
        }
    }

}
