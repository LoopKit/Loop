//
//  LoanControl.swift
//  LoopCore
//
//  Who controls the pod: the decisions of Documentation/SportMode/Control.md, section 5, as one function. Both apps
//  describe the situation at each decision point, call `decide`, and carry out what it returns; the
//  mechanisms (take back, stand aside, query, hand back) decide nothing. One case per row, in the
//  document's order; each case's comment is the row's reason. A different ruling for a row is a change
//  to its case and to its test in LoanControlTests.
//
//  The document's physical-configuration columns (where a device is, whether it is alive) are not
//  inputs: no device can know them. The inputs are the control state and what the acting device can
//  see; the physical columns become the tests' scenarios.
//

import Foundation

public enum LoanControl {

    // MARK: - Inputs

    public enum Device: Equatable {
        case phone, watch
    }

    /// The phone's part in control, as it knows it.
    public enum PhoneRole: Equatable {
        /// The resting state: it holds the pod and loops.
        case holdsPod
        /// It lent the pod to the watch (a grant, or a loan it adopted).
        case lending
        /// It stands aside for a loan the watch started without it.
        case standingAside
        /// Mid-transfer (a grant out, a hand-back being written, a take-back reaching for the pod):
        /// transfers decide for themselves.
        case transferring
    }

    /// How the loan the watch claims relates to the phone's own record.
    public enum ClaimedLoan: Equatable {
        /// One the phone has ended.
        case closed
        /// The phone's live loan.
        case current
        /// One newer than any the phone knows: started on the watch without it.
        case newer
    }

    /// The watch saying it holds the pod: a status report, or records.
    public struct Claim: Equatable {
        public var loan: ClaimedLoan
        /// When the loan started, or the latest it could have: a report says it; records bound it by
        /// their first record or their send time. A bound before the takeover is as sure as the time.
        public var startedAt: Date?
        /// Whether the watch read the pod within its last cycle; nil when not said.
        public var podReachable: Bool?
        /// The phone already refused this loan as a revived claim.
        public var refusedBefore: Bool

        public init(loan: ClaimedLoan, startedAt: Date? = nil, podReachable: Bool? = nil, refusedBefore: Bool = false) {
            self.loan = loan
            self.startedAt = startedAt
            self.podReachable = podReachable
            self.refusedBefore = refusedBefore
        }
    }

    /// What just happened, as the acting device sees it.
    public enum Trigger: Equatable {
        // The watch's taps and events
        case startTapped
        case endTapped
        /// The watch app is back from being off (dead, or relaunched) with a loan saved.
        case backFromOff
        /// A message from the phone while no loan runs: the watch hears the phone, which loops (state 1).
        case phoneHeardWithNoLoan

        // The phone's observations and taps
        /// A pod reading: whether it shows a difference from the phone's records beyond the band.
        case podReading(differenceBeyondBand: Bool)
        /// No report from the watch for longer than a cycle.
        case watchReportOverdue
        case watchClaims(Claim)
        case takeBackTapped
    }

    public struct Situation: Equatable {
        public var device: Device
        public var trigger: Trigger
        /// The phone's role; ignored on the watch.
        public var phoneRole: PhoneRole
        /// When the phone last took control on silence.
        public var tookOverOnSilenceAt: Date?
        /// The phone sees the sensor, so it is near the body (and the pod).
        public var sensorFresh: Bool
        /// The phone left an offline-start copy with the watch, so the watch could have started without it.
        public var offlineCopyOut: Bool
        /// The watch holds an offline-start copy.
        public var watchHasStoredCopy: Bool

        public init(device: Device, trigger: Trigger, phoneRole: PhoneRole = .holdsPod, tookOverOnSilenceAt: Date? = nil,
                    sensorFresh: Bool = true, offlineCopyOut: Bool = false, watchHasStoredCopy: Bool = false) {
            self.device = device
            self.trigger = trigger
            self.phoneRole = phoneRole
            self.tookOverOnSilenceAt = tookOverOnSilenceAt
            self.sensorFresh = sensorFresh
            self.offlineCopyOut = offlineCopyOut
            self.watchHasStoredCopy = watchHasStoredCopy
        }
    }

    // MARK: - Outputs

