//
//  LoanControlTests.swift
//  LoopTests
//
//  SPORT_MODE_CONTROL.md, section 5, row by row: each test sets up what the acting device sees in that
//  row's physical configuration and checks the row's result. A different ruling for a row changes its
//  case in LoanControl.swift and its test here.
//

import XCTest
import LoopCore
import LoopKit

final class LoanControlTests: XCTestCase {

    private typealias C = LoanControl
    private let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    private func phone(_ trigger: C.Trigger, role: C.PhoneRole = .holdsPod, tookOver: Date? = nil,
                       sensorFresh: Bool = true, offlineCopyOut: Bool = true) -> C.Decision {
        C.decide(C.Situation(device: .phone, trigger: trigger, phoneRole: role, tookOverOnSilenceAt: tookOver,
                             sensorFresh: sensorFresh, offlineCopyOut: offlineCopyOut))
    }

    private func watch(_ trigger: C.Trigger, storedCopy: Bool = false) -> C.Decision {
        C.decide(C.Situation(device: .watch, trigger: trigger, watchHasStoredCopy: storedCopy))
    }

    // Rows 1 and 2 · Start tapped on the watch. The request is the query; with no answer, the offline
    // start is offered if the watch holds a copy, else the looper is told the phone did not answer.
    func testRows1And2_StartAsksThePhoneAndOffersTheOfflineStartOnSilence() {
        XCTAssertEqual(watch(.startTapped, storedCopy: true), .query(.onScreen, onSilence: .prompt(.startWithoutPhone)))
        XCTAssertEqual(watch(.startTapped, storedCopy: false), .query(.onScreen, onSilence: .tell(.noResponseFromPhone)))
    }

    // Row 3 · Phone dead or away, no loan: the watch takes nothing (deliberate exception); each word from
    // the phone pushes out a warning that fires after 25 minutes of silence, after the phone's own at 20.
    func testRow3_TheWatchWarnsAfterTwentyFiveMinutesWithoutThePhoneAndTakesNothing() {
        XCTAssertEqual(watch(.phoneHeardWithNoLoan), .tellIfSilent(.notHearingFromPhone, after: 25 * 60))
    }

    // Row 4 · Phone back, clean reading: carry on.
    func testRow4_ACleanReadingChangesNothing() {
        XCTAssertEqual(phone(.podReading(differenceBeyondBand: false)), .nothing)
    }

    // Rows 5 and 18 · A reading shows insulin from another device; the phone holds the pod: it asks,
    // and keeps the pod on silence.
    func testRows5And18_AnotherDevicesInsulinIsQueriedAndThePodKeptOnSilence() {
        XCTAssertEqual(phone(.podReading(differenceBeyondBand: true)), .query(.inBackground, onSilence: .keepPodOnSilence))
        XCTAssertEqual(phone(.podReading(differenceBeyondBand: true), offlineCopyOut: false), .nothing,
                       "no offline copy out: no watch could have started without this phone")
    }

    // Row 6 · A message about a loan the phone has ended: the stop again.
    func testRow6_AClosedLoanGetsTheStopAgain() {
        XCTAssertEqual(phone(.watchClaims(.init(loan: .closed))), .sendStop)
        XCTAssertEqual(phone(.watchClaims(.init(loan: .closed)), role: .standingAside), .nothing)
    }

    // Rows 7, 8 and 21 · End tapped: the offer is the query; silence refuses with how to stop dosing.
    func testRows7To8_EndAsksThePhoneAndIsRefusedOnSilence() {
        XCTAssertEqual(watch(.endTapped), .query(.onScreen, onSilence: .refuse(.phoneAwayCannotHandBack)))
        XCTAssertEqual(C.afterQuery(.answered, onSilence: .refuse(.phoneAwayCannotHandBack)), .nothing,
                       "row 7: the phone answered, the hand-back goes ahead")
        XCTAssertEqual(C.afterQuery(.silence, onSilence: .refuse(.phoneAwayCannotHandBack)), .refuse(.phoneAwayCannotHandBack),
                       "row 8: silence refuses")
    }

    // Row 9 · Take Back tapped on the phone: take, no query.
    func testRow9_TakeBackIsTheLoopersDecision() {
        XCTAssertEqual(phone(.takeBackTapped, role: .lending), .takeOnTap)
    }

