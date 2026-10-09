//
//  PodLoanPhoneController+Mirror.swift
//  Loop
//
//  Keeping the phone's view of a loan in step with the watch's. The phone stands aside only
//  on the watch's word, never on pod evidence, and releases the radio when it does.
//

import Foundation
import HealthKit
import LoopKit
import LoopCore
import UserNotifications
import os.log

extension PodLoanPhoneController {
    /// The watch recently said it holds a loan newer than `epochN`.
    func supersededByLiveLoan(_ epochN: Int) -> Bool {
        guard let evidence = newestForeignLoanEvidence, evidence.epoch > epochN else { return false }
        return deps.now().timeIntervalSince(evidence.at) < 600
    }

    /// Stand aside for a loan the watch started without this phone. Callers have the watch's word.
    /// Known gap: the phone's own running temp is not counted in the audit window opened here.
    func engageInferredLoanYield(evidence: String) {
        guard state == .owner, !yieldingToInferredLoan else { return }
        // The yield, first contact for the silence watchdog, and the audit anchored on the pod's
        // total while it is still readable: one save.
        let units = (deps.pumpManager() as? PumpDeliveryOdometer)?.deliveredUnits?.units
        let asOf = deps.pumpManager()?.lastSync ?? deps.now()
        let now = deps.now()
        updateState {
            $0.yieldingToInferredLoan = true
            $0.holdRenewedAt = now
            $0.holdLapseNoticedAt = nil
            $0.watchSilenceWarningsIssued = 0
            if let units {
                $0.audit.base = AuditBase(units: units, asOf: asOf)
                $0.audit.baseEpoch = $0.epoch
                $0.audit.loanStartedAt = asOf
            }
        }
        deps.setAutomaticDosingPaused(true)

        // Dosing authority and the radio go together.
        (deps.pumpManager() as? ExclusiveDeviceControl)?.releaseControl()

        // A settle window left open would escalate at +12 s and re-take the radio and the dosing gate.
        closeReclaimSettleWindow(reason: "yielding to an inferred loan — this phone is not reaching for the pod")
        syncUIMirror()
        deps.ownershipDidChange()

        deps.issueNotice(
            NSLocalizedString("Pod Looks Controlled by the Watch", comment: "Phone notice title when the phone yields to an inferred watch loan"),
            NSLocalizedString("This phone has paused automatic dosing because the pod appears to be in use by the watch. Tap the pod tile to take it back.", comment: "Phone notice body when the phone yields to an inferred watch loan"))
        PhoneLog.event("mirror", "YIELDING to an inferred loan — \(evidence); pill=Pod on Watch, dosing paused, pod BLE released, exits: pill tap / watch revival / reunion prompt; on conflict the phone yields [mirror]")
    }

    /// Take the radio back; every route back to ownership must call it.
    func reclaimPodConnection() {
        (deps.pumpManager() as? ExclusiveDeviceControl)?.takeControl()
    }

    /// Does not re-take the radio or resume dosing; callers differ on both.
    func clearInferredLoanYield(reason: String) {
        guard yieldingToInferredLoan else { return }
        yieldingToInferredLoan = false
        syncUIMirror()
        deps.ownershipDidChange()
        PhoneLog.event("mirror", "inferred-loan yield CLEARED — \(reason) [mirror]")
    }

    /// The grant failed before the watch acted on it: tell the watch and keep the pod.
    func abortGrant(reason: String) {
        os_log("Grant aborted: %{public}@", log: log, type: .error, reason)
        sendMessage(.denied(LoanDenied(reason: "The loan could not start (\(reason)). The phone kept the pod.")))
        reclaimToOwner(alert: nil, reason: "grant ABORTED before it left the phone: \(reason)")
    }

    /// Comfortably past a normal takeover, which lands in well under half this.
    private static let grantLostProbeDelay: TimeInterval = 20

    /// Asks only: a watch mid-takeover is as silent as one that heard nothing.
    private func armGrantLostProbe(for grantEpoch: Int) {
        queue.asyncAfter(deadline: .now() + Self.grantLostProbeDelay) { [weak self] in
            guard let self = self, self.state == .grantOffered, self.epoch == grantEpoch else { return }
            self.handbackDiag(grantEpoch, String(format: "grant unconfirmed after %.0fs — asking the watch whether it arrived", Self.grantLostProbeDelay))

            if !self.deps.watchAppInstalled() {
                self.handbackDiag(grantEpoch, "grant unconfirmed AND isWatchAppInstalled=false — one-way wedge signature")
            }
            self.sendMessage(.statusQuery(StatusQuery(epoch: grantEpoch)))
        }
    }

