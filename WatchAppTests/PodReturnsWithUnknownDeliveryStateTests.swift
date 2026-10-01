//
//  PodReturnsWithUnknownDeliveryStateTests.swift
//  WatchAppTests
//

import XCTest
import LoopKit
@testable import OmnipodKit

/// A pod that comes back from another controller comes back with its delivery state UNKNOWN.
/// 2026-09-19: the phone kept "no temp running" from before the loan, skipped the cancel, set a
/// temp basal over the watch's running one, and the pod faulted 0x31.
final class PodReturnsWithUnknownDeliveryStateTests: XCTestCase {
    func testReclaimingThePodForgetsTheDeliveryStatusLastReceived() throws {
        let podState = PodState(address: 0x1f0b3557, firmwareVersion: "2.7.0", iFirmwareVersion: "2.7.0",
                                lotNo: 1, lotSeq: 1, insulinType: .novolog, podType: dashType)
        let raw: [String: Any] = ["basalSchedule": ["entries": [["rate": 1.0, "startTime": 0.0]]],
                                  "controllerId": UInt32(0x1234_5678), "podId": UInt32(0x1234_5679),
                                  "podState": podState.rawValue]
        let manager = try XCTUnwrap(OmniPumpManager(rawState: raw))
        XCTAssertNotNil(manager.podComms.podState, "the manager came up with a pod")

        manager.releaseConnection()
        // What the lender still believes when the loan ends: its last reply, from before the grant.
        manager.podComms.podState?.lastDeliveryStatusReceived = .scheduledBasal
        manager.reclaimConnection()

        XCTAssertNil(manager.podComms.podState?.lastDeliveryStatusReceived,
                     "nil is what makes the driver read the pod, and cancel a running temp, before it sets one")
        XCTAssertNil(manager.state.podState?.lastDeliveryStatusReceived, "and the manager's own copy agrees")
    }
}
