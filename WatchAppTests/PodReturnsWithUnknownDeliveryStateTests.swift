//
//  PodReturnsWithUnknownDeliveryStateTests.swift
//  WatchAppTests
//
//  Hosted here because a real OmniPumpManager needs a host app with the bluetooth-central
//  background mode; the kit's own tests cover the same rules at the state level.
//

import XCTest
import LoopKit
@testable import OmnipodKit

/// A pump taken back after a release has unknown delivery: the controller reads before it
/// writes (or faults 0x31), and the copies of doses in flight at release are the other
/// controller's.
final class PodReturnsWithUnknownDeliveryStateTests: XCTestCase {
    private func makeManager(bolusInFlight: Bool) throws -> OmniPumpManager {
        var podState = PodState(address: 0x1f0b3557, firmwareVersion: "2.7.0", iFirmwareVersion: "2.7.0",
                                lotNo: 1, lotSeq: 1, insulinType: .novolog, podType: dashType)
        if bolusInFlight {
            podState.unfinalizedBolus = UnfinalizedDose(decisionId: nil, bolusAmount: 2.0, startTime: Date(),
                                                        scheduledCertainty: .certain, insulinType: .novolog)
        }
        let raw: [String: Any] = ["basalSchedule": ["entries": [["rate": 1.0, "startTime": 0.0]]],
                                  "controllerId": UInt32(0x1234_5678), "podId": UInt32(0x1234_5679),
                                  "podState": podState.rawValue]
        return try XCTUnwrap(OmniPumpManager(rawState: raw))
    }

    func testTakingControlBackForgetsTheDeliveryStatusLastReceived() throws {
        let manager = try makeManager(bolusInFlight: false)
        XCTAssertNotNil(manager.podComms.podState, "the manager came up with a pod")

        manager.releaseControl()
        // What the releasing controller still believes: its last reply, from before the release.
        manager.podComms.podState?.lastDeliveryStatusReceived = .scheduledBasal
        manager.takeControl()

        XCTAssertNil(manager.podComms.podState?.lastDeliveryStatusReceived,
                     "nil is what makes the driver read the pod, and cancel a running temp, before it sets one")
        XCTAssertNil(manager.state.podState?.lastDeliveryStatusReceived, "and the manager's own copy agrees")
    }

    /// LoopKit's contract: nil when there is nothing to escalate.
    func testEscalatingATakeWithNoPodReturnsNil() throws {
        let raw: [String: Any] = ["basalSchedule": ["entries": [["rate": 1.0, "startTime": 0.0]]],
                                  "controllerId": UInt32(0x1234_5678), "podId": UInt32(0x1234_5679)]
        let manager = try XCTUnwrap(OmniPumpManager(rawState: raw))
        XCTAssertNil(manager.escalateTakeControl())
        XCTAssertNotNil(try makeManager(bolusInFlight: false).escalateTakeControl(), "a pod to find: the scan-adopt is armed")
    }

    func testTakingControlBackDropsTheCopyOfABolusInFlightAtRelease() throws {
        let manager = try makeManager(bolusInFlight: true)
        manager.releaseControl()
        XCTAssertTrue(manager.isControlReleased)
        manager.takeControl()

        XCTAssertFalse(manager.isControlReleased)
        XCTAssertNil(manager.state.podState?.unfinalizedBolus, "the other controller owns that bolus's record now")
        XCTAssertEqual(manager.state.podState?.untrackedDeliveryIsForeign, true, "and its remainder is not booked here")
    }
}
