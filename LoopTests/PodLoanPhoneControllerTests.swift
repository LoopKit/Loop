//
//  PodLoanPhoneControllerTests.swift
//  LoopTests
//
//  The phone controller's loan protocol: epoch races, cursor idempotency, stale offers, grant
//  denial, reclaim ladder, settle, audits and the inferred-loan yield.
//

import XCTest
import HealthKit
import LoopKit
import LoopAlgorithm
import LoopCore
import MockKit
import UserNotifications
@testable import Loop

/// The test pump's hand-off state, shared by every instance.
extension MockPumpManager {
    static var testConnectionReleased = false
    /// The odometer the PHONE reads on its reclaim round-trip. nil = pump reports none.
    static var testOdometer: Double?
    /// PHONE MIRROR: the books-dirty primitive (SQN-resync stamp) the inferred-loan
    /// detector reads. nil = no foreign sessions observed.
    static var testForeignSessionAt: Date?
    /// Counts escalations.
    static var testEscalations = 0
    /// Counts forced reads, so a test can assert the settle forces without flooding the radio.
    static var testForcedReadCount = 0
}

/// Test-only hand-off conformance so the full grant path runs against the test pump.
final class LendableMockPumpManager: MockPumpManager, ExclusiveDeviceControl, PumpDeliveryOdometer {
    func exportConfiguration() -> SharedDeviceConfiguration {
        SharedDeviceConfiguration(managerIdentifier: pluginIdentifier, asOf: Date(), deliveredUnits: Self.testOdometer, state: rawState)
    }
    convenience init?(adopting configuration: SharedDeviceConfiguration, localState: [String: Any]?) {
        self.init()
    }
    var isConfiguredByAnotherController: Bool { false }
    var isControlReleased: Bool { Self.testConnectionReleased }
    func releaseControl() { Self.testConnectionReleased = true }
    func takeControl() { Self.testConnectionReleased = false }
    var deliveredUnits: (units: Double, at: Date)? { Self.testOdometer.map { ($0, Date()) } }
    var deliveryPulseUnits: Double { 0.05 }
    var lastForeignSessionAt: Date? { Self.testForeignSessionAt }
    /// Like the real one, lifts the release.
    func escalateTakeControl() -> String? {
        Self.testEscalations += 1
        Self.testConnectionReleased = false
        return "test escalation"
    }
    func refreshDeliveredUnits(completion: @escaping (Bool) -> Void) {
        Self.testForcedReadCount += 1
        completion(true)
    }
}

final class PodLoanPhoneControllerTests: XCTestCase {

    var sent: [LoanMessage] = []
    var sentExpectations: [XCTestExpectation] = []
    var addedDoses: [[DoseEntry]] = []
    /// Every NewCarbEntry the controller committed, for round-trip assertions.
    var addedCarbs: [NewCarbEntry] = []
    var pauseCalls: [Bool] = []
    var notices: [String] = []
    /// Drives Dependencies.isConnectionReady — false = pod still returning from a reclaim.
    var connectionReady = true
    /// Every HANDBACK-DIAG line the controller emitted (the harness otherwise drops .diag).
    var diags: [String] = []
    /// How many times the phone enacted the post-return temp cancel, and its result.
    var cancelCalls = 0
    var cancelError: Error?
    /// How many times the phone stopped automatic dosing over a reconciliation difference.
    var openLoopCalls = 0
    var pump: MockPumpManager!
    var settings: LoopSettings!
    /// Captures for the dead-watch reclaim audit.
    var urgentNotices: [String] = []
    var urgentNoticeBodies: [String] = []
    /// Every scheduled reminder, for its interruption level.
    var addedNotifications: [UNNotificationRequest] = []
    var bookedGapDoses: [DoseEntry] = []
    /// Every batch of the watch's dosing decisions the controller handed to the store.
    var addedDosingDecisions: [[StoredDosingDecision]] = []
    /// Every batch of the watch's alert records the controller handed to the store.
    var addedAlerts: [[SyncAlertObject]] = []
    /// Every batch of the watch's device log lines the controller handed to the log.
    var addedDeviceLog: [[LoanDeviceLogEntry]] = []
    var deletedGapSyncs: [String] = []
    var gapDeleteSucceeds = true
    /// Virtual clock for the reclaim bars; only tests passing `now:` use it.
    var clock = Date()
    /// Background-hold pairing counters: a begin without a matching end is a battery leak iOS
    /// logs against the app, so the tests assert balance at rest.
    var backgroundTaskBegins = 0
    var backgroundTaskEnds = 0
    /// Parks `addPumpEvents` completions, holding the commit open to observe `.reconciling`.
    var holdPumpEventWrites = false
    var heldPumpEventWrite: ((Error?) -> Void)?
    private let lock = NSLock()
    /// Called for every non-diag send, before it is recorded: lets a test inspect disk at send time.
    var onSend: ((LoanMessage) -> Void)?
    var stateDir: URL!
    /// What `Dependencies.glucoseAlertSettings` hands the grant.
    var glucoseAlertSettings: Data?
    /// What `Dependencies.overrideHistory` hands the grant, and the start it was asked for.
    var phoneOverrideHistory: [TemporaryScheduleOverride] = []
    var overrideHistoryAskedFrom: Date?
    /// What `Dependencies.settingsHistory` hands the grant, and the window it was asked for.
    var phoneSettingsHistory: LoanSettingsHistory?
    var settingsHistoryAskedFor: DateInterval?
    /// The phone's current override, and every override change the controller applied.
    var phoneScheduleOverride: TemporaryScheduleOverride?
    var appliedOverrideChanges: [(override: TemporaryScheduleOverride?, changedAt: Date)] = []

