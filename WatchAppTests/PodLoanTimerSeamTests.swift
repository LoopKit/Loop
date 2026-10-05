//
//  PodLoanTimerSeamTests.swift
//  WatchAppTests
//
//  Every delayed call in PodLoanWatchController crosses `scheduler`; firing inline on the
//  controller's queue is a virtual jump past the deadline. Stores follow StockLoopStack.makeStores.
//

import XCTest
import LoopKit
import LoopCore
import LoopAlgorithm
@testable import WatchApp

final class PodLoanTimerSeamTests: XCTestCase {

    private var cacheDir: URL!
    private var cacheStore: PersistenceController!
    private var journalDir: URL!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        cacheDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        cacheStore = PersistenceController(directoryURL: cacheDir)
        journalDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: journalDir, withIntermediateDirectories: true)
        defaults = UserDefaults(suiteName: "PodLoanTimerSeamTests-\(UUID().uuidString)")!
    }

    override func tearDown() {
        // Never unlink a live store's directory synchronously; unique names avoid collisions.
        cacheStore = nil
        cacheDir = nil
        journalDir = nil
        defaults = nil
        super.tearDown()
    }

    private func makeController() async -> PodLoanWatchController {
        let doseStore = await DoseStore(
            healthKitSampleStore: nil,
            cacheStore: cacheStore,
            longestEffectDuration: ExponentialInsulinModelPreset.rapidActingAdult.effectDuration,
            provenanceIdentifier: "PodLoanTimerSeamTests"
        )
        let glucoseStore = await GlucoseStore(
            healthKitSampleStore: nil,
            cacheStore: cacheStore,
            cacheLength: .hours(4),
            provenanceIdentifier: "PodLoanTimerSeamTests"
        )
        let carbStore = CarbStore(
            healthKitSampleStore: nil,
            cacheStore: cacheStore,
            cacheLength: .hours(24),
            provenanceIdentifier: "PodLoanTimerSeamTests"
        )
        let manager = WatchLoopManager(doseStore: doseStore, glucoseStore: glucoseStore, carbStore: carbStore,
                                       defaults: defaults, stateDirectory: journalDir)
        return PodLoanWatchController(loopManager: manager,
                                      journal: LoanEventJournal(directory: journalDir),
                                      stateDirectory: journalDir)
    }

    /// The 60 s request timeout crosses the seam.
    func testRequestTimeoutCrossesTheSeamAt60Seconds() async {
        let controller = await makeController()

        var sent = 0
        controller.send = { _ in sent += 1 }

        // Fulfill on the SCHEDULER, not the send: both happen in one queue block, send first,
        // and a wait keyed on the send can return in the gap between them.
        var captured: [(TimeInterval, String)] = []
        let timerArmed = expectation(description: "timeout armed")
        controller.scheduler = { delay, label, _ in captured.append((delay, label)); timerArmed.fulfill() }

        controller.requestLoan(watchBuild: "seam-test")
        wait(for: [timerArmed], timeout: 5)

        XCTAssertEqual(sent, 1)
        XCTAssertEqual(captured.map(\.0), [60], "the request timeout is the only timer a bare request arms")
        XCTAssertEqual(captured.map(\.1), ["request-timeout"], "and it is the one we think it is")
    }

    /// A fired timeout returns to idle and a new request is accepted.
    func testFiredTimeoutReturnsToIdleAndANewRequestIsAccepted() async {
        let controller = await makeController()

        var sends = 0
        let secondSend = expectation(description: "two requests sent")
        secondSend.expectedFulfillmentCount = 2
        controller.send = { _ in sends += 1; secondSend.fulfill() }

        // Jump every one-shot timer to its deadline the moment it is armed.
        controller.scheduler = { _, _, work in work.perform() }

        controller.requestLoan(watchBuild: "seam-test")   // request → inline timeout → idle
        controller.requestLoan(watchBuild: "seam-test")   // must be accepted again

        wait(for: [secondSend], timeout: 5)
        XCTAssertEqual(sends, 2, "a timed-out request must not wedge the controller in .requested")

        // Poll, bounded: an unbounded poller outlives a failed wait and traps the runner.
        let idled = expectation(description: "returned to idle")
        let deadline = Date().addingTimeInterval(5)
        DispatchQueue.global().async {
            while controller.phase != .idle {
                guard Date() < deadline else { return }
                usleep(10_000)
            }
            idled.fulfill()
        }
        wait(for: [idled], timeout: 5)
        XCTAssertEqual(controller.phase, .idle, "timed out and recovered")
    }

    /// Holding time still, the second Start is refused while the first is pending — the
    /// dedupe that stops a double-tap arming two loans.
    func testSecondRequestIgnoredWhileFirstIsPending() async {
        let controller = await makeController()

        var sends = 0
        let firstSend = expectation(description: "first request sent")
        controller.send = { _ in sends += 1; if sends == 1 { firstSend.fulfill() } }
        controller.scheduler = { _, _, _ in }   // time never advances

        controller.requestLoan(watchBuild: "seam-test")
        wait(for: [firstSend], timeout: 5)
        controller.requestLoan(watchBuild: "seam-test")

        // Drain the controller's queue: a third call's guard runs after the second's.
        let drained = expectation(description: "queue drained")
        controller.scheduler = { _, _, _ in }
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) { drained.fulfill() }
        wait(for: [drained], timeout: 5)

        XCTAssertEqual(sends, 1, "the pending request absorbs the double-tap")
        XCTAssertEqual(controller.phase, .requested)
    }
}

/// Screen-off scans cannot find a pod, so first contact asks for the wrist and nudges;
/// a pod with a saved handle connects silently.
final class TakeoverDiscoveryHintTests: XCTestCase {

    func testAPodWithASavedHandleSaysNothing() {
        XCTAssertNil(PodLoanWatchController.takeoverHint(firstContact: false, podReached: false, nudged: false))
        XCTAssertNil(PodLoanWatchController.takeoverHint(firstContact: false, podReached: true, nudged: true),
                     "a handle connect needs no screen, so even a slow one asks nothing")
    }

    func testFirstContactAsksForTheWristThenReleasesIt() {
        XCTAssertEqual(PodLoanWatchController.takeoverHint(firstContact: true, podReached: false, nudged: false)?
            .contains("keep your wrist up"), true)
        XCTAssertEqual(PodLoanWatchController.takeoverHint(firstContact: true, podReached: false, nudged: true)?
            .contains("Raise your wrist"), true, "after the tap the ask changes")
        XCTAssertEqual(PodLoanWatchController.takeoverHint(firstContact: true, podReached: true, nudged: true)?
            .contains("lower your wrist"), true, "once the pod is reached the rest needs no screen")
    }

    func testTheTapFiresOnlyWhenItCanHelp() {
        XCTAssertTrue(PodLoanWatchController.shouldNudgeTakeover(podReached: false, appActive: false, nudgesSoFar: 0))
        XCTAssertFalse(PodLoanWatchController.shouldNudgeTakeover(podReached: true, appActive: false, nudgesSoFar: 0),
                       "reached: the rest works with the wrist down")
        XCTAssertFalse(PodLoanWatchController.shouldNudgeTakeover(podReached: false, appActive: true, nudgesSoFar: 0),
                       "screen on: the scan is already active")
        XCTAssertFalse(PodLoanWatchController.shouldNudgeTakeover(podReached: false, appActive: false, nudgesSoFar: 2),
                       "twice at most")
    }
}
