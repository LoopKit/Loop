//
//  PodLoanTimerSeamTests.swift
//  WatchAppTests
//
//  First behavioral tests against the watch's loan controller — possible because every delayed
//  execution in PodLoanWatchController now crosses one seam (`scheduler`), so a test can hold
//  time still or jump it forward deterministically. No sleeps, no 25-second waits.
//
//  The determinism trick: every `schedule(after:)` call site already runs ON the controller's
//  serial queue, so a test scheduler that fires the work item INLINE executes it on the correct
//  queue with no races. Firing inline is a virtual jump past the timer's deadline.
//
//  Construction here is the answer to an open question: WatchLoopManager CAN be stood up in a
//  test — its init takes three plain stores against a temp-directory PersistenceController and
//  touches no radio. The recipe is StockLoopStack.makeStores, minus HealthKit.
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
        // Never unlink a live store's directory synchronously — the async-init race answers
        // later reads with zero rows (a lesson from the iOS suites). Unique names mean
        // nothing collides; the OS reclaims temp.
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
        let manager = WatchLoopManager(doseStore: doseStore, glucoseStore: glucoseStore, carbStore: carbStore)
        return PodLoanWatchController(loopManager: manager,
                                      journal: LoanEventJournal(directory: journalDir),
                                      defaults: defaults)
    }

    /// A request schedules its 60 s no-grant timeout (phone reachable) through the seam — the delay crosses as
    /// data a test can see, instead of vanishing into `asyncAfter`.
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

    /// Virtual time: fire the timeout inline (we are on the controller's queue at schedule
    /// time) and the controller must return to idle and accept a NEW request — the recovery
    /// the timeout exists to provide. Without the seam this test would take 60 real seconds.
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

        // The send fulfills MID-queue-block; the inline timeout that flips phase back to idle
        // runs after it in the same block. Poll rather than read immediately — and bound the
        // poller, because an unbounded one outlives a failed wait and SIGTRAPs the runner.
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