    /// Never reset: a controller's late log lines must not reach the host app's Documents either.
    static let phoneLogDirectory: URL = {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("PhoneLogTests", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    override func tearDown() {
        try? FileManager.default.removeItem(at: stateDir)
        super.tearDown()
    }

    override func setUp() {
        super.setUp()
        // Every test gets a fresh state folder.
        PhoneLog.directoryOverride = Self.phoneLogDirectory
        stateDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: stateDir, withIntermediateDirectories: true)
        MockPumpManager.testForcedReadCount = 0
        MockPumpManager.testForeignSessionAt = nil
        backgroundTaskBegins = 0
        backgroundTaskEnds = 0
        urgentNotices = []
        urgentNoticeBodies = []
        addedNotifications = []
        bookedGapDoses = []
        addedDosingDecisions = []
        addedAlerts = []
        addedDeviceLog = []
        deletedGapSyncs = []
        gapDeleteSucceeds = true
        sent = []
        sentExpectations = []
        glucoseAlertSettings = nil
        phoneOverrideHistory = []
        overrideHistoryAskedFrom = nil
        phoneSettingsHistory = nil
        settingsHistoryAskedFor = nil
        phoneScheduleOverride = nil
        appliedOverrideChanges = []
        addedDoses = []
        pauseCalls = []
        notices = []
        connectionReady = true
        diags = []
        cancelCalls = 0
        cancelError = nil
        openLoopCalls = 0
        clock = Date()
        holdPumpEventWrites = false
        heldPumpEventWrite = nil
        pump = LendableMockPumpManager()
        MockPumpManager.testConnectionReleased = false
        MockPumpManager.testOdometer = nil
        MockPumpManager.testEscalations = 0

        let timeZone = TimeZone(identifier: "GMT")!
        settings = LoopSettings(
            dosingEnabled: true,
            glucoseTargetRangeSchedule: GlucoseRangeSchedule(unit: .milligramsPerDeciliter, dailyItems: [RepeatingScheduleValue(startTime: 0, value: DoubleRange(minValue: 100, maxValue: 110))], timeZone: timeZone),
            insulinSensitivitySchedule: InsulinSensitivitySchedule(unit: .milligramsPerDeciliter, dailyItems: [RepeatingScheduleValue(startTime: 0, value: 50.0)], timeZone: timeZone),
            basalRateSchedule: BasalRateSchedule(dailyItems: [RepeatingScheduleValue(startTime: 0, value: 1.0)], timeZone: timeZone),
            carbRatioSchedule: CarbRatioSchedule(unit: .gram, dailyItems: [RepeatingScheduleValue(startTime: 0, value: 10.0)], timeZone: timeZone),
            maximumBasalRatePerHour: 3.0,
            maximumBolus: 5.0)
    }

    /// Writes the controller's state file as a previous launch left it.
    func saveState(_ change: (inout PodLoanPhoneState) -> Void) {
        var store = PersistedProperty<[String: Any]>(key: PodLoanPhoneController.stateFileKey, directory: stateDir)
        var state = store.wrappedValue.flatMap(PodLoanPhoneState.init(rawValue:)) ?? PodLoanPhoneState()
        change(&state)
        store.wrappedValue = state.rawValue
    }

    /// The reclaim-ladder inputs are fixed at the tap; defaults reproduce the dead branch.
    func makeController(watchReachable: @escaping () -> Bool = { false },
                        bluetoothPoweredOff: @escaping () -> Bool = { false },
                        lastWatchContact: @escaping () -> Date? = { nil },
                        latestGlucose: (() -> Date?)? = nil,
                        now: @escaping () -> Date = { Date() },
                        whenProtectedDataAvailable: @escaping (@escaping () -> Void) -> Void = { $0() }) -> PodLoanPhoneController {
        return PodLoanPhoneController(dependencies: .init(
            pumpManager: { [weak self] in self?.pump },
            settings: { [weak self] in self?.settings ?? LoopSettings() },
            setAutomaticDosingPaused: { [weak self] paused in
                guard let self = self else { return }
                self.lock.lock(); self.pauseCalls.append(paused); self.lock.unlock()
            },
            send: { [weak self] dictionary in
                guard let self = self else { return }
                // Diag lines are kept out of `sent` but their text is captured (the audit's output is one).
                if let message = try? LoanMessage.decode(fromTransport: dictionary), case .diag(let d) = message {
                    self.lock.lock(); self.diags.append(d.text); self.lock.unlock()
                    return
                }
                if let message = try? LoanMessage.decode(fromTransport: dictionary) { self.onSend?(message) }
                self.lock.lock()
                if let message = try? LoanMessage.decode(fromTransport: dictionary) {
                    self.sent.append(message)
                }
                let pending = self.sentExpectations
                self.sentExpectations = []
                self.lock.unlock()
                pending.forEach { $0.fulfill() }
            },
            addPumpEvents: { [weak self] events, _, completion in
                guard let self = self else { completion(nil); return }
                // Capture the doses inside the pump events so existing count assertions hold.
                self.lock.lock()
                self.addedDoses.append(events.compactMap { $0.dose })
                let hold = self.holdPumpEventWrites
                if hold { self.heldPumpEventWrite = completion }
                self.lock.unlock()
                if !hold { completion(nil) }
            },
            addCarb: { [weak self] entry, syncIdentifier, completion in
                // Raw append: the controller's guards must not hide behind a store dedupe.
                self?.lock.lock(); self?.addedCarbs.append(entry); self?.lock.unlock()
                _ = syncIdentifier
                completion(nil)
            },
            scheduleOverride: { [weak self] in
                guard let self = self else { return nil }
                self.lock.lock(); defer { self.lock.unlock() }
                return self.phoneScheduleOverride
            },
            applyScheduleOverride: { [weak self] override, changedAt in
                guard let self = self else { return }
                self.lock.lock(); self.appliedOverrideChanges.append((override, changedAt)); self.phoneScheduleOverride = override; self.lock.unlock()
            },
            doseHistory: { _, completion in completion([]) },
            overrideHistory: { [weak self] start, completion in
                guard let self = self else { return completion([]) }
                self.lock.lock(); self.overrideHistoryAskedFrom = start; let history = self.phoneOverrideHistory; self.lock.unlock()
                completion(history)
            },
            settingsHistory: { [weak self] start, end, completion in
                guard let self = self else { return completion(nil) }
                self.lock.lock(); self.settingsHistoryAskedFor = DateInterval(start: start, end: end); let history = self.phoneSettingsHistory; self.lock.unlock()
                completion(history)
            },
            glucoseAlertSettings: { [weak self] completion in completion(self?.glucoseAlertSettings) },
            issueNotice: { [weak self] title, _ in
                guard let self = self else { return }
                self.lock.lock(); self.notices.append(title); self.lock.unlock()
            },
            isConnectionReady: { [weak self] in self?.connectionReady ?? true },
            cancelTempBasalAfterPodReturn: { [weak self] completion in
                guard let self = self else { return completion(nil) }
                self.lock.lock(); self.cancelCalls += 1; let error = self.cancelError; self.lock.unlock()
                completion(error)
            },
            openLoopForUncertainReconciliation: { [weak self] in
                guard let self = self else { return }
                self.lock.lock(); self.openLoopCalls += 1; self.lock.unlock()
            },
            issueUrgentNotice: { [weak self] title, body in
                guard let self = self else { return }
                self.lock.lock(); self.urgentNotices.append(title); self.urgentNoticeBodies.append(body); self.lock.unlock()
            },
            bookGapDose: { [weak self] entry, completion in
                guard let self = self else { return completion(false) }
                self.lock.lock(); self.bookedGapDoses.append(entry); self.lock.unlock()
                completion(true)
            },
            deleteGapDose: { [weak self] sync, completion in
                guard let self = self else { return completion(false) }
                self.lock.lock(); self.deletedGapSyncs.append(sync); let ok = self.gapDeleteSucceeds; self.lock.unlock()
                completion(ok)
            },
            addDosingDecisions: { [weak self] decisions, completion in
                guard let self = self else { return completion(.success(0)) }
                self.lock.lock(); self.addedDosingDecisions.append(decisions); self.lock.unlock()
                completion(.success(decisions.count))
            },
            addAlerts: { [weak self] alerts, completion in
                guard let self = self else { return completion(.success(0)) }
                self.lock.lock(); self.addedAlerts.append(alerts); self.lock.unlock()
                completion(.success(alerts.count))
            },
            addDeviceLogEntries: { [weak self] entries, completion in
                guard let self = self else { return completion(.success(0)) }
                self.lock.lock(); self.addedDeviceLog.append(entries); self.lock.unlock()
                completion(.success(entries.count))
            },
            whenProtectedDataAvailable: whenProtectedDataAvailable,
            beginReclaimBackgroundTask: { [weak self] in
                guard let self = self else { return }
                self.lock.lock(); self.backgroundTaskBegins += 1; self.lock.unlock()
            },
            endReclaimBackgroundTask: { [weak self] in
                guard let self = self else { return }
                self.lock.lock(); self.backgroundTaskEnds += 1; self.lock.unlock()
            },
            isWatchReachable: watchReachable,
            isBluetoothPoweredOff: bluetoothPoweredOff,
            lastWatchContactAt: lastWatchContact,
            latestGlucoseDate: latestGlucose ?? { now() },   // by default the phone is beside the body: a reading just now
            now: now,
            stateDirectory: stateDir,
            addNotification: { [weak self] request in
                guard let self = self else { return }
                self.lock.lock(); self.addedNotifications.append(request); self.lock.unlock()
            },
            removeNotifications: { _ in }
        ))
    }

    /// Release a hand-back commit parked by `holdPumpEventWrites`.
    func releaseHeldPumpEventWrite() {
        lock.lock(); let completion = heldPumpEventWrite; heldPumpEventWrite = nil; lock.unlock()
        completion?(nil)
    }

    func diagMatching(_ needle: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return diags.first { $0.contains(needle) }
    }

    /// Setup that could not complete. Thrown rather than fatal.
    enum SetupFailure: Error { case noGrant }

    /// Wait until the controller's send fires once more.
    func expectSend() -> XCTestExpectation {
        let e = expectation(description: "message sent")
        lock.lock(); sentExpectations.append(e); lock.unlock()
        return e
    }

    func lastSent() -> LoanMessage? {
        lock.lock(); defer { lock.unlock() }
        return sent.last
    }

    /// The ack fires the send expectation a hair before the controller's queue runs
    /// its post-commit transition; poll instead of racing it.
    func waitForState(_ controller: PodLoanPhoneController, _ state: PodLoanPhoneController.State) {
        let e = expectation(description: "state \(state.rawValue)")
        DispatchQueue.global().async {
            while controller.state != state { usleep(20_000) }
            e.fulfill()
        }
        wait(for: [e], timeout: 5)
    }

    /// Carbs the phone actually committed, for the watch->phone round-trip tests.
    func carbEvent(seq: Int, grams: Double, at date: Date, absorption: TimeInterval,
                   foodType: String? = nil, enteredAt: Date? = nil) -> LoanEvent {
        LoanEvent(id: UUID(), seq: seq, provenance: .confirmed,
                  record: LoanDoseRecord(kind: .carb, startDate: date, amount: grams, absorptionTime: absorption,
                                         note: foodType, userCreatedDate: enteredAt),
                  loggedAt: date)
    }

    private func makeEvent(seq: Int, units: Double, at date: Date) -> LoanEvent {
        LoanEvent(id: UUID(), seq: seq, provenance: .confirmed,
                  record: LoanDoseRecord(kind: .bolus, startDate: date, amount: units), loggedAt: date)
    }

    func tempEvent(seq: Int, rate: Double, start: Date, durationMinutes: Double) -> LoanEvent {
        LoanEvent(id: UUID(), seq: seq, provenance: .confirmed,
                  record: LoanDoseRecord(kind: .tempBasal, startDate: start,
                                         endDate: start.addingTimeInterval(durationMinutes * 60), unitsPerHour: rate),
                  loggedAt: start)
    }

    /// Drives a controller to LOANED at epoch 1. A settle-window denial is retried as a user
    /// would; any other non-grant reply is fatal.
    @discardableResult
    func establishLoan(_ controller: PodLoanPhoneController) -> LoanGrant {
        var grant: LoanGrant?
        for _ in 0..<25 {
            let grantSent = expectSend()
            controller.handleIncoming(userInfo: try! LoanMessage.request(LoanRequest(watchBuild: "t")).transportDictionary())
            wait(for: [grantSent], timeout: 5)
            if case .grant(let g)? = lastSent() { grant = g; break }
            if case .denied? = lastSent() { usleep(100_000); continue }
            break
        }
        guard let grant else {
            XCTFail("expected a grant, got \(String(describing: lastSent()))")
            fatalError()
        }
        let status = LoanPodStatus(timestamp: Date(), deliveredUnits: 10, reservoirLevel: nil, isSuspended: false, faultCode: nil)
        controller.handleIncoming(userInfo: try! LoanMessage.takeoverComplete(TakeoverComplete(epoch: grant.epoch, firstPodStatus: status)).transportDictionary())
        // takeoverComplete sends nothing; poll state.
        let loaned = expectation(description: "loaned")
        DispatchQueue.global().async {
            while controller.state != .loaned { usleep(20_000) }
            loaned.fulfill()
        }
        wait(for: [loaned], timeout: 5)
        return grant
    }

    // MARK: - Grant path

    func testGrantFlowReachesLoanedAndPausesDosing() throws {
        let controller = makeController()
        let grant = establishLoan(controller)

        XCTAssertEqual(grant.epoch, 1)
        XCTAssertTrue(MockPumpManager.testConnectionReleased, "grant must release the pod connection")
        XCTAssertEqual(pauseCalls, [true], "dosing paused exactly once at grant")
        XCTAssertEqual(grant.sharedPumpConfiguration?.managerIdentifier, pump.pluginIdentifier,
                       "the grant carries the pump's exported configuration")
        XCTAssertFalse(grant.therapySettingsRaw.isEmpty)
        XCTAssertEqual(grant.settingsTimeZoneID, "GMT")
    }

    func testGrantDeniedOnIncompleteSettings() throws {
        settings.maximumBolus = nil  // deny, never default
        let controller = makeController()
        controller.handleIncoming(userInfo: try LoanMessage.request(LoanRequest(watchBuild: "t")).transportDictionary())

        // The refusal is observed on the wire; the watch shows the reason.
        let refused = expectation(description: "refused")
        DispatchQueue.global().async {
            while true {
                // lastSent() takes `lock` itself — do NOT wrap it, the lock is not recursive.
                if case .denied? = self.lastSent() { refused.fulfill(); return }
                usleep(20_000)
            }
        }
        wait(for: [refused], timeout: 5)
        XCTAssertEqual(controller.state, .owner)
        XCTAssertTrue(pauseCalls.isEmpty, "denied grant must not touch dosing")
        XCTAssertFalse(notices.contains("Sport Mode Not Started"), "the phone must not duplicate the watch's refusal reason")
        if case .grant? = lastSent() { XCTFail("no grant may be sent on refusal") }
    }

    /// A stranded non-owner state recovers on a fresh request (denying once while the settle
    /// verifies) and never refuses forever.
    func testStrandedStateRecoversOnNewRequest() throws {
        // Recent contact keeps the live branch, the only way to strand in reclaimPending now.
        let controller = makeController(lastWatchContact: { Date() })
        establishLoan(controller)
        controller.reclaimNow()
        waitForState(controller, .reclaimPending)

        // First request: force-recovers to owner, denies (unverified), and kicks the
        // verification round-trip.
        let deniedSent = expectSend()
        controller.handleIncoming(userInfo: try LoanMessage.request(LoanRequest(watchBuild: "t")).transportDictionary())
        wait(for: [deniedSent], timeout: 5)
        waitForState(controller, .owner)
        if case .denied? = lastSent() {} else if case .grant? = lastSent() {
            XCTFail("must not grant an unverified pod straight out of a stranded state")
        }

        // The eager kick runs MockPumpManager.ensureCurrentPumpData (fresh lastSync) —
        // wait for the settle window to clear, then a fresh request grants.
        waitUntil(timeout: 8, "reclaim verification") { !controller.isReclaimSettling }
        let grantSent = expectSend()
        controller.handleIncoming(userInfo: try LoanMessage.request(LoanRequest(watchBuild: "t")).transportDictionary())
        wait(for: [grantSent], timeout: 5)
        if case .grant? = lastSent() {} else {
            XCTFail("expected a grant after recovery + verification, got \(String(describing: lastSent()))")
        }
        waitForState(controller, .grantOffered)
    }

    /// A transport redelivery of the same request is ignored: exactly one grant, pod stays released.
    func testDuplicateRequestRedeliveryIsIgnored() throws {
        let controller = makeController()
        let request = LoanRequest(watchBuild: "t")          // ONE id, sent twice by the transport

        let granted = expectSend()
        controller.handleIncoming(userInfo: try LoanMessage.request(request).transportDictionary())
        wait(for: [granted], timeout: 5)
        guard case .grant? = lastSent() else { return XCTFail("expected a grant on the first copy") }
        waitForState(controller, .grantOffered)
        XCTAssertTrue(MockPumpManager.testConnectionReleased, "the grant released the pod")

        let epochAfterFirst = grantedEpochs().last
        XCTAssertEqual(grantedEpochs().count, 1, "one request, one grant")

        // The grant count is what bites: a second copy would re-grant under a new epoch.
        controller.handleIncoming(userInfo: try LoanMessage.request(request).transportDictionary())
        settle()
        XCTAssertEqual(grantedEpochs().count, 1,
                       "a redelivered request must not mint a second grant")
        XCTAssertEqual(grantedEpochs().last, epochAfterFirst,
                       "the epoch the watch is acting on must not be superseded")
        XCTAssertFalse(sentKinds().contains("denied"),
                       "a redelivered request must not produce a denial")
        XCTAssertEqual(controller.state, .grantOffered, "state must be untouched by a redelivery")
        XCTAssertTrue(MockPumpManager.testConnectionReleased,
                      "the redelivery must not re-arm/reclaim the released pod")
    }

    /// Epochs of every grant sent so far — the count is the invariant a redelivered request
    /// must not change.
    private func grantedEpochs() -> [Int] {
        lock.lock(); defer { lock.unlock() }
        return sent.compactMap { if case .grant(let g) = $0 { return g.epoch } else { return nil } }
    }

    private func sentKinds() -> [String] {
        lock.lock(); defer { lock.unlock() }
        return sent.map { message in
            switch message {
            case .grant: return "grant"
            case .denied: return "denied"
            case .nack: return "nack"
            default: return "other"
            }
        }
    }

    /// Let the controller's serial queue drain when the expectation is that NOTHING is sent.
    func settle(_ seconds: TimeInterval = 0.6) {
        let e = expectation(description: "queue settled")
        DispatchQueue.global().asyncAfter(deadline: .now() + seconds) { e.fulfill() }
        wait(for: [e], timeout: seconds + 2)
    }

    /// The dedupe keys on identity, not on "a request arrived recently" — a genuine retry
    /// carries a fresh ID and must still be honoured.
    func testFreshRequestAfterDuplicateStillHandled() throws {
        let controller = makeController()
        let first = LoanRequest(watchBuild: "t")
        let granted = expectSend()
        controller.handleIncoming(userInfo: try LoanMessage.request(first).transportDictionary())
        wait(for: [granted], timeout: 5)
        controller.handleIncoming(userInfo: try LoanMessage.request(first).transportDictionary())

        // A NEW request (fresh id) while .grantOffered takes the recovery path as before.
        let second = LoanRequest(watchBuild: "t")
        XCTAssertNotEqual(first.requestID, second.requestID, "each request mints its own id")
        let responded = expectSend()
        controller.handleIncoming(userInfo: try LoanMessage.request(second).transportDictionary())
        wait(for: [responded], timeout: 5)
        // Grant or deny is state-dependent; the invariant is that it was NOT silently dropped.
        switch lastSent() {
        case .grant?, .denied?: break
        default: XCTFail("a fresh request must be handled, got \(String(describing: lastSent()))")
        }
    }

    // MARK: - Watch-entered carbs follow the pod home

    /// During a loan the watch raises the glucose alerts, until the phone notices it silent beside
    /// the body; then the phone's own alerts come back on.
    func testTheWatchOwnsAlertsDuringALoanUntilThePhoneNoticesItSilent() {
        let controller = makeController()
        XCTAssertFalse(controller.watchOwnsAlerts, "no loan: the phone's alerts")

        _ = establishLoan(controller)
        XCTAssertTrue(controller.watchOwnsAlerts, "a loan with the watch heard from: the wrist's")

        controller.holdLapseNoticedAt = Date()
        XCTAssertFalse(controller.watchOwnsAlerts, "the watch silent beside the body: the phone's again")

        controller.holdLapseNoticedAt = nil
        XCTAssertTrue(controller.watchOwnsAlerts, "the watch reporting again: back to the wrist")
    }

    /// A wrist carb lands in the phone's CarbStore intact at hand-back.
    func testWatchCarbRoundTripsToThePhoneOnHandback() throws {
        let controller = makeController()
        let grant = establishLoan(controller)
        let mealAt = Date().addingTimeInterval(-.minutes(20))
        let enteredAt = mealAt.addingTimeInterval(.minutes(5))

        let acked = expectSend()
        let offer = HandbackOffer(epoch: grant.epoch, handedBackAt: Date(), finalStatus: nil, odometer: nil,
                                  events: [carbEvent(seq: 1, grams: 42, at: mealAt, absorption: .hours(3),
                                                     foodType: "🌮", enteredAt: enteredAt)],
                                  tombstones: [], recovered: false)
        controller.handleIncoming(userInfo: try LoanMessage.handbackOffer(offer).transportDictionary())
        wait(for: [acked], timeout: 5)
        waitForState(controller, .owner)

        XCTAssertEqual(addedCarbs.count, 1, "the wrist carb must reach the phone's CarbStore")
        guard let carb = addedCarbs.first else { return }
        XCTAssertEqual(carb.quantity.doubleValue(for: .gram), 42, accuracy: 0.001, "grams must survive the fold")
        XCTAssertEqual(carb.startDate.timeIntervalSince1970, mealAt.timeIntervalSince1970, accuracy: 1,
                       "meal time must survive — absorption is computed from it")
        XCTAssertEqual(carb.absorptionTime ?? -1, .hours(3), accuracy: 1,
                       "absorption interval must survive; without it the phone re-derives a default curve")
        XCTAssertEqual(carb.date.timeIntervalSince1970, enteredAt.timeIntervalSince1970, accuracy: 1,
                       "entered when the wrist entered it, not at the hand-back: stock filters on it")
        XCTAssertEqual(carb.foodType, "🌮")
    }

    /// CarbStore cannot dedupe carbs, so a redelivered offer commits once via the committed-ID gate.
    func testRedeliveredCarbCommitsOnlyOnce() throws {
        let controller = makeController()
        let grant = establishLoan(controller)
        let mealAt = Date().addingTimeInterval(-.minutes(10))
        let event = carbEvent(seq: 1, grams: 30, at: mealAt, absorption: .hours(2))

        let first = expectSend()
        let offer = HandbackOffer(epoch: grant.epoch, handedBackAt: Date(), finalStatus: nil, odometer: nil,
                                  events: [event], tombstones: [], recovered: false)
        controller.handleIncoming(userInfo: try LoanMessage.handbackOffer(offer).transportDictionary())
        wait(for: [first], timeout: 5)
        XCTAssertEqual(addedCarbs.count, 1, "first delivery commits the carb")

        // Same offer, same event id — the watch resends until acked, so this is routine.
        let second = expectSend()
        controller.handleIncoming(userInfo: try LoanMessage.handbackOffer(offer).transportDictionary())
        wait(for: [second], timeout: 5)
        XCTAssertEqual(addedCarbs.count, 1,
                       "a redelivered carb must NOT be committed twice — COB would inflate on every resend")
    }

    /// Carbs and insulin arrive through different stores; a drain carrying both must not let one
    /// interfere with the other.
    func testMixedCarbAndBolusDrainLandsInBothStores() throws {
        let controller = makeController()
        let grant = establishLoan(controller)
        let at = Date().addingTimeInterval(-.minutes(5))

        let acked = expectSend()
        let offer = HandbackOffer(epoch: grant.epoch, handedBackAt: Date(), finalStatus: nil, odometer: nil,
                                  events: [makeEvent(seq: 1, units: 2.5, at: at),
                                           carbEvent(seq: 2, grams: 15, at: at, absorption: .hours(2))],
                                  tombstones: [], recovered: false)
        controller.handleIncoming(userInfo: try LoanMessage.handbackOffer(offer).transportDictionary())
        wait(for: [acked], timeout: 5)
        waitForState(controller, .owner)

        XCTAssertEqual(addedCarbs.count, 1, "the carb landed")
        XCTAssertEqual(addedDoses.flatMap { $0 }.filter { $0.type == .bolus }.count, 1, "the bolus landed")
    }

    /// A wrist carb committed by an interim drain, then deleted on the wrist: the delete carries
    /// the event ID the phone stored it under, so the phone's match removes it.
    func testAWristDeleteAfterAnInterimCommitRemovesThePhonesCarb() throws {
        let controller = makeController()
        let grant = establishLoan(controller)
        var phoneCarbs: [StoredCarbEntry] = []
        controller.deps.addCarb = { entry, sync, done in
            self.lock.lock(); phoneCarbs.append(StoredCarbEntry(startDate: entry.startDate, quantity: entry.quantity, syncIdentifier: sync)); self.lock.unlock()
            done(nil)
        }
        controller.deps.deleteCarb = { gone, done in
            self.lock.lock(); let before = phoneCarbs.count; phoneCarbs.removeAll(where: gone.matches); let hit = phoneCarbs.count < before; self.lock.unlock()
            done(hit ? nil : NSError(domain: "test", code: 404))
        }
        let now = Date()
        let carb = carbEvent(seq: 1, grams: 30, at: now.addingTimeInterval(-.minutes(10)), absorption: .hours(3))

        let committed = expectSend()
        controller.handleIncoming(userInfo: try LoanMessage.handbackOffer(HandbackOffer(
            epoch: grant.epoch, handedBackAt: now, finalStatus: nil, odometer: nil,
            events: [carb], tombstones: [], recovered: false, released: false)).transportDictionary())
        wait(for: [committed], timeout: 5)
        lock.lock(); XCTAssertEqual(phoneCarbs.map(\.syncIdentifier), [carb.id.uuidString]); lock.unlock()

        let delete = LoanEvent(id: UUID(), seq: 2, provenance: .confirmed,
                               record: LoanDoseRecord(kind: .carbDeleted, startDate: carb.record.startDate, amount: 30,
                                                      syncIdentifier: carb.id.uuidString),
                               loggedAt: now)
        let deleted = expectSend()
        controller.handleIncoming(userInfo: try LoanMessage.handbackOffer(HandbackOffer(
            epoch: grant.epoch, handedBackAt: now.addingTimeInterval(60), finalStatus: nil, odometer: nil,
            events: [delete], tombstones: [], recovered: false, released: false)).transportDictionary())
        wait(for: [deleted], timeout: 5)

        lock.lock(); XCTAssertTrue(phoneCarbs.isEmpty, "the phone's copy is gone"); lock.unlock()
        XCTAssertNotNil(diagMatching("carb DELETE applied on phone"))
        XCTAssertNil(diagMatching("carb DELETE MISSED"))
    }

    /// A force reclaim records committed IDs, so a redelivered offer does not re-add the carb.
    func testForceReclaimThenRedeliveryCommitsCarbOnce() throws {
        let controller = makeController()
        let grant = establishLoan(controller)
        let mealAt = Date().addingTimeInterval(-.minutes(15))
        let event = carbEvent(seq: 1, grams: 25, at: mealAt, absorption: .hours(3))

        // The watch streams the carb, then goes unreachable before any hand-back completes.
        controller.handleIncoming(userInfo: try LoanMessage.doseRecordBatch(
            DoseRecordBatch(epoch: grant.epoch, events: [event], tombstones: [])).transportDictionary())
        settle()

        // The phone gives up and force-reclaims — this commits the staged carb.
        controller.forceReclaimToOwner(reason: "test: watch unreachable")
        waitForState(controller, .owner)
        let afterReclaim = addedCarbs.count
        XCTAssertEqual(afterReclaim, 1, "force-reclaim commits the staged carb once")

        // The watch reconnects and redelivers, as its resend loop does — no ack was ever sent.
        controller.handleIncoming(userInfo: try LoanMessage.handbackOffer(
            HandbackOffer(epoch: grant.epoch, handedBackAt: Date(), finalStatus: nil, odometer: nil,
                          events: [event], tombstones: [], recovered: true)).transportDictionary())
        settle()

        XCTAssertEqual(addedCarbs.count, 1,
                       "the redelivered carb must NOT be committed again after a force-reclaim — " +
                       "duplicates here mirror into every later grant and inflate COB")
    }

    /// A force parked behind the final commit is dropped when that commit closes the loan.
    func testForceDeferredBehindTheFinalCommitIsDroppedByTheClose() throws {
        let controller = makeController()
        let grant = establishLoan(controller)

        // Park the commit so the force has something to defer behind.
        holdPumpEventWrites = true
        let event = makeEvent(seq: 1, units: 0.6, at: clock.addingTimeInterval(-.minutes(3)))
        controller.handleIncoming(userInfo: try LoanMessage.handbackOffer(
            HandbackOffer(epoch: grant.epoch, handedBackAt: clock, finalStatus: nil, odometer: nil,
                          events: [event], tombstones: [], recovered: false)).transportDictionary())
        waitUntil(timeout: 5, "commit parked") {
            self.lock.lock(); defer { self.lock.unlock() }; return self.heldPumpEventWrite != nil
        }

        // The ladder spending its last rung, or a new Start — either lands here mid-write.
        controller.forceReclaimToOwner(reason: "test: force lands mid-commit")
        XCTAssertNotNil(controller.pendingForceReclaimReason,
                        "a force must park behind a write in flight")

        let ackSent = expectSend()
        holdPumpEventWrites = false
        releaseHeldPumpEventWrite()
        wait(for: [ackSent], timeout: 5)
        waitForState(controller, .owner)
        settle()

        XCTAssertNil(controller.pendingForceReclaimReason,
                     "the hand-back satisfies the force: records committed, radio back, judged by the close")
        XCTAssertNil(diagMatching("force-reclaim audit armed"),
                     "no second audit — its expectation is bare schedule fill against an emptied staging area")
        XCTAssertNil(diagMatching("force-reclaim audit IMPOSSIBLE"))
        XCTAssertEqual(openLoopCalls, 0, "a hand-back that went perfectly must not open the loop")
    }

    /// A stale offer commits no carbs.
    func testStaleOfferDoesNotCommitCarbs() throws {
        let controller = makeController()
        let grant = establishLoan(controller)
        let mealAt = Date().addingTimeInterval(-.minutes(15))

        // Close the loan cleanly so the epoch advances; a later offer on the OLD epoch is stale.
        let acked = expectSend()
        controller.handleIncoming(userInfo: try LoanMessage.handbackOffer(
            HandbackOffer(epoch: grant.epoch, handedBackAt: Date(), finalStatus: nil, odometer: nil,
                          events: [], tombstones: [], recovered: false)).transportDictionary())
        wait(for: [acked], timeout: 5)
        waitForState(controller, .owner)
        let baseline = addedCarbs.count

        // A stale offer arrives carrying a carb.
        controller.handleIncoming(userInfo: try LoanMessage.handbackOffer(
            HandbackOffer(epoch: grant.epoch - 1, handedBackAt: Date(), finalStatus: nil, odometer: nil,
                          events: [carbEvent(seq: 9, grams: 40, at: mealAt, absorption: .hours(3))],
                          tombstones: [], recovered: false)).transportDictionary())
        settle()

        XCTAssertEqual(addedCarbs.count, baseline,
                       "a stale offer must not commit carbs — it records no IDs, so every resend would add another")
    }

    /// The override: forceReclaimToOwner returns to owner and restores dosing.
    func testForceReclaimReturnsToOwner() throws {
        let controller = makeController()
        establishLoan(controller)
        // No contact on record and unreachable = the dead branch, which forces on its own —
        // the tap IS the force now, no separate call needed.
        controller.reclaimNow()
        waitForState(controller, .owner)
        XCTAssertFalse(MockPumpManager.testConnectionReleased, "pod reclaimed on force")
        // Dosing waits for the audit's verdict; unverified opens the loop.
        waitUntil(timeout: 5, "audit verdict") { self.pauseCalls.last == false }
        XCTAssertEqual(openLoopCalls, 1, "unverifiable session opens the loop rather than resuming closed")
        XCTAssertTrue(urgentNotices.contains { $0.contains("Unverified") })
    }

    // MARK: - Dosing decisions from the watch

    /// The decision ids the watch's doses carry reach the phone's dose entries, through the
    /// hand-back's write.
    func testWatchDoseDecisionIdsReachThePhonesDoseEntries() throws {
        let controller = makeController()
        let grant = establishLoan(controller)
        let at = Date().addingTimeInterval(-.minutes(10))
        let bolusDecision = UUID(), tempDecision = UUID()
        let bolus = LoanEvent(id: UUID(), seq: 1, provenance: .confirmed,
                              record: LoanDoseRecord(kind: .bolus, startDate: at, amount: 1.5, decisionId: bolusDecision),
                              loggedAt: at)
        let temp = LoanEvent(id: UUID(), seq: 2, provenance: .confirmed,
                             record: LoanDoseRecord(kind: .tempBasal, startDate: at, endDate: at.addingTimeInterval(.minutes(5)),
                                                    unitsPerHour: 2.0, decisionId: tempDecision),
                             loggedAt: at)

        let acked = expectSend()
        let offer = HandbackOffer(epoch: grant.epoch, handedBackAt: Date(), finalStatus: nil, odometer: nil,
                                  events: [bolus, temp], tombstones: [], recovered: false)
        controller.handleIncoming(userInfo: try LoanMessage.handbackOffer(offer).transportDictionary())
        wait(for: [acked], timeout: 5)
        waitForState(controller, .owner)

        let doses = addedDoses.flatMap { $0 }
        XCTAssertEqual(doses.first { $0.type == .bolus }?.decisionId, bolusDecision)
        XCTAssertEqual(doses.first { $0.type == .tempBasal }?.decisionId, tempDecision)
    }

    /// The watch's decisions for a loan this phone granted go to the store; a loan it never
    /// granted (a later epoch) is ignored.
    func testWatchDosingDecisionsAreAddedOnlyForALoanThisPhoneGranted() throws {
        let controller = makeController()
        let grant = establishLoan(controller)
        let decisions = [StoredDosingDecision(reason: "loop"), StoredDosingDecision(reason: "updateRemoteRecommendation")]

        controller.handleWatchLoanHistory(LoanHistory(epoch: grant.epoch + 1, decisions: decisions))
        controller.handleWatchLoanHistory(LoanHistory(epoch: grant.epoch, decisions: decisions))
        waitUntil(timeout: 5, "the granted loan's decisions handed over") { self.lock.lock(); defer { self.lock.unlock() }; return !self.addedDosingDecisions.isEmpty }
        settle()

        XCTAssertEqual(addedDosingDecisions.count, 1, "only the granted loan's")
        XCTAssertEqual(addedDosingDecisions.first?.map(\.id), decisions.map(\.id))
    }

    /// The watch's alert records for a loan this phone granted go to the alert store, with the
    /// decisions; a loan it never granted is ignored.
    func testWatchAlertsAreAddedOnlyForALoanThisPhoneGranted() throws {
        let controller = makeController()
        let grant = establishLoan(controller)
        let content = Alert.Content(title: "Low Reservoir", body: "Change Pod soon.", acknowledgeActionButtonLabel: "OK")
        let alerts = [SyncAlertObject(identifier: Alert.Identifier(managerIdentifier: "Omnipod", alertIdentifier: "lowReservoir"),
                                      trigger: .immediate, interruptionLevel: .timeSensitive, foregroundContent: content,
                                      backgroundContent: content, sound: nil, metadata: nil, issuedDate: Date().addingTimeInterval(-600),
                                      acknowledgedDate: nil, retractedDate: nil, syncIdentifier: UUID())]

        controller.handleWatchLoanHistory(LoanHistory(epoch: grant.epoch + 1, decisions: [], alerts: alerts))
        controller.handleWatchLoanHistory(LoanHistory(epoch: grant.epoch, decisions: [], alerts: alerts))
        waitUntil(timeout: 5, "the granted loan's alerts handed over") { self.lock.lock(); defer { self.lock.unlock() }; return !self.addedAlerts.isEmpty }
        settle()

        XCTAssertEqual(addedAlerts.count, 1, "only the granted loan's")
        XCTAssertEqual(addedAlerts.first?.map(\.syncIdentifier), alerts.map(\.syncIdentifier))
    }

    /// The watch's device log lines for a loan this phone granted go to the device log; a loan
    /// it never granted is ignored.
    func testWatchDeviceLogIsAddedOnlyForALoanThisPhoneGranted() throws {
        let controller = makeController()
        let grant = establishLoan(controller)
        let lines = [LoanDeviceLogEntry(StoredDeviceLogEntry(type: .send, managerIdentifier: "Omni", deviceIdentifier: "177E6B7D",
                                                             message: "177e6b7d34030e01070200", timestamp: Date().addingTimeInterval(-600)))]

        controller.handleWatchLoanHistory(LoanHistory(epoch: grant.epoch + 1, decisions: [], deviceLog: lines))
        controller.handleWatchLoanHistory(LoanHistory(epoch: grant.epoch, decisions: [], deviceLog: lines))
        waitUntil(timeout: 5, "the granted loan's lines handed over") { self.lock.lock(); defer { self.lock.unlock() }; return !self.addedDeviceLog.isEmpty }
        settle()

        XCTAssertEqual(addedDeviceLog, [lines], "only the granted loan's")
    }

    /// Yielding to an inferred loan closes the settle window, whose +12 s escalation would
    /// otherwise restore this phone's authority to dose.
    func testYieldingToAnInferredLoanClosesTheSettleWindow() throws {
        let controller = makeController()
        establishLoan(controller)
        connectionReady = false                       // the pod never answers: the window stays open
        controller.reclaimNow()
        waitForState(controller, .owner)
        XCTAssertTrue(controller.isReclaimSettling, "the settle window is open to begin with")

        // The phone concludes another controller is running the pod and stands down.
        controller.engageInferredLoanYield(evidence: "test: evidence of a live foreign loan")
        waitUntil(timeout: 5, "settle window closed") { !controller.isReclaimSettling }
        XCTAssertNotNil(diagMatching("settle window CLOSED early"))
        // The hold the settle was carrying is released with it. Counts are not symmetric here —
        // production's `begin` ends any previous hold first, so only one is ever outstanding.
        lock.lock(); let ends = backgroundTaskEnds; lock.unlock()
        XCTAssertGreaterThanOrEqual(ends, 1, "closing the window releases the background hold it carried")

        // Past the escalation mark, with room for the 2 s chase ticks either side of it.
        Thread.sleep(forTimeInterval: PodLoanPhoneController.reclaimEscalateAfter + 2)

        XCTAssertEqual(MockPumpManager.testEscalations, 0,
                       "a phone that has stood down must not escalate for the pod")
        XCTAssertTrue(MockPumpManager.testConnectionReleased,
                      "and the dosing gate must stay released — escalating clears it, which is dual control")
        XCTAssertNil(diagMatching("escalating"))
    }

    /// A re-Start while the pod is still returning is denied until the pod is back.
    func testGrantDeferredWhilePodStillReturningFromReclaim() throws {
        let controller = makeController()
        establishLoan(controller)
        connectionReady = false                       // pod's BLE not truly back yet
        // Dead branch: the tap forces on its own and opens the settle window.
        controller.reclaimNow()
        waitForState(controller, .owner)              // settle window now open

        let denied = expectSend()
        controller.handleIncoming(userInfo: try LoanMessage.request(LoanRequest(watchBuild: "t")).transportDictionary())
        wait(for: [denied], timeout: 5)
        if case .denied? = lastSent() {} else {
            XCTFail("expected .denied while the pod is returning, got \(String(describing: lastSent()))")
        }
        if case .grant? = lastSent() { XCTFail("must not grant a not-yet-returned pod") }
        XCTAssertFalse(MockPumpManager.testConnectionReleased, "a denied re-Start must not release the pod")

        // Readiness is a completed pod round-trip, not the link coming up.
        connectionReady = true
        waitUntil(timeout: 8, "reclaim verification") { !controller.isReclaimSettling }
        let granted = expectSend()
        controller.handleIncoming(userInfo: try LoanMessage.request(LoanRequest(watchBuild: "t")).transportDictionary())
        wait(for: [granted], timeout: 5)
        if case .grant? = lastSent() {} else {
            XCTFail("expected a grant once the round-trip verified, got \(String(describing: lastSent()))")
        }
    }

    /// Spin-wait for conditions settled on background queues.
    private func waitUntil(timeout: TimeInterval, _ label: String, _ condition: @escaping () -> Bool) {
        let exp = expectation(description: label)
        DispatchQueue.global().async {
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline {
                if condition() { exp.fulfill(); return }
                usleep(100_000)
            }
        }
        wait(for: [exp], timeout: timeout + 1)
    }

    // MARK: - Hand-back ordering + idempotency

    func testHandbackCommitsThenAcksThenRestoresOwner() throws {
        let controller = makeController()
        let grant = establishLoan(controller)

        let event = makeEvent(seq: 1, units: 1.0, at: Date())
        let ackSent = expectSend()
        let offer = HandbackOffer(epoch: grant.epoch, handedBackAt: Date(), finalStatus: nil,
                                  odometer: nil, events: [event], tombstones: [], recovered: false)
        controller.handleIncoming(userInfo: try LoanMessage.handbackOffer(offer).transportDictionary())
        wait(for: [ackSent], timeout: 5)

        guard case .handbackAck(let ack)? = lastSent() else { return XCTFail("expected ack") }
        XCTAssertEqual(ack.committedCursor, 1)
        XCTAssertFalse(ack.stale)
        XCTAssertEqual(addedDoses.count, 1)
        XCTAssertEqual(addedDoses[0].count, 1, "the bolus event enters the store before the ack")
        waitForState(controller, .owner)
        waitUntil(timeout: 5, "dosing resumed") { self.lock.lock(); defer { self.lock.unlock() }; return self.pauseCalls.last == false }
        XCTAssertEqual(pauseCalls, [true, false], "dosing restored only after commit")
        XCTAssertFalse(MockPumpManager.testConnectionReleased, "pod reclaimed at loan close")
    }

    /// The committed IDs are on disk before the ack leaves: a relaunch after an ack can never
    /// re-commit, and carbs have no identity to dedup a second meal by.
    func testTheAckIsNeverSentBeforeTheCommitIsSaved() throws {
        let controller = makeController()
        let grant = establishLoan(controller)
        let event = makeEvent(seq: 1, units: 1.0, at: Date())
        var savedAtAck: PodLoanPhoneState?
        let dir = stateDir!
        onSend = { message in
            guard case .handbackAck = message else { return }
            let file = PersistedProperty<[String: Any]>(key: PodLoanPhoneController.stateFileKey, directory: dir)
            savedAtAck = file.wrappedValue.flatMap(PodLoanPhoneState.init(rawValue:))
        }
        let ackSent = expectSend()
        controller.handleIncoming(userInfo: try LoanMessage.handbackOffer(HandbackOffer(
            epoch: grant.epoch, handedBackAt: Date(), finalStatus: nil, odometer: nil,
            events: [event], tombstones: [], recovered: false)).transportDictionary())
        wait(for: [ackSent], timeout: 5)
        XCTAssertEqual(savedAtAck?.committedIDs, [event.id], "the save holding the IDs lands before the ack")
        XCTAssertEqual(savedAtAck?.committedCursor, 1)
    }

    /// A loan saved mid-flight restores field for field; the relaunch pauses dosing at once.
    func testASavedLoanRestoresAndPausesDosing() {
        let committed = UUID(), token = UUID()
        let started = Date(timeIntervalSinceNow: -3600), renewed = Date(timeIntervalSinceNow: -1200)
        var saved = PodLoanPhoneState()
        saved.phase = .loaned
        saved.epoch = 5
        saved.committedCursor = 3
        saved.committedIDs = [committed]
        saved.holdRenewedAt = renewed
        saved.watchSupportsSeize = true
        saved.seizeToken = token
        saved.audit.loanStartedAt = started
        saved.audit.deliveredAtGrant = 12.0
        saved.audit.base = .init(units: 13.0, asOf: started)
        saved.audit.baseEpoch = 5
        saved.audit.checkpoints = 2
        saved.pendingForceAudit = .init(epoch: 5, deliveredAtStart: 12.5, expected: 0.8, loanMinutes: 60)
        saveState { $0 = saved }

        let controller = makeController()
        let p = controller.persisted
        XCTAssertEqual(p.phase, .loaned)
        XCTAssertEqual(p.epoch, 5)
        XCTAssertEqual(p.committedCursor, 3)
        XCTAssertEqual(p.committedIDs, [committed])
        XCTAssertEqual(p.holdRenewedAt, renewed)
        XCTAssertTrue(p.watchSupportsSeize)
        XCTAssertEqual(p.seizeToken, token)
        XCTAssertEqual(p.audit.base?.units, 13.0, "a base from this epoch is kept")
        XCTAssertEqual(p.audit.checkpoints, 2)
        XCTAssertEqual(controller.queue.sync { controller.pendingHandbackAudit?.flavor }, .forceReclaim, "the owed verdict re-arms")
        XCTAssertEqual(pauseCalls, [true], "dosing pauses at launch")
    }

    // MARK: - The phone reads the end-of-loan odometer and cancels the inherited temp

    /// The audit's end reading is the phone's reclaim round-trip, not the watch's stale offer.
    func testHandbackAuditUsesThePhonesOwnOdometerNotTheWatchsStaleOne() throws {
        let controller = makeController()
        let grant = establishLoan(controller)

        // The watch's endpoint: stale, and it knows it (freshenSucceeded false).
        let handedBackAt = Date()
        let odometer = LoanOdometerSnapshot(deliveredAtStart: 10.0, deliveredLatest: 10.400,
                                            freshenSucceeded: false)
        // What the pod ACTUALLY reads when the phone gets there: half a unit further on.
        MockPumpManager.testOdometer = 10.900

        let ackSent = expectSend()
        let offer = HandbackOffer(epoch: grant.epoch, handedBackAt: handedBackAt, finalStatus: nil,
                                  odometer: odometer, events: [], tombstones: [],
                                  recovered: false, released: true)
        controller.handleIncoming(userInfo: try LoanMessage.handbackOffer(offer).transportDictionary())
        wait(for: [ackSent], timeout: 5)
        waitForState(controller, .owner)

        // The provisional line still prints — it is all we have if the pod never comes home.
        XCTAssertNotNil(diagMatching("reconcile[provisional]"), "the provisional audit must still be logged")

        // Then the reclaim round-trip lands and supersedes it.
        waitUntil(timeout: 8, "authoritative audit") { self.diagMatching("reconcile[AUTHORITATIVE]") != nil }
        let line = diagMatching("reconcile[AUTHORITATIVE]")!
        XCTAssertTrue(line.contains("delivered=0.900"),
                      "delivered must be phone-read latest (10.900) minus the watch's start (10.000) — got: \(line)")
        XCTAssertTrue(line.contains("vs watch endpoint +0.500"),
                      "the line must state how much delivery the watch's stale endpoint missed — got: \(line)")
    }

    /// Phone-enforced: the temp the WATCH programmed is cancelled once — and only once the
    /// pod is provably reachable. The watch cannot do this itself; its link is down by then.
    func testInheritedTempIsCancelledOnTheVerifiedReclaimRoundTrip() throws {
        let controller = makeController()
        let grant = establishLoan(controller)

        connectionReady = false          // pod not back yet
        MockPumpManager.testOdometer = 12.0

        let ackSent = expectSend()
        let offer = HandbackOffer(epoch: grant.epoch, handedBackAt: Date(), finalStatus: nil,
                                  odometer: LoanOdometerSnapshot(deliveredAtStart: 10, deliveredLatest: 11,
                                                                 freshenSucceeded: true),
                                  events: [], tombstones: [], recovered: false, released: true)
        controller.handleIncoming(userInfo: try LoanMessage.handbackOffer(offer).transportDictionary())
        wait(for: [ackSent], timeout: 5)
        waitForState(controller, .owner)

        // Nothing is commanded at a pod we cannot reach — that was the whole bug.
        XCTAssertEqual(cancelCalls, 0, "must not command a pod that is not back yet")

        connectionReady = true
        waitUntil(timeout: 8, "reclaim temp cancel") { self.lock.lock(); defer { self.lock.unlock() }; return self.cancelCalls > 0 }
        XCTAssertEqual(cancelCalls, 1, "cancel exactly once per loan, on the verified round-trip")
        XCTAssertNotNil(diagMatching("temp cancelled — pod reverts to the user's schedule until"), "the cancel's outcome must be in the log")

        // The chase keeps ticking after verification; the audit must not re-fire on later ticks.
        let settle = expectation(description: "no second cancel")
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) { settle.fulfill() }
        wait(for: [settle], timeout: 5)
        XCTAssertEqual(cancelCalls, 1, "one cancel per loan, not one per chase tick")
    }