    /// How long a query waits for its answer before silence counts.
    public enum Wait: Equatable {
        /// The looper waits on screen (Start, End): the watch app is in front and its live path usually
        /// works; a late answer costs a second tap.
        case onScreen
        /// In the background a question and its answer may each travel queued; the slowest one-way
        /// delivery seen was 15 s and a round trip took 15.5 s. A late answer here moves control wrongly,
        /// so the wait covers twice the slowest delivery.
        case inBackground

        public var seconds: TimeInterval {
            switch self {
            case .onScreen: return 10
            case .inBackground: return 30
            }
        }
    }

    /// What the looper is told.
    public enum Tell: Equatable {
        case watchNotResponding
        case phoneAwayCannotHandBack
        case noResponseFromPhone
        case notHearingFromPhone
    }

    public enum Prompt: Equatable {
        case startWithoutPhone
    }

    public indirect enum Decision: Equatable {
        case nothing
        /// Ask the other device whether it holds the pod. An answer that says it does is acted on where
        /// it lands; silence, or "I hold it but cannot reach it", leads to `onSilence` (`afterQuery`).
        case query(Wait, onSilence: Decision)
        /// Phone: it already holds the pod and keeps it; remember the takeover on silence.
        case keepPodOnSilence
        /// Phone: take the pod back after silence; remember the takeover; tell.
        case takeOnSilence(Tell)
        /// Phone: take the pod back because the looper tapped.
        case takeOnTap
        /// Phone: stand aside for the watch's loan.
        case standAside
        /// Phone: send the stop for the claimed loan.
        case sendStop
        /// Phone: the watch is still there; renew its hold.
        case renewHold
        /// Watch: carry on with what it was last told.
        case carryOn
        /// Watch: refuse the looper's tap and say why.
        case refuse(Tell)
        case prompt(Prompt)
        case tell(Tell)
        /// Watch: tell the looper if nothing more is heard within `after`; each new word pushes it out.
        /// Pre-scheduled, so it fires even if the watch app is not running.
        case tellIfSilent(Tell, after: TimeInterval)
    }

    /// What came back to a query.
    public enum Answer: Equatable {
        case silence
        case holdsPodButCannotReach
        /// The other device says it does not hold the pod (a watch that let it go, or never had it).
        case holdsNothing
        /// Anything else: the other device is there, and its message is acted on where it lands.
        case answered
    }

    /// The one rule for answers. Silence means the other device is not looping; so does "I hold it but
    /// cannot reach it" (rows 14, 20) and "I hold nothing" (a watch that let the pod go after a hand-back
    /// whose final offer went unacknowledged, transfer H: without this the phone would leave the pod
    /// with nobody).
    public static func afterQuery(_ answer: Answer, onSilence: Decision) -> Decision {
        switch answer {
        case .silence, .holdsPodButCannotReach, .holdsNothing: return onSilence
        case .answered: return .nothing
        }
    }

    /// The watch's report is overdue after this long without one: one loop cycle and a margin.
    public static let watchReportOverdue: TimeInterval = 6 * 60

    /// With no loan running, the watch warns when it has heard nothing from the phone for this long:
    /// after the phone's own pre-scheduled Loop Failure (20 min), which reaches the wrist when the phone is
    /// near or by a cellular watch's relay (seen 10-18), so the watch's is the backup for a dead phone or
    /// a watch with no route to it.
    public static let notHearingFromPhoneWarning: TimeInterval = 25 * 60

    // MARK: - The decisions, row by row