    /// Five-minute dead-man on an unconfirmed takeover: ask once more, then take the pod back.
    /// Per grant; every path that abandons a loan clears it.
    func armT1(for grantEpoch: Int) {
        if grantOfferedAt == nil { grantOfferedAt = deps.now() }
        armGrantLostProbe(for: grantEpoch)

        scheduleNotification(id: NotificationID.t1,
                             title: NSLocalizedString("Watch Loan Not Confirmed", comment: "Phone notification title: the watch never confirmed a takeover"),
                             body: NSLocalizedString("The watch hasn't confirmed taking the pod. The phone will take it back.", comment: "Phone notification body: the watch never confirmed a takeover"),
                             delay: .minutes(5), repeats: false)
        t1WorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, self.state == .grantOffered, self.epoch == grantEpoch else { return }
            self.sendMessage(.statusQuery(StatusQuery(epoch: grantEpoch)))
            // Guards are re-checked inside the rungs.
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

    /// The watch has the pod; the audit is measured from the total it first read.
    func handleTakeoverComplete(_ complete: TakeoverComplete) {
        guard complete.epoch == epoch, state == .grantOffered else { return }
        noteHoldRenewal(sentAt: complete.firstPodStatus.timestamp)
        grantOfferedAt = nil
        t1WorkItem?.cancel()
        cancelNotification(id: NotificationID.t1)

        if let atTakeover = complete.firstPodStatus.deliveredUnits {
            updateState { $0.audit.deliveredAtTakeover = atTakeover }

            auditBase = AuditBase(units: atTakeover, asOf: complete.firstPodStatus.timestamp)
        }
        state = .loaned

    }

    /// An explicit failure is safe to act on at once.
    func handleTakeoverFailed(_ failed: TakeoverFailed) {
        guard failed.epoch == epoch, state == .grantOffered else { return }
        t1WorkItem?.cancel()
        cancelNotification(id: NotificationID.t1)

        reclaimToOwner(alert: nil, reason: "watch reported takeover FAILED: \(failed.reason)")
    }

    /// The one place an ungranted loan can be recognised. `knowsGrant` nil means no information;
    /// only an explicit false may act. A pod fault is announced once.
    func handleStatusReport(_ report: StatusReport) {
        // A newer epoch the watch holds backs both a yield and a re-aimed revoke.
        if report.holdsPod, report.epoch > epoch {
            if newestForeignLoanEvidence.map({ report.epoch >= $0.epoch }) ?? true {
                newestForeignLoanEvidence = (report.epoch, deps.now())
            }
            // Only a watch holding this phone's seize credential could have started a session.
            let hasCredential = persisted.seizeToken != nil
            switch state {
            case .owner where hasCredential:
                engageInferredLoanYield(evidence: "statusReport — watch holds the pod on e\(report.epoch)")
            // The awaited grant is a ghost; yield to the loan actually running.
            case .grantOffered where hasCredential:

                t1WorkItem?.cancel()
                cancelNotification(id: NotificationID.t1)
                handbackDiag(epoch, "ghost grant e\(epoch) ABANDONED — the watch answered holdsPod e\(report.epoch); yielding instead of waiting on a takeover that cannot come [mirror]")
                state = .owner
                engageInferredLoanYield(evidence: "statusReport — watch holds e\(report.epoch), ghost grant abandoned")
            // Re-aim the revoke at the watch's newer epoch; a stale-epoch revoke would be refused.
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

        // Takeover landed but its message did not; the grant-time reading stays the audit origin.
        if state == .grantOffered, report.holdsPod {
            handleTakeoverComplete(TakeoverComplete(epoch: report.epoch, firstPodStatus: LoanPodStatus(timestamp: deps.now(), deliveredUnits: nil, reservoirLevel: nil, isSuspended: false, faultCode: report.podFault)))
        }

        if state == .grantOffered, report.knowsGrant == true, !report.holdsPod {
            let elapsed = grantOfferedAt.map { deps.now().timeIntervalSince($0) } ?? 0
            handbackDiag(report.epoch, String(format: "takeover IN PROGRESS on the watch at +%.0fs — the 5-minute dead-man runs unchanged", elapsed))
        }
        // The watch does not know this grant: no need to wait out the dead-man.
        if state == .grantOffered, report.knowsGrant == false, !report.holdsPod {
            handbackDiag(report.epoch, "grant CONFIRMED LOST by the watch — reclaiming now instead of waiting out the 5-minute timer")
            t1WorkItem?.cancel()
            cancelNotification(id: NotificationID.t1)

            sendMessage(.denied(LoanDenied(reason: "The hand-over never reached the watch. The phone kept the pod. Tap Start again.")))
            reclaimToOwner(alert: nil, reason: "grant CONFIRMED LOST by the watch")
        }
        if let fault = report.podFault {
            handbackDiag(report.epoch, "pod fault reported by the watch (\(fault)) — the watch raises the pod's alarm; the phone posts one notice")
            noticePodFault(fault, epoch: report.epoch)
        }
    }

    /// The watch alarms too, but the user may be nearer the phone.
    func noticePodFault(_ fault: String, epoch: Int) {
        let key = "\(epoch) \(fault)"
        guard podFaultNoticed != key else { return }
        podFaultNoticed = key
        deps.issueUrgentNotice(
            NSLocalizedString("Pod Fault", comment: "Phone notice title when the watch reports a pod fault during a loan"),
            String(format: NSLocalizedString("The watch reports a pod fault: %1$@. Insulin delivery has stopped — replace the pod.", comment: "Phone notice body when the watch reports a pod fault during a loan (1: the pump's own fault text)"), fault))
    }

}
