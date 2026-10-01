//
//  HandbackWedgeTests.swift
//  WatchAppTests
//
//  The hand-back wedge discriminator's full truth table. This shipped with no tests, and it
//  decides which of two OPPOSITE instructions the user gets when a hand-back hangs: force-quit
//  the watch app, or wait a minute. Getting it backwards sends them to the wrong device.
//
//  Testable because the decision is now a pure function. Before that it was two separate
//  if/else-if chains inside handbackTimedOut() — evaluated twice, so the log line and the alert
//  could disagree — behind a path that needs a live pump manager.
//

import XCTest
import LoopKit
import LoopAlgorithm
import LoopCore
@testable import WatchApp

final class HandbackWedgeTests: XCTestCase {

    // MARK: - The two variants

    /// Variant A: offers went out, the phone was reachable throughout, no acks, and the sends
    /// themselves reported success. Only a watch-app restart has ever recovered this.
    func testReachableThroughoutWithSilentSendsIsTheOneWayWedge() {
        XCTAssertEqual(
            HandbackWedge.classify(resendCount: 3, sawUnreachable: false, reachableNow: true, sendsErrored: false),
            .oneWay)
    }

    /// Variant B: same picture, except the sends ERRORED. That is a session tearing down and
    /// re-establishing, and the queued fallback delivers when it returns — so the advice is
    /// "wait", not "force-quit".
    func testErroringSendsAreTheReestablishingSessionNotTheWedge() {
        XCTAssertEqual(
            HandbackWedge.classify(resendCount: 3, sawUnreachable: false, reachableNow: true, sendsErrored: true),
            .sessionReestablishing)
    }

    // MARK: - Everything that must NOT be called a wedge
    //
    // These matter more than the positives. A false wedge tells the user to force-quit the
    // watch app during a hand-back — the most disruptive advice the app can give — for what is
    // usually an ordinary phone-out-of-range hang that would have healed on its own.

    /// Under three offers there is not enough evidence yet, whatever else is true.
    func testTooFewOffersIsNeverAWedge() {
        for count in 0...2 {
            XCTAssertEqual(
                HandbackWedge.classify(resendCount: count, sawUnreachable: false, reachableNow: true, sendsErrored: false),
                .none, "\(count) offers is not enough evidence")
            XCTAssertEqual(
                HandbackWedge.classify(resendCount: count, sawUnreachable: false, reachableNow: true, sendsErrored: true),
                .none, "\(count) offers is not enough evidence, erroring sends included")
        }
    }

    /// A phone that went away even ONCE explains the hang innocently. This is the sticky flag:
    /// it must veto the wedge even though the phone is reachable again right now, which is the
    /// common case by the time the timeout fires.
    func testAPhoneThatWasEverUnreachableVetoesTheWedge() {
        XCTAssertEqual(
            HandbackWedge.classify(resendCount: 9, sawUnreachable: true, reachableNow: true, sendsErrored: false),
            .none, "one unreachable moment explains the hang without a wedge")
        XCTAssertEqual(
            HandbackWedge.classify(resendCount: 9, sawUnreachable: true, reachableNow: true, sendsErrored: true),
            .none)
    }

    /// A phone that is out of range AT the timeout is the ordinary case, not a wedge.
    func testAnUnreachablePhoneAtTimeoutIsNotAWedge() {
        XCTAssertEqual(
            HandbackWedge.classify(resendCount: 9, sawUnreachable: false, reachableNow: false, sendsErrored: false),
            .none)
    }

    // MARK: - Boundary

    /// Three is the threshold, and it is inclusive. Two is not enough; three is.
    func testThreeOffersIsTheInclusiveThreshold() {
        XCTAssertEqual(
            HandbackWedge.classify(resendCount: 2, sawUnreachable: false, reachableNow: true, sendsErrored: false),
            .none)
        XCTAssertEqual(
            HandbackWedge.classify(resendCount: 3, sawUnreachable: false, reachableNow: true, sendsErrored: false),
            .oneWay)
    }

    /// Exhaustive over the whole input space that matters, so no combination is unspecified.
    /// A wedge requires ALL THREE of: enough offers, never unreachable, reachable now — and
    /// only then does `sendsErrored` choose between the variants.
    func testFullTruthTable() {
        for count in [0, 2, 3, 10] {
            for sawUnreachable in [false, true] {
                for reachableNow in [false, true] {
                    for sendsErrored in [false, true] {
                        let actual = HandbackWedge.classify(resendCount: count,
                                                            sawUnreachable: sawUnreachable,
                                                            reachableNow: reachableNow,
                                                            sendsErrored: sendsErrored)
                        let expected: HandbackWedge
                        if count >= 3 && !sawUnreachable && reachableNow {
                            expected = sendsErrored ? .sessionReestablishing : .oneWay
                        } else {
                            expected = .none
                        }
                        XCTAssertEqual(actual, expected,
                                       "count=\(count) sawUnreachable=\(sawUnreachable) reachableNow=\(reachableNow) sendsErrored=\(sendsErrored)")
                    }
                }
            }
        }
    }
}

