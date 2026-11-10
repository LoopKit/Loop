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

@MainActor
final class FirstContactNoteTests: XCTestCase {

    private let address: UInt32 = 0x17A6219A
    private let handle = "0B1D2C3E-0000-4000-8000-00000000B002"
    private var defaults: UserDefaults!
    private var dir: URL!

    override func setUp() async throws {
        try await super.setUp()
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
        let grant = LoanGrant(epoch: 3, expiresAt: Date(), pumpConfiguration: data, therapySettingsRaw: Data([4, 5]), settingsTimeZoneID: "GMT", doseHistory: [])
        return DormantGrant(grant: grant, issuedAt: Date(), seizeToken: UUID())
    }

    /// The pump manager a Start builds, installed as Start installs it.
    private func adoptAsStartDoes(_ copy: DormantGrant, on controller: PodLoanWatchController) async throws -> OmniPumpManager {
        let configuration = try XCTUnwrap(copy.grant.sharedPumpConfiguration)
        let manager = try XCTUnwrap(watchPumpManager(adopting: configuration,
                                                     localState: controller.pumpLocalState(for: configuration)) as? OmniPumpManager)
        await controller.onMain {
            manager.pumpManagerDelegate = controller
            manager.delegateQueue = .main
            controller.pumpManager = manager
            controller.savePumpLocalState(of: manager)
        }
        return manager
    }

    private func firstContactExpected(_ controller: PodLoanWatchController) async -> Bool {
        await controller.fencedSnapshot().pumpFirstContactExpected
    }

    func testTheStartPageAsksForTheWristOnlyForAPodThisWatchHasNotMet() async throws {
        let controller = await makeController()
        let firstContact1 = await firstContactExpected(controller)
        XCTAssertFalse(firstContact1, "no standing copy yet: nothing to say")

        let copy = try standingCopy()
        await controller.onMain { controller.handleDormantGrant(copy) }
        let firstContact2 = await firstContactExpected(controller)
        XCTAssertTrue(firstContact2, "a pod with no saved handle has to be found, which needs the screen on")

        controller.pumpLocalStateStore.wrappedValue = ["Omni": ["podAddress": address, "bleIdentifier": handle]]
        let firstContact3 = await firstContactExpected(controller)
        XCTAssertFalse(firstContact3, "a saved handle connects with the wrist down")

        let relaunched = await makeController()
        let firstContact4 = await firstContactExpected(relaunched)
        XCTAssertFalse(firstContact4, "the stored copy and local state are read back after a relaunch")
        relaunched.pumpLocalStateStore.wrappedValue = nil
        let firstContact5 = await firstContactExpected(relaunched)
        XCTAssertTrue(firstContact5)
    }

    /// Loan 1 finds the pod; its handle is saved as the kit's local state, survives the teardown
    /// and a relaunch, and reaches loan 2's adopt. Another pod gets no use of it.
    func testTheHandleALoanFoundReachesTheNextAdopt() async throws {
        let controller = await makeController()
        let copy = try standingCopy()
        await controller.onMain { controller.handleDormantGrant(copy) }
        let firstContact6 = await firstContactExpected(controller)
        XCTAssertTrue(firstContact6)

        // Loan 1: nothing saved, so the kit searches and adopts the peripheral it finds.
        let first = try await adoptAsStartDoes(copy, on: controller)
        XCTAssertTrue(first.takeControlNeedsSearch)
        let ble = try XCTUnwrap(first.podComms as? BlePodComms)
        ble.omnipodDidAdoptLoanPod(uuidString: handle)
        await controller.onMain { }
        await controller.onMain { controller.teardownPump() }
        await controller.onMain { }   // anything the release sent the delegate

        let firstContact7 = await firstContactExpected(controller)
        XCTAssertFalse(firstContact7, "the handle outlived the loan")
        let relaunched = await makeController()
        let firstContact8 = await firstContactExpected(relaunched)
        XCTAssertFalse(firstContact8, "and the relaunch")

        // A new pod: the saved handle is another pod's.
        let newPod = try standingCopy(address: address &+ 1)
        await relaunched.onMain { relaunched.handleDormantGrant(newPod) }
        let firstContact9 = await firstContactExpected(relaunched)
        XCTAssertTrue(firstContact9, "a new pod is found with the screen on")

        // Loan 2, the same pod: the adopt gets the handle and dials it.
        await relaunched.onMain { relaunched.handleDormantGrant(copy) }
        let second = try await adoptAsStartDoes(copy, on: relaunched)
        XCTAssertEqual(second.state.podState?.bleIdentifier, handle)
        XCTAssertFalse(second.takeControlNeedsSearch)
    }

    /// A saved handle that never connected is dropped at release, and the watch saves that: the
    /// next Start asks for the wrist again.
    func testASavedHandleThatNeverConnectedIsDroppedAtRelease() async throws {
        let controller = await makeController()
        let copy = try standingCopy()
        await controller.onMain { controller.handleDormantGrant(copy) }
        controller.pumpLocalStateStore.wrappedValue = ["Omni": ["podAddress": address, "bleIdentifier": handle]]

        let manager = try await adoptAsStartDoes(copy, on: controller)
        XCTAssertEqual(manager.state.podState?.bleIdentifier, handle)
        await controller.onMain { controller.teardownPump() }   // no radio here, so it never connected
        await controller.onMain { }

        XCTAssertNil(manager.localState)
        XCTAssertNil(controller.pumpLocalState(for: try XCTUnwrap(copy.grant.sharedPumpConfiguration)))
        let firstContact10 = await firstContactExpected(controller)
        XCTAssertTrue(firstContact10, "the next adopt searches")
    }
}