    // Row 10 · The watch dies with the phone beside the body: ask, take on silence.
    func testRow10_ASilentWatchIsQueriedThenTakenFrom() {
        let decision = phone(.watchReportOverdue, role: .lending)
        XCTAssertEqual(decision, .query(.inBackground, onSilence: .takeOnSilence(.watchNotResponding)))
        XCTAssertEqual(C.afterQuery(.silence, onSilence: .takeOnSilence(.watchNotResponding)), .takeOnSilence(.watchNotResponding))
        XCTAssertEqual(C.afterQuery(.answered, onSilence: .takeOnSilence(.watchNotResponding)), .nothing, "a live watch answers: nothing moves")
    }

    // Rows 11 and 15 · The phone does not see the sensor: the body is elsewhere; nothing.
    func testRows11And15_AwayFromTheBodyThePhoneDoesNothing() {
        XCTAssertEqual(phone(.watchReportOverdue, role: .lending, sensorFresh: false), .nothing)
    }

    // Rows 12, 13 and 19, the watch's side · Back from off: ask first, carry on only on silence.
    func testRows12And13_AWatchBackFromOffAsksFirst() {
        XCTAssertEqual(watch(.backFromOff), .query(.inBackground, onSilence: .carryOn))
        XCTAssertEqual(C.afterQuery(.silence, onSilence: .carryOn), .carryOn, "row 13: nobody else holds the pod")
    }

    // Row 12, the phone's side · The revived watch claims a loan the phone has ended: the stop.
    func testRow12_ThePhoneThatHoldsThePodAnswersWithTheStop() {
        XCTAssertEqual(phone(.watchClaims(.init(loan: .closed))), .sendStop)
    }

    // Rows 14 and 20 · A holder that answers but cannot reach the pod is answered like silence.
    func testRows14And20_CannotReachThePodCountsAsSilence() {
        XCTAssertEqual(C.afterQuery(.holdsPodButCannotReach, onSilence: .takeOnSilence(.watchNotResponding)), .takeOnSilence(.watchNotResponding))
        XCTAssertEqual(C.afterQuery(.holdsPodButCannotReach, onSilence: .keepPodOnSilence), .keepPodOnSilence)
        XCTAssertEqual(phone(.watchClaims(.init(loan: .current, podReachable: false)), role: .lending), .nothing,
                       "and its report does not renew its hold")
    }

    // Transfer H (Q2) · A watch that let the pod go after an unacknowledged final offer answers "I hold
    // nothing": counted as silence, so the phone takes the pod instead of leaving it with nobody.
    func testAWatchThatHoldsNothingIsAnsweredLikeSilence() {
        XCTAssertEqual(C.afterQuery(.holdsNothing, onSilence: .takeOnSilence(.watchNotResponding)), .takeOnSilence(.watchNotResponding))
    }

    // Row 16 · The watch reporting on the live loan: its hold is renewed.
    func testRow16_AReportOnTheLiveLoanRenewsTheHold() {
        XCTAssertEqual(phone(.watchClaims(.init(loan: .current, podReachable: true)), role: .lending), .renewHold)
    }

    // Row 17 · A watch that started without the phone, alive: the phone stands aside.
    func testRow17_ThePhoneStandsAsideForALiveWatchsLoan() {
        XCTAssertEqual(phone(.watchClaims(.init(loan: .newer, startedAt: t0))), .standAside)
        XCTAssertEqual(phone(.watchClaims(.init(loan: .newer, startedAt: t0)), offlineCopyOut: false), .nothing,
                       "no offline copy out: no watch could have started without this phone")
    }

    // Row 19 · A watch back after the phone took over on silence: a loan started before the takeover is
    // refused; one started after is a fresh Start, honoured.
    func testRow19_ARevivedClaimIsRefusedAndAFreshStartHonoured() {
        let tookOver = t0.addingTimeInterval(.minutes(30))
        XCTAssertEqual(phone(.watchClaims(.init(loan: .newer, startedAt: t0)), tookOver: tookOver), .sendStop)
        XCTAssertEqual(phone(.watchClaims(.init(loan: .newer, startedAt: tookOver.addingTimeInterval(60))), tookOver: tookOver), .standAside)
        XCTAssertEqual(phone(.watchClaims(.init(loan: .newer, refusedBefore: true)), tookOver: tookOver), .sendStop,
                       "its records, which carry no start time, get the stop too")
    }

    // Rows 22 and 23 · No device can act: no trigger reaches `decide`. Anything else is not a decision point.
    func testOtherPairingsDecideNothing() {
        XCTAssertEqual(phone(.startTapped), .nothing)
        XCTAssertEqual(watch(.watchReportOverdue), .nothing)
    }

    func testTheWaits() {
        XCTAssertEqual(C.Wait.onScreen.seconds, 10)
        XCTAssertEqual(C.Wait.inBackground.seconds, 30)
        XCTAssertEqual(C.watchReportOverdue, 6 * 60)
    }
}