    public static func decide(_ s: Situation) -> Decision {
        switch (s.device, s.trigger) {

        // Rows 1 and 2 · Start tapped on the watch. The request is the query. The phone answers with a
        // grant (a transfer, decided there). With no answer, the phone is away or dead; starting from the
        // stored copy is entering Sport Mode, which needs the looper's tap, so it is offered, as the
        // nearest thing to the refused Start.
        case (.watch, .startTapped):
            return .query(.onScreen, onSilence: s.watchHasStoredCopy ? .prompt(.startWithoutPhone) : .tell(.noResponseFromPhone))

        // Row 3 · The phone is dead or away and no loan runs. Deliberate exception: looping is safer,
        // but taking the pod would enter Sport Mode without a tap, and the watch cannot tell a dead phone
        // from one left at home. Nothing is taken; the looper is told. This state is easy to enter and
        // rarely chosen (a forgotten phone), so the watch warns once when the phone has been silent for
        // 25 minutes, and Start is one tap away. Each word from the phone pushes the warning out. The phone
        // talks with its loop cycles, so a phone that stops looping also goes quiet; its own Loop Failure
        // at 20 minutes comes first, and the watch's is the backup for a dead phone.
        case (.watch, .phoneHeardWithNoLoan):
            return .tellIfSilent(.notHearingFromPhone, after: notHearingFromPhoneWarning)

        // Row 4 · A clean reading: the resting state carries on.
        // Rows 5 and 18 · A reading shows insulin the phone's records cannot explain, so another device
        // controlled the pod. The insulin is booked regardless (rule 1, in the ledger). The phone already
        // holds the pod, so asking can only end with it standing aside (the watch says it holds a loan,
        // row 17) or keeping the pod.
        case (.phone, .podReading(let beyondBand)):
            guard beyondBand, s.phoneRole == .holdsPod, s.offlineCopyOut else { return .nothing }
            return .query(.inBackground, onSilence: .keepPodOnSilence)

        // Rows 6, 12, 16, 17 and 19 · The watch says it holds the pod.
        case (.phone, .watchClaims(let claim)):
            switch claim.loan {
            // Row 6, and row 12 from the phone's side · A loan the phone has ended: the watch missed the
            // stop, so it gets it again.
            case .closed:
                return s.phoneRole == .holdsPod ? .sendStop : .nothing
            // Row 16 · The watch reporting on the live loan is still there, unless it says it cannot
            // reach the pod (row 14), which is not renewed.
            case .current:
                return s.phoneRole == .lending && claim.podReachable != false ? .renewHold : .nothing
            case .newer:
                guard s.phoneRole == .holdsPod else { return .nothing }
                // Row 19 · A watch back from off claiming a loan started before this phone took over on
                // silence. A watch's word normally makes the phone stand aside, because a watch that says
                // it holds a loan is usually looping it. But this watch was out of the conversation: the
                // phone queried, heard nothing, and has looped since. Standing aside would move control,
                // silently, to a device the looper stopped using. The takeover stands; a loan started
                // after it is a fresh Start, honoured below.
                if claim.refusedBefore || startedBefore(claim.startedAt, s.tookOverOnSilenceAt) {
                    return .sendStop
                }
                // Row 17 · A watch that started without the phone and is alive: the looper's latest
                // decision was that Start; the phone's return is not a decision.
                return s.offlineCopyOut ? .standAside : .nothing
            }

        // Rows 7, 8 and 21 · End tapped on the watch. The hand-back offer is the query. With the phone
        // there, the hand-back goes ahead (a transfer). With no answer the End is refused: it names an
        // action that needs the phone, and what the looper meant may be "stop dosing", which can be done,
        // so the refusal says how.
        case (.watch, .endTapped):
            return .query(.onScreen, onSilence: .refuse(.phoneAwayCannotHandBack))

        // Row 9 · Take Back tapped on the phone: the looper's latest decision; no query needed.
        case (.phone, .takeBackTapped):
            return .takeOnTap

        // Rows 10 and 14 · No report from the watch for longer than a cycle, with the phone beside the
        // body. A live watch on the wrist answers within seconds; silence (or "cannot reach the pod")
        // means it is not looping, and looping conservatively is safer than not looping. The watch's
        // first word would end a mistake.
        // Rows 11 and 15 · The phone does not see the sensor: the body is elsewhere, nothing to act on.
        case (.phone, .watchReportOverdue):
            guard s.sensorFresh, s.phoneRole == .lending || s.phoneRole == .standingAside else { return .nothing }
            return .query(.inBackground, onSilence: .takeOnSilence(.watchNotResponding))

        // Rows 12, 13 and 19 · The watch back from off. It cannot know what was decided while it was out,
        // so it asks before touching the pod. A phone that holds the pod answers with the stop, acted on
        // where it lands. With no answer it is the only device there and carries on.
        case (.watch, .backFromOff):
            return .query(.inBackground, onSilence: .carryOn)

        // Rows 11, 15, 22 and 23 have no acting device. Any other pairing is not a decision point.
        default:
            return .nothing
        }
    }

    /// Row 19's test: a loan started before this phone took over on silence. No start time: not refused.
    static func startedBefore(_ started: Date?, _ tookOver: Date?) -> Bool {
        guard let started, let tookOver else { return false }
        return started < tookOver
    }
}
