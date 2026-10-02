//
//  LoanHistoryTests.swift
//  WatchAppTests
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//
//  Stock's alert history on the watch: recorded while it holds the pod, as stock's AlertManager
//  records it, answered from by the lookups a kit may call, and sent home once at a loan's close.
//

import XCTest
import LoopKit
import LoopCore
import LoopAlgorithm
import UserNotifications
@testable import OmnipodKit
@testable import WatchApp

@MainActor
final class LoanHistoryTests: XCTestCase {

    private var dir: URL!
    private var scheduler: RecordingWristAlertScheduler!

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("loan-history-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        scheduler = RecordingWristAlertScheduler()
        WristAlerts.scheduler = scheduler
    }

    override func tearDown() async throws {
        WristAlerts.scheduler = UNUserNotificationCenter.current()
        scheduler = nil
        dir = nil
    }

    private func makeManager() async -> WatchLoopManager {
        let cacheStore = PersistenceController(directoryURL: dir.appendingPathComponent(UUID().uuidString))
        let doseStore = await DoseStore(healthKitSampleStore: nil, cacheStore: cacheStore,
                                        longestEffectDuration: ExponentialInsulinModelPreset.rapidActingAdult.effectDuration,
                                        provenanceIdentifier: "LoanHistoryTests")
        let glucoseStore = await GlucoseStore(healthKitSampleStore: nil, cacheStore: cacheStore,
                                              cacheLength: TimeInterval(24 * 3600), provenanceIdentifier: "LoanHistoryTests")
        let carbStore = CarbStore(healthKitSampleStore: nil, cacheStore: cacheStore,
                                  cacheLength: TimeInterval(24 * 3600), provenanceIdentifier: "LoanHistoryTests")
        let alertDirectory = dir.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: alertDirectory, withIntermediateDirectories: true)
        let defaults = UserDefaults(suiteName: "LoanHistoryTests-\(UUID().uuidString)")!
        return WatchLoopManager(doseStore: doseStore, glucoseStore: glucoseStore, carbStore: carbStore,
                                alertStore: AlertStore(storageDirectoryURL: alertDirectory, expireAfter: TimeInterval(90 * 24 * 3600)),
                                defaults: defaults,
                                stateDirectory: dir.appendingPathComponent(UUID().uuidString, isDirectory: true))
    }

    private func makePump() throws -> OmniPumpManager {
        var podState = PodState(address: 0x1f0b3557, firmwareVersion: "2.7.0", iFirmwareVersion: "2.7.0",
                                lotNo: 1, lotSeq: 1, insulinType: .novolog, podType: dashType)
        podState.setupProgress = .completed
        let raw: [String: Any] = ["basalSchedule": ["entries": [["rate": 0.7, "startTime": 0.0]]],
                                  "controllerId": UInt32(0x1234_5678), "podId": UInt32(0x1234_5679),
                                  "podState": podState.rawValue]
        return try XCTUnwrap(OmniPumpManager(rawState: raw))
    }

    /// A pod alert as the Omnipod kit builds one.
    private func podAlert(_ id: String = "lowReservoir", trigger: LoopKit.Alert.Trigger = .immediate) -> LoopKit.Alert {
        let content = LoopKit.Alert.Content(title: "Low Reservoir", body: "10 U insulin or less remaining in Pod. Change Pod soon.",
                                            acknowledgeActionButtonLabel: "OK")
        return LoopKit.Alert(identifier: .init(managerIdentifier: "Omnipod", alertIdentifier: id),
                             foregroundContent: content, backgroundContent: content, trigger: trigger)
    }

    private func stored(_ manager: WatchLoopManager, _ alert: LoopKit.Alert) async throws -> [StoredAlert] {
        let settled = await manager.settledAlertStore()
        let store = try XCTUnwrap(settled)
        return try await store.lookupAllMatching(identifier: alert.identifier)
    }

    // MARK: - Recorded while the watch holds the pod

    /// Issued, acknowledged on the wrist, retracted: one record carrying all three, as stock's
    /// AlertManager leaves it.
    func testAnAlertIssuedAcknowledgedAndRetractedOnTheWristIsRecorded() async throws {
        let manager = await makeManager()
        manager.pumpManager = try makePump()
        let alert = podAlert()

        manager.issueAlert(alert)
        XCTAssertEqual(scheduler.pending.count, 1, "presented, as before")
        manager.recordAlertAcknowledgement(alert.identifier)
        manager.retractAlert(identifier: alert.identifier)

        let records = try await stored(manager, alert)
        XCTAssertEqual(records.count, 1)
        let record = try XCTUnwrap(records.first)
        XCTAssertNotNil(record.syncIdentifier)
        XCTAssertNotNil(record.acknowledgedDate)
        XCTAssertNotNil(record.retractedDate)
        XCTAssertEqual(record.title, "Low Reservoir")
        XCTAssertLessThanOrEqual(record.issuedDate, try XCTUnwrap(record.acknowledgedDate))
    }

    /// The lookups a kit may call answer from the store, as stock's do.
    func testTheLookupsAnswerFromTheStore() async throws {
        let manager = await makeManager()
        manager.pumpManager = try makePump()
        let low = podAlert("lowReservoir"), expiring = podAlert("podExpiring")
        let earlier = podAlert("suspendEnded"), unknown = podAlert("timeOffsetChangeDetected")

        manager.issueAlert(low)
        manager.issueAlert(expiring)
        manager.recordAlertAcknowledgement(expiring.identifier)
        manager.recordRetractedAlert(earlier, at: Date().addingTimeInterval(-600))

        let issuedLow = try await manager.doesIssuedAlertExist(identifier: low.identifier)
        let issuedEarlier = try await manager.doesIssuedAlertExist(identifier: earlier.identifier)
        let issuedUnknown = try await manager.doesIssuedAlertExist(identifier: unknown.identifier)
        XCTAssertTrue(issuedLow)
        XCTAssertTrue(issuedEarlier, "a retracted alert recorded by the kit exists")
        XCTAssertFalse(issuedUnknown)

        let unretracted = try await manager.lookupAllUnretracted(managerIdentifier: "Omnipod").map(\.alert.identifier)
        XCTAssertEqual(unretracted, [low.identifier, expiring.identifier])
        let unacknowledged = try await manager.lookupAllUnacknowledgedUnretracted(managerIdentifier: "Omnipod")
        XCTAssertEqual(unacknowledged.map(\.alert.identifier), [low.identifier])
        XCTAssertEqual(unacknowledged.first?.alert.backgroundContent, low.backgroundContent)
        let otherManager = try await manager.lookupAllUnretracted(managerIdentifier: "G7")
        XCTAssertTrue(otherManager.isEmpty)

        manager.retractAlert(identifier: low.identifier)
        let afterRetraction = try await manager.lookupAllUnretracted(managerIdentifier: "Omnipod").map(\.alert.identifier)
        XCTAssertEqual(afterRetraction, [expiring.identifier])
    }

    /// Between loans the phone is the controller: nothing is recorded, and the lookups find nothing.
    func testWithoutAPodNothingIsRecorded() async throws {
        let manager = await makeManager()
        let alert = podAlert()

        manager.issueAlert(alert)
        manager.recordAlertAcknowledgement(alert.identifier)
        manager.recordRetractedAlert(podAlert("suspendEnded"), at: Date())
        manager.retractAlert(identifier: alert.identifier)

        XCTAssertEqual(scheduler.pending.count, 0, "presented and withdrawn, as before")
        let settled = await manager.settledAlertStore()
        let store = try XCTUnwrap(settled)
        let (_, all) = try await store.executeAlertQuery(fromQueryAnchor: nil, limit: 100)
        XCTAssertTrue(all.isEmpty, "got \(all.map(\.identifier.value))")
        let exists = try await manager.doesIssuedAlertExist(identifier: alert.identifier)
        XCTAssertFalse(exists)
    }

    // MARK: - Home once at the loan's close

    /// At a loan's close the alerts recorded since the last file go home: a second close sends
    /// nothing, and an acknowledgement after the first goes with the next.
    func testALoansAlertsGoHomeOnceAtItsClose() async throws {
        let manager = await makeManager()
        manager.pumpManager = try makePump()
        let low = podAlert("lowReservoir"), suspend = podAlert("suspendEnded", trigger: .repeating(repeatInterval: 900))
        manager.issueAlert(low)
        manager.issueAlert(suspend)

        let controller = PodLoanWatchController(loopManager: manager, journal: LoanEventJournal(directory: dir),
                                                stateDirectory: dir.appendingPathComponent(UUID().uuidString, isDirectory: true))
        let lock = NSLock()
        var files: [(data: Data, metadata: [String: Any])] = []
        controller.transferLoanHistory = { data, metadata in
            lock.lock(); files.append((data, metadata)); lock.unlock()
            return true
        }
        func closeAndSettle() async {
            controller.queue.sync { controller.sendLoanHistoryHome(epoch: 7) }
            try? await Task.sleep(nanoseconds: 500_000_000)
            controller.queue.sync {}
        }

        await closeAndSettle()
        XCTAssertEqual(files.count, 1, "one file")
        XCTAssertEqual(files.first?.metadata["kind"] as? String, LoanHistory.fileKind)
        let first = try LoanHistory.decode(try XCTUnwrap(files.first).data)
        XCTAssertEqual(first.epoch, 7)
        let sent = try XCTUnwrap(first.alerts)
        XCTAssertEqual(sent.map(\.identifier), [low.identifier, suspend.identifier], "in the order recorded")
        let records = try await stored(manager, low)
        XCTAssertEqual(sent.first?.syncIdentifier, records.first?.syncIdentifier, "under the watch's own identity")
        XCTAssertEqual(sent.first?.issuedDate, records.first?.issuedDate, "with the watch's dates")
        XCTAssertEqual(sent.last?.trigger, .repeating(repeatInterval: 900))
        print("[history-size] \(sent.count) alerts: \(files[0].data.count) bytes (binary plist)")

        await closeAndSettle()
        XCTAssertEqual(files.count, 1, "nothing new: no second file")

        manager.recordAlertAcknowledgement(low.identifier)
        await closeAndSettle()
        XCTAssertEqual(files.count, 2)
        let second = try XCTUnwrap(LoanHistory.decode(try XCTUnwrap(files.dropFirst().first).data).alerts)
        XCTAssertEqual(second.map(\.syncIdentifier), [sent.first?.syncIdentifier], "only the changed record")
        XCTAssertNotNil(second.first?.acknowledgedDate)
    }
}
