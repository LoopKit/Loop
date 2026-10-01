//
//  G7TimedConnectTests.swift
//  WatchAppTests
//
//  Pins the pure half of the watch's G7 acquisition arm (G7WatchAcquisition) and the direct-auth
//  fast path's primitives. The file keeps its timed-connect-era name only because Loop.xcodeproj
//  lists it by name; the timed, bounded connect itself is gone (lean-out step 7, 2026-09-16).
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

/// The watch adopts a sensor by identity from the phone, so discovery — where stock latches the
/// activation time — never runs. 2026-09-19: with it unknown, every reading was named "invalid",
/// the store kept the first and dropped the rest as duplicates, and the loop ran on a frozen 128.
final class G7AdoptedSensorActivationTests: XCTestCase {
    private func message(_ hex: String) -> G7GlucoseMessage { G7GlucoseMessage(data: Data(hexadecimalString: hex)!)! }

    func testAnAdoptedSensorLatchesItsActivationOnTheFirstReading() {
        var state = G7CGMManagerState()
        state.sensorID = "DXCMQj"            // adopted: identity known, activation not
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

    // MARK: the re-lodge toggle (Diagnostics ▸ Sensor ▸ Re-lodge)

    func testTheProvenArmIsTheDefault() {
        UserDefaults.standard.removeObject(forKey: G7WatchAcquisition.relodgeKey)
        XCTAssertEqual(G7WatchAcquisition.relodge, .holdApp, "33 in 33; Pete's formula measured 1 in 4")
        XCTAssertEqual(G7WatchAcquisition.Relodge(rawValue: "peteDelay"), .peteDelay)
        XCTAssertEqual(G7WatchAcquisition.Relodge(rawValue: "holdApp"), .holdApp)
        XCTAssertNil(G7WatchAcquisition.Relodge(rawValue: "tailDelay"), "the 31-s arm is gone")
    }

    // MARK: Pete's start delay — the grid arithmetic

    func testPetesDelayIsHisFormulaOnTheReadingsGrid() {
        // Pete (2026-09-15 11:56): "delay = 298 - (now - bg_timestamp)". A lodge happens at the
        // sensor's close, a few seconds after the reading's own timestamp.
        for sinceReading in [3.5, 4.0, 5.5, 12.0, 60.0] {
            let now = anchor.addingTimeInterval(sinceReading)
            XCTAssertEqual(Double(G7WatchAcquisition.peteDelay(anchor: anchor, now: now)), 298 - sinceReading, accuracy: 0.5,
                           "whole seconds of his formula, not a variant of it")
        }
        XCTAssertEqual(G7WatchAcquisition.period + G7WatchAcquisition.fireOffset - G7WatchAcquisition.lead, 298, accuracy: 0.001,
                       "period + fireOffset - lead == 298 is what makes it his formula")
    }

    func testPetesDelayIsWholeSecondsNeverBelowOneAndInsideTheCycle() {
        let d = G7WatchAcquisition.peteDelay(anchor: anchor, now: anchor.addingTimeInterval(10))
        XCTAssertGreaterThan(d, 0)
        XCTAssertLessThan(Double(d), G7WatchAcquisition.period, "never past the burst it is aimed at")
        // The burst is already here: a delay would land after it — the shortest legal delay instead
        // (a zero or fractional NSNumber is refused with CBError 1).
        XCTAssertEqual(G7WatchAcquisition.peteDelay(anchor: anchor, now: anchor.addingTimeInterval(299)), 1)
        // Hours later the anchor still names the grid: it is the sensor's own clock.
        XCTAssertEqual(Double(G7WatchAcquisition.peteDelay(anchor: anchor, now: anchor.addingTimeInterval(47 * 300 + 12))),
                       298 - 12, accuracy: 0.5)
    }

    func testTheNextFireStaysGridAligned() {
        let fire = G7WatchAcquisition.nextFire(anchor: anchor, now: anchor.addingTimeInterval(100))
        XCTAssertEqual(fire.timeIntervalSince(anchor), G7WatchAcquisition.period + G7WatchAcquisition.fireOffset, accuracy: 0.001)
        let close = anchor.addingTimeInterval(G7WatchAcquisition.period + G7WatchAcquisition.fireOffset - 0.5)
        XCTAssertEqual(G7WatchAcquisition.nextFire(anchor: anchor, now: close).timeIntervalSince(anchor),
                       2 * G7WatchAcquisition.period + G7WatchAcquisition.fireOffset, accuracy: 0.001, "inside the margin: take the next one")
    }

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

    // MARK: the plan the toggle selects

    func testTheToggleSelectsThePlan() {
        let now = anchor.addingTimeInterval(3.5)
        XCTAssertEqual(G7WatchAcquisition.relodgePlan(.peteDelay, sinceLinkUp: 3.5, anchor: anchor, now: now), .startDelay(seconds: 295))
        XCTAssertEqual(G7WatchAcquisition.relodgePlan(.holdApp, sinceLinkUp: 3.5, anchor: anchor, now: now), .holdThenConnect(wait: 31.5))
    }

    func testPastTheClearanceTheHoldHasNothingToWaitFor() {
        XCTAssertNil(G7WatchAcquisition.relodgePlan(.holdApp, sinceLinkUp: 120, anchor: anchor), "a wake mid-cycle: a plain request now")
        XCTAssertEqual(G7WatchAcquisition.relodgePlan(.holdApp, sinceLinkUp: 0, anchor: nil), .holdThenConnect(wait: 35),
                       "a late connect failure counts from now: hold the full clearance")
    }

    func testPetesDelayWithNoReadingOnRecordClearsTheTailLikeTheHold() {
        // No grid to aim at, but never a plain connect straight after a close: on 2026-09-16 a
        // same-burst failure storm (58 of 77 handshakes) began with exactly that.
        XCTAssertEqual(G7WatchAcquisition.relodgePlan(.peteDelay, sinceLinkUp: 3.5, anchor: nil), .holdThenConnect(wait: 31.5))
        XCTAssertNil(G7WatchAcquisition.relodgePlan(.peteDelay, sinceLinkUp: 120, anchor: nil))
    }

    // MARK: refusals — Pete's back-off, stop after two

    func testASynchronousRefusalBacksOffAndTwoStandDown() {
        let first = G7WatchAcquisition.onConnectFailure(refusals: 0, sinceLodge: 0.4)
        XCTAssertEqual(first.0, .backOff(G7WatchAcquisition.refusalBackoffSeconds)); XCTAssertEqual(first.refusals, 1)
        let second = G7WatchAcquisition.onConnectFailure(refusals: 1, sinceLodge: 0.3)
        XCTAssertEqual(second.0, .standDown); XCTAssertEqual(second.refusals, 2)
    }

    func testALateFailureRelodgesThroughTheArmAndClearsTheCount() {
        let r = G7WatchAcquisition.onConnectFailure(refusals: 1, sinceLodge: 120)
        XCTAssertEqual(r.0, .relodge); XCTAssertEqual(r.refusals, 0)
    }

    // MARK: the 3-miss test

    func testThreeSilentBurstsOnTheLodgedRequestMeanABootstrapPass() {
        XCTAssertEqual(G7WatchAcquisition.missedBursts(since: anchor, now: anchor.addingTimeInterval(8)), 0)
        XCTAssertEqual(G7WatchAcquisition.missedBursts(since: anchor, now: anchor.addingTimeInterval(2 * 300 + 8)), 2)
        XCTAssertGreaterThanOrEqual(G7WatchAcquisition.missedBursts(since: anchor, now: anchor.addingTimeInterval(3 * 300 + 8)),
                                    G7WatchAcquisition.missedBurstsBeforeBootstrap)
        XCTAssertEqual(G7WatchAcquisition.missedBursts(since: nil, now: anchor), 0, "nothing on record: nothing missed")
    }

    func testTheKeysSurviveTheTimedConnectEra() {
        // Kept verbatim so the first build after the collapse re-adopts the remembered peripheral
        // and keeps its last reading's grid without a scan.
        XCTAssertEqual(G7WatchAcquisition.adoptedPeripheralKey, "G7Lab.timedConnect.adoptedPeripheral")
        XCTAssertEqual(G7WatchAcquisition.lastReadingKey, "G7Lab.timedConnect.anchor")
    }
}

final class LoanWorkoutTests: XCTestCase {
    // The whole-loan workout session is opt-in: the 2026-09-15 no-keepalive loan passed.
    func testTheLoanWorkoutSessionStaysOff() {
        UserDefaults.standard.removeObject(forKey: StockLoopSession.loanWorkoutKey)
        XCTAssertFalse(StockLoopSession.loanWorkout)
    }
}
