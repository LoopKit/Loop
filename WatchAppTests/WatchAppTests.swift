//
//  WatchAppTests.swift
//  WatchAppTests
//
//  The first test target that can see the watch extension's own code.
//
//  Until now every "Watch…" suite in LoopTests exercised watch-RELEVANT logic that happens to
//  live in files shared with the iOS app — the protocol, the ledger, the journal. 76 of the
//  extension's 103 source files, including WatchLoopManager and PodLoanWatchController, were
//  reachable from no test at all.
//
//  This file's only job is to prove the target works: that `@testable import WatchApp`
//  resolves and that watch-only types are visible and usable. Real coverage comes after, against
//  the types the WatchLoopManager split produces — they have far smaller dependency surfaces than
//  the object they come out of.
//

import XCTest
@testable import WatchApp

final class WatchAppTargetReachabilityTests: XCTestCase {

    /// Watch-only ERROR type: proves the module is linked and its internal types are visible.
    /// `WatchLoopError` lives in WatchLoopManager.swift, which no previous test could reach.
    func testWatchOnlyTypesAreVisibleToThisTarget() {
        let expired = WatchLoopError.recommendationExpired(date: Date())
        XCTAssertFalse(expired.localizedDescription.isEmpty,
                       "watch-only types resolve and carry their localized text")

        // Distinct cases must not collapse to the same message — the wrist shows these verbatim.
        let suspended = WatchLoopError.pumpSuspended
        let unconnected = WatchLoopError.pumpManagerUnconnected
        XCTAssertNotEqual(expired.localizedDescription, suspended.localizedDescription)
        XCTAssertNotEqual(expired.localizedDescription, unconnected.localizedDescription)
    }

    /// The transport-channel tag. Watch-only, pure, and the thing that will make
    /// the next one-way-WCSession incident diagnosable — so it is worth pinning that the two
    /// channels are distinguishable rather than both rendering as the same string.
    func testTransportChannelsAreDistinguishable() {
        XCTAssertEqual(LoanTransportChannel.urgent.rawValue, "urgent")
        XCTAssertEqual(LoanTransportChannel.queued.rawValue, "queued")
        XCTAssertNotEqual(LoanTransportChannel.urgent.rawValue, LoanTransportChannel.queued.rawValue)
    }

    /// Proves we can reach a watch-only TYPE (not just an enum) without standing up the whole
    /// stack. Deliberately does not instantiate WatchLoopManager: that pulls in StockLoopStack,
    /// CoreBluetooth and the pod manager, and a failure there would say nothing about whether
    /// this target is wired correctly.
    func testWatchLoopManagerSymbolIsReachable() {
        XCTAssertFalse(String(describing: WatchLoopManager.self).isEmpty)
        XCTAssertFalse(String(describing: PodLoanWatchController.self).isEmpty)
    }
}
