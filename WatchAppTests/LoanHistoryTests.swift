//
//  LoanHistoryTests.swift
//  WatchAppTests
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//
//  Stock's alert history and device log on the watch: recorded while it holds the pod, as
//  stock's AlertManager and DeviceDataManager record them, the alerts answered from by the
//  lookups a kit may call, and both sent home once at a loan's close.
//

import XCTest
import LoopKit
import LoopCore
import LoopAlgorithm
import UserNotifications
@testable import OmnipodKit
@testable import G7SensorKit
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
                                deviceLog: PersistentDeviceLog(storageFile: alertDirectory.appendingPathComponent("DeviceLog.sqlite"),
                                                               maxEntryAge: TimeInterval(90 * 24 * 3600)),
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

    // MARK: - Device log

    /// A kit's line, through the delegate as the kit sends it, once the store has it.
    private func logLine(_ manager: WatchLoopManager, from device: DeviceManager, _ type: DeviceLogEntryType,
                         _ message: String, id: String? = "177E6B7D") async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            manager.deviceManager(device, logEventForDeviceIdentifier: id, type: type, message: message) { _ in continuation.resume() }
        }
    }

    private func deviceLogLines(_ manager: WatchLoopManager) async throws -> [StoredDeviceLogEntry] {
        try await XCTUnwrap(manager.deviceLog).fetch(startDate: .distantPast, endDate: .distantFuture)
    }

    /// The pod's lines are stored as stock's DeviceDataManager stores them, under the kit's
    /// plugin identifier; while the watch holds the pod the CGM's are too.
    func testAKitsDeviceLogLineIsStoredWhileTheWatchHoldsThePod() async throws {
        let manager = await makeManager()
        let pump = try makePump()
        let cgm = G7CGMManager()
        manager.pumpManager = pump

        await logLine(manager, from: pump, .send, "177e6b7d34030e01070200")
        await logLine(manager, from: cgm, .receive, "Sensor comms 5200c0d70d00540600020404ff0c00", id: "DXCMqL")

        let lines = try await deviceLogLines(manager)
        XCTAssertEqual(lines.map(\.message), ["177e6b7d34030e01070200", "Sensor comms 5200c0d70d00540600020404ff0c00"])
        XCTAssertEqual(lines.map(\.managerIdentifier), [pump.pluginIdentifier, cgm.pluginIdentifier])
        XCTAssertEqual(lines.map(\.deviceIdentifier), ["177E6B7D", "DXCMqL"])
        XCTAssertEqual(lines.map(\.type), [.send, .receive])
    }

    /// Without a pod the CGM's lines go only to the text log, as before; a pump's line is stored
    /// whenever it comes, since the watch has a pump only during a loan.
    func testWithoutAPodTheCGMsLinesAreNotStored() async throws {
        let manager = await makeManager()
        let cgm = G7CGMManager()

        await logLine(manager, from: cgm, .connection, "Sensor connected", id: "DXCMqL")
        let between = try await deviceLogLines(manager)
        XCTAssertTrue(between.isEmpty, "got \(between.map(\.message))")

        await logLine(manager, from: try makePump(), .connection, "Pod connected 8752D1D3-2009-8769-2091-F5B0CE32418E")
        let duringTakeover = try await deviceLogLines(manager)
        XCTAssertEqual(duringTakeover.map(\.message), ["Pod connected 8752D1D3-2009-8769-2091-F5B0CE32418E"])
    }

    /// At a loan's close the lines written since the last file go home with their own times: a
    /// second close sends nothing, and a later line goes with the next.
    func testALoansDeviceLogGoesHomeOnceAtItsClose() async throws {
        let manager = await makeManager()
        let pump = try makePump()
        manager.pumpManager = pump
        await logLine(manager, from: pump, .send, "177e6b7d34030e01070200")
        await logLine(manager, from: pump, .receive, "177e6b7d380a1d1801b81800002bbfff001d")

        let controller = PodLoanWatchController(loopManager: manager, journal: LoanEventJournal(directory: dir),
                                                stateDirectory: dir.appendingPathComponent(UUID().uuidString, isDirectory: true))
        let lock = NSLock()
        var files: [Data] = []
        controller.transferLoanHistory = { data, _ in
            lock.lock(); files.append(data); lock.unlock()
            return true
        }
        func closeAndSettle() async {
            controller.queue.sync { controller.sendLoanHistoryHome(epoch: 7) }
            try? await Task.sleep(nanoseconds: 500_000_000)
            controller.queue.sync {}
        }

        await closeAndSettle()
        XCTAssertEqual(files.count, 1, "one file")
        let sent = try XCTUnwrap(LoanHistory.decode(try XCTUnwrap(files.first)).deviceLog)
        let stored = try await deviceLogLines(manager)
        XCTAssertEqual(sent, stored.map(LoanDeviceLogEntry.init), "every line, oldest first, with its own time")

        await closeAndSettle()
        XCTAssertEqual(files.count, 1, "nothing new: no second file")

        await logLine(manager, from: pump, .connection, "Pod disconnected 8752D1D3-2009-8769-2091-F5B0CE32418E nil")
        await closeAndSettle()
        XCTAssertEqual(files.count, 2)
        let second = try XCTUnwrap(LoanHistory.decode(try XCTUnwrap(files.dropFirst().first)).deviceLog)
        XCTAssertEqual(second.map(\.message), ["Pod disconnected 8752D1D3-2009-8769-2091-F5B0CE32418E nil"], "only the line since")
    }

    /// What a loan's history weighs as sent: an hour of device log at the rate an archived loan's
    /// text log showed (about 300 pod and G7 lines an hour, most of them short), and alerts.
    func testMeasureTheHistoryFileForAnHourAndAThreeHourLoan() throws {
        let pod = ["177e6b7d34030e01070200", "177e6b7d380a1d1801b81800002bbfff001d",
                   "177e6b7d3c201a0e494e532e0100a901384000180018160e000000f500701afa00f500701afa01fc",
                   "177e6b7d000a1d2801b87800002bbfff01ff", "177e6b7d00030e010703b1", "177e6b7d040a1d2801b87800002bbfff02fb",
                   "Pod connected 8752D1D3-2009-8769-2091-F5B0CE32418E", "Pod disconnected 8752D1D3-2009-8769-2091-F5B0CE32418E nil",
                   "[heartbeat] pid=4821 setBLEHeartbeatRequest(lastCGMReadingDate: 2026-10-02 14:31:41 +0000, expectedInterval: 300.0)",
                   "[heartbeat] pumpManagerBLEHeartbeatDidFire — Loop cycle triggered",
                   "[CONFIG] configure branch SKIPPED · needsConfiguration=false servicesNil=false",
                   "[CONFIG] handshake OK in 1.72s — sendHello 0.12s, enableNotifications 0.36s, establishNewSession 1.24s",
                   "[SCAN] ad seen: pod 0x177e6b7d rssi -82 — MATCHES takeover target 0x177e6b7d", "[BLE] connect RSSI -83",
                   "177e6b7d04030e010782ba", "177e6b7d080a1d2801b87800002bbfff835b",
                   "177e6b7d081f1a0e3c5ed82b0100a901384000180018160e000000f500701afa00f500701afa01fc",
                   "177e6b7d0c0a1d2801b87800002bbfff0f23", "[POD-ALERT] detected [] from advertisement — fetching pod status to surface it"]
        let g7 = ["Sensor connected",
                  "Sensor didRead G7GlucoseMessage(glucose:Optional(194), sequence:1926 glucoseIsDisplayOnly:false state:ok messageTimestamp:577099 age:4, data:4e004bce0800860700010400c200060e0e00)",
                  "Sensor comms 5200c0d70d00540600020404ff0c00", "Sensor disconnected: suspectedEndOfSession=false",
                  "Authenticated with the sensor directly.", "direct-read: timed connect requested 12 s before the reading is due"]
        // 25 lines a cycle, 12 cycles an hour: 19 pod, 6 G7. Pod messages, readings and sensor
        // packets differ every cycle (sequence numbers, CRCs, values), so each gets fresh hex: the
        // property list stores a repeated string once, and a repeated corpus would understate it.
        func fresh(_ message: String) -> String {
            func hex(_ count: Int) -> String { String((0..<count).map { _ in "0123456789abcdef".randomElement()! }) }
            if message.hasPrefix("177e6b7d") { return "177e6b7d" + hex(message.count - 8) }
            if message.hasPrefix("Sensor comms ") { return "Sensor comms " + hex(message.count - 13) }
            if message.hasPrefix("Sensor didRead") {
                return "Sensor didRead G7GlucoseMessage(glucose:Optional(\(Int.random(in: 70...250))), sequence:\(Int.random(in: 1000...9999)) glucoseIsDisplayOnly:false state:ok messageTimestamp:\(Int.random(in: 500000...900000)) age:\(Int.random(in: 2...9)), data:\(hex(36)))"
            }
            if message.hasPrefix("[heartbeat] pid=") { return message.replacingOccurrences(of: "14:31:41", with: String(format: "14:%02d:%02d", Int.random(in: 0...59), Int.random(in: 0...59))) }
            return message
        }
        func hour(startingAt start: Date) -> [LoanDeviceLogEntry] {
            (0..<12).flatMap { cycle -> [LoanDeviceLogEntry] in
                let at = start.addingTimeInterval(Double(cycle) * 300)
                return pod.map(fresh).enumerated().map { i, message in
                    LoanDeviceLogEntry(StoredDeviceLogEntry(type: message.hasPrefix("177e") ? (i % 2 == 0 ? .send : .receive) : .connection,
                                                            managerIdentifier: "Omni", deviceIdentifier: "177E6B7D", message: message,
                                                            timestamp: at.addingTimeInterval(Double(i) * 0.7)))
                } + g7.map(fresh).enumerated().map { i, message in
                    LoanDeviceLogEntry(StoredDeviceLogEntry(type: message.hasPrefix("Sensor didRead") || message.hasPrefix("Sensor comms") ? .receive : .connection,
                                                            managerIdentifier: "G7CGMManager", deviceIdentifier: "DXCMqL", message: message,
                                                            timestamp: at.addingTimeInterval(40 + Double(i) * 0.9)))
                }
            }
        }
        let start = Date()
        let oneHour = hour(startingAt: start)
        let threeHours = oneHour + hour(startingAt: start.addingTimeInterval(3600)) + hour(startingAt: start.addingTimeInterval(7200))
        let content = LoopKit.Alert.Content(title: "Low Reservoir", body: "10 U insulin or less remaining in Pod. Change Pod soon.",
                                            acknowledgeActionButtonLabel: "OK")
        let alert = SyncAlertObject(identifier: .init(managerIdentifier: "Omni", alertIdentifier: "lowReservoir"), trigger: .immediate,
                                    interruptionLevel: .timeSensitive, foregroundContent: content, backgroundContent: content,
                                    sound: nil, metadata: nil, issuedDate: start, acknowledgedDate: start.addingTimeInterval(30),
                                    retractedDate: nil, syncIdentifier: UUID())

        let empty = try LoanHistory(epoch: 7, decisions: []).encoded().count
        let hourBytes = try LoanHistory(epoch: 7, decisions: [], deviceLog: oneHour).encoded().count
        let threeHourBytes = try LoanHistory(epoch: 7, decisions: [], deviceLog: threeHours).encoded().count
        let alertBytes = try LoanHistory(epoch: 7, decisions: [], alerts: [alert]).encoded().count - empty
        let messageBytes = oneHour.map { $0.message.utf8.count }.reduce(0, +)
        print("[history-size] device log, 1 h: \(oneHour.count) lines, \(hourBytes - empty) bytes (messages alone \(messageBytes)); 3 h: \(threeHours.count) lines, \(threeHourBytes - empty) bytes")
        print("[history-size] one alert: \(alertBytes) bytes")
        XCTAssertEqual(oneHour.count, 300)
    }
}
