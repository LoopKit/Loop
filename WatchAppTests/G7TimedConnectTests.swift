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
import LoopKit
import LoopCore
import LoopAlgorithm
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

/// The phone's relay and the watch's own G7 name a reading alike, so the store keeps one row.
final class G7RelayDedupTests: XCTestCase {
    private func message(_ hex: String) -> G7GlucoseMessage { G7GlucoseMessage(data: Data(hexadecimalString: hex)!)! }

    private func reading(_ date: Date, id: String) -> NewGlucoseSample {
        NewGlucoseSample(date: date, quantity: LoopQuantity(unit: .milligramsPerDeciliter, doubleValue: 150),
                         condition: nil, trend: .flat, trendRate: nil, isDisplayOnly: false, wasUserEntered: false,
                         syncIdentifier: id)
    }

    /// With no pod, a cycle asked for is recorded by the idle log's latch.
    private func readingAskedForACycle(_ manager: WatchLoopManager) -> Bool {
        manager.loggedIdleNoPump
    }

    /// Stock's `storedNewGlucose`: a CGM reading runs a cycle only when the store did not already
    /// hold it (the relay usually lands first).
    func testAReadingTheStoreAlreadyHoldsRunsNoCycleAndANewOneDoes() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let cacheStore = PersistenceController(directoryURL: dir.appendingPathComponent("cache"))
        let doseStore = await DoseStore(healthKitSampleStore: nil, cacheStore: cacheStore,
                                        longestEffectDuration: ExponentialInsulinModelPreset.rapidActingAdult.effectDuration,
                                        provenanceIdentifier: "G7RelayDedupTests")
        let glucoseStore = await GlucoseStore(healthKitSampleStore: nil, cacheStore: cacheStore,
                                              cacheLength: 4 * 60 * 60, provenanceIdentifier: "G7RelayDedupTests")
        let carbStore = CarbStore(healthKitSampleStore: nil, cacheStore: cacheStore,
                                  cacheLength: 24 * 60 * 60, provenanceIdentifier: "G7RelayDedupTests")
        let wrist = WatchLoopManager(doseStore: doseStore, glucoseStore: glucoseStore, carbStore: carbStore,
                                     defaults: UserDefaults(suiteName: "G7RelayDedupTests-\(UUID().uuidString)")!,
                                     stateDirectory: dir)
        let cgm = G7CGMManager()
        let now = Date()
        let held = reading(now.addingTimeInterval(-5 * 60), id: "held-\(UUID().uuidString)")
        _ = try await glucoseStore.addGlucoseSamples([held])

        wrist.deviceQueue.sync { wrist.cgmManager(cgm, hasNew: .newData([held])) }
        try await Task.sleep(nanoseconds: 1_000_000_000)
        XCTAssertFalse(readingAskedForACycle(wrist), "the store already held it: no cycle")

        wrist.deviceQueue.sync { wrist.cgmManager(cgm, hasNew: .newData([reading(now, id: "new-\(UUID().uuidString)")])) }
        var tries = 0
        while !readingAskedForACycle(wrist), tries < 50 {
            tries += 1
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertTrue(readingAskedForACycle(wrist), "a stored reading runs one")
    }

    func testARelayedReadingAndTheWatchsOwnReadingOfItAreOneRow() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let cacheStore = PersistenceController(directoryURL: dir.appendingPathComponent("cache"))
        let doseStore = await DoseStore(healthKitSampleStore: nil, cacheStore: cacheStore,
                                        longestEffectDuration: ExponentialInsulinModelPreset.rapidActingAdult.effectDuration,
                                        provenanceIdentifier: "G7RelayDedupTests")
        let glucoseStore = await GlucoseStore(healthKitSampleStore: nil, cacheStore: cacheStore,
                                              cacheLength: 4 * 60 * 60, provenanceIdentifier: "G7RelayDedupTests")
        let carbStore = CarbStore(healthKitSampleStore: nil, cacheStore: cacheStore,
                                  cacheLength: 24 * 60 * 60, provenanceIdentifier: "G7RelayDedupTests")
        let wrist = WatchLoopManager(doseStore: doseStore, glucoseStore: glucoseStore, carbStore: carbStore,
                                     defaults: UserDefaults(suiteName: "G7RelayDedupTests-\(UUID().uuidString)")!,
                                     stateDirectory: dir)

        // The phone discovered the sensor; the watch adopts its export.
        let activatedAt = Date().addingTimeInterval(-87_485 - 60)
        var phone = G7CGMManagerState()
        phone.sensorID = "DXCMQj"
        phone.activatedAt = activatedAt
        let adopted = G7CGMManagerState.adopted(from: phone.sharedState)
        let sensor = G7Sensor(mode: .direct, credentials: adopted.sensorCredentials, bluetoothManager: TestBluetoothManager())
        let g7 = G7CGMManager(state: adopted, sensor: sensor)
        wrist.installCGMManager(g7, builtFrom: nil)

        // The phone's reading, relayed under the phone's name (G7CGMManager: activation hours,
        // sensor ID, sensor timestamp). The hours are computed as the kit does, minutes then
        // hours: `t / 3600` rounds differently for about a quarter of timestamps.
        let reading = message("4e00c35501002601000106008a00060187000f")
        let relayed = try XCTUnwrap(WatchContext(
            glucose: LoopQuantity(unit: .milligramsPerDeciliter, doubleValue: 138),
            glucoseDate: activatedAt.addingTimeInterval(TimeInterval(reading.glucoseTimestamp)),
            glucoseSyncIdentifier: "\(activatedAt.timeIntervalSince1970 / 60 / 60) DXCMQj \(reading.glucoseTimestamp)"
        ).newGlucoseSample)
        _ = try await glucoseStore.addGlucoseSamples([relayed])

        // The watch then reads the same sample itself (its own activation estimate is a fraction
        // off), then the next one, which marks that the first has been through the store.
        sensor.activationDate = activatedAt.addingTimeInterval(0.4)
        g7.sensor(sensor, didRead: reading)
        g7.sensor(sensor, didRead: message("4e00ef5601002701000106008c00060187000f"))

        var stored: [StoredGlucoseSample] = []
        for _ in 0..<50 {
            stored = try await glucoseStore.getGlucoseSamples(start: activatedAt, end: nil)
            if stored.contains(where: { $0.quantity.doubleValue(for: .milligramsPerDeciliter) == 140 }) { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertTrue(stored.contains { $0.quantity.doubleValue(for: .milligramsPerDeciliter) == 140 },
                      "the watch's own readings reach the store")
        XCTAssertEqual(stored.filter { $0.syncIdentifier == relayed.syncIdentifier }.count, 1,
                       "one row for the sample both devices read")
        XCTAssertEqual(stored.count, 2)
    }
}
