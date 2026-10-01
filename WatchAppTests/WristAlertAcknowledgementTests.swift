//
//  WristAlertAcknowledgementTests.swift
//  WatchAppTests
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//
//  OK on a wrist alert reaches the manager that raised it, so a borrowed pod stops beeping.
//

import XCTest
import LoopKit
import LoopCore
import LoopAlgorithm
import UserNotifications
@testable import OmnipodKit
@testable import WatchApp

final class WristAlertAcknowledgementTests: XCTestCase {

    private final class SpyResponder: AlertResponder {
        var acknowledged: [String] = []
        var failure: Error?
        func acknowledgeAlert(alertIdentifier: LoopKit.Alert.AlertIdentifier) async throws {
            if let failure { throw failure }
            acknowledged.append(alertIdentifier)
        }
    }

    private var scheduler: RecordingWristAlertScheduler!
    private var defaults: UserDefaults!
    private var dir: URL!

    override func setUp() {
        super.setUp()
        scheduler = RecordingWristAlertScheduler()
        WristAlerts.scheduler = scheduler
        defaults = UserDefaults(suiteName: "WristAlertAcknowledgementTests-\(UUID().uuidString)")!
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        WristAlerts.scheduler = UNUserNotificationCenter.current()
        super.tearDown()
    }

    private func podAlert(_ id: String = "podExpiring") -> LoopKit.Alert {
        let content = LoopKit.Alert.Content(title: "Pod Expiring", body: "Change the pod soon.", acknowledgeActionButtonLabel: "OK")
        return LoopKit.Alert(identifier: .init(managerIdentifier: "Omni", alertIdentifier: id),
                             foregroundContent: content, backgroundContent: content, trigger: .immediate)
    }

    func testAWristAlertCarriesWhatAnAcknowledgementNeeds() throws {
        WatchAlertPresenter.present(podAlert())
        let request = try XCTUnwrap(scheduler.pending.first)

        XCTAssertEqual(request.content.categoryIdentifier, LoopNotificationCategory.alert.rawValue, "the OK button")
        XCTAssertEqual(WatchAlertPresenter.alertIdentifier(in: request.content.userInfo),
                       LoopKit.Alert.Identifier(managerIdentifier: "Omni", alertIdentifier: "podExpiring"))
        XCTAssertTrue(WatchAlertPresenter.isWristAlert(request.identifier))
    }

    func testOKAndDismissAcknowledgeButOpeningDoesNot() {
        XCTAssertTrue(WatchAlertPresenter.acknowledges(NotificationManager.Action.acknowledgeAlert.rawValue))
        XCTAssertTrue(WatchAlertPresenter.acknowledges(UNNotificationDismissActionIdentifier))
        XCTAssertFalse(WatchAlertPresenter.acknowledges(UNNotificationDefaultActionIdentifier))
    }

    func testAnAcknowledgementReachesTheManagerAndClearsTheAlert() async throws {
        let alert = podAlert()
        WatchAlertPresenter.present(alert)
        let content = try XCTUnwrap(scheduler.pending.first?.content)
        let responder = SpyResponder()

        await WatchAlertPresenter.acknowledge(alert.identifier, with: responder, content: content)

        XCTAssertEqual(responder.acknowledged, ["podExpiring"], "the pump's own acknowledgeAlert, as the phone calls it")
        XCTAssertTrue(scheduler.pending.isEmpty)
    }

    func testAFailedAcknowledgementPutsTheAlertBack() async throws {
        let alert = podAlert()
        WatchAlertPresenter.present(alert)
        let content = try XCTUnwrap(scheduler.pending.first?.content)
        let responder = SpyResponder()
        responder.failure = NSError(domain: "pod", code: 1)

        await WatchAlertPresenter.acknowledge(alert.identifier, with: responder, content: content)

        XCTAssertEqual(scheduler.pending.count, 1, "the pod is still beeping, so the user must be able to try again")
    }

    /// Only the loaned pump, only for its own alerts, only while the loan is live.
    func testTheLoanedPumpAnswersForItsOwnAlertsWhileTheLoanIsLive() async throws {
        let controller = await makeController()
        let pump = try makePump()
        controller.queue.sync { controller.pumpManager = pump }

        let idle = await controller.pumpAlertResponder(for: "Omni")
        XCTAssertNil(idle, "no live loan: the phone owns the pod")

        controller.queue.sync { controller.phase = .active }
        let live = await controller.pumpAlertResponder(for: "Omni")
        XCTAssertTrue(live === pump)
        let other = await controller.pumpAlertResponder(for: "GlucoseAlertManager")
        XCTAssertNil(other, "a glucose alert is not the pump's to acknowledge")
    }

    /// The phone hears the kit's own words for a fault, read through LoopKit, not Omnipod state.
    func testTheFaultSentToThePhoneIsThePumpsOwnText() async throws {
        let controller = await makeController()
        let working = try makePump()
        controller.queue.sync { controller.pumpManager = working }
        XCTAssertNil(controller.queue.sync { controller.pumpFaultDescription }, "no fault, nothing to report")

        // A detailed status carrying fault code 0x8F.
        let status = try DetailedStatus(encodedData: Data([0x02, 0x0d, 0, 0, 0, 0x06, 0, 0, 0x8f, 0, 0, 0x03, 0xff,
                                                           0, 0, 0, 0, 0x03, 0xa2, 0x03, 0x86, 0xa0]))
        let faulted = try makePump(fault: status)
        XCTAssertEqual((faulted as DeviceManager).localizedInoperableDescription, "Critical Pod Fault 143",
                       "the kit's implementation, not LoopKit's nil default")
        controller.queue.sync { controller.pumpManager = faulted }
        XCTAssertEqual(controller.queue.sync { controller.pumpFaultDescription }, "Critical Pod Fault 143")
    }

    private func makeController() async -> PodLoanWatchController {
        let cacheStore = PersistenceController(directoryURL: dir.appendingPathComponent("cache"))
        let doseStore = await DoseStore(healthKitSampleStore: nil, cacheStore: cacheStore,
                                        longestEffectDuration: ExponentialInsulinModelPreset.rapidActingAdult.effectDuration,
                                        provenanceIdentifier: "WristAlertAcknowledgementTests")
        let glucoseStore = await GlucoseStore(healthKitSampleStore: nil, cacheStore: cacheStore,
                                              cacheLength: 4 * 60 * 60, provenanceIdentifier: "WristAlertAcknowledgementTests")
        let carbStore = CarbStore(healthKitSampleStore: nil, cacheStore: cacheStore,
                                  cacheLength: 24 * 60 * 60, provenanceIdentifier: "WristAlertAcknowledgementTests")
        let manager = WatchLoopManager(doseStore: doseStore, glucoseStore: glucoseStore, carbStore: carbStore,
                                       defaults: defaults, stateDirectory: dir)
        return PodLoanWatchController(loopManager: manager, journal: LoanEventJournal(directory: dir),
                                      stateDirectory: dir)
    }

    private func makePump(fault: DetailedStatus? = nil) throws -> OmniPumpManager {
        var podState = PodState(address: 0x1f0b3557, firmwareVersion: "2.7.0", iFirmwareVersion: "2.7.0",
                                lotNo: 1, lotSeq: 1, insulinType: .novolog, podType: dashType)
        podState.fault = fault
        let raw: [String: Any] = ["basalSchedule": ["entries": [["rate": 1.0, "startTime": 0.0]]],
                                  "controllerId": UInt32(0x1234_5678), "podId": UInt32(0x1234_5679),
                                  "podState": podState.rawValue]
        return try XCTUnwrap(OmniPumpManager(rawState: raw))
    }
}
