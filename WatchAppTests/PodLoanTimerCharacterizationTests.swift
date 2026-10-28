//
//  PodLoanTimerCharacterizationTests.swift
//  WatchAppTests
//
//  Characterization: records which labelled timers each action arms today, so a refactor that
//  moves behaviour has to say so.
//

import XCTest
import LoopKit
import LoopCore
import LoopAlgorithm
@testable import WatchApp

/// Records every arming and fires nothing unless asked.
final class TimerRecorder {
    struct Armed: Equatable, CustomStringConvertible {
        let label: String
        let delay: TimeInterval
        var description: String { "\(label)@\(delay < 1 ? String(format: "%.2f", delay) : String(format: "%.0f", delay))s" }
    }

    private let lock = NSLock()
    private var _armed: [Armed] = []
    /// Every arming is kept; a superseded timer still reaches its deadline in production.
    private var _work: [String: [DispatchWorkItem]] = [:]

    /// Set to fire work items inline as they are armed — a virtual jump to every deadline.
    var fireInline = false

    var armed: [Armed] { lock.lock(); defer { lock.unlock() }; return _armed }
    var labels: [String] { armed.map(\.label) }

    @MainActor func install(on controller: PodLoanWatchController) {
        controller.scheduler = { [weak self] delay, label, work in
            guard let self = self else { return }
            self.lock.lock()
            self._armed.append(Armed(label: label, delay: delay))
            self._work[label, default: []].append(work)
            let fire = self.fireInline
            self.lock.unlock()
            if fire { work.perform() }
        }
    }

    /// Fires the latest arming of a label.
    @discardableResult
    func fire(_ label: String) -> Bool {
        lock.lock()
        let work = _work[label]?.last
        lock.unlock()
        guard let work = work else { return false }
        work.perform()
        return true
    }

    /// Fire EVERY arming of a label, oldest first — the only way to observe what happens to a
    /// superseded timer, since production fires all of them and lets the guards sort it out.
    func fireAll(_ label: String) {
        lock.lock()
        let items = _work[label] ?? []
        lock.unlock()
        items.forEach { $0.perform() }
    }

    func reset() { lock.lock(); _armed.removeAll(); _work.removeAll(); lock.unlock() }
}

@MainActor
final class PodLoanTimerCharacterizationTests: XCTestCase {

    private var cacheDir: URL!
    private var cacheStore: PersistenceController!
    private var journalDir: URL!
    private var defaults: UserDefaults!
    /// The controller keeps `loopManager` private, so the test holds its own reference rather
    /// than widening production API for a test's convenience.
    private var loopManager: WatchLoopManager!

