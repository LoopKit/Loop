//
//  PodLoanPhoneController+Hold.swift
//  Loop
//
//  The phone's side of `LoanControl`: it describes the situation, asks `LoanControl.decide`, and
//  carries out the decision. Who controls the pod is decided there, in the row order of
//  Documentation/SportMode/Control.md; this file only observes and acts.
//

import Foundation
import LoopKit
import LoopCore

extension PodLoanPhoneController {
    /// The phone acts only if its own sensor reading is this fresh, i.e. it is near the user. Away from
    /// the user a dead watch and a distant one look the same, and the pod is out of reach anyway.
    static let nearTheBodyWindow: TimeInterval = .minutes(11)

    /// `LoanControl.Wait.inBackground`: every query this phone makes is in the background. Silence is
    /// judged no sooner than this after asking, at the next cycle. Settable for tests.
    static var answerWait: TimeInterval = LoanControl.Wait.inBackground.seconds

    /// When the watch last reported a cycle. Persisted, so a relaunch is not read as silence.
    var holdRenewedAt: Date? {
        get { persisted.holdRenewedAt }
        set { updateState { $0.holdRenewedAt = newValue } }
    }

    /// The watch raises this user's glucose alerts while it has the pod.
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
        case .query(_, let onSilence, let onHoldsNothing):
            askWatch(why: why, onSilence: onSilence, onHoldsNothing: onHoldsNothing, claimEpoch: claimEpoch)
        case .keepPodOnSilence:
            updateState { $0.tookOverOnSilenceAt = deps.now() }
            handbackDiag(epoch, "this phone keeps the pod and keeps looping: no answer from the watch, or it cannot reach the pod; \(why)")
        case .takeOnSilence(let tell):
            guard state == .loaned || (state == .owner && yieldingToInferredLoan) else { return }
            updateState { $0.tookOverOnSilenceAt = deps.now() }
            handbackDiag(epoch, "taking the pod back: no answer from the watch, or it cannot reach the pod; \(why)")
            tellLooper(tell)
            reclaimNow(onSilence: true)
        case .takeOnTap:
            // A loan this phone never lent, whose pod the watch deactivated (row 27): stop it and forget the pod.
            if !podIsOnLoan, let claimEpoch, persisted.podDeactivatedOnWatch != nil {
                sendMessage(.revoke(Revoke(epoch: claimEpoch)))
                reclaimPodConnection()
                return
            }
            reclaimNow()
        case .standAside:
            engageInferredLoanYield(evidence: why)
        case .sendStop:
            guard let claimEpoch else { return }
            resendRevokeForClosedSession(epoch: claimEpoch, evidence: why)
        case .renewHold:
            noteHoldRenewal(sentAt: deps.now())
        case .tell(let tell):
            // Once for each silent stretch: the question is asked again every cycle while it lasts.
            guard silenceWarnedFor != watchLastHeard else { return }
            silenceWarnedFor = watchLastHeard
            handbackDiag(epoch, "telling the looper the watch may not be looping: no answer from the watch, or it cannot reach the pod; \(why)")
            tellLooper(tell)
        case .refuse, .prompt, .tellIfSilent:
            // The watch's decisions; never returned for the phone.
            break
        }
    }

    func tellLooper(_ tell: LoanControl.Tell) {
        switch tell {
        case .watchNotResponding:
            deps.issueUrgentNotice(
                NSLocalizedString("Watch Not Looping", comment: "Phone notice title: the watch did not answer, or cannot reach the pod, and the phone is taking the pod back"),
                NSLocalizedString("The watch has stopped looping (off or out of range). This iPhone is taking the pod back; insulin the watch gave is counted.", comment: "Phone notice body: the phone takes the pod back from a silent watch"))
        case .watchMayNotBeLooping:
            deps.issueUrgentNotice(
                NSLocalizedString("Watch May Not Be Looping", comment: "Phone notice title: the watch has not reported and did not answer, and the phone could loop"),
                NSLocalizedString("Usually it missed glucose readings. This iPhone can loop: open Loop and tap the pod to take it back.", comment: "Phone notice body: the watch may not be looping; the looper can take the pod back"))
        case .phoneAwayCannotHandBack, .noResponseFromPhone, .noResponseFromPhoneAndNoCGM, .notHearingFromPhone,
             .podDeactivatedPhoneAway:
            break
        }
    }

    // MARK: - Observations that ask for a decision

    /// Called every phone cycle: the watch's report overdue is rows 10, 11, 14 and 15.
    func considerHoldLapse() {
        guard state == .loaned || (state == .owner && yieldingToInferredLoan), watchAskedAt == nil,
              let heard = watchLastHeard else { return }
        let silence = deps.now().timeIntervalSince(heard)
        guard silence > LoanControl.watchReportOverdue else { return }
        decideAndAct(silence >= LoanControl.watchSilenceWarning ? .watchSilentLong : .watchReportOverdue,
                     why: String(format: "no report from the watch for %.0f min", silence / 60))
    }

    /// The Take Back tap: row 9.
    func takeBackTapped() {
        decideAndAct(.takeBackTapped, why: "Take Back tapped")
    }

    // MARK: - The query

    /// A question to the watch, open until its answer arrives or a later cycle judges its silence.
    struct OpenQuestion {
        let askedAt: Date
        let epoch: Int
        let role: LoanControl.PhoneRole
        let heardBefore: Date?
        let foreignBefore: Date?
        let why: String
        let onSilence: LoanControl.Decision
        let onHoldsNothing: LoanControl.Decision?
        let claimEpoch: Int?
    }

    var watchAskedAt: Date? { openQuestion?.askedAt }

    /// Asks the watch whether it holds the pod. No countdown: this phone is usually asleep, and a timer
    /// would act minutes late on what it knew when it asked. The answer is acted on when it arrives
    /// (`answerArrived`); silence is judged at the first cycle at least `answerWait` after asking
    /// (`judgeOpenQuestion`), in practice the next sensor reading.
    func askWatch(why: String, onSilence: LoanControl.Decision, onHoldsNothing: LoanControl.Decision?, claimEpoch: Int?) {
        guard openQuestion == nil else { return }
        openQuestion = OpenQuestion(askedAt: deps.now(), epoch: epoch, role: controlRole, heardBefore: watchLastHeard,
                                    foreignBefore: newestForeignLoanEvidence?.at, why: why, onSilence: onSilence,
                                    onHoldsNothing: onHoldsNothing, claimEpoch: claimEpoch)
        handbackDiag(epoch, "asking the watch whether it holds the pod: \(why)")
        sendMessage(.statusQuery(StatusQuery(epoch: epoch)))
    }

    /// A status report from the watch answers the open question now.
    func answerArrived() {
        settleOpenQuestion(silenceIsDue: false)
    }

    /// Each cycle: an open question still unanswered `answerWait` after it was asked is silence.
    func judgeOpenQuestion() {
        settleOpenQuestion(silenceIsDue: true)
    }

    /// An answer is any word from the watch since asking: a report (which may say it holds nothing, or
    /// holds the pod but cannot reach it), its records, or its claims.
    private func settleOpenQuestion(silenceIsDue: Bool) {
        guard let question = openQuestion else { return }
        // The question was about one situation, this loan and this phone's role; a verdict for
        // another is moot.
        guard epoch == question.epoch, controlRole == question.role else {
            openQuestion = nil
            handbackDiag(question.epoch, "question to the watch dropped: the loan or this phone's role changed while waiting")
            return
        }
        let reported = lastWatchAnswerAt.map { $0 >= question.askedAt } == true
        let answer: LoanControl.Answer
        if reported && lastWatchAnswerCannotReachPod {
            answer = .holdsPodButCannotReach
        } else if reported && lastWatchAnswerHoldsNothing {
            answer = .holdsNothing
        } else if reported || watchLastHeard != question.heardBefore || newestForeignLoanEvidence?.at != question.foreignBefore {
            answer = .answered
        } else {
            guard silenceIsDue, deps.now().timeIntervalSince(question.askedAt) >= Self.answerWait else { return }
            answer = .silence
        }
        openQuestion = nil
        if answer == .answered { handbackDiag(epoch, "the watch answered: nothing changes hands") }
        carryOut(LoanControl.afterQuery(answer, onSilence: question.onSilence, onHoldsNothing: question.onHoldsNothing),
                 why: question.why, claimEpoch: question.claimEpoch)
    }
}
