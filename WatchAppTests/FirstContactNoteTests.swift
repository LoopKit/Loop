//
//  FirstContactNoteTests.swift
//  WatchAppTests
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//
//  A pod this watch has never met is found only with the screen on, so the Start page says so,
//  asking the kit about the standing copy rather than reading the pod's state itself.
//

import XCTest
import LoopKit
import LoopCore
import LoopAlgorithm
@testable import OmnipodKit
@testable import WatchApp

final class FirstContactNoteTests: XCTestCase {

    private let address: UInt32 = 0x17A6219A
    private var defaults: UserDefaults!
    private var dir: URL!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "FirstContactNoteTests-\(UUID().uuidString)")!
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        PeripheralHandleCache.forget(podAddress: address)
    }

    override func tearDown() {
        PeripheralHandleCache.forget(podAddress: address)
        super.tearDown()
    }

    private func makeController() async -> PodLoanWatchController {
        let cacheStore = PersistenceController(directoryURL: dir.appendingPathComponent("cache"))
        let doseStore = await DoseStore(healthKitSampleStore: nil, cacheStore: cacheStore,
                                        longestEffectDuration: ExponentialInsulinModelPreset.rapidActingAdult.effectDuration,
                                        provenanceIdentifier: "FirstContactNoteTests")
        let glucoseStore = await GlucoseStore(healthKitSampleStore: nil, cacheStore: cacheStore,
                                              cacheLength: 4 * 60 * 60, provenanceIdentifier: "FirstContactNoteTests")
        let carbStore = CarbStore(healthKitSampleStore: nil, cacheStore: cacheStore,
                                  cacheLength: 24 * 60 * 60, provenanceIdentifier: "FirstContactNoteTests")
        let manager = WatchLoopManager(doseStore: doseStore, glucoseStore: glucoseStore, carbStore: carbStore,
                                       defaults: defaults, stateDirectory: dir)
        return PodLoanWatchController(loopManager: manager, journal: LoanEventJournal(directory: dir),
                                      stateDirectory: dir)
    }

    /// The phone's standing copy of a DASH pod, as its export puts it on the wire.
    private func standingCopy() throws -> DormantGrant {
        let podState = PodState(address: address, firmwareVersion: "2.7.0", iFirmwareVersion: "2.7.0",
                                lotNo: 1, lotSeq: 1, insulinType: .novolog, podType: dashType)
        let raw: [String: Any] = ["basalSchedule": ["entries": [["rate": 1.0, "startTime": 0.0]]],
                                  "controllerId": UInt32(0x1234_5678), "podId": UInt32(0x1234_5679),
                                  "podState": podState.rawValue]
        let phonePump = try XCTUnwrap(OmniPumpManager(rawState: raw))
        let data = try PropertyListSerialization.data(fromPropertyList: phonePump.exportConfiguration().rawValue,
                                                      format: .binary, options: 0)
        let grant = LoanGrant(epoch: 3, expiresAt: Date(), pumpConfiguration: data, podAddress: 0,
                              therapySettingsRaw: Data([4, 5]), settingsTimeZoneID: "GMT", doseHistory: [])
        return DormantGrant(grant: grant, issuedAt: Date(), seizeToken: UUID())
    }

    func testTheStartPageAsksForTheWristOnlyForAPodThisWatchHasNotMet() async throws {
        let controller = await makeController()
        XCTAssertFalse(controller.debugSnapshot().pumpFirstContactExpected, "no standing copy yet: nothing to say")

        let copy = try standingCopy()
        controller.queue.sync { controller.handleDormantGrant(copy) }
        XCTAssertTrue(controller.debugSnapshot().pumpFirstContactExpected,
                      "a pod with no saved handle has to be found, which needs the screen on")

        PeripheralHandleCache.store("SAVED-HANDLE", forPodAddress: address)
        XCTAssertFalse(controller.debugSnapshot().pumpFirstContactExpected, "a saved handle connects with the wrist down")

        let relaunched = await makeController()
        XCTAssertFalse(relaunched.debugSnapshot().pumpFirstContactExpected, "the stored copy is read back after a relaunch")
        PeripheralHandleCache.forget(podAddress: address)
        XCTAssertTrue(relaunched.debugSnapshot().pumpFirstContactExpected)
    }
}