    /// A failed cancel is a logged diagnostic, not a stall: the pod keeps running the watch's last
    /// automatic rate (computed from real CGM data minutes ago) until the phone's next cycle.
    func testFailedInheritedTempCancelIsLoggedAndDoesNotBlockTheReclaim() throws {
        struct Boom: Error {}
        let controller = makeController()
        let grant = establishLoan(controller)
        cancelError = Boom()
        MockPumpManager.testOdometer = 11.0

        let ackSent = expectSend()
        let offer = HandbackOffer(epoch: grant.epoch, handedBackAt: Date(), finalStatus: nil,
                                  odometer: LoanOdometerSnapshot(deliveredAtStart: 10, deliveredLatest: 10.5,
                                                                 freshenSucceeded: true),
                                  events: [], tombstones: [], recovered: false, released: true)
        controller.handleIncoming(userInfo: try LoanMessage.handbackOffer(offer).transportDictionary())
        wait(for: [ackSent], timeout: 5)
        waitForState(controller, .owner)

        waitUntil(timeout: 8, "failed-cancel diag") { self.diagMatching("temp cancel FAILED — pod keeps") != nil }
        XCTAssertEqual(controller.state, .owner, "a failed cancel must not strand the loan state")
        // The audit is independent of the cancel and must still have landed.
        XCTAssertNotNil(diagMatching("reconcile[AUTHORITATIVE]"))
    }

