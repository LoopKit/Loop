//
//  HandbackWedgeTests.swift
//  WatchAppTests
//
//  The hand-back wedge classifier's truth table: force-quit the watch app, or wait.
//

import XCTest
import LoopKit
import LoopAlgorithm
import LoopCore
import UserNotifications
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

    /// Errored sends mean a re-establishing session: wait.
    func testErroringSendsAreTheReestablishingSessionNotTheWedge() {
        XCTAssertEqual(
            HandbackWedge.classify(resendCount: 3, sawUnreachable: false, reachableNow: true, sendsErrored: true),
            .sessionReestablishing)
    }

    // MARK: - Everything that must NOT be called a wedge
    // A false wedge gives the most disruptive advice for an ordinary out-of-range hang.

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

    /// The sticky flag vetoes a wedge even when the phone is reachable again.
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

    /// A wedge needs enough offers, never unreachable, and reachable now; `sendsErrored` picks the variant.
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

/// Drain state (resend count, classifier flags, seize marker) resets per session, so the next
/// drain does not start at the ceiling.
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
        let manager = WatchLoopManager(doseStore: doseStore, glucoseStore: glucoseStore, carbStore: carbStore,
                                       defaults: defaults, stateDirectory: journalDir)
        return PodLoanWatchController(loopManager: manager,
                                      journal: LoanEventJournal(directory: journalDir),
                                      stateDirectory: journalDir)
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
        c.updateState { $0.seizeToken = UUID() }

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
        XCTAssertNil(c.persisted.seizeToken,
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

// MARK: - Interruption levels of the loan's own alerts

/// Pod unattended → time-sensitive; the watch still dosing → normal.
final class LoanAlertLevelTests: XCTestCase {

    private var defaults: UserDefaults!
    private var journalDir: URL!
    private var scheduler: RecordingWristAlertScheduler!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "LoanAlertLevelTests-\(UUID().uuidString)")!
        journalDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: journalDir, withIntermediateDirectories: true)
        scheduler = RecordingWristAlertScheduler()
        WristAlerts.scheduler = scheduler
    }

    override func tearDown() {
        WristAlerts.scheduler = UNUserNotificationCenter.current()
        try? FileManager.default.removeItem(at: journalDir)
        scheduler = nil
        defaults = nil
        journalDir = nil
        super.tearDown()
    }

    private func makeController() async -> PodLoanWatchController {
        let cacheStore = PersistenceController(directoryURL: journalDir.appendingPathComponent("cache"))
        let doseStore = await DoseStore(healthKitSampleStore: nil, cacheStore: cacheStore,
                                        longestEffectDuration: ExponentialInsulinModelPreset.rapidActingAdult.effectDuration,
                                        provenanceIdentifier: "LoanAlertLevelTests")
        let glucoseStore = await GlucoseStore(healthKitSampleStore: nil, cacheStore: cacheStore,
                                              cacheLength: .hours(4), provenanceIdentifier: "LoanAlertLevelTests")
        let carbStore = CarbStore(healthKitSampleStore: nil, cacheStore: cacheStore,
                                  cacheLength: .hours(24), provenanceIdentifier: "LoanAlertLevelTests")
        let manager = WatchLoopManager(doseStore: doseStore, glucoseStore: glucoseStore, carbStore: carbStore,
                                       defaults: defaults, stateDirectory: journalDir)
        let controller = PodLoanWatchController(loopManager: manager,
                                                journal: LoanEventJournal(directory: journalDir),
                                                stateDirectory: journalDir)
        controller.scheduler = { _, _, _ in }
        controller.isPhoneReachable = { true }
        return controller
    }

    /// Alerts are issued from a main-actor task.
    private func alert(titled title: String, other: String? = nil) async throws -> UNNotificationRequest {
        for _ in 0..<100 {
            let scheduler = self.scheduler!
            if let request = await MainActor.run(body: {
                scheduler.pending.first { $0.content.title == title && $0.identifier != other }
            }) {
                return request
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        return try XCTUnwrap(nil, "no alert titled \(title)")
    }

    /// One-way wedge while the loan is live: the watch is still dosing.
    func testEndNotConfirmedWhileStillDosingIsNormal() async throws {
        let c = await makeController()
        c.queue.sync {
            c.phase = .active
            c.handbackResendCount = 3
            c.handbackTimedOut()
        }
        let request = try await alert(titled: "End Not Confirmed")
        XCTAssertEqual(request.content.interruptionLevel, .active)
    }

    /// The watch has let go of the pod and the phone has not confirmed: nobody is dosing.
    func testEndNotConfirmedAfterTheFinalOfferIsTimeSensitive() async throws {
        let c = await makeController()
        c.queue.sync {
            c.phase = .handingBack
            c.handbackTimedOut()
        }
        let request = try await alert(titled: "End Not Confirmed")
        XCTAssertEqual(request.content.interruptionLevel, .timeSensitive)
    }

    /// The two variants never replace each other.
    func testTheTwoEndNotConfirmedVariantsHaveTheirOwnIdentifiers() async throws {
        let c = await makeController()
        c.queue.sync {
            c.phase = .active
            c.handbackResendCount = 3
            c.handbackTimedOut()
        }
        let stillDosing = try await alert(titled: "End Not Confirmed")
        c.queue.sync {
            c.phase = .handingBack
            c.handbackTimedOut()
        }
        let final = try await alert(titled: "End Not Confirmed", other: stillDosing.identifier)
        XCTAssertNotEqual(stillDosing.identifier, final.identifier)
        XCTAssertEqual(scheduler.pending.filter { $0.content.title == "End Not Confirmed" }.count, 2)
    }

    /// The phone's return during a seized loan is a routine prompt; the watch keeps dosing.
    func testIPhoneIsBackIsNormal() async throws {
        let c = await makeController()
        c.issueReunionPromptAlert()
        let request = try await alert(titled: "iPhone Is Back")
        XCTAssertEqual(request.content.interruptionLevel, .active)
    }
}
