//
//  WatchAppTests.swift
//  WatchAppTests
//
//  Proves the target can reach the watch extension's own types.
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

    /// The two transport channels render distinctly in the log.
    func testTransportChannelsAreDistinguishable() {
        XCTAssertEqual(LoanTransportChannel.urgent.rawValue, "urgent")
        XCTAssertEqual(LoanTransportChannel.queued.rawValue, "queued")
        XCTAssertNotEqual(LoanTransportChannel.urgent.rawValue, LoanTransportChannel.queued.rawValue)
    }

    /// Reaches a watch-only type without standing up the stack.
    func testWatchLoopManagerSymbolIsReachable() {
        XCTAssertFalse(String(describing: WatchLoopManager.self).isEmpty)
        XCTAssertFalse(String(describing: PodLoanWatchController.self).isEmpty)
    }
}

/// Blocking readers only the tests use; production reads the mirrors.
extension WatchLoopManager {
    var closedLoopEnabled: Bool { dataAccessQueue.sync { _closedLoopEnabled } }

    var isIntegralRetrospectiveCorrectionEnabled: Bool { dataAccessQueue.sync { integralRetrospectiveCorrectionEnabled } }

    func glanceData() -> GlanceData { dataAccessQueue.sync { buildGlanceData() } }
}
