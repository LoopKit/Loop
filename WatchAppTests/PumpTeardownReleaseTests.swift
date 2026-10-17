//
//  PumpTeardownReleaseTests.swift
//  WatchAppTests
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//
//  A loan's pod manager must be gone once its teardown has run. CoreBluetooth lets one live
//  central hold a restore identifier per process, and every Omnipod manager registers the same
//  two ("com.OmnipodKit" and "com.rileylink.CentralManager"). A manager that outlives its loan
//  leaves the next loan's central refused as "unsupported" (bench, 2026-10-04).
//

import XCTest
import LoopKit
import LoopCore
import LoopAlgorithm
@testable import OmnipodKit
@testable import WatchApp

final class PumpTeardownReleaseTests: XCTestCase {

    private var defaults: UserDefaults!
    private var dir: URL!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "PumpTeardownReleaseTests-\(UUID().uuidString)")!
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    private func makeController() async -> PodLoanWatchController {
        let cacheStore = PersistenceController(directoryURL: dir.appendingPathComponent("cache"))
        let doseStore = await DoseStore(healthKitSampleStore: nil, cacheStore: cacheStore,
                                        longestEffectDuration: ExponentialInsulinModelPreset.rapidActingAdult.effectDuration,
                                        provenanceIdentifier: "PumpTeardownReleaseTests")
        let glucoseStore = await GlucoseStore(healthKitSampleStore: nil, cacheStore: cacheStore,
                                              cacheLength: 4 * 60 * 60, provenanceIdentifier: "PumpTeardownReleaseTests")
        let carbStore = CarbStore(healthKitSampleStore: nil, cacheStore: cacheStore,
                                  cacheLength: 24 * 60 * 60, provenanceIdentifier: "PumpTeardownReleaseTests")
        let manager = WatchLoopManager(doseStore: doseStore, glucoseStore: glucoseStore, carbStore: carbStore,
                                       defaults: defaults, stateDirectory: dir)
        return PodLoanWatchController(loopManager: manager, journal: LoanEventJournal(directory: dir),
                                      stateDirectory: dir)
    }

    /// A DASH manager with a completed pod.
    private func makePump() throws -> OmniPumpManager {
        var podState = PodState(address: 0x1f0b3557, firmwareVersion: "2.7.0", iFirmwareVersion: "2.7.0",
                                lotNo: 1, lotSeq: 1, insulinType: .novolog, podType: dashType)
        podState.setupProgress = .completed
        let raw: [String: Any] = ["basalSchedule": ["entries": [["rate": 0.7, "startTime": 0.0]]],
                                  "controllerId": UInt32(0x1234_5678), "podId": UInt32(0x1234_5679),
                                  "podState": podState.rawValue]
        return try XCTUnwrap(OmniPumpManager(rawState: raw))
    }

    /// Holds the manager the way a live loan does, runs `teardownPump()`, and reports what is left.
    private func loanThenTeardown(takeControl: Bool) async throws -> (pumpGone: () -> Bool, bluetoothGone: () -> Bool) {
        let controller = await makeController()
        weak var weakPump: OmniPumpManager?
        weak var weakBluetooth: BluetoothManager?
        do {
            let pump = try makePump()
            weakPump = pump
            weakBluetooth = (pump.podComms as? BlePodComms)?.bluetoothManager
            XCTAssertNotNil(weakBluetooth, "a DASH manager owns a Bluetooth manager")
            controller.queue.sync {
                pump.pumpManagerDelegate = controller
                pump.delegateQueue = controller.queue
                controller.pumpManager = pump
                controller.loopManager.pumpManager = pump
                if takeControl { pump.takeControl() }
            }
        }

        controller.queue.sync { controller.teardownPump() }
        controller.queue.sync {}
        controller.loopManager.dataAccessQueue.sync {}
        return ({ weakPump == nil }, { weakBluetooth == nil })
    }

    /// Lets queued callbacks that briefly hold the object run before judging it leaked.
    private func released(within seconds: TimeInterval = 3, _ isGone: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if isGone() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return isGone()
    }

    func testTeardownReleasesThePodManagerAndItsBluetoothManager() async throws {
        let left = try await loanThenTeardown(takeControl: false)
        XCTAssertTrue(released(left.pumpGone), "the pod manager outlives its loan")
        XCTAssertTrue(released(left.bluetoothGone), "its Bluetooth manager outlives the loan, still holding the restore identifiers")
    }

    /// As a real loan: the take has started the link before the teardown.
    func testTeardownReleasesAManagerThatHadTakenControl() async throws {
        let left = try await loanThenTeardown(takeControl: true)
        XCTAssertTrue(released(left.pumpGone), "the pod manager outlives its loan")
        XCTAssertTrue(released(left.bluetoothGone), "its Bluetooth manager outlives the loan, still holding the restore identifiers")
    }
}
