//
//  EndDuringBolusTests.swift
//  WatchAppTests
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//
//  Nobody takes the pod while it is giving a bolus (control document, rows G and H): the watch's
//  End is refused on the spot while its own bolus is being given, and a refusal is felt. Nor while a
//  command to it is unconfirmed: the pod driver keeps the pod, and the End is refused. Hosted with a real DASH manager, which
//  needs the host app's bluetooth-central background mode.
//

import XCTest
import LoopKit
import LoopCore
import LoopAlgorithm
@testable import OmnipodKit
@testable import WatchApp

@MainActor
final class EndDuringBolusTests: XCTestCase {

    private var defaults: UserDefaults!
    private var dir: URL!

    override func setUp() async throws {
        try await super.setUp()
        defaults = UserDefaults(suiteName: "EndDuringBolusTests-\(UUID().uuidString)")!
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    private func makeController() async -> PodLoanWatchController {
        let cacheStore = PersistenceController(directoryURL: dir.appendingPathComponent("cache"))
        let doseStore = await DoseStore(healthKitSampleStore: nil, cacheStore: cacheStore,
                                        longestEffectDuration: ExponentialInsulinModelPreset.rapidActingAdult.effectDuration,
                                        provenanceIdentifier: "EndDuringBolusTests")
        let glucoseStore = await GlucoseStore(healthKitSampleStore: nil, cacheStore: cacheStore,
                                              cacheLength: 4 * 60 * 60, provenanceIdentifier: "EndDuringBolusTests")
        let carbStore = CarbStore(healthKitSampleStore: nil, cacheStore: cacheStore,
                                  cacheLength: 24 * 60 * 60, provenanceIdentifier: "EndDuringBolusTests")
        let manager = WatchLoopManager(doseStore: doseStore, glucoseStore: glucoseStore, carbStore: carbStore,
                                       defaults: defaults, stateDirectory: dir)
        return PodLoanWatchController(loopManager: manager, journal: LoanEventJournal(directory: dir),
                                      stateDirectory: dir)
    }

    /// A DASH manager whose pod is giving a 2 U bolus started just now, or no bolus.
    private func makePumpMidBolus(_ bolusing: Bool = true) throws -> OmniPumpManager {
        var podState = PodState(address: 0x1f0b3557, firmwareVersion: "2.7.0", iFirmwareVersion: "2.7.0",
                                lotNo: 1, lotSeq: 1, insulinType: .novolog, podType: dashType)
        podState.setupProgress = .completed
        if bolusing {
            podState.unfinalizedBolus = UnfinalizedDose(decisionId: nil, bolusAmount: 2.0, startTime: Date(),
                                                        scheduledCertainty: .certain, insulinType: .novolog)
        }
        let raw: [String: Any] = ["basalSchedule": ["entries": [["rate": 1.0, "startTime": 0.0]]],
                                  "controllerId": UInt32(0x1234_5678), "podId": UInt32(0x1234_5679),
                                  "podState": podState.rawValue]
        return try XCTUnwrap(OmniPumpManager(rawState: raw))
    }

    /// End with the watch's bolus still being given: refused at once, no offer goes to the phone,
    /// the loan continues, and the screen says when to try again.
    func testEndWhileTheWatchsBolusIsBeingGivenIsRefusedAtOnce() async throws {
        let c = await makeController()
        let pump = try makePumpMidBolus()
        guard case .inProgress = pump.status.bolusState else { return XCTFail("precondition: the pod is giving a bolus") }
        await c.onMain {
            pump.pumpManagerDelegate = c
            pump.delegateQueue = .main
            c.pumpManager = pump
            c.loopManager.pumpManager = pump
            c.phase = .active
        }
        var sent: [[String: Any]] = []
        c.send = { sent.append($0) }
        var refusalsFelt = 0
        c.playRefusal = { refusalsFelt += 1 }

        c.beginHandback()
        await c.onMain { }

        XCTAssertEqual(refusalsFelt, 1, "felt as well as read")
        XCTAssertTrue(sent.isEmpty, "no offer goes out")
        let snapshot1 = await c.fencedSnapshot()
        XCTAssertFalse(snapshot1.handbackPending)
        XCTAssertEqual(c.phase, .active, "the loan continues")
        XCTAssertNotNil(c.pumpManager, "the watch still holds the pod")
        let snapshot2 = await c.fencedSnapshot()
        XCTAssertTrue(snapshot2.handbackFailureText?.contains("bolus") == true,
                      "on screen: why, and when to try again")
    }

    /// A loan with no bolus on the pod, the End about to be tapped.
    private func activeLoan(_ c: PodLoanWatchController) async throws -> OmniPumpManager {
        let pump = try makePumpMidBolus(false)
        await c.onMain {
            pump.pumpManagerDelegate = c
            pump.delegateQueue = .main
            c.pumpManager = pump
            c.loopManager.pumpManager = pump
            c.phase = .active
        }
        return pump
    }

    /// End tapped while the watch's bolus is still being sent, before the pod has taken it up: the
    /// bolus counts from the moment it is sent, so the End is refused on the spot, not started.
    func testEndWhileTheWatchsBolusIsBeingSentIsRefusedAtOnce() async throws {
        let c = await makeController()
        _ = try await activeLoan(c)
        c.loopManager.setManualBolusInFlight(true, units: 1)
        var sent: [[String: Any]] = []
        c.send = { sent.append($0) }
        var refusalsFelt = 0
        c.playRefusal = { refusalsFelt += 1 }

        c.beginHandback()
        await c.onMain { }

        XCTAssertTrue(sent.isEmpty, "no offer: no Cancel screen")
        let snapshot3 = await c.fencedSnapshot()
        XCTAssertFalse(snapshot3.handbackPending)
        XCTAssertEqual(refusalsFelt, 1)
        let snapshot4 = await c.fencedSnapshot()
        XCTAssertEqual(snapshot4.handbackFailureText, "A bolus is still being given. Try again when it has finished.")
    }

    /// A bolus started while the End waited for the phone: at the release the End is refused, and
    /// the watch keeps the pod.
    func testABolusStartedDuringAPendingEndRefusesItAtTheRelease() async throws {
        let c = await makeController()
        _ = try await activeLoan(c)
        c.send = { _ in }
        var refusalsFelt = 0
        c.playRefusal = { refusalsFelt += 1 }
        await c.onMain { c.handbackRequested = true }      // the End is waiting for the phone
        c.loopManager.setManualBolusInFlight(true, units: 1)

        await c.onMain { c.finalizeHandback() }            // the drain is complete

        XCTAssertEqual(c.phase, .active, "the loan continues")
        XCTAssertNotNil(c.pumpManager, "the watch still holds the pod")
        let snapshot5 = await c.fencedSnapshot()
        XCTAssertFalse(snapshot5.handbackPending)
        XCTAssertEqual(refusalsFelt, 1)
        let snapshot6 = await c.fencedSnapshot()
        XCTAssertTrue(snapshot6.handbackFailureText?.contains("bolus") == true)
    }

    /// A command to the pod unconfirmed at the release: the pod driver keeps the pod, the End is refused,
    /// no final offer goes out, and the watch's loop has the pod again.
    func testAnUnconfirmedCommandAtTheReleaseRefusesTheEnd() async throws {
        let c = await makeController()
        let pump = try await activeLoan(c)
        pump.setState { state in
            var pod = state.podState
            pod?.unacknowledgedCommand = .stopProgram(.tempBasal, 3, Date(), false)
            state.updatePodStateFromPodComms(pod)
        }
        var sent: [[String: Any]] = []
        c.send = { sent.append($0) }
        var refusalsFelt = 0
        c.playRefusal = { refusalsFelt += 1 }
        await c.onMain { c.handbackRequested = true }      // the End is waiting for the phone

        await c.onMain { c.finalizeHandback() }            // the drain is complete
        await c.loopManager.laneSettled()
        await c.onMain { }
        await c.loopManager.laneSettled()

        XCTAssertFalse(pump.isControlReleased, "the driver kept the pod")
        XCTAssertEqual(c.phase, .active, "the loan continues")
        XCTAssertTrue(c.pumpManager === pump, "the watch still holds the pod")
        XCTAssertTrue(c.loopManager.pumpManager === pump, "the watch's loop doses again")
        XCTAssertTrue(sent.isEmpty, "no final offer")
        let snapshot7 = await c.fencedSnapshot()
        XCTAssertFalse(snapshot7.handbackPending)
        XCTAssertEqual(refusalsFelt, 1)
        let snapshot8 = await c.fencedSnapshot()
        XCTAssertEqual(snapshot8.handbackFailureText, LoanControl.unconfirmedCommandRefusal)
    }

    /// Nobody starts a bolus while the pod is being handed back: with an End waiting, the watch
    /// refuses a bolus and says how to give one; the End itself is untouched.
    func testABolusIsRefusedWhileAnEndIsWaiting() async throws {
        let c = await makeController()
        _ = try await activeLoan(c)
        XCTAssertNil(c.bolusRefusalWhileEnding(), "no End waiting: a bolus may go")

        await c.onMain { c.handbackRequested = true }
        XCTAssertEqual(c.bolusRefusalWhileEnding(), "Sport Mode is ending. Bolus on the iPhone once it has the pod.")
        let snapshot9 = await c.fencedSnapshot()
        XCTAssertTrue(snapshot9.handbackPending, "the End carries on")

        let content = CarbAndBolusFlowViewModel.bolusFailureContent(units: 1, carbGrams: nil,
                                                                    error: BolusRefusedWhileEnding(reason: c.bolusRefusalWhileEnding()!))
        XCTAssertEqual(content.title, "Bolus Not Sent")
    }

    /// A Start the phone denies (its own bolus still being given, for one) is felt on the watch too.
    func testAStartThePhoneDeniesIsFelt() async throws {
        let c = await makeController()
        var refusalsFelt = 0
        c.playRefusal = { refusalsFelt += 1 }
        let reason = "A bolus is still being given. Try again in 30 seconds."
        c.handleIncoming(userInfo: try LoanMessage.denied(LoanDenied(reason: reason)).transportDictionary())
        await c.onMain { }

        XCTAssertEqual(refusalsFelt, 1)
        XCTAssertEqual(c.phase, .idle)
    }
}