    /// If the pod never comes home there is no authoritative reading — and no invented one. The
    /// provisional line stands, and nothing leaks into the NEXT loan's audit.
    func testNoAuthoritativeAuditWhenThePodNeverComesBack() throws {
        let controller = makeController()
        let grant = establishLoan(controller)
        connectionReady = false

        let ackSent = expectSend()
        let offer = HandbackOffer(epoch: grant.epoch, handedBackAt: Date(), finalStatus: nil,
                                  odometer: LoanOdometerSnapshot(deliveredAtStart: 10, deliveredLatest: 10.5,
                                                                 freshenSucceeded: false),
                                  events: [], tombstones: [], recovered: false, released: true)
        controller.handleIncoming(userInfo: try LoanMessage.handbackOffer(offer).transportDictionary())
        wait(for: [ackSent], timeout: 5)
        waitForState(controller, .owner)

        let settle = expectation(description: "settle")
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) { settle.fulfill() }
        wait(for: [settle], timeout: 5)
        XCTAssertNil(diagMatching("reconcile[AUTHORITATIVE]"), "no reading means no audit — never a fabricated one")
        XCTAssertEqual(cancelCalls, 0, "no cancel at an unreachable pod")
        XCTAssertNotNil(diagMatching("reconcile[provisional]"), "the provisional line is what stands")
    }

    // MARK: - A hand-over lost in transit

    /// Drives a controller into `.grantOffered` (grant sent, watch has not confirmed).
    private func offerGrant(_ controller: PodLoanPhoneController) -> LoanGrant {
        let grantSent = expectSend()
        controller.handleIncoming(userInfo: try! LoanMessage.request(LoanRequest(watchBuild: "t")).transportDictionary())
        wait(for: [grantSent], timeout: 5)
        // Barrier: `grantOfferedAt` is stamped on the controller's queue.
        controller.queue.sync { }
        guard case .grant(let grant)? = lastSent() else {
            XCTFail("expected a grant, got \(String(describing: lastSent()))")
            fatalError()
        }
        return grant
    }

    /// The grant's audit base belongs to the grant's own epoch, so a relaunch before the watch
    /// confirms keeps it (it was saved under the previous epoch and dropped at launch).
    func testRelaunchBetweenGrantAndTakeoverKeepsTheAuditBase() {
        MockPumpManager.testOdometer = 10.0
        let grant = offerGrant(makeController())
        let relaunched = makeController()
        relaunched.queue.sync { }
        XCTAssertEqual(relaunched.epoch, grant.epoch)
        XCTAssertEqual(relaunched.auditBase?.units, 10.0, "the grant's base survives the relaunch")
    }

    /// The fix: an explicit "I never got it" reclaims immediately instead of after 5 min 15 s.
    func testExplicitGrantLostReportReclaimsImmediately() throws {
        let controller = makeController()
        let grant = offerGrant(controller)
        XCTAssertTrue(MockPumpManager.testConnectionReleased, "the phone releases the pod to hand over")

        let report = StatusReport(epoch: grant.epoch, mode: .closedDirect, lastDirectGlucoseAge: nil,
                                  lastEventSeq: 0, podFault: nil, holdsPod: false, knowsGrant: false)
        controller.handleIncoming(userInfo: try LoanMessage.statusReport(report).transportDictionary())

        waitForState(controller, .owner)
        XCTAssertFalse(MockPumpManager.testConnectionReleased, "the pod comes straight back")
        waitUntil(timeout: 5, "dosing resumed") { self.lock.lock(); defer { self.lock.unlock() }; return self.pauseCalls.last == false }
        XCTAssertEqual(pauseCalls.last, false, "and the phone resumes its own dosing")
    }

    /// A watch mid-takeover also reports `holdsPod: false`; that is not a lost grant.
    func testMidTakeoverReportIsNotMistakenForALostGrant() throws {
        let controller = makeController()
        let grant = offerGrant(controller)

        let report = StatusReport(epoch: grant.epoch, mode: .closedDirect, lastDirectGlucoseAge: nil,
                                  lastEventSeq: 0, podFault: nil, holdsPod: false, knowsGrant: true)
        controller.handleIncoming(userInfo: try LoanMessage.statusReport(report).transportDictionary())

        let settle = expectation(description: "settle")
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) { settle.fulfill() }
        wait(for: [settle], timeout: 5)
        XCTAssertEqual(controller.state, .grantOffered, "a watch that HAS the grant must be left alone")
        XCTAssertTrue(MockPumpManager.testConnectionReleased, "the pod stays released for the takeover")
    }

    /// `knowsGrant == nil` falls through to the 5-minute timer, never read as a denial.
    func testUnansweredKnowsGrantDoesNotReclaim() throws {
        let controller = makeController()
        let grant = offerGrant(controller)

        let report = StatusReport(epoch: grant.epoch, mode: .closedDirect, lastDirectGlucoseAge: nil,
                                  lastEventSeq: 0, podFault: nil, holdsPod: false)   // knowsGrant nil
        controller.handleIncoming(userInfo: try LoanMessage.statusReport(report).transportDictionary())

        let settle = expectation(description: "settle")
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) { settle.fulfill() }
        wait(for: [settle], timeout: 5)
        XCTAssertEqual(controller.state, .grantOffered, "no information is not a denial")
    }

    /// The added field must survive a round trip, and its absence must decode as "no answer"
    /// rather than failing the whole message.
    func testKnowsGrantRoundTripsAndIsOptionalOnDecode() throws {
        let report = StatusReport(epoch: 7, mode: .closedDirect, lastDirectGlucoseAge: 30,
                                  lastEventSeq: 3, podFault: nil, holdsPod: true, knowsGrant: true)
        var transport = try LoanMessage.statusReport(report).transportDictionary()
        guard case .statusReport(let decoded)? = try? LoanMessage.decode(fromTransport: transport) else {
            return XCTFail("round trip failed")
        }
        XCTAssertEqual(decoded.knowsGrant, true)

        // The envelope rides as an encoded Data blob, so strip inside it, not in the outer dict.
        guard let data = transport[LoanProtocol.userInfoKey] as? Data,
              var json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return XCTFail("expected an encoded envelope")
        }
        XCTAssertTrue(Self.stripKey("knowsGrant", from: &json), "expected the key to be present to strip")
        transport[LoanProtocol.userInfoKey] = try JSONSerialization.data(withJSONObject: json)

        guard case .statusReport(let old)? = try? LoanMessage.decode(fromTransport: transport) else {
            return XCTFail("a report without knowsGrant must still decode")
        }
        XCTAssertNil(old.knowsGrant, "absent must mean 'could not answer', not false")
        XCTAssertTrue(old.holdsPod, "the rest of the report must be unaffected")
    }

    // MARK: - What a reconciliation difference DOES

    /// One clean loan to the audit; handing back immediately keeps expected ~0, so delivered is the residual.
    private func runLoanToAudit(_ controller: PodLoanPhoneController, deliveredDuringLoan: Double) throws {
        let grant = establishLoan(controller)
        MockPumpManager.testOdometer = 10.0 + deliveredDuringLoan
        let ackSent = expectSend()
        let offer = HandbackOffer(epoch: grant.epoch, handedBackAt: Date(), finalStatus: nil,
                                  odometer: LoanOdometerSnapshot(deliveredAtStart: 10.0, deliveredLatest: 10.0,
                                                                 freshenSucceeded: true),
                                  events: [], tombstones: [], recovered: false, released: true)
        controller.handleIncoming(userInfo: try LoanMessage.handbackOffer(offer).transportDictionary())
        wait(for: [ackSent], timeout: 5)
        waitForState(controller, .owner)
        waitUntil(timeout: 8, "authoritative audit") { self.diagMatching("reconcile[AUTHORITATIVE]") != nil }
    }

    /// POSITIVE beyond the bound: the pod delivered insulin the books do not contain, so closed
    /// loop would dose on top of insulin it cannot see. Stop the machine.
    func testLargePositiveResidualOpensTheLoop() throws {
        let controller = makeController()
        try runLoanToAudit(controller, deliveredDuringLoan: 2.0)   // vs ~0 expected

        // The verdict logs first, then stops dosing, then notifies: wait on the last of the three.
        waitUntil(timeout: 5, "open-loop verdict") {
            guard self.diagMatching("OPEN LOOP — residual") != nil else { return false }
            self.lock.lock(); defer { self.lock.unlock() }
            return self.urgentNotices.contains("Loop Open — Unexplained Insulin")
        }
        lock.lock(); let openLoops = openLoopCalls; lock.unlock()
        XCTAssertEqual(openLoops, 1, "automatic dosing must be stopped exactly once")
    }

    /// NEGATIVE beyond the bound: the books carry phantom IOB, so the loop runs CAUTIOUS. Opening
    /// it would make the real failure — under-treatment — worse. Warn, keep looping.
    func testLargeNegativeResidualWarnsButKeepsLooping() throws {
        let controller = makeController()
        let grant = establishLoan(controller)

        // Books say 2 U bolus, odometer says nothing moved (a bolus keeps it timing-independent).
        MockPumpManager.testOdometer = 10.0
        let bolus = makeEvent(seq: 1, units: 2.0, at: Date())
        let ackSent = expectSend()
        let offer = HandbackOffer(epoch: grant.epoch, handedBackAt: Date().addingTimeInterval(60),
                                  finalStatus: nil,
                                  odometer: LoanOdometerSnapshot(deliveredAtStart: 10.0, deliveredLatest: 10.0,
                                                                 freshenSucceeded: true),
                                  events: [bolus], tombstones: [], recovered: false, released: true)
        controller.handleIncoming(userInfo: try LoanMessage.handbackOffer(offer).transportDictionary())
        wait(for: [ackSent], timeout: 5)
        waitForState(controller, .owner)

        waitUntil(timeout: 8, "warn verdict") { self.diagMatching("WARN — residual") != nil }
        XCTAssertEqual(openLoopCalls, 0, "a shortfall must NOT open the loop — that worsens under-treatment")
        // "Overstated": the pod delivered less than the records. Urgent both ways; only positive opens the loop.
        XCTAssertTrue(urgentNotices.contains("Insulin On Board May Be Overstated"))
    }

    /// The ordinary case — a residual inside the bounds — must be silent. If routine loans warn,
    /// the warning stops meaning anything.
    func testResidualWithinBoundsIsSilent() throws {
        let controller = makeController()
        try runLoanToAudit(controller, deliveredDuringLoan: 0.10)

        XCTAssertEqual(openLoopCalls, 0)
        XCTAssertNil(diagMatching("OPEN LOOP — residual"))
        XCTAssertNil(diagMatching("WARN — residual"))
        XCTAssertTrue(notices.isEmpty, "a normal loan must produce no notice at all, got \(notices)")
    }

    /// A base saved under another epoch is dropped at launch.
    func testASavedBaseFromAnotherEpochIsDropped() {
        var saved = PodLoanPhoneState()
        saved.epoch = 5
        saved.audit.base = .init(units: 13.0, asOf: Date())
        saved.audit.baseEpoch = 4
        saved.audit.checkpoints = 2
        saveState { $0 = saved }
        let controller = makeController()
        XCTAssertNil(controller.auditBase)
        XCTAssertEqual(controller.checkpointsThisLoan, 0)
    }

    /// +0.25 U is over the ±0.20 bound and under the old ±0.5, so a revert fails this.
    func testResidualJustAboveTheTightenedBoundOpensTheLoop() throws {
        let controller = makeController()
        try runLoanToAudit(controller, deliveredDuringLoan: 0.25)

        waitUntil(timeout: 5, "open-loop verdict") { self.diagMatching("OPEN LOOP — residual") != nil }
        XCTAssertEqual(openLoopCalls, 1, "+0.25 U is over the 0.20 U bound — the loop must open")
        XCTAssertTrue(urgentNotices.contains("Loop Open — Unexplained Insulin"))
    }

    /// +0.200 with float dust stays inside the band.
    func testResidualExactlyOnTheBandStaysSilentDespiteFloatDust() throws {
        let controller = makeController()
        let grant = establishLoan(controller)

        // Books say 2.2 U bolused; the pod metered 2.4 — a raw float residual of 0.2000…018.
        MockPumpManager.testOdometer = 12.4
        let bolus = makeEvent(seq: 1, units: 2.2, at: Date())
        let ackSent = expectSend()
        let offer = HandbackOffer(epoch: grant.epoch, handedBackAt: Date(), finalStatus: nil,
                                  odometer: LoanOdometerSnapshot(deliveredAtStart: 10.0, deliveredLatest: 12.4,
                                                                 freshenSucceeded: true),
                                  events: [bolus], tombstones: [], recovered: false, released: true)
        controller.handleIncoming(userInfo: try LoanMessage.handbackOffer(offer).transportDictionary())
        wait(for: [ackSent], timeout: 5)
        waitForState(controller, .owner)
        waitUntil(timeout: 8, "authoritative audit") { self.diagMatching("reconcile[AUTHORITATIVE]") != nil }

        XCTAssertEqual(openLoopCalls, 0, "exactly ±0.200 is ON the band, not beyond it — float dust must not open the loop")
        XCTAssertNil(diagMatching("OPEN LOOP — residual"))
    }

    /// The negative twin: −0.2000000000000007 stays inside the band.
    func testResidualExactlyOnTheNegativeBandStaysSilentDespiteFloatDust() throws {
        let controller = makeController()
        let grant = establishLoan(controller)

        MockPumpManager.testOdometer = 12.2
        let bolus = makeEvent(seq: 1, units: 2.4, at: Date())
        let ackSent = expectSend()
        let offer = HandbackOffer(epoch: grant.epoch, handedBackAt: Date(), finalStatus: nil,
                                  odometer: LoanOdometerSnapshot(deliveredAtStart: 10.0, deliveredLatest: 12.2,
                                                                 freshenSucceeded: true),
                                  events: [bolus], tombstones: [], recovered: false, released: true)
        controller.handleIncoming(userInfo: try LoanMessage.handbackOffer(offer).transportDictionary())
        wait(for: [ackSent], timeout: 5)
        waitForState(controller, .owner)
        waitUntil(timeout: 8, "authoritative audit") { self.diagMatching("reconcile[AUTHORITATIVE]") != nil }

        XCTAssertEqual(openLoopCalls, 0)
        XCTAssertNil(diagMatching("WARN — residual"), "exactly −0.200 is ON the band — float dust must not warn")
    }

    // MARK: - Since-last-sync checkpoints

    /// Sends a checkpoint batch and waits for it on the controller's queue, so the next step sees
    /// the new base. `asOf: nil` models an older watch.
    private func sendCheckpoint(_ controller: PodLoanPhoneController, epoch: Int,
                                events: [LoanEvent] = [], latest: Double, asOf: Date?) throws {
        let snap = LoanOdometerSnapshot(deliveredAtStart: 10.0, deliveredLatest: latest,
                                        freshenSucceeded: false, asOf: asOf)
        controller.handleIncoming(userInfo: try LoanMessage.doseRecordBatch(
            DoseRecordBatch(epoch: epoch, events: events, tombstones: [], odometer: snap)).transportDictionary())
        controller.queue.sync { }
    }

    /// Closes the loan with a final offer whose end odometer the phone then verifies first-hand.
    private func finishLoan(_ controller: PodLoanPhoneController, epoch: Int, finalOdometer: Double) throws {
        MockPumpManager.testOdometer = finalOdometer
        let ackSent = expectSend()
        let offer = HandbackOffer(epoch: epoch, handedBackAt: Date().addingTimeInterval(5), finalStatus: nil,
                                  odometer: LoanOdometerSnapshot(deliveredAtStart: 10.0, deliveredLatest: finalOdometer,
                                                                 freshenSucceeded: true),
                                  events: [], tombstones: [], recovered: false, released: true)
        controller.handleIncoming(userInfo: try LoanMessage.handbackOffer(offer).transportDictionary())
        wait(for: [ackSent], timeout: 5)
        waitForState(controller, .owner)
        waitUntil(timeout: 8, "authoritative audit") { self.diagMatching("reconcile[AUTHORITATIVE]") != nil }
    }

    /// Drift within each synced window stays silent even when the loan total exceeds the band.
    func testCheckpointedDriftWithinEachWindowStaysSilent() throws {
        let controller = makeController()
        let grant = establishLoan(controller)   // audit base = 10.0 @ the takeover reading

        try sendCheckpoint(controller, epoch: grant.epoch, latest: 10.15, asOf: Date().addingTimeInterval(2))
        try finishLoan(controller, epoch: grant.epoch, finalOdometer: 10.30)

        XCTAssertEqual(openLoopCalls, 0, "each window reconciled at a sync — no verdict may fire on the loan total")
        XCTAssertNil(diagMatching("OPEN LOOP — residual"))
        XCTAssertNil(diagMatching("WARN — residual"))
    }

    /// The checkpoint must not blunt detection: insulin the tail cannot explain still opens.
    func testUnexplainedTailAfterACheckpointStillOpensTheLoop() throws {
        let controller = makeController()
        let grant = establishLoan(controller)

        try sendCheckpoint(controller, epoch: grant.epoch, latest: 10.0, asOf: Date().addingTimeInterval(2))
        try finishLoan(controller, epoch: grant.epoch, finalOdometer: 10.5)

        waitUntil(timeout: 5, "open-loop verdict") { self.diagMatching("OPEN LOOP — residual") != nil }
        XCTAssertEqual(openLoopCalls, 1, "+0.5 U since the last sync is unexplained — the loop must open")
    }

    /// An older watch sends snapshots without `asOf`; the base must never advance on one, so
    /// the audit keeps its whole-loan window — the exact pre-checkpoint behavior.
    func testSnapshotWithoutAsOfNeverCheckpoints() throws {
        let controller = makeController()
        let grant = establishLoan(controller)

        try sendCheckpoint(controller, epoch: grant.epoch, latest: 10.15, asOf: nil)
        try finishLoan(controller, epoch: grant.epoch, finalOdometer: 10.30)

        waitUntil(timeout: 5, "open-loop verdict") { self.diagMatching("OPEN LOOP — residual") != nil }
        XCTAssertEqual(openLoopCalls, 1, "no asOf = no checkpoint — +0.30 over the whole loan must still open")
    }

    /// A breaching window is carried, not retired: the base stays put.
    func testBreachingCheckpointDoesNotAdvanceTheBase() throws {
        let controller = makeController()
        let grant = establishLoan(controller)

        try sendCheckpoint(controller, epoch: grant.epoch, latest: 10.5, asOf: Date().addingTimeInterval(2))
        try finishLoan(controller, epoch: grant.epoch, finalOdometer: 10.5)

        waitUntil(timeout: 5, "open-loop verdict") { self.diagMatching("OPEN LOOP — residual") != nil }
        XCTAssertEqual(openLoopCalls, 1, "a checkpoint that failed to reconcile must not retire its window")
    }

    /// A loan that synced then died: the force audit judges only the tail since the last sync.
    func testForceReclaimJudgesOnlyTheTailSinceTheLastSync() throws {
        let controller = makeController()
        let grant = establishLoan(controller)

        // A synced stretch: a 1.0 U bolus streamed, and the checkpoint shows the pod metered
        // it plus 0.15 U of benign drift — within the band, window retired (base → 11.15).
        let bolus = makeEvent(seq: 1, units: 1.0, at: Date())
        try sendCheckpoint(controller, epoch: grant.epoch, events: [bolus], latest: 11.15,
                           asOf: Date().addingTimeInterval(2))

        // Then the watch dies. The pod's final odometer adds only 0.15 U since the sync.
        // Whole-loan framing reads +0.30 and opens; since-last-sync reads +0.15 and stays closed.
        MockPumpManager.testOdometer = 11.30
        controller.forceReclaimToOwner(reason: "test: watch dead after a synced stretch")
        waitForState(controller, .owner)
        waitUntil(timeout: 8, "force verdict") { self.diagMatching("reconcile[FORCE-RECLAIM]") != nil }

        lock.lock()
        let opened = openLoopCalls
        let booked = bookedGapDoses
        lock.unlock()
        XCTAssertEqual(opened, 0, "the tail since the sync is 0.15 U — inside the band")
        XCTAssertTrue(booked.isEmpty, "the synced window is already in the records — nothing to book")
        XCTAssertNil(diagMatching("OPEN LOOP — force-reclaim"))
    }

    /// Row 10: the same offer redelivered (lost ack) re-acks the same cursor and
    /// writes NOTHING new.
    func testOfferRedeliveryIsIdempotent() throws {
        let controller = makeController()
        let grant = establishLoan(controller)
        let event = makeEvent(seq: 1, units: 1.0, at: Date())
        let offer = HandbackOffer(epoch: grant.epoch, handedBackAt: Date(), finalStatus: nil,
                                  odometer: nil, events: [event], tombstones: [], recovered: false)

        let firstAck = expectSend()
        controller.handleIncoming(userInfo: try LoanMessage.handbackOffer(offer).transportDictionary())
        wait(for: [firstAck], timeout: 5)

        let secondAck = expectSend()
        controller.handleIncoming(userInfo: try LoanMessage.handbackOffer(offer).transportDictionary())
        wait(for: [secondAck], timeout: 5)

        guard case .handbackAck(let ack)? = lastSent() else { return XCTFail("expected ack") }
        XCTAssertEqual(ack.committedCursor, 1, "same cursor on redelivery")
        let totalWritten = addedDoses.reduce(0) { $0 + $1.count }
        XCTAssertEqual(totalWritten, 1, "redelivery writes no duplicate doses")
    }

    /// Rows 13/14 + D22: a stale-epoch offer drains its records but cannot speak to
    /// loan state — the active loan is untouched and the ack says stale.
    func testStaleEpochOfferDrainsButCannotTouchState() throws {
        let controller = makeController()
        let grant1 = establishLoan(controller)

        // Close loan 1 normally.
        let ack1 = expectSend()
        controller.handleIncoming(userInfo: try LoanMessage.handbackOffer(HandbackOffer(
            epoch: grant1.epoch, handedBackAt: Date(), finalStatus: nil, odometer: nil,
            events: [], tombstones: [], recovered: false)).transportDictionary())
        wait(for: [ack1], timeout: 5)
        waitForState(controller, .owner)

        // Open loan 2.
        let grant2 = establishLoan(controller)
        XCTAssertEqual(grant2.epoch, grant1.epoch + 1)

        // A late loan-1 offer arrives (WC redelivery). Its record still drains, the
        // ack is stale, and loan 2 is untouched.
        let staleAck = expectSend()
        let lateEvent = makeEvent(seq: 7, units: 0.5, at: Date())
        controller.handleIncoming(userInfo: try LoanMessage.handbackOffer(HandbackOffer(
            epoch: grant1.epoch, handedBackAt: Date(), finalStatus: nil, odometer: nil,
            events: [lateEvent], tombstones: [], recovered: true)).transportDictionary())
        wait(for: [staleAck], timeout: 5)

        guard case .handbackAck(let ack)? = lastSent() else { return XCTFail("expected ack") }
        XCTAssertTrue(ack.stale, "dead loans cannot speak")
        XCTAssertEqual(ack.epoch, grant1.epoch)
        XCTAssertEqual(controller.state, .loaned, "the ACTIVE loan is untouched")
        let lastBatch = addedDoses.last ?? []
        XCTAssertEqual(lastBatch.count, 1, "the stale offer's record still drained")
    }

    /// An interim offer acks the open temp's cursor but defers its write to the final offer.
    func testInterimDrainAcksOpenTempButDefersWriteToFinal() throws {
        let controller = makeController()
        let grant = establishLoan(controller)
        let now = Date()
        // A temp still running: its 30-min window extends well past handedBackAt (now).
        let openTemp = tempEvent(seq: 1, rate: 1.5, start: now.addingTimeInterval(-60), durationMinutes: 30)

        // Phase 1 — INTERIM offer (released:false): watch still dosing.
        let interimAck = expectSend()
        controller.handleIncoming(userInfo: try LoanMessage.handbackOffer(HandbackOffer(
            epoch: grant.epoch, handedBackAt: now, finalStatus: nil, odometer: nil,
            events: [openTemp], tombstones: [], recovered: false, released: false)).transportDictionary())
        wait(for: [interimAck], timeout: 5)

        guard case .handbackAck(let ack1)? = lastSent() else { return XCTFail("expected interim ack") }
        XCTAssertEqual(ack1.committedCursor, openTemp.seq, "open temp's seq IS acked so the watch can finalize (deadlock fix)")
        XCTAssertEqual(addedDoses.flatMap { $0 }.count, 0, "but the open temp is withheld from the store write")
        XCTAssertEqual(controller.state, .loaned, "an interim drain does not reclaim")

        // Phase 2 — FINAL offer (released:true): the watch acked everything, so it carries
        // no events; the phone re-drains the still-staged open temp and writes it.
        let finalAck = expectSend()
        controller.handleIncoming(userInfo: try LoanMessage.handbackOffer(HandbackOffer(
            epoch: grant.epoch, handedBackAt: now.addingTimeInterval(5), finalStatus: nil, odometer: nil,
            events: [], tombstones: [], recovered: false, released: true)).transportDictionary())
        wait(for: [finalAck], timeout: 5)

        XCTAssertEqual(addedDoses.flatMap { $0 }.count, 1, "the withheld open temp is written on the final drain")
        waitForState(controller, .owner)
    }

    // MARK: - KNOWN_RESIDUALS §16 (two-phase hand-back test debt)

    /// An offer without the `released` key (older watch) finalizes the loan.
    func testLegacyOfferWithoutReleasedKeyFinalizesTheLoan() throws {
        let controller = makeController()
        let grant = establishLoan(controller)
        let event = makeEvent(seq: 1, units: 1.0, at: Date())

        var dict = try LoanMessage.handbackOffer(HandbackOffer(
            epoch: grant.epoch, handedBackAt: Date(), finalStatus: nil, odometer: nil,
            events: [event], tombstones: [], recovered: false, released: true)).transportDictionary()
        var json = try JSONSerialization.jsonObject(with: dict[LoanProtocol.userInfoKey] as! Data) as! [String: Any]
        XCTAssertTrue(Self.stripKey("released", from: &json), "fixture must contain a released key to strip")
        dict[LoanProtocol.userInfoKey] = try JSONSerialization.data(withJSONObject: json)

        let ackSent = expectSend()
        controller.handleIncoming(userInfo: dict)
        wait(for: [ackSent], timeout: 5)

        XCTAssertEqual(addedDoses.flatMap { $0 }.count, 1, "the legacy offer's records are committed")
        waitForState(controller, .owner)
        waitUntil(timeout: 5, "dosing resumed") { self.lock.lock(); defer { self.lock.unlock() }; return self.pauseCalls.last == false }
        XCTAssertEqual(pauseCalls, [true, false], "dosing is restored — the loan is not left open")
    }

    /// A final offer with no events still acks and closes the loan.
    func testFinalOfferWithNoEventsStillAcksAndReturnsToOwner() throws {
        let controller = makeController()
        let grant = establishLoan(controller)

        let ackSent = expectSend()
        controller.handleIncoming(userInfo: try LoanMessage.handbackOffer(HandbackOffer(
            epoch: grant.epoch, handedBackAt: Date(), finalStatus: nil, odometer: nil,
            events: [], tombstones: [], recovered: false, released: true)).transportDictionary())
        wait(for: [ackSent], timeout: 5)

        guard case .handbackAck(let ack)? = lastSent() else { return XCTFail("expected ack") }
        XCTAssertEqual(ack.committedCursor, 0, "an empty drain acks cursor 0 (finding :948)")
        XCTAssertFalse(ack.stale)
        XCTAssertEqual(addedDoses.flatMap { $0 }.count, 0, "nothing to write")
        waitForState(controller, .owner)
        // The unpause lands a few ms AFTER the state flip (notification-center XPC sits between
        // them), so an instant read here races it — wait for the value, then assert the shape.
        waitUntil(timeout: 5, "dosing resumed") { self.lock.lock(); defer { self.lock.unlock() }; return self.pauseCalls.contains(false) }
        XCTAssertEqual(pauseCalls, [true, false], "the loan still closes and dosing resumes")
        XCTAssertFalse(MockPumpManager.testConnectionReleased, "pod reclaimed on the empty close")
    }

    /// With this phone's Bluetooth off, the final offer is not acked.
    func testFinalOfferIsNotAcceptedWhileThisPhonesBluetoothIsOff() throws {
        var off = true
        let controller = makeController(bluetoothPoweredOff: { [unowned self] in
            self.lock.lock(); defer { self.lock.unlock() }; return off
        })
        let grant = establishLoan(controller)
        let offer = try LoanMessage.handbackOffer(HandbackOffer(
            epoch: grant.epoch, handedBackAt: Date(), finalStatus: nil, odometer: nil,
            events: [], tombstones: [], recovered: false, released: true)).transportDictionary()

        controller.handleIncoming(userInfo: offer)
        waitUntil(timeout: 5, "refusal sent") { if case .denied? = self.lastSent() { return true }; return false }
        guard case .denied(let refusal)? = lastSent() else { return XCTFail("expected a refusal") }
        XCTAssertTrue(refusal.reason.contains("Bluetooth"), "the watch shows this reason as-is, so it must say why")
        XCTAssertEqual(controller.state, .loaned, "the phone does not take a pod it cannot reach")
        XCTAssertTrue(MockPumpManager.testConnectionReleased, "the pod stays lent; the watch keeps the loan")

        // The INTERIM offer that opens End is refused too — that is what makes it quick.
        let interim = try LoanMessage.handbackOffer(HandbackOffer(
            epoch: grant.epoch, handedBackAt: Date(), finalStatus: nil, odometer: nil,
            events: [], tombstones: [], recovered: false, released: false)).transportDictionary()
        controller.handleIncoming(userInfo: interim)
        controller.queue.sync { }
        if case .handbackAck? = lastSent() { XCTFail("an interim offer is not acked either while Bluetooth is off") }
        XCTAssertEqual(controller.state, .loaned)

        // Bluetooth back on: the very same offer is accepted.
        lock.lock(); off = false; lock.unlock()
        controller.handleIncoming(userInfo: offer)
        waitUntil(timeout: 5, "ack once Bluetooth is on") { if case .handbackAck? = self.lastSent() { return true }; return false }
        waitForState(controller, .owner)
    }

    // MARK: - Stale offer clamps a LATER epoch's doses

    /// A stale offer's drain must not clamp a later epoch's temps to its own hand-back time
    /// (Core Data rejected the negative durations).
    func testStaleOfferMustNotClampALaterEpochsDosesToItsOwnHandbackTime() throws {
        let controller = makeController()
        let grant1 = establishLoan(controller)
        let epoch1HandedBackAt = Date().addingTimeInterval(-.minutes(30))

        // Close loan 1 cleanly (this is the offer that gets redelivered later).
        let closeAck = expectSend()
        let epoch1Offer = HandbackOffer(epoch: grant1.epoch, handedBackAt: epoch1HandedBackAt,
                                        finalStatus: nil, odometer: nil, events: [],
                                        tombstones: [], recovered: false, released: true)
        controller.handleIncoming(userInfo: try LoanMessage.handbackOffer(epoch1Offer).transportDictionary())
        wait(for: [closeAck], timeout: 5)
        waitForState(controller, .owner)

        // Loan 2 starts and streams a temp that is still running NOW — i.e. it both starts
        // and ends well AFTER epoch 1's hand-back instant.
        let grant2 = establishLoan(controller)
        let liveTempStart = Date().addingTimeInterval(-.minutes(2))
        let liveTemp = tempEvent(seq: 1, rate: 1.3, start: liveTempStart, durationMinutes: 30)
        controller.handleIncoming(userInfo: try LoanMessage.doseRecordBatch(
            DoseRecordBatch(epoch: grant2.epoch, events: [liveTemp], tombstones: [])).transportDictionary())

        // The stale epoch-1 offer is redelivered by the transport.
        let staleAck = expectSend()
        controller.handleIncoming(userInfo: try LoanMessage.handbackOffer(epoch1Offer).transportDictionary())
        wait(for: [staleAck], timeout: 5)

        // A stale offer drains only the events it actually carried,
        // so epoch 2's live temp is never in scope to be clamped to epoch 1's handedBackAt.
        let written = addedDoses.flatMap { $0 }
        let inverted = written.filter { $0.endDate < $0.startDate }
        XCTAssertTrue(inverted.isEmpty,
                      "a stale offer must never write a dose that ends before it starts — got \(inverted.count) inverted of \(written.count)")

        // The live temp is not written by the stale drain at all; it waits for its own epoch.
        XCTAssertFalse(written.contains { $0.startDate >= liveTempStart.addingTimeInterval(-1) },
                       "the stale drain must not write epoch 2's live temp at all")
    }

    /// Recursively remove `key`; returns whether anything was removed. Mirrors the helper in
    /// LoanProtocolV2Tests so neither test pins the envelope's nesting.
    private static func stripKey(_ key: String, from json: inout [String: Any]) -> Bool {
        var removed = false
        if json.removeValue(forKey: key) != nil { removed = true }
        for (k, v) in json {
            if var child = v as? [String: Any] {
                if stripKey(key, from: &child) { json[k] = child; removed = true }
            }
        }
        return removed
    }

    // MARK: - A pod fault during a loan

    /// The watch reports a fault: the phone posts one urgent notice, however often it hears it.
    func testAPodFaultReportedByTheWatchIsAnnouncedOnceOnThePhone() throws {
        let controller = makeController()
        let grant = offerGrant(controller)
        let status = LoanPodStatus(timestamp: Date(), deliveredUnits: 10, reservoirLevel: nil, isSuspended: false, faultCode: nil)
        controller.handleIncoming(userInfo: try LoanMessage.takeoverComplete(TakeoverComplete(epoch: grant.epoch, firstPodStatus: status)).transportDictionary())
        waitForState(controller, .loaned)

        func report(fault: String?) throws {
            controller.handleIncoming(userInfo: try LoanMessage.statusReport(StatusReport(
                epoch: grant.epoch, mode: .closedDirect, lastDirectGlucoseAge: 60, lastEventSeq: 0,
                podFault: fault, holdsPod: true, knowsGrant: true)).transportDictionary())
            controller.queue.sync { }
        }
        try report(fault: nil)
        XCTAssertFalse(urgentNotices.contains("Pod Fault"), "no fault, no notice")

        try report(fault: "Critical Pod Fault 049")
        try report(fault: "Critical Pod Fault 049")
        XCTAssertEqual(urgentNotices.filter { $0 == "Pod Fault" }.count, 1, "one notice per fault, not one per report")
        XCTAssertTrue(urgentNoticeBodies.last?.contains("Critical Pod Fault 049") == true,
                      "the notice shows the pump's own fault text")
        XCTAssertEqual(controller.state, .loaned, "the loan itself is the watch's to end")
    }

    // MARK: - Interruption levels of loan notices

    /// Version skew can strand a loan with nobody dosing, so the warning is time-sensitive.
    func testAnUnreadableWatchMessageWarnsTimeSensitively() {
        let controller = makeController()
        controller.handleIncoming(userInfo: [LoanProtocol.userInfoKey: Data("not a loan message".utf8)])
        controller.queue.sync { }
        XCTAssertEqual(urgentNotices, ["Watch Message Unreadable"])
        XCTAssertFalse(notices.contains("Watch Message Unreadable"))
    }

    /// Nothing doses automatically until the user acts, so the reminder is time-sensitive.
    func testTheClosedLoopIsOffReminderIsTimeSensitive() throws {
        let controller = makeController()
        controller.queue.sync { controller.armOpenLoopReminder() }
        lock.lock(); let added = addedNotifications; lock.unlock()
        let reminder = try XCTUnwrap(added.first { $0.content.title == "Closed Loop Is Off" })
        XCTAssertEqual(reminder.content.interruptionLevel, .timeSensitive)
    }

    // MARK: - Glucose alarms on the wrist

    /// The grant carries the phone's glucose alert settings, so the wrist sounds the same lows.
    func testTheGrantCarriesTheGlucoseAlertSettings() throws {
        let profile = GlucoseAlertProfile.makePrimary()
        glucoseAlertSettings = GlucoseAlertSettings(profiles: [profile], activeProfileID: profile.id,
                                                    cgmProvidesOwnAlerts: false,
                                                    loopAlertsOverrideForOwnAlertingCGM: false).encoded
        let grant = offerGrant(makeController())
        XCTAssertEqual(GlucoseAlertSettings(encoded: grant.glucoseAlertSettings)?.profiles, [profile])
    }

    /// The grant carries the phone's last 24 h of overrides; an early end rides in the duration.
    func testTheGrantCarriesTheLastDaysOverrides() throws {
        let now = Date()
        func override(start: Date, duration: TemporaryScheduleOverride.Duration, end: End = .natural) -> TemporaryScheduleOverride {
            TemporaryScheduleOverride(context: .custom,
                                      settings: TemporaryPresetSettings(unit: .milligramsPerDeciliter, targetRange: nil,
                                                                        insulinNeedsScaleFactor: 0.5),
                                      startDate: start, duration: duration, enactTrigger: .local, syncIdentifier: UUID(),
                                      actualEnd: end)
        }
        let ended = override(start: now.addingTimeInterval(-.hours(5)), duration: .finite(.hours(3)),
                             end: .early(now.addingTimeInterval(-.hours(3))))
        let deleted = override(start: now.addingTimeInterval(-.hours(2)), duration: .finite(.hours(1)), end: .deleted)
        let active = override(start: now.addingTimeInterval(-.hours(1)), duration: .indefinite)
        phoneOverrideHistory = [ended, deleted, active]

        let grant = offerGrant(makeController())

        let carried = try XCTUnwrap(grant.overrideHistory, "a current phone always sends the field")
        XCTAssertEqual(carried.map(\.syncIdentifier), [ended.syncIdentifier, active.syncIdentifier], "a deleted one is left out")
        XCTAssertEqual(carried[0].scheduledEndDate.timeIntervalSince(ended.actualEndDate), 0, accuracy: 0.001,
                       "the early end, folded in because the raw form drops it")
        XCTAssertEqual(carried[1].duration, .indefinite)
        XCTAssertEqual(try XCTUnwrap(overrideHistoryAskedFrom).timeIntervalSince(now), -.hours(24), accuracy: 60)
    }

    /// The grant carries the phone's settings history for the last 24 h, up to the grant.
    func testTheGrantCarriesTheLastDaysSettingsHistory() throws {
        let now = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded())
        let mgdl = LoopUnit.milligramsPerDeciliter
        let history = LoanSettingsHistory(
            basal: [AbsoluteScheduleValue(startDate: now.addingTimeInterval(-.hours(24)), endDate: now, value: 0.8)],
            sensitivity: [AbsoluteScheduleValue(startDate: now.addingTimeInterval(-.hours(24)), endDate: now, value: LoopQuantity(unit: mgdl, doubleValue: 40))],
            carbRatio: [AbsoluteScheduleValue(startDate: now.addingTimeInterval(-.hours(24)), endDate: now, value: 8)],
            targetRange: [])
        phoneSettingsHistory = history

        let grant = offerGrant(makeController())

        XCTAssertEqual(grant.settingsHistory, history)
        let window = try XCTUnwrap(settingsHistoryAskedFor)
        XCTAssertEqual(window.duration, .hours(24), accuracy: 1)
        XCTAssertEqual(window.end.timeIntervalSinceNow, 0, accuracy: 60, "up to the grant")
    }

    /// The active override and the schedules ride in the grant's own fields; the settings blob
    /// (`LoopSettings.rawValue`) carries neither.
    func testTheGrantCarriesTheActiveOverrideInItsOwnField() throws {
        let exercise = TemporaryScheduleOverride(context: .custom,
                                                 settings: TemporaryPresetSettings(unit: .milligramsPerDeciliter,
                                                                                   targetRange: DoubleRange(minValue: 140, maxValue: 160),
                                                                                   insulinNeedsScaleFactor: 0.6),
                                                 startDate: Date().addingTimeInterval(-.minutes(5)), duration: .finite(.hours(1)),
                                                 enactTrigger: .local, syncIdentifier: UUID())
        phoneScheduleOverride = exercise

        let grant = offerGrant(makeController())

        let raw = try XCTUnwrap(grant.activeOverrideRaw, "the active override rides in its own field")
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: raw, options: [], format: nil) as? TemporaryScheduleOverride.RawValue)
        let carried = try XCTUnwrap(TemporaryScheduleOverride(rawValue: plist))
        XCTAssertEqual(carried.syncIdentifier, exercise.syncIdentifier, "identity, so both devices agree on which override")
        XCTAssertEqual(carried.settings.effectiveInsulinNeedsScaleFactor, 0.6, accuracy: 0.001)
        XCTAssertEqual(carried.settings.targetRange?.lowerBound.doubleValue(for: .milligramsPerDeciliter) ?? 0, 140, accuracy: 0.1)

        let settingsPlist = try XCTUnwrap(PropertyListSerialization.propertyList(from: grant.therapySettingsRaw, options: [], format: nil) as? LoopSettings.RawValue)
        XCTAssertNil(LoopSettings(rawValue: settingsPlist)?.basalRateSchedule, "the settings blob drops the schedules")
        let supplementData = try XCTUnwrap(grant.therapySettingsSupplementRaw)
        let supplement = try XCTUnwrap(PropertyListSerialization.propertyList(from: supplementData, options: [], format: nil) as? [String: Any])
        XCTAssertNotNil(supplement["basalRateSchedule"], "the supplement carries them")
    }

    /// End to end: an override set on the phone, a loan, a wrist clear at a known time, the
    /// hand-back an hour later. The phone's history ends the override at the clear.
    @MainActor
    func testAWristClearEndsThePhonesOverrideAtTheClearNotAtTheHandback() throws {
        let presets = TemporaryPresetsManager(settingsProvider: MockSettingsProvider(settings: StoredSettings()),
                                              presetHistory: TemporaryScheduleOverrideHistory())
        let start = Date().addingTimeInterval(-.hours(2))
        let exercise = TemporaryScheduleOverride(context: .custom,
                                                 settings: TemporaryPresetSettings(unit: .milligramsPerDeciliter, targetRange: nil,
                                                                                   insulinNeedsScaleFactor: 0.5),
                                                 startDate: start, duration: .indefinite, enactTrigger: .local, syncIdentifier: UUID())
        presets.scheduleOverride = exercise
        phoneScheduleOverride = exercise

        let controller = makeController()
        let grant = establishLoan(controller)

        let clearedAt = Date().addingTimeInterval(-.hours(1))
        let clear = LoanEvent(id: UUID(), seq: 1, provenance: .confirmed,
                              record: .overrideChange(nil, at: clearedAt), loggedAt: clearedAt)
        let ackSent = expectSend()
        controller.handleIncoming(userInfo: try LoanMessage.handbackOffer(HandbackOffer(
            epoch: grant.epoch, handedBackAt: Date(), finalStatus: nil, odometer: nil,
            events: [clear], tombstones: [], recovered: false)).transportDictionary())
        wait(for: [ackSent], timeout: 5)

        // The production setter, applied on main as the wiring's closure applies it.
        lock.lock(); let changes = appliedOverrideChanges; lock.unlock()
        XCTAssertEqual(changes.count, 1, "the clear is applied once")
        for change in changes { presets.setScheduleOverride(change.override, changedAt: change.changedAt) }

        XCTAssertNil(presets.scheduleOverride, "the phone no longer runs the override")
        let recorded = try XCTUnwrap(presets.presetHistory.getOverrideHistory(startDate: start.addingTimeInterval(-60), endDate: Date()).first)
        XCTAssertEqual(recorded.syncIdentifier, exercise.syncIdentifier)
        XCTAssertEqual(recorded.actualEndDate.timeIntervalSince(clearedAt), 0, accuracy: 0.01,
                       "ended when the wrist cleared it, not an hour later at the hand-back")
    }

    /// The wiring's apply, called from the controller's queue, runs on main, in call order; until
    /// it does, the change is visible as unapplied, which is what the controller's next read sees.
    @MainActor
    func testAWristOverrideIsAppliedOnMainInCallOrder() throws {
        let presets = TemporaryPresetsManager(settingsProvider: MockSettingsProvider(settings: StoredSettings()),
                                              presetHistory: TemporaryScheduleOverrideHistory())
        let observer = MainThreadPresetObserver(expectation(description: "cleared"))
        presets.addTemporaryPresetObserver(observer)
        let setAt = Date().addingTimeInterval(-.hours(1))
        let clearedAt = Date().addingTimeInterval(-.minutes(30))
        let exercise = TemporaryScheduleOverride(context: .custom,
                                                 settings: TemporaryPresetSettings(unit: .milligramsPerDeciliter, targetRange: nil,
                                                                                   insulinNeedsScaleFactor: 0.5),
                                                 startDate: setAt, duration: .indefinite, enactTrigger: .local, syncIdentifier: UUID())

        let unapplied = Locked<[TemporaryScheduleOverride?]>([])
        DispatchQueue.global().sync {
            presets.setScheduleOverrideOnMain(exercise, changedAt: setAt, unapplied: unapplied)
            XCTAssertEqual(unapplied.value.last, .some(exercise), "the set, before main has run")
            presets.setScheduleOverrideOnMain(nil, changedAt: clearedAt, unapplied: unapplied)
            XCTAssertEqual(unapplied.value.last, .some(nil), "then the clear")
        }
        XCTAssertTrue(observer.calls.isEmpty, "nothing is applied on the calling queue")
        waitForExpectations(timeout: 5)

        XCTAssertEqual(observer.calls, ["activated on main", "deactivated on main"])
        XCTAssertTrue(unapplied.value.isEmpty, "both applied")
        let recorded = try XCTUnwrap(presets.presetHistory.getOverrideHistory(startDate: setAt.addingTimeInterval(-60), endDate: Date()).first)
        XCTAssertEqual(recorded.actualEndDate.timeIntervalSince(clearedAt), 0, accuracy: 0.01)
    }

    // MARK: - The outbound handover is two states, not one

    /// "Taking over…" from grant until the watch confirms, then "Pod on Watch".
    func testTakeoverInProgressIsTrueOnlyBetweenGrantAndConfirmation() throws {
        let controller = makeController()
        XCTAssertFalse(controller.isPodTakeoverInProgress, "no loan, no handover")

        let grantSent = expectSend()
        controller.handleIncoming(userInfo: try LoanMessage.request(LoanRequest(watchBuild: "t")).transportDictionary())
        wait(for: [grantSent], timeout: 5)
        guard case .grant(let grant)? = lastSent() else { return XCTFail("expected a grant") }

        XCTAssertTrue(controller.isPodTakeoverInProgress, "grant is out, watch has not confirmed — 'Taking over…'")
        XCTAssertTrue(controller.podIsOnLoan, "still true here, which is exactly why the tile needed a second predicate")

        let status = LoanPodStatus(timestamp: Date(), deliveredUnits: 10, reservoirLevel: nil, isSuspended: false, faultCode: nil)
        controller.handleIncoming(userInfo: try LoanMessage.takeoverComplete(TakeoverComplete(epoch: grant.epoch, firstPodStatus: status)).transportDictionary())
        waitForState(controller, .loaned)

        XCTAssertFalse(controller.isPodTakeoverInProgress, "confirmed — the tile may now say 'Pod on Watch'")
        XCTAssertTrue(controller.podIsOnLoan)
    }
}

