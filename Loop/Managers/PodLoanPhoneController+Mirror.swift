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

    /// Take the radio back; every route back to ownership must call it. A pod the looper deactivated
    /// on the watch is forgotten instead (rows 26 and 27).
    func reclaimPodConnection() {
        guard let control = deps.pumpManager() as? ExclusiveDeviceControl else { return }
        if let deactivatedIn = persisted.podDeactivatedOnWatch {
            // Only the pod this phone let go of: one paired here since is not the watch's to end.
            guard control.isControlReleased else {
                updateState { $0.podDeactivatedOnWatch = nil }
                handbackDiag(deactivatedIn, "the watch deactivated a pod this phone no longer holds released; nothing forgotten")
                return reclaimPodConnection()
            }
            forgetPodDeactivatedOnWatch(control, loan: deactivatedIn)
            return
        }
        reclaimForgotPod = false
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

    static let grantNotTakenNotice = (
        title: NSLocalizedString("The Watch Didn't Take the Pod", comment: "Phone notice title: a grant the watch never confirmed"),
        body: NSLocalizedString("Sport Mode didn't start on the watch. This iPhone kept the pod and is looping.", comment: "Phone notice body: a grant the watch never confirmed"))

    /// A grant waits for the watch's word: its confirmation, its failure, or "no such grant", each acted
    /// on when it arrives. No countdown: this phone is usually asleep and would act late. After the
    /// grant's lease the watch refuses it, so the first cycle past the lease takes an unconfirmed grant
    /// back without asking (`considerUnconfirmedTakeover`).
    func awaitTakeover() {
        if grantOfferedAt == nil { grantOfferedAt = deps.now() }
    }

    /// Each cycle while a grant is out.
    func considerUnconfirmedTakeover() {
        guard state == .grantOffered, let offeredAt = grantOfferedAt,
              deps.now().timeIntervalSince(offeredAt) >= LoanControl.takeoverLease else { return }
        reclaimToOwner(alert: Self.grantNotTakenNotice, reason: "the takeover lease ended unconfirmed")
    }

    /// The watch has the pod; the audit is measured from the total it first read.
    func handleTakeoverComplete(_ complete: TakeoverComplete) {
        guard complete.epoch == epoch, state == .grantOffered else { return }
        noteHoldRenewal(sentAt: complete.firstPodStatus.timestamp)
        grantOfferedAt = nil

        if let atTakeover = complete.firstPodStatus.deliveredUnits {
            noteTakeoverReading(units: atTakeover, at: complete.firstPodStatus.timestamp)
        }
        state = .loaned

    }

    /// An explicit failure is safe to act on at once.
    func handleTakeoverFailed(_ failed: TakeoverFailed) {
        guard failed.epoch == epoch, state == .grantOffered else { return }

        reclaimToOwner(alert: nil, reason: "the watch could not take the pod: \(failed.reason)")
    }

    /// The watch's word by Apple push, from a watch that started a loan without this phone and has its
    /// own internet. Taken as the same message over WatchConnectivity would be, once it shows this phone's
    /// own offline-start credential and is recent; anything else is logged and dropped.
    func handlePush(_ push: LoanPush) {
        let age = deps.now().timeIntervalSince(push.sentAt)
        let line = String(format: "push from the watch, sent %.0f s ago", age)
        guard push.token == persisted.seizeToken else {
            PhoneLog.event("push", "\(line): ignored, not this phone's offline-start credential")
            return
        }
        guard age <= LoanPush.maxAge else {
            PhoneLog.event("push", "\(line): ignored, too old")
            return
        }
        guard case .statusReport(let report) = push.message else {
            PhoneLog.event("push", "\(line): ignored, not a status report")
            return
        }
        PhoneLog.event("push", "\(line): the watch holds the pod on e\(report.epoch)")
        handleStatusReport(report)
    }

    /// The one place an ungranted loan can be recognised. `knowsGrant` nil means no information;
    /// only an explicit false may act. A pod fault is announced once.
    func handleStatusReport(_ report: StatusReport) {
        // Any report answers a question this phone asked (`askWatch`), once the report's own decisions are made.
        lastWatchAnswerAt = deps.now()
        lastWatchAnswerCannotReachPod = report.holdsPod && report.podReachable == false
        lastWatchAnswerHoldsNothing = !report.holdsPod
        defer { answerArrived() }
        if report.holdsPod {
            let loan: LoanControl.ClaimedLoan = report.epoch > epoch ? .newer
                : (report.epoch == epoch && state != .owner ? .current : .closed)
            if report.podDeactivated, loan != .closed { notePodDeactivatedOnWatch(loan: report.epoch) }
            let claim = LoanControl.Claim(loan: loan, startedAt: report.loanStartedAt, podReachable: report.podReachable,
                                          refusedBefore: refusedRevivedEpochs.contains(report.epoch),
                                          podDeactivated: report.podDeactivated)
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
            sendMessage(.denied(LoanDenied(reason: "The hand-over never reached the watch. The iPhone kept the pod. Tap Start again.")))
            reclaimToOwner(alert: nil, reason: "the watch never received the grant")
        }
        if let fault = report.podFault {
            handbackDiag(report.epoch, "the watch reports a pod fault: \(fault)")
            noticePodFault(fault, epoch: report.epoch)
        }
    }

    /// Kept until the phone's next return to the pod, which forgets it.
    func notePodDeactivatedOnWatch(loan: Int) {
        guard persisted.podDeactivatedOnWatch != loan else { return }
        updateState { $0.podDeactivatedOnWatch = loan }
        handbackDiag(loan, "the watch deactivated the pod; this phone forgets it when Sport Mode ends")
    }

    /// The watch booked the pod's last delivery, so nothing is booked here, and there is no pod to read:
    /// the insulin check rules on the watch's last reading, and no settle window opens.
    private func forgetPodDeactivatedOnWatch(_ control: ExclusiveDeviceControl, loan: Int) {
        updateState { $0.podDeactivatedOnWatch = nil }
        reclaimForgotPod = true
        if let pending = pendingHandbackAudit {
            ruleOnWatchReading(pending)
        }
        Task { await control.forgetDeviceDeactivatedElsewhere() }
        deps.pumpControlChanged(false)
        handbackDiag(loan, "the pod was deactivated on the watch: forgotten here; pair a new pod")
        deps.issueUrgentNotice(
            NSLocalizedString("Pod Deactivated on the Watch", comment: "Phone notice title: the looper deactivated the faulted pod on the watch"),
            NSLocalizedString("Pair a new pod to resume insulin delivery.", comment: "Phone notice body: the looper deactivated the faulted pod on the watch"))
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
