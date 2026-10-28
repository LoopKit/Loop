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

@MainActor
final class PumpTeardownReleaseTests: XCTestCase {

    private var defaults: UserDefaults!
    private var dir: URL!

    override func setUp() async throws {
        try await super.setUp()
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
            await controller.onMain {
                pump.pumpManagerDelegate = controller
                pump.delegateQueue = .main
                controller.pumpManager = pump
                controller.loopManager.pumpManager = pump
                if takeControl { pump.takeControl() }
            }
        }

        await controller.onMain { controller.teardownPump() }
        await controller.onMain {}
        await controller.loopManager.laneSettled()
        return ({ weakPump == nil }, { weakBluetooth == nil })
    }

    /// Lets queued callbacks that briefly hold the object run before judging it leaked.
    private func released(within seconds: TimeInterval = 3, _ isGone: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if isGone() { return true }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return isGone()
    }

    /// A driver released by a teardown can still report once, when the release let its last command
    /// finish. The controller stays its delegate (the driver treats none as impossible), drops the
    /// report, and saves nothing for it.
    func testAReleasedDriversLateReportIsDroppedNotCrashed() async throws {
        let controller = await makeController()
        let pump = try makePump()
        await controller.onMain {
            pump.pumpManagerDelegate = controller
            pump.delegateQueue = .main
            controller.pumpManager = pump
            controller.loopManager.pumpManager = pump
        }
        await controller.onMain { controller.teardownPump() }
        await controller.onMain {}
        XCTAssertTrue((pump.pumpManagerDelegate as AnyObject?) === controller, "still the delegate: a late report must find one")
        XCTAssertNil(controller.pumpStateStore.wrappedValue, "precondition: the teardown cleared the saved state")

        let reported = expectation(description: "the late report completes")
        let event = NewPumpEvent(date: Date(), dose: nil, raw: Data([1]), title: "late")
        await controller.onMain {
            controller.pumpManagerDidUpdateState(pump)
            controller.pumpManager(pump, hasNewPumpEvents: [event], lastReconciliation: Date(), replacePendingEvents: false) { error in
                XCTAssertNil(error)
                reported.fulfill()
            }
        }
        await fulfillment(of: [reported], timeout: 5)
        XCTAssertNil(controller.pumpStateStore.wrappedValue, "a released driver's state is not saved: the next launch must not resume it")
        XCTAssertNil(controller.pumpManager)
    }

    func testTeardownReleasesThePodManagerAndItsBluetoothManager() async throws {
        let left = try await loanThenTeardown(takeControl: false)
        let pumpGone = await released(left.pumpGone)
        let bluetoothGone = await released(left.bluetoothGone)
        XCTAssertTrue(pumpGone, "the pod manager outlives its loan")
        XCTAssertTrue(bluetoothGone, "its Bluetooth manager outlives the loan, still holding the restore identifiers")
    }

    /// As a real loan: the take has started the link before the teardown.
    func testTeardownReleasesAManagerThatHadTakenControl() async throws {
        let left = try await loanThenTeardown(takeControl: true)
        let pumpGone = await released(left.pumpGone)
        let bluetoothGone = await released(left.bluetoothGone)
        XCTAssertTrue(pumpGone, "the pod manager outlives its loan")
        XCTAssertTrue(bluetoothGone, "its Bluetooth manager outlives the loan, still holding the restore identifiers")
    }
}