// MARK: - The dead-watch reclaim audit
// The hand-back audit applied to a force reclaim: dosing held for the verdict, urgent alerts, and
// unexplained insulin booked as a placeholder the watch's return retires.
extension PodLoanPhoneControllerTests {

    /// The watch delivered 2.5 U it never streamed, then died. The odometer knows. The phone
    /// must open the loop, alert urgently, and book the gap under a deterministic identity.
    func testForceReclaimWithUnstreamedInsulinOpensLoopAndBooksTheGap() throws {
        let controller = makeController()
        let grant = establishLoan(controller)   // takeoverComplete banks deliveredAtStart = 10

        MockPumpManager.testOdometer = 12.5     // 2.5 U the phone has no records for

        controller.forceReclaimToOwner(reason: "test: watch dead")
        waitForState(controller, .owner)
        waitUntil(timeout: 5, "force verdict") { self.diagMatching("reconcile[FORCE-RECLAIM]") != nil }
        waitUntil(timeout: 5, "gap booked") { self.lock.lock(); defer { self.lock.unlock() }; return !self.bookedGapDoses.isEmpty }

        lock.lock()
        let opened = openLoopCalls
        let urgent = urgentNotices
        let booked = bookedGapDoses
        lock.unlock()

        XCTAssertEqual(opened, 1, "unexplained insulin beyond +0.20 U opens the loop")
        XCTAssertTrue(urgent.contains { $0.contains("Unverified Insulin") },
                      "the alert rides the URGENT channel — the watch is dead, the phone must get attention")
        XCTAssertEqual(booked.count, 1, "the gap books as a placeholder bolus")
        XCTAssertEqual(booked.first?.deliveredUnits ?? 0, 2.5, accuracy: 0.1, "booked amount = the odometer gap")
        XCTAssertEqual(booked.first?.syncIdentifier, "LOAN-AUDIT-GAP-e\(grant.epoch)",
                       "deterministic identity, so the watch's return can retire it")
        XCTAssertEqual(booked.first?.manuallyEntered, true,
                       "manual-entry namespace — pump events overwrite syncIdentifier with hex(raw); manual doses keep it")
    }

    /// The clean case: the odometer matches the books. Dosing resumes, nothing books, no alarm.
    func testForceReclaimWithMatchingOdometerResumesQuietly() throws {
        let controller = makeController()
        establishLoan(controller)

        MockPumpManager.testOdometer = 10.05    // within the 0.20 bound of expected ≈ 0

        controller.forceReclaimToOwner(reason: "test: watch dead, but books are complete")
        waitForState(controller, .owner)
        waitUntil(timeout: 5, "clean verdict") { self.diagMatching("force-reclaim audit CLEAN") != nil }

        lock.lock()
        let opened = openLoopCalls
        let booked = bookedGapDoses
        let resumed = pauseCalls.contains(false)
        lock.unlock()

        XCTAssertEqual(opened, 0, "a clean audit does not open the loop")
        XCTAssertTrue(booked.isEmpty, "nothing to book")
        XCTAssertTrue(resumed, "automatic dosing resumes on the clean verdict")
    }

