//
//  PodLoanPhoneController+Hold.swift
//  Loop
//
//  The phone's side of `LoanControl`: it describes the situation, asks `LoanControl.decide`, and
//  carries out the decision. Who controls the pod is decided there, in SPORT_MODE_CONTROL.md's row
//  order; this file only observes and acts.
//

import Foundation
import LoopKit
import LoopCore

extension PodLoanPhoneController {
    /// The phone acts only if its own sensor reading is this fresh, i.e. it is near the user. Away from
    /// the user a dead watch and a distant one look the same, and the pod is out of reach anyway.
    static let nearTheBodyWindow: TimeInterval = .minutes(11)

    /// `LoanControl.Wait.inBackground`: every query this phone makes is in the background. Settable for tests.
    static var answerWait: TimeInterval = LoanControl.Wait.inBackground.seconds

    /// When the watch last reported a cycle. Persisted, so a relaunch is not read as silence.
    var holdRenewedAt: Date? {
        get { persisted.holdRenewedAt }
        set { updateState { $0.holdRenewedAt = newValue } }
    }

    /// The watch raises this user's glucose alerts while it has the pod. Read on main by the phone's
    /// alert managers, so it never waits on the loan queue.
    var watchOwnsAlerts: Bool {
        isLoanedOutForUI
    }

    /// Judged by send time: a batch that sat in a queue renews nothing.
    func noteHoldRenewal(sentAt: Date?) {
        let now = deps.now()
        let stamp = min(sentAt ?? now, now)
        // Never move the stamp backwards: batches can arrive out of order.
        guard stamp > (holdRenewedAt ?? .distantPast) else { return }
        holdRenewedAt = stamp
    }

    /// The last word from the watch about the loan this phone is standing aside for: its reports, or
    /// for a loan it started without this phone, its claims.
    var watchLastHeard: Date? {
        let told = state == .owner && yieldingToInferredLoan
        return told ? [holdRenewedAt, newestForeignLoanEvidence?.at].compactMap { $0 }.max() : holdRenewedAt
    }

    // MARK: - The situation, as this phone sees it

    var controlRole: LoanControl.PhoneRole {
        switch state {
        case .owner: return yieldingToInferredLoan ? .standingAside : .holdsPod
        case .loaned: return .lending
        default: return .transferring
        }
    }

    func controlSituation(_ trigger: LoanControl.Trigger) -> LoanControl.Situation {
        let reading = deps.latestGlucoseDate()
        let sensorFresh = reading.map { deps.now().timeIntervalSince($0) <= Self.nearTheBodyWindow } ?? false
        return LoanControl.Situation(device: .phone, trigger: trigger, phoneRole: controlRole,
                                     tookOverOnSilenceAt: persisted.tookOverOnSilenceAt,
                                     sensorFresh: sensorFresh, offlineCopyOut: persisted.seizeToken != nil)
    }

    /// Decides and carries out; returns the decision. `claimEpoch` is the loan a claim named, for a stop.
    @discardableResult
    func decideAndAct(_ trigger: LoanControl.Trigger, why: String, claimEpoch: Int? = nil) -> LoanControl.Decision {
        let decision = LoanControl.decide(controlSituation(trigger))
        carryOut(decision, why: why, claimEpoch: claimEpoch)
        return decision
    }

    // MARK: - Carrying out a decision

    func carryOut(_ decision: LoanControl.Decision, why: String, claimEpoch: Int? = nil) {
        switch decision {
        case .nothing, .carryOn:
            break
        case .query(_, let onSilence):
            askWatch(why: why) { [weak self] answer in
                self?.carryOut(LoanControl.afterQuery(answer, onSilence: onSilence), why: why, claimEpoch: claimEpoch)
            }
        case .keepPodOnSilence:
            updateState { $0.tookOverOnSilenceAt = deps.now() }
            handbackDiag(epoch, "no answer from the watch, or it cannot reach the pod — this phone keeps the pod and keeps looping (\(why))")
        case .takeOnSilence(let tell):
            guard state == .loaned || (state == .owner && yieldingToInferredLoan) else { return }
            updateState { $0.tookOverOnSilenceAt = deps.now() }
            handbackDiag(epoch, "the watch did NOT answer, or cannot reach the pod — taking the pod back (\(why))")
            tellLooper(tell)
            reclaimNow()
        case .takeOnTap:
            reclaimNow()
        case .standAside:
            engageInferredLoanYield(evidence: why)
        case .sendStop:
            guard let claimEpoch else { return }
            resendRevokeForClosedSession(epoch: claimEpoch, evidence: why)
        case .renewHold:
            noteHoldRenewal(sentAt: deps.now())
        case .refuse, .prompt, .tell:
            // The watch's decisions; never returned for the phone.
            break
        }
    }

    func tellLooper(_ tell: LoanControl.Tell) {
        switch tell {
        case .watchNotResponding:
            deps.issueUrgentNotice(
                NSLocalizedString("Watch Not Responding", comment: "Phone notice title: the watch did not answer and the phone is taking the pod back"),
                NSLocalizedString("The watch stopped reporting and didn't answer. This phone is taking the pod back; insulin the watch gave is counted.", comment: "Phone notice body: the phone takes the pod back from a silent watch"))
        case .phoneAwayCannotHandBack, .noResponseFromPhone:
            break
        }
    }

    // MARK: - Observations that ask for a decision

    /// Called every phone cycle: the watch's report overdue is rows 10, 11, 14 and 15.
    func considerHoldLapse() {
        queue.async { self.queue_considerHoldLapse() }
    }

    func queue_considerHoldLapse() {
        guard state == .loaned || (state == .owner && yieldingToInferredLoan), watchAskedAt == nil,
              let heard = watchLastHeard else { return }
        let silence = deps.now().timeIntervalSince(heard)
        guard silence > LoanControl.watchReportOverdue else { return }
        decideAndAct(.watchReportOverdue, why: String(format: "no report from the watch for %.0f min", silence / 60))
    }

    /// The Take Back tap: row 9.
    func takeBackTapped() {
        queue.async { self.decideAndAct(.takeBackTapped, why: "Take Back tapped") }
    }

    // MARK: - The query

    /// Asks the watch whether it holds the pod and hands back what came of it: an answer (any word from
    /// the watch within the wait), "holds it but cannot reach it", or silence.
    func askWatch(why: String, then: @escaping (LoanControl.Answer) -> Void) {
        guard watchAskedAt == nil else { return }
        let askedAt = deps.now()
        let heardBefore = watchLastHeard
        let foreignBefore = newestForeignLoanEvidence?.at
        watchAskedAt = askedAt
        handbackDiag(epoch, "asking the watch whether it holds the pod — \(why)")
        sendMessage(.statusQuery(StatusQuery(epoch: epoch)))
        queue.asyncAfter(deadline: .now() + Self.answerWait) { [weak self] in
            guard let self = self, self.watchAskedAt == askedAt else { return }
            self.watchAskedAt = nil
            let reported = self.lastWatchAnswerAt.map { $0 >= askedAt } == true
            let answer: LoanControl.Answer
            if reported && self.lastWatchAnswerCannotReachPod {
                answer = .holdsPodButCannotReach
            } else if reported && self.lastWatchAnswerHoldsNothing {
                answer = .holdsNothing
            } else if reported || self.watchLastHeard != heardBefore || self.newestForeignLoanEvidence?.at != foreignBefore {
                answer = .answered
            } else {
                answer = .silence
            }
            if answer == .answered { self.handbackDiag(self.epoch, "the watch answered — nothing changes hands on silence") }
            then(answer)
        }
    }
}
