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
        let lastPodReading = deps.pumpManager()?.lastSync
        updateState {
            $0.yieldingToInferredLoan = true
            $0.holdRenewedAt = now
            // Until the watch's records come in, this phone's end at its own last pod reading.
            $0.recordsCurrentAt = lastPodReading
            if let units {
                $0.ledger.last = .init(units: units, at: asOf)
                $0.loanStartedAt = asOf
            }
        }

        // Dosing authority and the radio go together. The yield holds dosing even if the pod driver
        // keeps the pod; each pump report then asks it again (`letGoAgainIfKept`).
        (deps.pumpManager() as? ExclusiveDeviceControl)?.releaseControl()
        deps.pumpControlChanged(true)
        readThePodIfKept()

        // A settle window left open would keep chasing a pod this phone has let go of.
        closeReclaimSettleWindow(reason: "standing aside for the watch's loan")
        deps.ownershipDidChange()

        // No notice: the looper started this loan on the watch; the banner shows it (control row 17).
        PhoneLog.event("mirror", "standing aside for a loan the watch started without this phone: \(evidence)")
    }

    /// Standing aside, the pod driver keeps the pod while a command to it is unconfirmed. A pump report
    /// follows an exchange with the pod, which settles the command: ask the driver again.
    func letGoAgainIfKept() {
        guard let control = deps.pumpManager() as? ExclusiveDeviceControl, !control.isControlReleased else { return }
        control.releaseControl()
        guard control.isControlReleased else {
            PhoneLog.event("mirror", "standing aside: the pod driver still keeps the pod; dosing stays paused")
            return
        }
        deps.pumpControlChanged(true)
        PhoneLog.event("mirror", "standing aside: the pod driver has let go of the pod")
    }

    /// The pod driver kept the pod when this phone stood aside. Only an exchange with the pod settles the
    /// unconfirmed command, and a phone standing aside runs no loop cycle to make one: its cycles start
    /// from its own new readings, which the watch's relayed copies usually reach the store before. So
    /// read the pod, then ask the driver again. A failed read waits for the next time the phone stands
    /// aside or the next pump report.
    func readThePodIfKept() {
        guard let control = deps.pumpManager() as? ExclusiveDeviceControl, !control.isControlReleased,
              let odometer = control as? PumpDeliveryOdometer else { return }
        PhoneLog.event("mirror", "standing aside: the pod driver keeps the pod until its last command is confirmed; reading the pod to settle it")
        Task { [weak self] in
            let read = await odometer.refreshDeliveredUnits()
            guard let self else { return }
            DispatchQueue.main.async {
                if !read {
                    PhoneLog.event("mirror", "standing aside: the pod read failed; the pod driver still keeps the pod")
                }
                self.letGoAgainIfKept()
            }
        }
    }

    /// The stop message can be lost on the way to a watch that was off. Anything the watch sends
    /// for a loan this phone has ended gets it again, at most every 20 s.
    func resendRevokeForClosedSession(epoch closed: Int, evidence: String) {
        guard lastClosedSessionRevokeAt.map({ deps.now().timeIntervalSince($0) >= 20 }) ?? true else { return }
        lastClosedSessionRevokeAt = deps.now()
        handbackDiag(closed, "telling the watch again to stop this closed loan: \(evidence)")
        sendMessage(.revoke(Revoke(epoch: closed)))
    }

    /// Take the radio back; every route back to ownership must call it.
    func reclaimPodConnection() {
        guard let control = deps.pumpManager() as? ExclusiveDeviceControl else { return }
        let wasReleased = control.isControlReleased
        control.takeControl()
        if wasReleased { deps.pumpControlChanged(false) }
    }

    /// Does not re-take the radio or resume dosing; callers differ on both.
    func clearInferredLoanYield(reason: String) {
        guard yieldingToInferredLoan else { return }
        yieldingToInferredLoan = false
        deps.ownershipDidChange()
        PhoneLog.event("mirror", "no longer standing aside: \(reason)")
    }

    /// The grant failed before the watch acted on it: tell the watch and keep the pod.
    func abortGrant(reason: String) {
        sendMessage(.denied(LoanDenied(reason: "Sport Mode couldn't start. The iPhone kept the pod. Try again.")))
        reclaimToOwner(alert: nil, reason: "lending failed before the grant left the phone: \(reason)")
    }

    /// Comfortably past a normal takeover, which lands in well under half this.
    /// Settable for tests.
    static var grantLostProbeDelay: TimeInterval = 20

    /// The grant unconfirmed: ask the watch. "Taking over" waits for the lease; "no such grant" takes the
    /// pod back at once (`handleStatusReport`); silence takes it back after the answer wait.
    private func armGrantLostProbe(for grantEpoch: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.grantLostProbeDelay) { [weak self] in
            guard let self = self, self.state == .grantOffered, self.epoch == grantEpoch else { return }
            self.handbackDiag(grantEpoch, String(format: "takeover not confirmed after %.0f s: asking the watch whether the grant arrived", Self.grantLostProbeDelay))

            if !self.deps.watchAppInstalled() {
                self.handbackDiag(grantEpoch, "the system reports the watch app as not installed")
            }
            let askedAt = self.deps.now()
            self.sendMessage(.statusQuery(StatusQuery(epoch: grantEpoch)))
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.answerWait) { [weak self] in
                guard let self = self, self.state == .grantOffered, self.epoch == grantEpoch,
                      self.lastWatchAnswerAt.map({ $0 >= askedAt }) != true else { return }
                self.t1WorkItem?.cancel()
                self.reclaimToOwner(alert: Self.grantNotTakenNotice, reason: "the watch neither confirmed the takeover nor answered")
            }
        }
    }

    static let grantNotTakenNotice = (
        title: NSLocalizedString("The Watch Didn't Take the Pod", comment: "Phone notice title: a grant the watch never confirmed"),
        body: NSLocalizedString("Sport Mode didn't start on the watch. This iPhone kept the pod and is looping.", comment: "Phone notice body: a grant the watch never confirmed"))

    /// The grant's lease for a takeover the watch said is under way: ask once more at its end, then
    /// take the pod back. Per grant; every path that abandons a loan clears it.
    func armT1(for grantEpoch: Int) {
        if grantOfferedAt == nil { grantOfferedAt = deps.now() }
        armGrantLostProbe(for: grantEpoch)

        t1WorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, self.state == .grantOffered, self.epoch == grantEpoch else { return }
            self.sendMessage(.statusQuery(StatusQuery(epoch: grantEpoch)))
            // Guards are re-checked inside the rungs.
            let confirm = DispatchWorkItem { [weak self] in
                guard let self = self, self.state == .grantOffered, self.epoch == grantEpoch else { return }

                self.reclaimToOwner(alert: Self.grantNotTakenNotice, reason: "the takeover lease ended unconfirmed")
            }
            self.t1WorkItem = confirm
            DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: confirm)
        }
        t1WorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + LoanControl.takeoverLease, execute: work)
    }

    /// The watch has the pod; the audit is measured from the total it first read.
    func handleTakeoverComplete(_ complete: TakeoverComplete) {
        guard complete.epoch == epoch, state == .grantOffered else { return }
        noteHoldRenewal(sentAt: complete.firstPodStatus.timestamp)
        grantOfferedAt = nil
        t1WorkItem?.cancel()
        cancelNotification(id: NotificationID.t1)

        if let atTakeover = complete.firstPodStatus.deliveredUnits {
            noteTakeoverReading(units: atTakeover, at: complete.firstPodStatus.timestamp)
        }
        state = .loaned

    }

    /// An explicit failure is safe to act on at once.
    func handleTakeoverFailed(_ failed: TakeoverFailed) {
        guard failed.epoch == epoch, state == .grantOffered else { return }
        t1WorkItem?.cancel()
        cancelNotification(id: NotificationID.t1)

        reclaimToOwner(alert: nil, reason: "the watch could not take the pod: \(failed.reason)")
    }

    /// The one place an ungranted loan can be recognised. `knowsGrant` nil means no information;
    /// only an explicit false may act. A pod fault is announced once.
    func handleStatusReport(_ report: StatusReport) {
        // Any report answers a question this phone asked (`askWatch`).
        lastWatchAnswerAt = deps.now()
        lastWatchAnswerCannotReachPod = report.holdsPod && report.podReachable == false
        lastWatchAnswerHoldsNothing = !report.holdsPod
        if report.holdsPod {
            let loan: LoanControl.ClaimedLoan = report.epoch > epoch ? .newer
                : (report.epoch == epoch && state != .owner ? .current : .closed)
            let claim = LoanControl.Claim(loan: loan, startedAt: report.loanStartedAt, podReachable: report.podReachable,
                                          refusedBefore: refusedRevivedEpochs.contains(report.epoch))
            let decision = decideAndAct(.watchClaims(claim), why: "the watch says it holds the pod on e\(report.epoch)",
                                        claimEpoch: report.epoch)
            if loan == .newer {
                if decision == .sendStop {
                    // Row 19: a revived claim, refused; its records will get the stop too.
                    refusedRevivedEpochs.insert(report.epoch)
                    return
                }
                if newestForeignLoanEvidence.map({ report.epoch >= $0.epoch }) ?? true {
                    newestForeignLoanEvidence = (report.epoch, deps.now())
                }
                // Transfer G: the awaited grant is a ghost; stand aside for the loan actually running.
                if state == .grantOffered, persisted.seizeToken != nil {
                    t1WorkItem?.cancel()
                    cancelNotification(id: NotificationID.t1)
                    handbackDiag(epoch, "lending abandoned: the watch runs its own loan e\(report.epoch)")
                    state = .owner
                    engageInferredLoanYield(evidence: "the watch holds the pod on e\(report.epoch)")
                }
            }
        }
        guard report.epoch == epoch else { return }

        // Takeover landed but its message did not; the grant-time reading stays the audit origin.
        if state == .grantOffered, report.holdsPod {
            handleTakeoverComplete(TakeoverComplete(epoch: report.epoch, firstPodStatus: LoanPodStatus(timestamp: deps.now(), deliveredUnits: nil, reservoirLevel: nil, isSuspended: false, faultCode: report.podFault)))
        }

        if state == .grantOffered, report.knowsGrant == true, !report.holdsPod {
            let elapsed = grantOfferedAt.map { deps.now().timeIntervalSince($0) } ?? 0
            handbackDiag(report.epoch, String(format: "the watch is taking the pod over, %.0f s after lending", elapsed))
        }
        // The watch does not know this grant: no need to wait out the dead-man.
        if state == .grantOffered, report.knowsGrant == false, !report.holdsPod {
            t1WorkItem?.cancel()
            cancelNotification(id: NotificationID.t1)

            sendMessage(.denied(LoanDenied(reason: "The hand-over never reached the watch. The iPhone kept the pod. Tap Start again.")))
            reclaimToOwner(alert: nil, reason: "the watch never received the grant")
        }
        if let fault = report.podFault {
            handbackDiag(report.epoch, "the watch reports a pod fault: \(fault)")
            noticePodFault(fault, epoch: report.epoch)
        }
    }

    /// The watch alarms too, but the user may be nearer the phone.
    func noticePodFault(_ fault: String, epoch: Int) {
        let key = "\(epoch) \(fault)"
        guard podFaultNoticed != key else { return }
        podFaultNoticed = key
        // As the pod's own fault alert reads on the phone outside Sport Mode: the fault, then the stock body.
        deps.issueUrgentNotice(
            fault,
            NSLocalizedString("Insulin delivery stopped. Change Pod now.", comment: "Phone notice body when the watch reports a pod fault during a loan (the pod's own alarm text)"))
    }

}