    /// With the pod unreachable, the gate the phone loop reads stays shut after the link is taken back.
    func testDosingIsHeldUntilTheAuditVerdictArrives() throws {
        let controller = makeController()
        establishLoan(controller)
        MockPumpManager.testOdometer = 12.5

        lock.lock(); connectionReady = false; lock.unlock()   // the pod is not back yet

        controller.forceReclaimToOwner(reason: "test: watch dead, pod not yet reachable")
        waitForState(controller, .owner)
        settle()

        XCTAssertFalse(MockPumpManager.testConnectionReleased, "the link is the phone's again, so the release no longer gates")
        XCTAssertTrue(controller.holdsAutomaticDosing, "no verdict, no automatic dosing — 'cannot verify' must never become 'assume fine'")
        lock.lock()
        let resumedEarly = pauseCalls.contains(false)
        lock.unlock()
        XCTAssertFalse(resumedEarly, "nor are the loop-not-running reminders re-armed")

        lock.lock(); connectionReady = true; lock.unlock()    // the pod comes back
        waitUntil(timeout: 8, "verdict after pod returns") { !controller.holdsAutomaticDosing }
        lock.lock(); let opened = openLoopCalls; let resumed = pauseCalls.contains(false); lock.unlock()
        XCTAssertEqual(opened, 1, "and the verdict still opens on the unexplained 2.5 U")
        XCTAssertTrue(resumed)
    }

    /// The returning watch's real records replace the placeholder.
    func testReturningWatchRetiresTheGapBooking() throws {
        let controller = makeController()
        let grant = establishLoan(controller)
        MockPumpManager.testOdometer = 12.5

        controller.forceReclaimToOwner(reason: "test: watch dead")
        waitForState(controller, .owner)
        waitUntil(timeout: 5, "gap booked") { self.lock.lock(); defer { self.lock.unlock() }; return !self.bookedGapDoses.isEmpty }

        // The watch returns and offers the events it never streamed.
        let realTail = tempEvent(seq: 1, rate: 5.0, start: Date().addingTimeInterval(-.minutes(30)), durationMinutes: 30)
        controller.handleIncoming(userInfo: try LoanMessage.handbackOffer(
            HandbackOffer(epoch: grant.epoch, handedBackAt: Date(), finalStatus: nil, odometer: nil,
                          events: [realTail], tombstones: [], recovered: true)).transportDictionary())

        waitUntil(timeout: 5, "gap retired") { self.lock.lock(); defer { self.lock.unlock() }; return !self.deletedGapSyncs.isEmpty }
        // The notice is sent after the delete returns, from the controller's queue. Good news,
        // so the normal channel: IOB and COB are now right.
        waitUntil(timeout: 5, "the user is told their numbers changed, and why") {
            self.lock.lock(); defer { self.lock.unlock() }
            return self.notices.contains { $0.contains("Watch Records Recovered") }
        }
        lock.lock()
        XCTAssertFalse(urgentNotices.contains { $0.contains("Watch Records Recovered") }, "not time-sensitive")
        lock.unlock()

        lock.lock()
        let deleted = deletedGapSyncs
        lock.unlock()

        XCTAssertEqual(deleted, ["LOAN-AUDIT-GAP-e\(grant.epoch)"], "the placeholder retires by its deterministic identity")
        waitUntil(timeout: 5, "state cleared") {
            controller.persisted.gapBooking == nil
        }
    }

    /// A redelivered pre-death offer explains nothing new and does not retire the placeholder.
    func testRedeliveredPreDeathOfferDoesNotRetireTheGap() throws {
        let controller = makeController()
        let grant = establishLoan(controller)

        // The watch streams ONE event, then dies. The salvage commits it.
        let streamed = tempEvent(seq: 1, rate: 2.0, start: Date().addingTimeInterval(-.minutes(20)), durationMinutes: 10)
        controller.handleIncoming(userInfo: try LoanMessage.doseRecordBatch(
            DoseRecordBatch(epoch: grant.epoch, events: [streamed], tombstones: [])).transportDictionary())
        settle()

        MockPumpManager.testOdometer = 13.0     // well beyond what the streamed temp explains

        controller.forceReclaimToOwner(reason: "test: watch dead")
        waitForState(controller, .owner)
        waitUntil(timeout: 5, "gap booked") { self.lock.lock(); defer { self.lock.unlock() }; return !self.bookedGapDoses.isEmpty }

        // WC redelivers the PRE-death offer — the same already-committed event, nothing new.
        controller.handleIncoming(userInfo: try LoanMessage.handbackOffer(
            HandbackOffer(epoch: grant.epoch, handedBackAt: Date(), finalStatus: nil, odometer: nil,
                          events: [streamed], tombstones: [], recovered: true)).transportDictionary())
        settle()

        lock.lock(); let deleted = deletedGapSyncs; lock.unlock()
        XCTAssertTrue(deleted.isEmpty, "an offer that commits no NEW doses explains nothing — the placeholder must stand")
        XCTAssertNotNil(controller.persisted.gapBooking)
    }

    /// A launch retries the placeholder delete only when it failed after the watch's records
    /// committed (`deleteFailedAfterRecords`).
    func testPersistedGapDeleteRetriesOnFreshLaunch() throws {
        saveState { $0.gapBooking = .init(epoch: 7, units: 1.75, bookedAt: Date(), deleteFailedAfterRecords: true) }

        // Held for the test's duration — init's retry runs on a `[weak self]` queue.async, so an
        // unretained controller can deallocate before its own retry fires.
        let controller = makeController()   // simulates the next app launch finding stale gap state
        _ = controller

        waitUntil(timeout: 5, "launch retry succeeds") {
            controller.persisted.gapBooking == nil
        }
        lock.lock()
        let deleted = deletedGapSyncs
        lock.unlock()
        XCTAssertEqual(deleted, ["LOAN-AUDIT-GAP-e7"], "retried against the PERSISTED epoch, no offer involved")
    }

    /// Launch-time store work waits for protected data (reboot before first unlock).
    func testLaunchStoreWorkWaitsForProtectedData() throws {
        saveState { $0.gapBooking = .init(epoch: 9, units: 1.0, bookedAt: Date(), deleteFailedAfterRecords: true) }
        var unlock: (() -> Void)?
        let controller = makeController(whenProtectedDataAvailable: { work in unlock = work })
        _ = controller

        // Locked: the retry must not have touched the store.
        Thread.sleep(forTimeInterval: 0.3)
        lock.lock(); let attemptsWhileLocked = deletedGapSyncs.count; lock.unlock()
        XCTAssertEqual(attemptsWhileLocked, 0, "store work ran during the pre-first-unlock window")
        XCTAssertNotNil(controller.persisted.gapBooking)

        // First unlock: the deferred work runs and the retry completes.
        unlock?()
        waitUntil(timeout: 5, "deferred retry runs at unlock") {
            self.lock.lock(); defer { self.lock.unlock() }; return self.deletedGapSyncs == ["LOAN-AUDIT-GAP-e9"]
        }
    }

    /// The failure side of the same path: launch retry fails again, state must survive for yet
    /// another attempt rather than being dropped or silently swallowed.
    func testPersistedGapDeleteThatFailsAgainAtLaunchKeepsState() throws {
        saveState { $0.gapBooking = .init(epoch: 3, units: 0.9, bookedAt: Date(), deleteFailedAfterRecords: true) }
        lock.lock(); gapDeleteSucceeds = false; lock.unlock()

        let controller = makeController()
        _ = controller

        waitUntil(timeout: 5, "launch retry attempted") { self.lock.lock(); defer { self.lock.unlock() }; return !self.deletedGapSyncs.isEmpty }
        XCTAssertNotNil(controller.persisted.gapBooking,
                        "still failing — state must survive for the NEXT launch or offer, not vanish")
    }

    /// A placeholder nothing explained survives launch: the insulin is still in the body.
    func testPersistedGapWithoutRecordsSurvivesLaunch() throws {
        saveState { $0.gapBooking = .init(epoch: 11, units: 0.85, bookedAt: Date()) }

        let controller = makeController()   // the next app launch
        _ = controller

        // Give init's queue.async retry the same room the other launch tests give it; the
        // assertion is that nothing happens in that window.
        let settled = expectation(description: "launch settled")
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) { settled.fulfill() }
        wait(for: [settled], timeout: 5)

