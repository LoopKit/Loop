//
//  WatchAppTests.swift
//  WatchAppTests
//
//  Proves the target can reach the watch extension's own types.
//

import XCTest
@testable import WatchApp

final class WatchAppTargetReachabilityTests: XCTestCase {

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