// MARK: - The counter that fed it

/// The wedge verdict and the drain's give-up rule both read `handbackResendCount`, and it used to
/// be reset in exactly one place: `beginHandback`. A drain reaches the give-up path without ever
/// running through that, so the count survived the session that earned it.
///
/// The consequence is the detector switching itself off: the next drain starts already at the
/// ceiling, gives up after a single offer, and its wedge verdict describes a session that ended.
/// The two flags feeding `classify` had the same lifetime problem, and the seize marker left
/// standing makes the next ordinary loan look like one grown from the standing copy.
final class HandbackDrainStateTests: XCTestCase {

    private var defaults: UserDefaults!
    private var journalDir: URL!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "HandbackDrainStateTests-\(UUID().uuidString)")!
        journalDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: journalDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: journalDir)
        defaults = nil
        journalDir = nil
        super.tearDown()
    }

    private func makeController() async -> PodLoanWatchController {
        let cacheStore = PersistenceController(directoryURL: journalDir.appendingPathComponent("cache"))
        let doseStore = await DoseStore(healthKitSampleStore: nil, cacheStore: cacheStore,
                                        longestEffectDuration: ExponentialInsulinModelPreset.rapidActingAdult.effectDuration,
                                        provenanceIdentifier: "HandbackDrainStateTests")
        let glucoseStore = await GlucoseStore(healthKitSampleStore: nil, cacheStore: cacheStore,
                                              cacheLength: .hours(4), provenanceIdentifier: "HandbackDrainStateTests")
        let carbStore = CarbStore(healthKitSampleStore: nil, cacheStore: cacheStore,
                                  cacheLength: .hours(24), provenanceIdentifier: "HandbackDrainStateTests")
        let manager = WatchLoopManager(doseStore: doseStore, glucoseStore: glucoseStore, carbStore: carbStore)
        return PodLoanWatchController(loopManager: manager,
                                      journal: LoanEventJournal(directory: journalDir),
                                      defaults: defaults)
    }

    /// A drain that gives up must leave nothing behind for the next session to inherit.
    func testAnAbandonedDrainLeavesNoStateForTheNextSession() async {
        let c = await makeController()

        // The state an abandoned drain reaches: the ceiling hit, both wedge flags tripped, and
        // the marker a phoneless start leaves on disk.
        c.queue.sync {
            c.handbackResendCount = PodLoanWatchController.maxDrainResends
            c.handbackSawUnreachable = true
            c.handbackSawUrgentSendError = true
            c.urgentSendWedged = true
            c.phase = .recoveredDrain
            c.epoch = 5          // an offer without a session number returns before it sends
        }
        c.defaults.set(UUID().uuidString, forKey: PodLoanWatchController.DormantKeys.activeToken)

        // The give-up check lives in the resend timer, not in the send. Firing the work item
        // inline is a jump past its deadline, on the queue it would really run on.
        c.scheduler = { _, _, work in work.perform() }
        c.sendHandbackOffer(freshened: false, recovered: true)
        c.queue.sync { }

        c.queue.sync {
            XCTAssertEqual(c.handbackResendCount, 0,
                           "the next drain must start with its full budget, not spent by the last one")
            XCTAssertFalse(c.handbackSawUnreachable, "a wedge verdict must describe THIS session")
            XCTAssertFalse(c.handbackSawUrgentSendError)
            XCTAssertFalse(c.urgentSendWedged)
            XCTAssertEqual(c.phase, .idle, "the drain closed")
        }
        XCTAssertNil(c.defaults.string(forKey: PodLoanWatchController.DormantKeys.activeToken),
                     "left set, the next ordinary loan is mistaken for a seized one")
    }

    /// With the budget spent, `classify` reports on a session that is over — which is the second
    /// half of the same defect, and the reason the reset has to happen at the give-up, not later.
    func testAStaleCountWouldMisreportTheNextSession() {
        // One offer into a fresh drain, phone reachable, sends fine: not a wedge.
        XCTAssertNotEqual(HandbackWedge.classify(resendCount: 1, sawUnreachable: false,
                                                 reachableNow: true, sendsErrored: false),
                          .oneWay)
        // The same moment, with a previous session's count carried in, reads as one.
        XCTAssertEqual(HandbackWedge.classify(resendCount: PodLoanWatchController.maxDrainResends,
                                              sawUnreachable: false, reachableNow: true, sendsErrored: false),
                       .oneWay)
    }
}