        lock.lock(); let deleted = deletedGapSyncs; lock.unlock()
        XCTAssertTrue(deleted.isEmpty, "an unexplained placeholder must NOT be deleted at launch — the insulin is still real")
        XCTAssertNotNil(controller.persisted.gapBooking,
                        "the booking must persist so it keeps standing until the watch returns or it decays out")
    }

    /// A failed placeholder delete must be loud and keep its state — a silent failure here is a
    /// double-counted IOB (placeholder + real records both in the books).
    func testFailedGapDeleteKeepsStateAndSaysSo() throws {
        let controller = makeController()
        let grant = establishLoan(controller)
        MockPumpManager.testOdometer = 12.5

        controller.forceReclaimToOwner(reason: "test: watch dead")
        waitForState(controller, .owner)
        waitUntil(timeout: 5, "gap booked") { self.lock.lock(); defer { self.lock.unlock() }; return !self.bookedGapDoses.isEmpty }

        lock.lock(); gapDeleteSucceeds = false; lock.unlock()

        let realTail = tempEvent(seq: 1, rate: 4.0, start: Date().addingTimeInterval(-.minutes(25)), durationMinutes: 25)
        controller.handleIncoming(userInfo: try LoanMessage.handbackOffer(
            HandbackOffer(epoch: grant.epoch, handedBackAt: Date(), finalStatus: nil, odometer: nil,
                          events: [realTail], tombstones: [], recovered: true)).transportDictionary())

        waitUntil(timeout: 5, "failure logged") { self.diagMatching("gap DELETE FAILED") != nil }
        XCTAssertNotNil(controller.persisted.gapBooking,
                        "state survives a failed delete, so the next offer retries it")
    }

    // MARK: - Reclaim ladder

    /// Every revoke the controller has sent so far. The ladder's whole contract is "two attempts,
    /// then force", and this is the only way to state the "two" half.
    private func revokeCount() -> Int {
        lock.lock(); defer { lock.unlock() }
        return sent.filter { if case .revoke = $0 { return true } else { return false } }.count
    }

    /// Live branch: the ladder arms live deadlines and forces only after two attempts.
    func testLiveBranchArmsLiveDeadlinesAndForcesOnlyAfterTwoAttempts() throws {
        let controller = makeController(lastWatchContact: { Date().addingTimeInterval(-30) })
        establishLoan(controller)
        let ladder = ReclaimLadderRecorder()
        ladder.install(on: controller)

        controller.reclaimNow()
        waitUntil(timeout: 5, "ladder armed") { ladder.armed.count == 2 }

        XCTAssertEqual(ladder.armed.map(\.label), ["reclaim-resend", "reclaim-force"])
        XCTAssertEqual(ladder.armed.map(\.delay), [10, 25],
                       "a watch heard from inside one log-pulse period gets the live budget, not the dead one")
        XCTAssertEqual(revokeCount(), 1, "the tap's own revoke is the only one until the first deadline")
        XCTAssertEqual(controller.reclaimProgress?.phase, .draining)
        XCTAssertNotNil(controller.reclaimProgress?.fraction, "the handover draws a bar now — the sweep is retired")
        XCTAssertEqual(controller.reclaimProgress.map { $0.expectedBy.timeIntervalSince($0.startedAt) } ?? 0, 10,
                       accuracy: 0.5, "the published deadline is the drain promise, past which the label concedes")
        XCTAssertNotNil(diagMatching("reclaim ladder LIVE"), "the branch and its evidence are in the log")

        ladder.fire("reclaim-resend")
        XCTAssertEqual(revokeCount(), 2, "the second attempt is a resend, not a force")
        XCTAssertEqual(controller.state, .reclaimPending, "an attempt is not a verdict")

        ladder.fire("reclaim-force")
        waitForState(controller, .owner)
        XCTAssertEqual(revokeCount(), 2, "two attempts is the whole budget")
    }

    /// The handover bar fills to the 10 s drain promise, then concedes at cap.
    func testLiveHandoverBarConcedesAtTheDrainPromise() throws {
        let controller = makeController(lastWatchContact: { [weak self] in (self?.clock ?? Date()).addingTimeInterval(-30) },
                                        now: { [weak self] in self?.clock ?? Date() })
        establishLoan(controller)
        let ladder = ReclaimLadderRecorder()
        ladder.install(on: controller)

        controller.reclaimNow()
        waitUntil(timeout: 5, "ladder armed") { ladder.armed.count == 2 }

        clock = clock.addingTimeInterval(5)        // halfway through the promise
        let mid = try XCTUnwrap(controller.reclaimProgress)
        XCTAssertEqual(mid.phase, .draining)
        XCTAssertEqual(mid.fraction ?? -1, 0.5, accuracy: 0.001, "the bar fills against the promise")

        clock = clock.addingTimeInterval(6)        // 11 s: promise expired, force not yet due
        let conceded = try XCTUnwrap(controller.reclaimProgress)
        XCTAssertEqual(conceded.phase, .watchNotAnswering, "past the promise the label concedes")
        XCTAssertEqual(conceded.fraction ?? -1, 0.95, accuracy: 0.001, "bar holds at cap, not restarted")
        XCTAssertEqual(conceded.expectedBy.timeIntervalSince(conceded.startedAt), 25, accuracy: 0.5,
                       "the republished deadline is the force rung — the event that resolves this")
        XCTAssertEqual(conceded.elapsed, 11, accuracy: 0.001, "the seconds keep counting the whole wait")
    }

    /// Dead branch (watch silent for 12 min): one revoke, force at zero delay, no resend rung.
    func testDeadBranchForcesImmediatelyWithoutWaitingOnTheWatch() throws {
        let controller = makeController(watchReachable: { false },
                                        lastWatchContact: { Date().addingTimeInterval(-.minutes(12)) })
        establishLoan(controller)
        let ladder = ReclaimLadderRecorder()
        ladder.install(on: controller)

        controller.reclaimNow()
        waitUntil(timeout: 5, "force armed") { ladder.armed.count == 1 }

        XCTAssertEqual(ladder.armed.map(\.label), ["reclaim-force"], "no resend rung — nothing can answer it")
        XCTAssertEqual(ladder.armed.first?.delay ?? -1, 0, accuracy: 0.001, "the force waits for nothing")
        XCTAssertEqual(revokeCount(), 1, "the tap's own revoke still goes out, fire-and-forget")
        XCTAssertEqual(controller.reclaimProgress?.phase, .forcing,
                       "the tile says what is actually happening from the first paint")
        XCTAssertNotNil(diagMatching("reclaim ladder DEAD"))
        XCTAssertNotNil(diagMatching("reachable 0"), "the evidence that chose the branch is logged, not just the verdict")
        XCTAssertNotNil(diagMatching("force NOW"), "the zero-wait plan is on the record, not implied")

        ladder.fire("reclaim-force")
        waitForState(controller, .owner)
        XCTAssertEqual(revokeCount(), 1, "nothing ever resends on the dead branch")
    }

    /// A post-force settle runs against its own 15 s promise and holds at cap.
    func testForcedSettleRunsOneStageAgainstTheForcedPromise() throws {
        let controller = makeController(watchReachable: { false },
                                        lastWatchContact: { nil },
                                        now: { [weak self] in self?.clock ?? Date() })
        establishLoan(controller)
        connectionReady = false                    // nothing verifies — the settle stays open
        let ladder = ReclaimLadderRecorder()
        ladder.install(on: controller)

        controller.reclaimNow()
        waitUntil(timeout: 5, "force armed") { ladder.armed.count == 1 }
        ladder.fire("reclaim-force")
        waitForState(controller, .owner)

        let early = try XCTUnwrap(controller.reclaimProgress,
                                  "a forced settle publishes progress like any other")
        XCTAssertEqual(early.phase, .forceReclaimingPod)
        // ONE promise for both settle flavors — the label differs,
        // the physics no longer do.
        XCTAssertEqual(early.expectedBy.timeIntervalSince(early.startedAt), 10, accuracy: 0.5)

        clock = clock.addingTimeInterval(5)        // halfway through the promise
        let mid = try XCTUnwrap(controller.reclaimProgress)
        XCTAssertEqual(mid.phase, .forceReclaimingPod,
                       "no re-baseline mid-force — one operation, one timer")
        XCTAssertEqual(mid.fraction ?? -1, 0.5, accuracy: 0.01)

        clock = clock.addingTimeInterval(15)       // 20 s: past the promise
        let over = try XCTUnwrap(controller.reclaimProgress)
        XCTAssertEqual(over.phase, .forceReclaimingPod)
        XCTAssertEqual(over.fraction ?? -1, 0.95, accuracy: 0.001,
                       "wrong-is-fine means cap-and-hold, not restart")
    }

    /// A drain before the first deadline cancels both rungs.
    func testDrainBeforeTheFirstDeadlineCancelsTheLadder() throws {
        let controller = makeController(lastWatchContact: { Date().addingTimeInterval(-30) })
        let grant = establishLoan(controller)
        let ladder = ReclaimLadderRecorder()
        ladder.install(on: controller)

        controller.reclaimNow()
        waitUntil(timeout: 5, "ladder armed") { ladder.armed.count == 2 }
        let revokesAtTap = revokeCount()

        // The watch answers the revoke the way the protocol says: a recovered final offer.
        let ackSent = expectSend()
        let event = makeEvent(seq: 1, units: 0.6, at: Date().addingTimeInterval(-.minutes(3)))
        controller.handleIncoming(userInfo: try LoanMessage.handbackOffer(
            HandbackOffer(epoch: grant.epoch, handedBackAt: Date(), finalStatus: nil, odometer: nil,
                          events: [event], tombstones: [], recovered: true)).transportDictionary())
        wait(for: [ackSent], timeout: 5)
        waitForState(controller, .owner)

        XCTAssertTrue(ladder.isCancelled("reclaim-resend"), "a completed drain kills the pending resend")
        XCTAssertTrue(ladder.isCancelled("reclaim-force"), "and the force with it")
        waitUntil(timeout: 5, "reclaim progress cleared") { controller.reclaimProgress == nil }
        XCTAssertNil(controller.reclaimProgress, "nothing left to draw a determinate bar for")

        // Belt and braces: even if a rung reached its deadline anyway, its guards refuse.
        ladder.fire("reclaim-resend")
        ladder.fire("reclaim-force")
        XCTAssertEqual(revokeCount(), revokesAtTap, "no revoke may go out after the loan is over")
        XCTAssertEqual(controller.state, .owner)
    }

    /// A reachability wake re-sends the revoke and spends the second attempt.
    func testReachabilityResendOnALiveLadderSpendsTheSecondAttempt() throws {
        let controller = makeController(lastWatchContact: { Date().addingTimeInterval(-10) })
        establishLoan(controller)
        let ladder = ReclaimLadderRecorder()
        ladder.install(on: controller)

        controller.reclaimNow()
        waitUntil(timeout: 5, "ladder armed") { ladder.armed.count == 2 }
        XCTAssertEqual(revokeCount(), 1)

        controller.watchDidBecomeReachable()
        waitUntil(timeout: 5, "revoke resent") { self.revokeCount() == 2 }

        ladder.fire("reclaim-resend")
        XCTAssertEqual(revokeCount(), 2, "the wake-up resend spent the budget — the rung must not buy a third")
        XCTAssertEqual(controller.state, .reclaimPending)
    }

    // MARK: - The BLE settle is the wait the bar draws

    /// A watch-initiated hand-back publishes settle progress.
    func testWatchInitiatedHandbackPublishesSettleProgress() throws {
        let controller = makeController(now: { [weak self] in self?.clock ?? Date() })
        let grant = establishLoan(controller)
        let ladder = ReclaimLadderRecorder()
        ladder.install(on: controller)
        connectionReady = false            // the pod's link is not back, so the settle stays open

        let ackSent = expectSend()
        let event = makeEvent(seq: 1, units: 0.4, at: clock.addingTimeInterval(-.minutes(3)))
        controller.handleIncoming(userInfo: try LoanMessage.handbackOffer(
            HandbackOffer(epoch: grant.epoch, handedBackAt: clock, finalStatus: nil, odometer: nil,
                          events: [event], tombstones: [], recovered: false)).transportDictionary())
        wait(for: [ackSent], timeout: 5)
        waitForState(controller, .owner)

        XCTAssertTrue(ladder.armed.isEmpty, "the watch ended this session — no tap, so no ladder")
        let atStart = try XCTUnwrap(controller.reclaimProgress,
                                    "a watch-initiated hand-back must publish progress for its settle")
        XCTAssertEqual(atStart.phase, .reconnectingToPod)
        XCTAssertEqual(atStart.fraction ?? -1, 0, accuracy: 0.001, "anchored where the settle began")
        XCTAssertEqual(atStart.expectedBy.timeIntervalSince(atStart.startedAt), 10, accuracy: 0.001,
                       "the settle runs to its own promise, not to the 5-minute ceiling")

        clock = clock.addingTimeInterval(6)
        let later = try XCTUnwrap(controller.reclaimProgress)
        XCTAssertEqual(later.phase, .reconnectingToPod)
        XCTAssertEqual(later.fraction ?? -1, 0.6, accuracy: 0.001, "the bar moves with the clock")
        XCTAssertEqual(later.elapsed, 6, accuracy: 0.001, "and so do the label's ticking seconds")
        XCTAssertGreaterThan(later.fraction ?? -1, atStart.fraction ?? 0)
    }

    /// A tapped reclaim keeps its phase from drain through settle without going nil.
    func testTappedReclaimCarriesThePhaseFromDrainThroughSettleWithoutGoingNil() throws {
        let controller = makeController(lastWatchContact: { [weak self] in (self?.clock ?? Date()).addingTimeInterval(-30) },
                                        now: { [weak self] in self?.clock ?? Date() })
        let grant = establishLoan(controller)
        let ladder = ReclaimLadderRecorder()
        ladder.install(on: controller)
        connectionReady = false

        controller.reclaimNow()
        waitUntil(timeout: 5, "ladder armed") { ladder.armed.count == 2 }
        let drain = try XCTUnwrap(controller.reclaimProgress)
        XCTAssertEqual(drain.phase, .draining)
        XCTAssertNotNil(drain.fraction, "the handover fills against the drain promise — the sweep is retired")

        // Park the commit so `.reconciling` is observable at all: completed inline, the whole
        // drain-to-settle crossing happens inside one queue block and nothing can sample it.
        holdPumpEventWrites = true
        let event = makeEvent(seq: 1, units: 0.6, at: clock.addingTimeInterval(-.minutes(3)))
        controller.handleIncoming(userInfo: try LoanMessage.handbackOffer(
            HandbackOffer(epoch: grant.epoch, handedBackAt: clock, finalStatus: nil, odometer: nil,
                          events: [event], tombstones: [], recovered: true)).transportDictionary())
        waitUntil(timeout: 5, "commit parked") {
            self.lock.lock(); defer { self.lock.unlock() }; return self.heldPumpEventWrite != nil
        }

        XCTAssertEqual(controller.state, .reconciling)
        let midWrite = try XCTUnwrap(controller.reclaimProgress,
                                     "the reclaim must stay described for the length of the write")
        XCTAssertEqual(midWrite.phase, .draining, "the tap's own branch still names this wait")
        XCTAssertNotNil(midWrite.fraction, "and the bar keeps filling across the store write")

        let ackSent = expectSend()
        holdPumpEventWrites = false
        releaseHeldPumpEventWrite()
        wait(for: [ackSent], timeout: 5)
        waitForState(controller, .owner)

        let settling = try XCTUnwrap(controller.reclaimProgress,
                                     "the settle is the half the user waits through")
        XCTAssertEqual(settling.phase, .reconnectingToPod)
        XCTAssertNotNil(settling.fraction, "and the only half that gets a bar")
        XCTAssertEqual(settling.expectedBy.timeIntervalSince(settling.startedAt), 10, accuracy: 0.001)
    }

    /// The settle promise is an expectation: the bar caps at 0.95 and holds; 5 min is the bound.
    func testSettleFractionCapsAndHoldsWhenTheSettleOverruns() throws {
        let controller = makeController(now: { [weak self] in self?.clock ?? Date() })
        let grant = establishLoan(controller)
        connectionReady = false

        let ackSent = expectSend()
        controller.handleIncoming(userInfo: try LoanMessage.handbackOffer(
            HandbackOffer(epoch: grant.epoch, handedBackAt: clock, finalStatus: nil, odometer: nil,
                          events: [], tombstones: [], recovered: false)).transportDictionary())
        wait(for: [ackSent], timeout: 5)
        waitForState(controller, .owner)
        // The phase is visible before its observer stamps the settle start; let that land first.
        controller.queue.sync {}

        clock = clock.addingTimeInterval(9.5)       // 0.95 of the 10 s promise
        let capped = try XCTUnwrap(controller.reclaimProgress)
        XCTAssertEqual(capped.phase, .reconnectingToPod)
        XCTAssertEqual(capped.fraction ?? -1, 0.95, accuracy: 0.001,
                       "the bar never reads done before the round-trip lands")

        clock = clock.addingTimeInterval(50.5)      // 60 s: deep past the promise
        let overrun = try XCTUnwrap(controller.reclaimProgress,
                                    "an overrun is still a live settle, not a cleared one")
        XCTAssertEqual(overrun.phase, .reconnectingToPod, "no slow-mode phase left to re-baseline into")
        XCTAssertEqual(overrun.fraction ?? -1, 0.95, accuracy: 0.001, "held at the cap, not restarted")
        XCTAssertEqual(overrun.elapsed, 60, accuracy: 0.001,
                       "the seconds keep climbing so a capped bar still reads as alive")

        clock = clock.addingTimeInterval(130)       // 190 s: the worst settle ever measured
        let worst = try XCTUnwrap(controller.reclaimProgress)
        XCTAssertEqual(worst.phase, .reconnectingToPod)
        XCTAssertEqual(worst.fraction ?? -1, 0.95, accuracy: 0.001)
        XCTAssertEqual(worst.elapsed, 190, accuracy: 0.001)
    }

    /// Every settle tick forces a real pod read (a cheap read returns the old lastSync); the
    /// in-flight latch keeps reads from stacking. Clock parked an hour ahead to keep the settle open.
    func testSettleForcesARealReadEveryTick() throws {
        clock = Date().addingTimeInterval(.hours(1))
        let controller = makeController(now: { [weak self] in self?.clock ?? Date() })
        let grant = establishLoan(controller)
        connectionReady = true              // the link is up, so the settle can force from tick 0

        let ackSent = expectSend()
        controller.handleIncoming(userInfo: try LoanMessage.handbackOffer(
            HandbackOffer(epoch: grant.epoch, handedBackAt: clock, finalStatus: nil, odometer: nil,
                          events: [], tombstones: [], recovered: false)).transportDictionary())
        wait(for: [ackSent], timeout: 5)
        waitForState(controller, .owner)

        waitUntil(timeout: 5, "the settle forces its first real read") {
            MockPumpManager.testForcedReadCount >= 1
        }

        // Reads must keep being real while the settle is open.
        let ticksPassed = XCTestExpectation(description: "several ticks pass")
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) { ticksPassed.fulfill() }
        wait(for: [ticksPassed], timeout: 10)
        XCTAssertGreaterThanOrEqual(MockPumpManager.testForcedReadCount, 2,
                                    "an open settle keeps doing REAL round-trips — the cheap no-radio path is what stalled 169 s in the field")
        XCTAssertTrue(controller.isReclaimSettling, "the settle is still open, so ticks are still running")

        // Drop the link so the leftover chase is a no-op for later tests.
        connectionReady = false
    }

    /// The end condition. "The pod is back" is a completed pod round-trip, not a Bluetooth state,
    /// so the bar clears on the verification and not a moment earlier.
    func testSettleProgressClearsOnceTheRoundTripVerifies() throws {
        // Real clock: verification compares the pump's lastSync with the settle start.
        let controller = makeController()
        let grant = establishLoan(controller)
        connectionReady = false

        let ackSent = expectSend()
        controller.handleIncoming(userInfo: try LoanMessage.handbackOffer(
            HandbackOffer(epoch: grant.epoch, handedBackAt: Date(), finalStatus: nil, odometer: nil,
                          events: [], tombstones: [], recovered: false)).transportDictionary())
        wait(for: [ackSent], timeout: 5)
        waitForState(controller, .owner)
        XCTAssertEqual(controller.reclaimProgress?.phase, .reconnectingToPod)

        connectionReady = true
        waitUntil(timeout: 8, "reclaim verification") { !controller.isReclaimSettling }
        XCTAssertNil(controller.reclaimProgress,
                     "a verified round-trip is the pod being home — there is nothing left to draw")
        // Background holds must balance at rest.
        lock.lock(); let begins = backgroundTaskBegins; let ends = backgroundTaskEnds; lock.unlock()
        XCTAssertGreaterThanOrEqual(begins, 1, "the reclaim held background execution for its wait")
        XCTAssertEqual(ends, begins, "every hold released once the wait resolved")
    }

    // MARK: - Request TTL (queued-channel ghosts)

    /// A request older than the TTL earns no grant; a fresh one still grants.
    func testStaleRequestIsIgnoredAndAFreshOneStillGrants() throws {
        let controller = makeController(now: { self.clock })

        controller.handleIncoming(userInfo: try LoanMessage.request(
            LoanRequest(watchBuild: "t", sentAt: clock.addingTimeInterval(-300))).transportDictionary())

        // The rejection is a silent return; stillness is the assertion.
        usleep(400_000)
        XCTAssertEqual(controller.state, .owner, "a stale request must not move the state machine")
        lock.lock(); let sentDuringGhost = sent; lock.unlock()
        XCTAssertTrue(sentDuringGhost.isEmpty, "a stale request earns NOTHING — no grant, no denial: \(sentDuringGhost)")

        try establishLoan(controller)   // fresh (nil-sentAt) request still grants — liveness + back-compat
    }

    // MARK: - Dormant-refresh throttle (seize credential pipe)

    /// The refresh throttle stamps at enqueue, so a burst yields one refresh.
    func testDormantRefreshBurstYieldsOneRefresh() {
        saveState { $0.watchSupportsSeize = true }
        let controller = makeController()

        let firstRefresh = expectSend()
        for _ in 0..<5 { controller.considerDormantRefresh() }
        wait(for: [firstRefresh], timeout: 5)
        // Let any leaked assemblies reach `sent`.
        usleep(400_000)

        lock.lock()
        let refreshes = sent.filter { if case .dormantGrant = $0 { return true }; return false }
        lock.unlock()
        XCTAssertEqual(refreshes.count, 1, "one burst, one refresh — the throttle stamps at enqueue")
    }

    // MARK: - PHONE MIRROR (the minimum-deviation paradigm)

    private func seizeCredentialOutstanding() -> UUID {
        let token = UUID()
        saveState {
            $0.seizeToken = token
            $0.watchSupportsSeize = true
        }
        return token
    }

    private func futureEpochBatch(epoch: Int) throws -> [String: Any] {
        let now = Date()
        let event = LoanEvent(id: UUID(), seq: 1, provenance: .confirmed,
                              record: LoanDoseRecord(kind: .bolus, startDate: now, amount: 0.5), loggedAt: now)
        return try LoanMessage.doseRecordBatch(DoseRecordBatch(epoch: epoch, events: [event], tombstones: [])).transportDictionary()
    }

    /// A future-epoch batch at `.owner` means a loan this phone never granted: yield instead of
    /// dosing on.
    func testFutureEpochBatchAtOwnerYieldsInsteadOfDosingOn() throws {
        let token = seizeCredentialOutstanding()
        let controller = makeController()

        controller.handleIncoming(userInfo: try futureEpochBatch(epoch: 5))
        waitUntil(timeout: 5, "yield engaged") { controller.yieldingToInferredLoan }

        XCTAssertTrue(controller.podIsOnLoan, "the yielded posture IS a loan for every consumer")
        XCTAssertTrue(controller.isPodLoanedOut, "pill reads Pod on Watch")
        XCTAssertEqual(controller.state, .owner, "…while the state machine stays truthful (retro-ack needs .owner)")
        XCTAssertTrue(MockPumpManager.testConnectionReleased, "authority and radio travel together — BLE released")
        lock.lock(); let paused = pauseCalls; lock.unlock()
        XCTAssertEqual(paused, [true], "automatic dosing paused")

        // An interim offer with a token: retro-ack adopts the loan and `.loaned` holds.
        controller.handleIncoming(userInfo: try LoanMessage.handbackOffer(
            HandbackOffer(epoch: 5, handedBackAt: Date(), finalStatus: nil, odometer: nil,
                          events: [], tombstones: [], recovered: false, released: false,
                          seizeToken: token)).transportDictionary())
        waitUntil(timeout: 5, "retro-ack adopted") { controller.state == .loaned && !controller.yieldingToInferredLoan }
        XCTAssertFalse(controller.yieldingToInferredLoan, "the inferred loan became the adopted loan")
    }

    /// A pill tap from the yield takes the ordinary dead-branch reclaim.
    func testInferredYieldPillTapTakesTheInheritedRoad() throws {
        _ = seizeCredentialOutstanding()
        let controller = makeController()
        controller.handleIncoming(userInfo: try futureEpochBatch(epoch: 5))
        waitUntil(timeout: 5, "yield engaged") { controller.yieldingToInferredLoan }

        controller.reclaimNow()
        // Wait on the terminal condition, since the controller starts at `.owner`.
        waitUntil(timeout: 5, "force landed") {
            controller.state == .owner && !controller.yieldingToInferredLoan && !MockPumpManager.testConnectionReleased
        }
        waitUntil(timeout: 5, "dosing resumed") {
            self.lock.lock(); defer { self.lock.unlock() }
            return self.pauseCalls.last == false
        }

        XCTAssertFalse(controller.podIsOnLoan)
        XCTAssertFalse(MockPumpManager.testConnectionReleased, "the pod bid re-armed")
    }

    /// The tile tap reaches Reclaim Now from the veto posture, and the reclaim re-arms the bid.
    func testTheTileTapReachesReclaimFromTheVetoPosture() throws {
        _ = seizeCredentialOutstanding()
        let controller = makeController()
        controller.handleIncoming(userInfo: try futureEpochBatch(epoch: 5))
        waitUntil(timeout: 5, "yield engaged") { controller.yieldingToInferredLoan }

        XCTAssertTrue(controller.isPodLoanedOutForUI, "the tile's tap predicate includes the yield → Reclaim Now")
        XCTAssertTrue(MockPumpManager.testConnectionReleased, "radio released, interlock armed — as a grant")
        waitUntil(timeout: 5, "notice posted") {
            self.lock.lock(); defer { self.lock.unlock() }
            return self.notices.contains("Pod Looks Controlled by the Watch")
        }

        controller.reclaimNow()                        // the tile tap
        waitUntil(timeout: 5, "force landed") {
            controller.state == .owner && !controller.yieldingToInferredLoan && !MockPumpManager.testConnectionReleased
        }
        XCTAssertFalse(controller.isPodLoanedOutForUI, "tile is the phone's own again")
        waitUntil(timeout: 5, "dosing resumed") {
            self.lock.lock(); defer { self.lock.unlock() }
            return self.pauseCalls.last == false
        }
    }

    /// A stale final offer draining during a live successor loan closes the books but yields
    /// rather than reclaiming.
    func testGhostDrainCloseYieldsInsteadOfStealingFromTheLiveLoan() throws {
        let token = seizeCredentialOutstanding()
        let controller = makeController()

        // The ghost era: retro-ack adopts e4 (interim first — the drain is in progress).
        controller.handleIncoming(userInfo: try LoanMessage.handbackOffer(
            HandbackOffer(epoch: 4, handedBackAt: Date(), finalStatus: nil, odometer: nil,
                          events: [], tombstones: [], recovered: true, released: false,
                          seizeToken: token)).transportDictionary())
        waitUntil(timeout: 5, "ghost adopted") { controller.state == .loaned }

        // The LIVE loan's traffic lands mid-drain — dropped, but remembered as evidence.
        controller.handleIncoming(userInfo: try futureEpochBatch(epoch: 5))
        usleep(200_000)

        // The ghost's FINAL offer closes its drain.
        controller.handleIncoming(userInfo: try LoanMessage.handbackOffer(
            HandbackOffer(epoch: 4, handedBackAt: Date(), finalStatus: nil, odometer: nil,
                          events: [], tombstones: [], recovered: true, released: true,
                          seizeToken: token)).transportDictionary())
        waitUntil(timeout: 5, "close yielded") { controller.yieldingToInferredLoan }
        // The yield flag is saved before the radio is released, in the same queue turn.
        controller.queue.sync {}

        XCTAssertEqual(controller.state, .owner, "books closed at .owner…")
        XCTAssertTrue(MockPumpManager.testConnectionReleased, "…but custody NOT resumed — the pod stays the live loan's")
        lock.lock(); let paused = pauseCalls; lock.unlock()
        XCTAssertNotEqual(paused.last, false, "and dosing never resumed under the live loan")
    }

    /// Every epoch advance re-issues the dormant credential.
    func testEpochAdvanceRefreshesTheDormantCredential() throws {
        let token = seizeCredentialOutstanding()
        saveState { $0.watchSupportsSeize = true }
        let controller = makeController()

        let first = expectSend()
        controller.considerDormantRefresh()
        wait(for: [first], timeout: 5)

        // Advance the epoch by retro-acking e3 and draining it; wait on the ack.
        controller.handleIncoming(userInfo: try LoanMessage.handbackOffer(
            HandbackOffer(epoch: 3, handedBackAt: Date(), finalStatus: nil, odometer: nil,
                          events: [], tombstones: [], recovered: true, released: true,
                          seizeToken: token)).transportDictionary())
        waitUntil(timeout: 5, "ghost drained") {
            self.lock.lock(); defer { self.lock.unlock() }
            return self.sent.contains { if case .handbackAck = $0 { return true }; return false }
        }
        waitForState(controller, .owner)

        controller.considerDormantRefresh()
        waitUntil(timeout: 5, "second refresh") {
            self.lock.lock(); defer { self.lock.unlock() }
            return self.sent.filter { if case .dormantGrant = $0 { return true }; return false }.count >= 2
        }
        lock.lock()
        let epochs: [Int] = sent.compactMap { if case .dormantGrant(let d) = $0 { return d.grant.epoch }; return nil }
        lock.unlock()
        XCTAssertEqual(epochs, [1, 4], "provisional epochs track the phone's counter (0+1, then adopted-3+1) with no settings change and no 30-minute wait")
    }

    /// The retro-ack anchors the audit window at the offer's era, not the 2-hour default.
    func testRetroAckAnchorsTheAuditWindowAtTheOffersEra() throws {
        let token = seizeCredentialOutstanding()
        let controller = makeController()
        let eventStart = Date().addingTimeInterval(-1200)
        let event = LoanEvent(id: UUID(), seq: 1, provenance: .confirmed,
                              record: LoanDoseRecord(kind: .bolus, startDate: eventStart, amount: 0.5), loggedAt: eventStart)
        controller.handleIncoming(userInfo: try LoanMessage.handbackOffer(
            HandbackOffer(epoch: 4, handedBackAt: Date(), finalStatus: nil, odometer: nil,
                          events: [event], tombstones: [], recovered: true, released: false,
                          seizeToken: token)).transportDictionary())
        waitUntil(timeout: 5, "adopted") { controller.state == .loaned }

        let anchor = controller.persisted.audit.loanStartedAt
        XCTAssertNotNil(anchor, "the window anchor is SET, never nil-to-default")
        XCTAssertEqual(anchor.map { abs($0.timeIntervalSince(eventStart)) < 1 }, true,
                       "…at the offer's earliest event")
    }

    /// Detector C, phone half: an unsolicited holdsPod status report for a newer epoch
    /// at .owner is books-dirty evidence — yield without waiting for dose traffic.
    func testHoldsPodStatusReportYieldsAtOwner() throws {
        _ = seizeCredentialOutstanding()
        let controller = makeController()
        controller.handleIncoming(userInfo: try LoanMessage.statusReport(StatusReport(
            epoch: 5, mode: .closedDirect, lastDirectGlucoseAge: 60, lastEventSeq: 2,
            podFault: nil, holdsPod: true)).transportDictionary())
        waitUntil(timeout: 5, "yielded on the report") { controller.yieldingToInferredLoan }
        XCTAssertTrue(controller.isPodLoanedOut, "pill reads Pod on Watch off the report alone")
    }

    /// A `holdsPod` report abandons a ghost grant into the yield.
    func testHoldsPodReportAbandonsAGhostGrantIntoTheYield() throws {
        let token = seizeCredentialOutstanding()
        let controller = makeController()

        // The ghost: a request grants normally (nobody confirms — the "watch" is mid-seize).
        let grantSent = expectSend()
        controller.handleIncoming(userInfo: try LoanMessage.request(LoanRequest(watchBuild: "t")).transportDictionary())
        wait(for: [grantSent], timeout: 5)
        guard case .grant(let ghost)? = lastSent() else { throw SetupFailure.noGrant }
        XCTAssertEqual(controller.state, .grantOffered)

        // The answer: the watch holds a NEWER loan. The ghost can never confirm.
        controller.handleIncoming(userInfo: try LoanMessage.statusReport(StatusReport(
            epoch: ghost.epoch + 1, mode: .closedDirect, lastDirectGlucoseAge: 30, lastEventSeq: 1,
            podFault: nil, holdsPod: true)).transportDictionary())
        waitUntil(timeout: 5, "ghost abandoned into the yield") {
            controller.state == .owner && controller.yieldingToInferredLoan
        }
        XCTAssertTrue(controller.isPodLoanedOut, "pill reads Pod on Watch, not Handing over…")
        XCTAssertTrue(MockPumpManager.testConnectionReleased, "the pod stays released — the live loan needs it")

        // The reunion: the seized loan's offer adopts the burned epoch forward (epoch N+1).
        controller.handleIncoming(userInfo: try LoanMessage.handbackOffer(
            HandbackOffer(epoch: ghost.epoch + 1, handedBackAt: Date(), finalStatus: nil, odometer: nil,
                          events: [], tombstones: [], recovered: false, released: false,
                          seizeToken: token)).transportDictionary())
        waitUntil(timeout: 5, "retro-ack adopted past the burned epoch") {
            controller.state == .loaned && !controller.yieldingToInferredLoan
        }
    }

    /// Structural gating holds for the abandon too: without the dormant credential a
    /// holdsPod report cannot move a grant-in-flight — watchless users stay bit-for-bit stock.
    func testGhostGrantAbandonRequiresTheCredential() throws {
        let controller = makeController()
        let grantSent = expectSend()
        controller.handleIncoming(userInfo: try LoanMessage.request(LoanRequest(watchBuild: "t")).transportDictionary())
        wait(for: [grantSent], timeout: 5)
        guard case .grant(let ghost)? = lastSent() else { throw SetupFailure.noGrant }

        controller.handleIncoming(userInfo: try LoanMessage.statusReport(StatusReport(
            epoch: ghost.epoch + 1, mode: .closedDirect, lastDirectGlucoseAge: 30, lastEventSeq: 1,
            podFault: nil, holdsPod: true)).transportDictionary())
        usleep(300_000)
        XCTAssertEqual(controller.state, .grantOffered, "no credential — the report changes nothing")
        XCTAssertFalse(controller.yieldingToInferredLoan)
    }

    /// A reclaim from the yield aims its revoke at the live loan and accepts its drain.
    func testReclaimFromYieldAimsTheRevokeAtTheLiveLoanAndAcceptsItsDrain() throws {
        let token = seizeCredentialOutstanding()
        // LIVE branch on purpose (reachable): the dead branch forces instantly and would
        // bury the drain this test exists to prove.
        let controller = makeController(watchReachable: { true }, lastWatchContact: { self.clock }, now: { self.clock })

        controller.handleIncoming(userInfo: try futureEpochBatch(epoch: 5))
        waitUntil(timeout: 5, "yield engaged") { controller.yieldingToInferredLoan }

        let revokeSent = expectSend()
        controller.reclaimNow()
        wait(for: [revokeSent], timeout: 5)
        guard case .revoke(let aimed)? = lastSent() else {
            return XCTFail("expected the tap's revoke, got \(String(describing: lastSent()))")
        }
        XCTAssertEqual(aimed.epoch, 5, "aimed at the live loan the evidence names, not this phone's stale epoch")
        // Wait for `.reclaimPending`: the revoke is sent before that state is set.
        waitForState(controller, .reclaimPending)

        // The watch drains that loan (FINAL — released nil by the legacy convention), token attached.
        controller.handleIncoming(userInfo: try LoanMessage.handbackOffer(
            HandbackOffer(epoch: 5, handedBackAt: clock, finalStatus: nil, odometer: nil,
                          events: [], tombstones: [], recovered: true, released: nil,
                          seizeToken: token)).transportDictionary())
        waitUntil(timeout: 8, "drain adopted and closed back to owner") {
            controller.state == .owner && !controller.yieldingToInferredLoan
        }
        XCTAssertNil(diagMatching("ladder spent"), "the aimed revoke got its drain — no force")
        XCTAssertNotNil(diagMatching("retro-ack arrived MID-RECLAIM"), "the .reclaimPending door took the offer")
    }

    /// Evidence can arrive BETWEEN the rungs: the watch's holdsPod answer to a mis-aimed
    /// attempt 1 re-aims the ladder's remaining attempt at the loan it actually holds.
    func testHoldsPodReportMidLadderReAimsTheRemainingAttempt() throws {
        _ = seizeCredentialOutstanding()
        let controller = makeController(watchReachable: { true }, lastWatchContact: { self.clock }, now: { self.clock })
        let grant = try establishLoan(controller)

        let revokeSent = expectSend()
        controller.reclaimNow()
        wait(for: [revokeSent], timeout: 5)
        guard case .revoke(let first)? = lastSent() else {
            return XCTFail("expected the tap's revoke, got \(String(describing: lastSent()))")
        }
        XCTAssertEqual(first.epoch, grant.epoch, "no foreign evidence — the tap names our own loan")

        // The watch answers: it holds a NEWER loan (a seize this phone never saw).
        let reAimed = expectSend()
        controller.handleIncoming(userInfo: try LoanMessage.statusReport(StatusReport(
            epoch: grant.epoch + 1, mode: .closedDirect, lastDirectGlucoseAge: 30, lastEventSeq: 1,
            podFault: nil, holdsPod: true)).transportDictionary())
        wait(for: [reAimed], timeout: 5)
        guard case .revoke(let second)? = lastSent() else {
            return XCTFail("expected the re-aimed revoke, got \(String(describing: lastSent()))")
        }
        XCTAssertEqual(second.epoch, grant.epoch + 1, "the remaining attempt spends on the loan the watch holds")
        // The diag rides the controller queue a beat behind the revoke that fulfilled the
        // wait — poll, don't sample (the bare assert lost that race on the first run).
        waitUntil(timeout: 5, "re-aim diag") { self.diagMatching("RE-AIMED") != nil }
    }

    // MARK: - Grant anchor

    /// A failed takeover's `grantOfferedAt` does not leak into the next grant.
    func testANewGrantDoesNotInheritAFailedTakeoversClock() throws {
        clock = Date()
        let controller = makeController(now: { [weak self] in self?.clock ?? Date() })

        // Grant once, then abandon it: the watch says the grant never
        // arrived, which reclaims to owner — and under the old code never cleared the anchor.
        let g1 = offerGrant(controller)
        controller.handleIncoming(userInfo: try LoanMessage.statusReport(
            StatusReport(epoch: g1.epoch, mode: .closedDirect, lastDirectGlucoseAge: nil,
                         lastEventSeq: 0, podFault: nil, holdsPod: false, knowsGrant: false)
        ).transportDictionary())
        waitForState(controller, .owner)

        // Six minutes: past the 5-minute settle window, which is asynchronous.
        clock = clock.addingTimeInterval(360)
        lock.lock(); diags.removeAll(); lock.unlock()
        let g2 = offerGrant(controller)
        XCTAssertNotEqual(g1.epoch, g2.epoch)

        // Ten seconds into the SECOND takeover, the watch reports progress.
        clock = clock.addingTimeInterval(10)
        controller.handleIncoming(userInfo: try LoanMessage.statusReport(
            StatusReport(epoch: g2.epoch, mode: .closedDirect, lastDirectGlucoseAge: nil,
                         lastEventSeq: 0, podFault: nil, holdsPod: false, knowsGrant: true)
        ).transportDictionary())

        waitUntil(timeout: 5, "in-progress diag") {
            self.lock.lock(); defer { self.lock.unlock() }
            return self.diags.contains { $0.contains("takeover IN PROGRESS") }
        }
        lock.lock()
        let line = diags.first { $0.contains("takeover IN PROGRESS") } ?? ""
        lock.unlock()

        // Measured from THIS grant (10 s), not from the abandoned one (130 s).
        XCTAssertTrue(line.contains("+10s"),
                      "elapsed must be measured from the second grant; got: \(line)")
        XCTAssertFalse(line.contains("+370s"),
                       "the abandoned takeover's clock leaked into the new grant: \(line)")
    }


    // MARK: - The grant carries the phone's own dosing strategy

    /// The watch now runs automatic bolus itself, so the grant passes the phone's strategy through.
    func testGrantCarriesThePhonesAutomaticBolusStrategy() {
        settings.automaticDosingStrategy = .automaticBolus
        let controller = makeController()
        let grant = establishLoan(controller)

        guard let carried = LoopSettings(rawValue: try! PropertyListSerialization.propertyList(
                from: grant.therapySettingsRaw, options: [], format: nil) as! LoopSettings.RawValue) else {
            return XCTFail("grant's therapy settings did not decode")
        }
        XCTAssertEqual(carried.automaticDosingStrategy, .automaticBolus,
                       "the wrist runs the phone's strategy, automatic bolus included")
    }

    /// A loan never writes the phone's own dosing strategy.
    func testTheLoanDoesNotTouchThePhonesOwnSetting() {
        settings.automaticDosingStrategy = .automaticBolus
        let controller = makeController()
        establishLoan(controller)

        XCTAssertEqual(settings.automaticDosingStrategy, .automaticBolus,
                       "the phone's own strategy must survive the loan untouched")
    }

    /// A phone already on temps is unaffected — no override, nothing to log, same grant as before.
    func testTempBasalOnlyPhoneIsPassedThroughUnchanged() {
        settings.automaticDosingStrategy = .tempBasalOnly
        let controller = makeController()
        let grant = establishLoan(controller)

        guard let carried = LoopSettings(rawValue: try! PropertyListSerialization.propertyList(
                from: grant.therapySettingsRaw, options: [], format: nil) as! LoopSettings.RawValue) else {
            return XCTFail("grant's therapy settings did not decode")
        }
        XCTAssertEqual(carried.automaticDosingStrategy, .tempBasalOnly)
        XCTAssertEqual(settings.automaticDosingStrategy, .tempBasalOnly)
    }

}

