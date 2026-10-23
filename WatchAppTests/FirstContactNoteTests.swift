//
//  FirstContactNoteTests.swift
//  WatchAppTests
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//
//  A pod this watch has never met is found only with the screen on, so the Start page says so,
//  asking the kit about the standing copy and the kit's saved local state rather than reading the
//  pod's state itself. The local state (this watch's handle for the pod) outlives each loan.
//

import XCTest
import LoopKit
import LoopCore
import LoopAlgorithm
@testable import OmnipodKit
@testable import WatchApp

final class FirstContactNoteTests: XCTestCase {

    private let address: UInt32 = 0x17A6219A
    private let handle = "0B1D2C3E-0000-4000-8000-00000000B002"
    private var defaults: UserDefaults!
    private var dir: URL!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "FirstContactNoteTests-\(UUID().uuidString)")!
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
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
    private func standingCopy(address: UInt32? = nil) throws -> DormantGrant {
        let podState = PodState(address: address ?? self.address, firmwareVersion: "2.7.0", iFirmwareVersion: "2.7.0",
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

    /// The pump manager a Start builds, installed as Start installs it.
    private func adoptAsStartDoes(_ copy: DormantGrant, on controller: PodLoanWatchController) throws -> OmniPumpManager {
        let configuration = try XCTUnwrap(copy.grant.sharedPumpConfiguration)
        let manager = try XCTUnwrap(watchPumpManager(adopting: configuration,
                                                     localState: controller.pumpLocalState(for: configuration)) as? OmniPumpManager)
        controller.queue.sync {
            manager.pumpManagerDelegate = controller
            manager.delegateQueue = controller.queue
            controller.pumpManager = manager
            controller.savePumpLocalState(of: manager)
        }
        return manager
    }

    private func firstContactExpected(_ controller: PodLoanWatchController) -> Bool {
        controller.debugSnapshot().pumpFirstContactExpected
    }

    func testTheStartPageAsksForTheWristOnlyForAPodThisWatchHasNotMet() async throws {
        let controller = await makeController()
        XCTAssertFalse(firstContactExpected(controller), "no standing copy yet: nothing to say")

        let copy = try standingCopy()
        controller.queue.sync { controller.handleDormantGrant(copy) }
        XCTAssertTrue(firstContactExpected(controller), "a pod with no saved handle has to be found, which needs the screen on")

        controller.pumpLocalStateStore.wrappedValue = ["Omni": ["podAddress": address, "bleIdentifier": handle]]
        XCTAssertFalse(firstContactExpected(controller), "a saved handle connects with the wrist down")

        let relaunched = await makeController()
        XCTAssertFalse(firstContactExpected(relaunched), "the stored copy and local state are read back after a relaunch")
        relaunched.pumpLocalStateStore.wrappedValue = nil
        XCTAssertTrue(firstContactExpected(relaunched))
    }

    /// Loan 1 finds the pod; its handle is saved as the kit's local state, survives the teardown
    /// and a relaunch, and reaches loan 2's adopt. Another pod gets no use of it.
    func testTheHandleALoanFoundReachesTheNextAdopt() async throws {
        let controller = await makeController()
        let copy = try standingCopy()
        controller.queue.sync { controller.handleDormantGrant(copy) }
        XCTAssertTrue(firstContactExpected(controller))

        // Loan 1: nothing saved, so the kit searches and adopts the peripheral it finds.
        let first = try adoptAsStartDoes(copy, on: controller)
        XCTAssertTrue(first.takeControlNeedsSearch)
        let ble = try XCTUnwrap(first.podComms as? BlePodComms)
        ble.omnipodDidAdoptLoanPod(uuidString: handle)
        controller.queue.sync { }
        controller.queue.sync { controller.teardownPump() }
        controller.queue.sync { }   // anything the release sent the delegate

        XCTAssertFalse(firstContactExpected(controller), "the handle outlived the loan")
        let relaunched = await makeController()
        XCTAssertFalse(firstContactExpected(relaunched), "and the relaunch")

        // A new pod: the saved handle is another pod's.
        let newPod = try standingCopy(address: address &+ 1)
        relaunched.queue.sync { relaunched.handleDormantGrant(newPod) }
        XCTAssertTrue(firstContactExpected(relaunched), "a new pod is found with the screen on")

        // Loan 2, the same pod: the adopt gets the handle and dials it.
        relaunched.queue.sync { relaunched.handleDormantGrant(copy) }
        let second = try adoptAsStartDoes(copy, on: relaunched)
        XCTAssertEqual(second.state.podState?.bleIdentifier, handle)
        XCTAssertFalse(second.takeControlNeedsSearch)
    }

    /// A saved handle that never connected is dropped at release, and the watch saves that: the
    /// next Start asks for the wrist again.
    func testASavedHandleThatNeverConnectedIsDroppedAtRelease() async throws {
        let controller = await makeController()
        let copy = try standingCopy()
        controller.queue.sync { controller.handleDormantGrant(copy) }
        controller.pumpLocalStateStore.wrappedValue = ["Omni": ["podAddress": address, "bleIdentifier": handle]]

        let manager = try adoptAsStartDoes(copy, on: controller)
        XCTAssertEqual(manager.state.podState?.bleIdentifier, handle)
        controller.queue.sync { controller.teardownPump() }   // no radio here, so it never connected
        controller.queue.sync { }

        XCTAssertNil(manager.localState)
        XCTAssertNil(controller.pumpLocalState(for: try XCTUnwrap(copy.grant.sharedPumpConfiguration)))
        XCTAssertTrue(firstContactExpected(controller), "the next adopt searches")
    }
}
