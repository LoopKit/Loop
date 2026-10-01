//
//  G7TimedConnectTests.swift
//  WatchAppTests
//
//  Pins the pure half of the watch's G7 acquisition arm (G7WatchAcquisition) and the direct-auth
//  fast path's primitives. The file keeps its timed-connect-era name only because Loop.xcodeproj
//  lists it by name; the timed, bounded connect itself is gone.
//

import XCTest
import CoreBluetooth
@testable import G7SensorKit
@testable import WatchApp

/// CBCentralManager with the restoration option raises in a test bundle (same seam the kit's own
/// tests use).
private class TestBluetoothManager: G7BluetoothManager {
    override func makeCentralManager(queue: DispatchQueue) -> CBCentralManager {
        return CBCentralManager(delegate: self, queue: queue)
    }
}

/// An adopted sensor skips discovery, where stock latches activation; unlatched, every reading
/// was "invalid" and glucose froze.
final class G7AdoptedSensorActivationTests: XCTestCase {
    private func message(_ hex: String) -> G7GlucoseMessage { G7GlucoseMessage(data: Data(hexadecimalString: hex)!)! }

    func testAnAdoptedSensorLatchesItsActivationOnTheFirstReading() {
        var state = G7CGMManagerState()
        state.sensorID = "DXCMQj"            // passed in: identity known, activation not
        state.configuredByAnotherController = true
        let sensor = G7Sensor(mode: .direct, credentials: state.sensorCredentials, bluetoothManager: TestBluetoothManager())
        let manager = G7CGMManager(state: state, sensor: sensor)
        XCTAssertNil(manager.state.activatedAt)

        let first = Date(timeIntervalSince1970: 1_789_000_000)
        sensor.activationDate = first
        manager.sensor(sensor, didRead: message("4e00c35501002601000106008a00060187000f"))
        XCTAssertEqual(manager.state.activatedAt, first, "the reading's name is built from this")

        // Each message re-estimates it by a fraction of a second; the name must not move with it.
        sensor.activationDate = first.addingTimeInterval(0.4)
        manager.sensor(sensor, didRead: message("4e00c35501002601000106008b00060187000f"))
        XCTAssertEqual(manager.state.activatedAt, first, "latched, as stock latches it at discovery")
    }
}

final class G7WatchAcquisitionTests: XCTestCase {
    private let anchor = Date(timeIntervalSince1970: 1_000_000)

    // MARK: the hold

    func testTheHoldWaitsOutTheTailFromLinkUp() {
        XCTAssertEqual(G7WatchAcquisition.holdWait(sinceLinkUp: 0), 35, accuracy: 0.001)
        XCTAssertEqual(G7WatchAcquisition.holdWait(sinceLinkUp: 3.5), 31.5, accuracy: 0.001)
        XCTAssertEqual(G7WatchAcquisition.holdWait(sinceLinkUp: 34.8), 0.5, accuracy: 0.001, "never below half a second")
        XCTAssertEqual(G7WatchAcquisition.holdWait(sinceLinkUp: 40), 0.5, accuracy: 0.001)
    }

    func testTheClearanceOutlastsTheMeasuredTail() {
        XCTAssertGreaterThan(G7WatchAcquisition.tailClearanceSeconds, 3.5 + 24, "read + the 20–24 s advertising tail")
        XCTAssertLessThan(G7WatchAcquisition.tailClearanceSeconds, G7WatchAcquisition.period - 60)
    }

    func testTheHoldRunsUntilTheClearanceThenNothingToWaitFor() {
        XCTAssertEqual(G7WatchAcquisition.relodgeHold(sinceLinkUp: 3.5), 31.5, "a close after the read: hold out the tail")
        XCTAssertNil(G7WatchAcquisition.relodgeHold(sinceLinkUp: 120), "a wake mid-cycle: a plain request now")
        XCTAssertEqual(G7WatchAcquisition.relodgeHold(sinceLinkUp: 0), 35,
                       "a late connect failure counts from now: hold the full clearance")
    }

    // MARK: refusals — wait, then ask again

    func testASynchronousRefusalWaitsBeforeAskingAgain() {
        XCTAssertEqual(G7WatchAcquisition.onConnectFailure(sinceLodge: 0.4), .backOff(G7WatchAcquisition.refusalBackoffSeconds))
        XCTAssertEqual(G7WatchAcquisition.onConnectFailure(sinceLodge: 0.3), .backOff(30), "every time: no stand-down")
    }

    func testALateFailureRelodgesThroughTheArm() {
        XCTAssertEqual(G7WatchAcquisition.onConnectFailure(sinceLodge: 120), .relodge)
    }

    // MARK: the arm is chosen by platform

    func testTheWatchBluetoothManagerHasTheAcquisitionArm() {
        XCTAssertNotNil(TestBluetoothManager().acquisitionArm)
    }

    // MARK: the 3-miss test

    func testThreeSilentBurstsOnTheLodgedRequestMeanABootstrapPass() {
        XCTAssertEqual(G7WatchAcquisition.missedBursts(since: anchor, now: anchor.addingTimeInterval(8)), 0)
        XCTAssertEqual(G7WatchAcquisition.missedBursts(since: anchor, now: anchor.addingTimeInterval(2 * 300 + 8)), 2)
        XCTAssertGreaterThanOrEqual(G7WatchAcquisition.missedBursts(since: anchor, now: anchor.addingTimeInterval(3 * 300 + 8)),
                                    G7WatchAcquisition.missedBurstsBeforeBootstrap)
        XCTAssertEqual(G7WatchAcquisition.missedBursts(since: nil, now: anchor), 0, "nothing on record: nothing missed")
    }
}