/// Records ladder rungs so a test can read the geometry and jump to a deadline. Every arming
/// is kept.
final class ReclaimLadderRecorder {
    struct Armed: Equatable {
        let label: String
        let delay: TimeInterval
    }

    private let lock = NSLock()
    private var _armed: [Armed] = []
    private var _work: [String: [DispatchWorkItem]] = [:]

    var armed: [Armed] { lock.lock(); defer { lock.unlock() }; return _armed }

    func install(on controller: PodLoanPhoneController) {
        controller.scheduler = { [weak self] delay, label, work in
            guard let self = self else { return }
            self.lock.lock()
            self._armed.append(Armed(label: label, delay: delay))
            self._work[label, default: []].append(work)
            self.lock.unlock()
        }
    }

    /// Fire the LATEST arming of a rung — virtual time for exactly that deadline.
    @discardableResult
    func fire(_ label: String) -> Bool {
        lock.lock()
        let work = _work[label]?.last
        lock.unlock()
        guard let work = work else { return false }
        work.perform()
        return true
    }

    /// `arming` nil = the latest. Index it to ask about a rung that has since been superseded.
    func isCancelled(_ label: String, arming index: Int? = nil) -> Bool {
        lock.lock()
        let items = _work[label] ?? []
        lock.unlock()
        let work: DispatchWorkItem?
        if let index = index {
            work = items.indices.contains(index) ? items[index] : nil
        } else {
            work = items.last
        }
        return work?.isCancelled ?? false
    }

}

// MARK: - A silent watch is warned about, never taken from

extension PodLoanPhoneControllerTests {

    private func tick(_ controller: PodLoanPhoneController) {
        controller.considerHoldLapse()
        controller.queue.sync { }
    }

    private func silenceWarnings() -> Int {
        lock.lock(); defer { lock.unlock() }
        return urgentNotices.filter { $0 == "Watch Not Reporting" }.count
    }

    /// A silent watch is warned about at ~20, 40 and 60 min and never taken from.
    func testASilentWatchIsWarnedAboutAndNeverTakenFrom() throws {
        let controller = makeController(now: { [weak self] in self?.clock ?? Date() })
        _ = establishLoan(controller)

        clock = clock.addingTimeInterval(.minutes(14))
        tick(controller)
        XCTAssertNil(controller.holdLapseNoticedAt, "inside three cycles: nothing")

        clock = clock.addingTimeInterval(.minutes(2))     // 16 min of silence
        tick(controller)
        XCTAssertNotNil(controller.holdLapseNoticedAt, "noticed")
        XCTAssertEqual(silenceWarnings(), 0, "but not yet said: the watch gets one cycle to report")

        clock = clock.addingTimeInterval(.minutes(5))     // 21 min
        tick(controller)
        XCTAssertEqual(silenceWarnings(), 1, "about twenty minutes")

        clock = clock.addingTimeInterval(.minutes(5))
        tick(controller)
        XCTAssertEqual(silenceWarnings(), 1, "no repeat inside the cadence")

        clock = clock.addingTimeInterval(.minutes(15))    // 41 min
        tick(controller)
        XCTAssertEqual(silenceWarnings(), 2, "about forty")

        clock = clock.addingTimeInterval(.minutes(20))    // 61 min
        tick(controller)
        XCTAssertEqual(silenceWarnings(), 3, "about sixty")

        clock = clock.addingTimeInterval(.minutes(60))
        tick(controller)
        XCTAssertEqual(silenceWarnings(), 3, "then it stops")

        XCTAssertEqual(controller.state, .loaned, "the pod stays assigned to the watch — taking it back is the user's tap")
        XCTAssertTrue(MockPumpManager.testConnectionReleased, "and the phone's pod link stays released")
        lock.lock(); let revoked = sent.contains { if case .revoke = $0 { return true }; return false }; lock.unlock()
        XCTAssertFalse(revoked, "nothing was sent to the watch either")
    }

    /// Coming back into range, the phone notices an hour of silence at once — while the watch,
    /// alive and dosing all along, is one cycle from reporting. No warning on the way back in.
    func testAWatchThatReportsOnTheWayBackInIsNotWarnedAbout() throws {
        let controller = makeController(now: { [weak self] in self?.clock ?? Date() })
        let grant = establishLoan(controller)

        clock = clock.addingTimeInterval(.minutes(90))
        tick(controller)
        XCTAssertNotNil(controller.holdLapseNoticedAt, "silence noticed")

        clock = clock.addingTimeInterval(.minutes(3))
        controller.handleIncoming(userInfo: try LoanMessage.doseRecordBatch(
            DoseRecordBatch(epoch: grant.epoch, events: [], tombstones: [], sentAt: clock)).transportDictionary())
        controller.queue.sync { }
        XCTAssertNil(controller.holdLapseNoticedAt, "the watch reported: the warning stands down")

        clock = clock.addingTimeInterval(.minutes(10))
        tick(controller)
        XCTAssertEqual(silenceWarnings(), 0)
    }

    /// An audit consumes its anchors.
    func testAnAuditConsumesItsAnchors() throws {
        let controller = makeController()
        _ = establishLoan(controller)
        XCTAssertNotNil(controller.auditBase, "a live loan has its anchor")

        MockPumpManager.testOdometer = 10.0
        controller.forceReclaimToOwner(reason: "test: the loan is over")
        waitForState(controller, .owner)
        waitUntil(timeout: 8, "verdict") { self.diagMatching("reconcile[FORCE-RECLAIM]") != nil }
        controller.queue.sync { }

        XCTAssertNil(controller.auditBase, "spent with its loan — nothing later can audit from here")
        XCTAssertNil(controller.loanStartedAt)
    }

    /// Records from a closed session are answered with the revoke again.
    func testRecordsFromAClosedSessionAreAnsweredWithTheRevoke() throws {
        let controller = makeController(now: { [weak self] in self?.clock ?? Date() })
        let grant = establishLoan(controller)
        MockPumpManager.testOdometer = 10.0
        controller.forceReclaimToOwner(reason: "test: pod tile, watch powered off")
        waitForState(controller, .owner)
        controller.queue.sync { }
        func revokes() -> Int {
            lock.lock(); defer { lock.unlock() }
            return sent.filter { if case .revoke(let r) = $0 { return r.epoch == grant.epoch }; return false }.count
        }
        let before = revokes()

        let batch = try LoanMessage.doseRecordBatch(
            DoseRecordBatch(epoch: grant.epoch, events: [], tombstones: [])).transportDictionary()
        controller.handleIncoming(userInfo: batch)
        controller.handleIncoming(userInfo: batch)   // the watch sends two per cycle
        controller.queue.sync { }
        XCTAssertEqual(revokes(), before + 1, "one revoke per cycle's worth of records, not one per batch")

        clock = clock.addingTimeInterval(.minutes(5))
        controller.handleIncoming(userInfo: batch)
        controller.queue.sync { }
        XCTAssertEqual(revokes(), before + 2, "and again at the next cycle, for as long as the watch keeps reporting")
        XCTAssertEqual(controller.state, .owner, "the phone keeps the pod throughout")
    }

    /// The standing copy refreshes on a bolus or carb, collapses bursts, and loses nothing.
    func testTheStandingCopyFollowsTheBook() {
        saveState { $0.watchSupportsSeize = true }
        let controller = makeController(now: { [weak self] in self?.clock ?? Date() })
        func copies() -> Int {
            lock.lock(); defer { lock.unlock() }
            return sent.filter { if case .dormantGrant = $0 { return true }; return false }.count
        }
        controller.considerDormantRefresh()
        waitUntil(timeout: 5, "first copy") { copies() == 1 }

        clock = clock.addingTimeInterval(.minutes(2))          // far inside the 30-minute floor
        controller.considerDormantRefresh()
        controller.queue.sync { }
        usleep(300_000)
        XCTAssertEqual(copies(), 1, "nothing changed — the periodic floor still holds")

        for _ in 0..<5 { controller.considerDormantRefresh(bookChanged: true) }   // carbs, then the bolus, in a burst
        waitUntil(timeout: 5, "the book changed") { copies() == 2 }
        usleep(400_000)
        XCTAssertEqual(copies(), 2, "one burst, one copy")
    }

    /// A glucose alert change reaches the standing copy at once, like a therapy change: neither
    /// the 30-minute periodic floor nor the book's short floor holds it.
    func testAGlucoseAlertChangeRefreshesTheStandingCopyAtOnce() {
        saveState { $0.watchSupportsSeize = true }
        let controller = makeController(now: { [weak self] in self?.clock ?? Date() })
        func copies() -> Int {
            lock.lock(); defer { lock.unlock() }
            return sent.filter { if case .dormantGrant = $0 { return true }; return false }.count
        }
        var alerts = GlucoseAlertSettings(profiles: [.makePrimary()], activeProfileID: UUID(),
                                          cgmProvidesOwnAlerts: false, loopAlertsOverrideForOwnAlertingCGM: false)
        alerts.activeProfileID = alerts.profiles[0].id
        controller.noteGlucoseAlertSettings(alerts)
        waitUntil(timeout: 5, "first copy") { copies() == 1 }

        controller.noteGlucoseAlertSettings(alerts)
        controller.considerDormantRefresh()
        controller.queue.sync { }
        usleep(300_000)
        XCTAssertEqual(copies(), 1, "the same settings again: nothing to send")

        alerts.profiles[0].configuration.lowThresholdMgDL = 80   // seconds after the last copy
        controller.noteGlucoseAlertSettings(alerts)
        waitUntil(timeout: 5, "the low threshold changed") { copies() == 2 }

        controller.considerDormantRefresh(bookChanged: true)      // a bolus right after: the book's floor holds
        controller.queue.sync { }
        usleep(300_000)
        XCTAssertEqual(copies(), 2, "a book change inside its floor waits for the trailing refresh")
    }

    /// A loan the watch ANNOUNCED (a seized pod) is anchored at this phone's own last pod read —
    /// never at an earlier loan's — and a silent one is warned about like any other.
    func testALoanTheWatchAnnouncedIsAnchoredHereAndWarnedAboutWhenSilent() throws {
        _ = seizeCredentialOutstanding()
        let controller = makeController(now: { [weak self] in self?.clock ?? Date() })
        MockPumpManager.testOdometer = 20.0
        controller.handleIncoming(userInfo: try LoanMessage.statusReport(StatusReport(
            epoch: 5, mode: .closedDirect, lastDirectGlucoseAge: 60, lastEventSeq: 2,
            podFault: nil, holdsPod: true)).transportDictionary())
        waitUntil(timeout: 5, "standing aside on the watch's word") { controller.yieldingToInferredLoan }
        controller.queue.sync { }
        XCTAssertEqual(controller.auditBase?.units, 20.0, "anchored at this phone's own last pod read")

        clock = clock.addingTimeInterval(.minutes(16))
        tick(controller)
        clock = clock.addingTimeInterval(.minutes(6))
        tick(controller)
        XCTAssertEqual(silenceWarnings(), 1)
        XCTAssertTrue(controller.yieldingToInferredLoan, "still standing aside: the way back is the pod tile")
    }

    /// The core use: the phone is left at home. It hears nothing from the watch for the same
    /// reason it cannot reach the pod — it is somewhere else — and has nothing to warn about.
    func testAPhoneAwayFromTheBodySaysNothing() throws {
        var lastReading = Date()
        let controller = makeController(latestGlucose: { lastReading },
                                        now: { [weak self] in self?.clock ?? Date() })
        _ = establishLoan(controller)
        lastReading = clock                                   // the last reading before leaving

        clock = clock.addingTimeInterval(.minutes(40))        // out for a run; the app happens to wake
        tick(controller)
        clock = clock.addingTimeInterval(.minutes(10))
        tick(controller)
        XCTAssertNil(controller.holdLapseNoticedAt)
        XCTAssertEqual(silenceWarnings(), 0, "fifty minutes of silence, and nothing: no sensor, no pod, nobody here to tell")

        lastReading = clock                                   // home again: the phone reads the sensor
        tick(controller)
        XCTAssertNotNil(controller.holdLapseNoticedAt, "now the silence counts")
        XCTAssertEqual(silenceWarnings(), 0, "and the watch still gets its cycle to report first")
    }

    /// A queued message can land an hour late and must not be believed. A report counts by
    /// when the watch SENT it, never by when it arrived.
    func testABatchThatSatInAQueueReportsNothingNew() throws {
        let controller = makeController(now: { [weak self] in self?.clock ?? Date() })
        let grant = establishLoan(controller)
        let sentEarly = clock.addingTimeInterval(.minutes(1))

        clock = clock.addingTimeInterval(.minutes(20))
        controller.handleIncoming(userInfo: try LoanMessage.doseRecordBatch(
            DoseRecordBatch(epoch: grant.epoch, events: [], tombstones: [], sentAt: sentEarly)).transportDictionary())
        controller.queue.sync { }
        tick(controller)
        XCTAssertNotNil(controller.holdLapseNoticedAt, "19 minutes old on arrival: the watch is still silent")
    }
}

/// Records each preset callback and whether it ran on main; fulfils on the first deactivation.
private final class MainThreadPresetObserver: PresetActivationObserver {
    private(set) var calls: [String] = []
    private let deactivated: XCTestExpectation

    init(_ deactivated: XCTestExpectation) { self.deactivated = deactivated }

    func presetActivated(context: TemporaryScheduleOverride.Context, duration: TemporaryScheduleOverride.Duration) {
        calls.append("activated \(Thread.isMainThread ? "on main" : "OFF main")")
    }

    func presetDeactivated(context: TemporaryScheduleOverride.Context) {
        calls.append("deactivated \(Thread.isMainThread ? "on main" : "OFF main")")
        deactivated.fulfill()
    }
}

extension PodLoanPhoneController {
    /// Blocking; the tests' view of the reclaim's settle window.
    var isReclaimSettling: Bool {
        return queue.sync {
            guard state == .owner, let started = reclaimStartedAt else { return false }
            if deps.now().timeIntervalSince(started) >= Self.reclaimSettleTimeout { return false }

            return reclaimVerifiedAt == nil
        }
    }
}
