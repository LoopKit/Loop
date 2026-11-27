//
//  WatchAppTests.swift
//  WatchAppTests
//
//  Proves the target can reach the watch extension's own types.
//

import XCTest
@testable import WatchApp

@MainActor
final class WatchAppTargetReachabilityTests: XCTestCase {

    /// Reaches a watch-only type without standing up the stack.
    func testWatchLoopManagerSymbolIsReachable() {
        XCTAssertFalse(String(describing: WatchLoopManager.self).isEmpty)
        XCTAssertFalse(String(describing: PodLoanWatchController.self).isEmpty)
    }
}

/// What the loan controller's `queue.sync` was before it moved to the main actor: the work already
/// queued on main runs first, then `body`.
extension PodLoanWatchController {
    func onMain<T>(_ body: () throws -> T) rethrows -> T {
        drainMainQueue()
        return try body()
    }
}

/// In an async test (itself a job on the main queue, which does not run nested inside one): the
/// same, by suspending until what is already queued on main has run.
extension PodLoanWatchController {
    func onMain<T>(_ body: () throws -> T) async rethrows -> T {
        await drainMainQueue()
        return try body()
    }
}

/// What `debugSnapshot()` was while it read the controller's queue: a fence, so the snapshot
/// follows the work already queued.
extension PodLoanWatchController {
    func fencedSnapshot() -> DebugSnapshot {
        drainMainQueue()
        return debugSnapshot()
    }

    func fencedSnapshot() async -> DebugSnapshot {
        await drainMainQueue()
        return debugSnapshot()
    }
}

/// Runs what is already queued on main. From a synchronous test only: inside a main-queue job the
/// main queue does not drain.
@MainActor func drainMainQueue() {
    var done = false
    DispatchQueue.main.async { done = true }
    while !done { RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01)) }
}

/// Suspends until what is already queued on main has run.
@MainActor func drainMainQueue() async {
    await withCheckedContinuation { done in DispatchQueue.main.async { done.resume() } }
}

/// Readers only the tests use, each after the cycle work asked for before it.
extension WatchLoopManager {
    func settledGlanceData() async -> GlanceData {
        await laneSettled()
        return buildGlanceData()
    }
}