    override func setUp() async throws {
        try await super.setUp()
        cacheDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        cacheStore = PersistenceController(directoryURL: cacheDir)
        journalDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: journalDir, withIntermediateDirectories: true)
        defaults = UserDefaults(suiteName: "PodLoanTimerCharacterization-\(UUID().uuidString)")!
    }

    override func tearDown() async throws {
        // Never unlink a live store's directory synchronously — the async-init race answers
        // later reads with zero rows. Unique names mean nothing collides.
        cacheStore = nil; cacheDir = nil; journalDir = nil; defaults = nil; loopManager = nil
        try await super.tearDown()
    }

    private func makeController() async -> PodLoanWatchController {
        let doseStore = await DoseStore(
            healthKitSampleStore: nil,
            cacheStore: cacheStore,
            longestEffectDuration: ExponentialInsulinModelPreset.rapidActingAdult.effectDuration,
            provenanceIdentifier: "TimerCharacterization"
        )
        let glucoseStore = await GlucoseStore(
            healthKitSampleStore: nil,
            cacheStore: cacheStore,
            cacheLength: .hours(4),
            provenanceIdentifier: "TimerCharacterization"
        )
        let carbStore = CarbStore(
            healthKitSampleStore: nil,
            cacheStore: cacheStore,
            cacheLength: .hours(24),
            provenanceIdentifier: "TimerCharacterization"
        )
        let manager = WatchLoopManager(doseStore: doseStore, glucoseStore: glucoseStore, carbStore: carbStore,
                                       defaults: defaults, stateDirectory: journalDir)
        loopManager = manager
        return PodLoanWatchController(loopManager: manager,
                                      journal: LoanEventJournal(directory: journalDir),
                                      stateDirectory: journalDir)
    }

    /// Waits for armings; `drain` alone races the controller's queue on a loaded machine.
    private func waitForArmed(_ rec: TimerRecorder, atLeast count: Int, timeout: TimeInterval = 5) async {
        let e = expectation(description: "recorder saw \(count) arming(s)")
        let deadline = Date().addingTimeInterval(timeout)
        DispatchQueue.global().async {
            while rec.armed.count < count {
                guard Date() < deadline else { return }
                usleep(10_000)
            }
            e.fulfill()
        }
        await fulfillment(of: [e], timeout: timeout + 1)
    }

    /// Fixed settle; only for asserting an absence.
    private func drain(_ controller: PodLoanWatchController, _ seconds: TimeInterval = 0.3) async {
        let done = expectation(description: "queue settled")
        DispatchQueue.global().asyncAfter(deadline: .now() + seconds) { done.fulfill() }
        await fulfillment(of: [done], timeout: seconds + 5)
    }

    // MARK: - The real request path

    /// A bare request arms exactly one timer, and it is the 10 s no-grant timeout (the phone is
    /// reachable in this fixture).
    func testRequestArmsOnlyTheRequestTimeout() async {
        let controller = await makeController()
        let rec = TimerRecorder()
        rec.install(on: controller)
        controller.send = { _ in }

        controller.requestLoan(watchBuild: "characterization")
        await waitForArmed(rec, atLeast: 1)

        XCTAssertEqual(rec.armed, [.init(label: "request-timeout", delay: PodLoanWatchController.requestTimeout)])
    }

    /// A double-tap must not arm a second timeout — the pending request absorbs it. This is
    /// the timer-level statement of the dedupe; the seam test states the send-level one.
    func testDoubleTapArmsOneTimeoutNotTwo() async {
        let controller = await makeController()
        let rec = TimerRecorder()
        rec.install(on: controller)
        controller.send = { _ in }

        controller.requestLoan(watchBuild: "characterization")
        controller.requestLoan(watchBuild: "characterization")
        await drain(controller)

        XCTAssertEqual(rec.labels, ["request-timeout"], "the second tap must not arm its own timeout")
    }

    /// After the timeout fires the controller is idle, and a fresh request arms a FRESH
    /// timeout. The recovery path has to re-arm or the second attempt hangs forever.
    func testTimeoutThenNewRequestArmsAFreshTimeout() async {
        let controller = await makeController()
        let rec = TimerRecorder()
        rec.install(on: controller)
        controller.send = { _ in }

        controller.requestLoan(watchBuild: "characterization")
        await waitForArmed(rec, atLeast: 1)
        XCTAssertTrue(rec.fire("request-timeout"), "the timeout must have been armed")

        controller.requestLoan(watchBuild: "characterization")
        await waitForArmed(rec, atLeast: 2)

        XCTAssertEqual(rec.labels, ["request-timeout", "request-timeout"],
                       "the recovered controller arms its own timeout rather than reusing the dead one")
    }

    // MARK: - Harness integrity

    /// Firing through the recorder runs the seam's wrapper and has real effects.
    func testRecorderCapturesTheSeamWrapperSoFiringHasRealEffects() async {
        let controller = await makeController()
        let rec = TimerRecorder()
        rec.install(on: controller)
        controller.send = { _ in }

        controller.requestLoan(watchBuild: "characterization")
        await waitForArmed(rec, atLeast: 1)
        XCTAssertEqual(controller.phase, .requested)

        rec.fire("request-timeout")

        XCTAssertEqual(controller.phase, .idle, "the wrapper ran the real body")
        XCTAssertNotNil(controller.lastIdleNote, "and the body's user-visible reason was set")
    }

    // Cross-epoch firing is logged but not enforced by the seam; not testable here without
    // asserting on call-site guards instead.

}
