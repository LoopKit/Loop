//
//  PodLoanPhoneControllerTests.swift
//  LoopTests
//
//  Controller-level protocol invariants (DESIGN_LOAN_PROTOCOL_V2.md §10): the epoch
//  race (drill D22 / bench B4 as unit tests), cursor idempotency under offer
//  redelivery (row 10), stale-epoch offers drain records without touching loan state
//  (rows 13/14 — dead loans cannot speak), grant deny-on-missing-settings, and
//  the reconcile-commit-ack ordering. The watch half and the timer-driven rows are
//  bench drills by design.
//

import XCTest
import HealthKit
import LoopKit
import LoopAlgorithm
import LoopCore
import MockKit
@testable import Loop

/// Test-only lendable conformance so the full grant path runs against MockKit's pump.
extension MockPumpManager: PumpConnectionLendable {
    static var testConnectionReleased = false
    /// Item 1: the odometer the PHONE reads on its reclaim round-trip. nil = pump reports none.
    static var testOdometer: Double?
    /// PHONE MIRROR: the books-dirty primitive (SQN-resync stamp) the inferred-loan
    /// detector reads. nil = no foreign sessions observed.
    static var testForeignSessionAt: Date?
    public var isConnectionReleased: Bool { Self.testConnectionReleased }
    public func releaseConnection() { Self.testConnectionReleased = true }
    public func reclaimConnection() { Self.testConnectionReleased = false }
    public var lentDeviceInsulinDelivered: Double? { Self.testOdometer }
    public var podLoanLastForeignSessionAt: Date? { Self.testForeignSessionAt }
    /// Counts the FORCED round-trips (the ones that bypass the freshness optimization), so a
    /// test can assert the settle forces early without forcing on every 2 s tick — the whole
    /// point of the backoff is that reclaim speed is not bought with radio time.
    static var testForcedReadCount = 0
    public func refreshLentDeviceStatus(completion: @escaping (Bool) -> Void) {
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
    /// Item 1: every HANDBACK-DIAG line the controller emitted (the harness otherwise drops .diag).
    var diags: [String] = []
    /// Item 1: how many times the phone enacted the post-return temp cancel, and its result.
    var cancelCalls = 0
    var cancelError: Error?
    /// How many times the phone stopped automatic dosing over a reconciliation difference.
    var openLoopCalls = 0
    var pump: MockPumpManager!
    var settings: LoopSettings!
    /// Captures for the dead-watch reclaim audit.
    var urgentNotices: [String] = []
    var bookedGapDoses: [DoseEntry] = []
    var deletedGapSyncs: [String] = []
    var gapDeleteSucceeds = true
    /// Virtual clock behind `Dependencies.now`, for the reclaim bars. Both fractions are pure
    /// functions of elapsed time, so a test that could not move the clock could only assert them
    /// by sleeping through a 45-second settle. Only the tests that pass `now:` to `makeController`
    /// see it; everything else keeps the real clock.
    var clock = Date()
    /// Background-hold pairing counters: a begin without a matching end is a battery leak iOS
    /// logs against the app, so the tests assert balance at rest.
    var backgroundTaskBegins = 0
    var backgroundTaskEnds = 0
    /// When true, `addPumpEvents` parks its completion in `heldPumpEventWrite` instead of calling
    /// it. That holds the hand-back commit open, which is the only way to observe the controller
    /// while state is `.reconciling` — the harness otherwise completes the write inline and the
    /// whole drain-to-settle transition happens inside one queue block.
    var holdPumpEventWrites = false
    var heldPumpEventWrite: ((Error?) -> Void)?
    private let lock = NSLock()

    override func setUp() {
        super.setUp()
        // The controller persists via UserDefaults.standard + a staging file; every
        // test starts from a clean slate.
        for key in ["PodLoanPhoneController.state", "PodLoanPhoneController.epoch",
                    "PodLoanPhoneController.cursor", "PodLoanPhoneController.pendingRevoke",
                    "PodLoanPhoneController.committedIDs", "PodLoanPhoneController.loanStartedAt",
                    "PodLoanPhoneController.deliveredAtTakeover", "PodLoanPhoneController.gapBooking",
                    "PodLoanPhoneController.pendingForceAudit", "PodLoanPhoneController.deliveredAtGrant",
                    "PodLoanPhoneController.auditBase", "PodLoanPhoneController.windowResidualWorst",
                    // The force-reclaim audit reads both of these, and only a GRANT clears them —
                    // so a test that reaches the audit without granting inherited the previous
                    // test's expected-units and audit-ran flag, and judged the reclaim against
                    // them. That is the whole of this class's order-dependence: the residual came
                    // out wrong by a different amount depending on what ran before.
                    "PodLoanPhoneController.expectedUnits", "PodLoanPhoneController.watchAuditRan"] {
            UserDefaults.standard.removeObject(forKey: key)
        }
        MockPumpManager.testForcedReadCount = 0
        MockPumpManager.testForeignSessionAt = nil
        // PHONE MIRROR keys: a leaked yield flag would re-pause dosing at the next
        // test's controller init (the flag folds into podIsOnLoan).
        for key in ["PodLoanPhoneController.yieldingToInferredLoan",
                    "PodLoanPhoneController.lastHandledForeignSessionAt",
                    "PodLoanPhoneController.dormantSeizeToken",
                    "PodLoanPhoneController.watchSupportsSeize",
                    "PodLoanPhoneController.rebidAt",
                    "PodLoanPhoneController.firstContactSinceRebid"] {
            UserDefaults.standard.removeObject(forKey: key)
        }
        backgroundTaskBegins = 0
        backgroundTaskEnds = 0
        urgentNotices = []
        bookedGapDoses = []
        deletedGapSyncs = []
        gapDeleteSucceeds = true
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        try? FileManager.default.removeItem(at: base.appendingPathComponent("PodLoanStagedRecordsV2.json"))

        sent = []
        sentExpectations = []
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
        pump = MockPumpManager()
        MockPumpManager.testConnectionReleased = false
        MockPumpManager.testOdometer = nil
        UserDefaults.standard.removeObject(forKey: "PodLoanPhoneController.deliveredAuthoritative")
        UserDefaults.standard.removeObject(forKey: "PodLoanPhoneController.holdRenewedAt")
        UserDefaults.standard.removeObject(forKey: "PodLoanPhoneController.holdLapseNoticedAt")
        UserDefaults.standard.removeObject(forKey: "PodLoanPhoneController.watchSilenceWarningsIssued")
        UserDefaults.standard.removeObject(forKey: "PodLoanPhoneController.residualHistory")
        // The residual-bank purge is one-shot per install, so its flag has to be cleared per test
        // or whichever test happens to construct the first controller consumes it for the rest.
        UserDefaults.standard.removeObject(forKey: "PodLoanPhoneController.residualHistoryPurged.2026-08-13")

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

    /// The two reclaim-ladder inputs are parameters rather than mutable test state because the
    /// branch is decided ONCE, at the tap — a test that could change them afterwards would be
    /// describing a controller this one is not. Defaults reproduce a phone that has heard nothing
    /// from the watch this launch, which is the dead branch.
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
                // Diagnostic breadcrumbs (.diag) aren't protocol messages the tests
                // assert on — keep them out of `sent` and out of the expectations, but DO
                // capture the text: the hand-back audit's whole output is a diag line.
                if let message = try? LoanMessage.decode(fromTransport: dictionary), case .diag(let d) = message {
                    self.lock.lock(); self.diags.append(d.text); self.lock.unlock()
                    return
                }
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
                // RAW append on purpose (no store emulation): this harness discriminates the
                // CONTROLLER's own guards — committedIDs, staleness — and a store-level
                // dedupe here would let a controller regression hide behind the store.
                self?.lock.lock(); self?.addedCarbs.append(entry); self?.lock.unlock()
                _ = syncIdentifier
                completion(nil)
            },
            doseHistory: { _, completion in completion([]) },
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
            issueUrgentNotice: { [weak self] title, _ in
                guard let self = self else { return }
                self.lock.lock(); self.urgentNotices.append(title); self.lock.unlock()
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
            now: now
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
    func carbEvent(seq: Int, grams: Double, at date: Date, absorption: TimeInterval) -> LoanEvent {
        LoanEvent(id: UUID(), seq: seq, provenance: .confirmed,
                  record: LoanDoseRecord(kind: .carb, startDate: date, amount: grams, absorptionTime: absorption),
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

    /// Drives a controller into LOANED at epoch 1, returning the grant it sent.
    ///
    /// The grant path is deny-and-retry BY DESIGN: right after a hand-back the phone
    /// refuses to grant until the settle verification round-trip lands on its queue, and
    /// the user's next Start succeeds ("Try Start again in a few seconds"). Whether that
    /// async completion beats this request is a queue race no test may depend on, so a
    /// denial here is retried the way a user would — any OTHER non-grant reply stays fatal.
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
        XCTAssertFalse(grant.pumpManagerRawState.isEmpty)
        XCTAssertFalse(grant.therapySettingsRaw.isEmpty)
        XCTAssertEqual(grant.settingsTimeZoneID, "GMT")
    }

    func testGrantDeniedOnIncompleteSettings() throws {
        settings.maximumBolus = nil  // deny, never default
        let controller = makeController()
        controller.handleIncoming(userInfo: try LoanMessage.request(LoanRequest(watchBuild: "t")).transportDictionary())

        // The refusal is observed on the WIRE, not as a phone notice: the phone-side
        // "Sport Mode Not Started" banner was removed as duplication — the watch the user
        // just tapped already shows the reason.
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

    /// Bug E regression: a phone stranded in a transient non-owner state must recover
    /// on a fresh request and must never refuse forever.
    ///
    /// The contract changed. Recovery still happens on the FIRST request,
    /// but it lands in .owner with the settle window open — a force-recovered phone has not
    /// yet completed a pod round-trip, and granting an unverified pod is exactly the race
    /// that fails takeovers in the field. So: first request recovers + denies (with the
    /// "still returning" reason, which eagerly kicks verification), and once the round-trip
    /// lands the NEXT request grants. The invariant this test protects is unchanged: no
    /// permanent refusal.
    func testStrandedStateRecoversOnNewRequest() throws {
        // Recent contact keeps this on the LIVE branch, which waits on its ladder — the only
        // way to strand in reclaimPending now, since the dead branch forces on its own. The
        // watch then never drains, which is the strand.
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

    /// Regression guard: a TRANSPORT redelivery of the same
    /// request must be ignored. Before the fix, copy 2 arrived while the phone sat in
    /// .grantOffered from copy 1, took the stale-state recovery path, force-reclaimed the pod
    /// it had just released, and re-granted — which the reclaim-settle guard denied. The watch
    /// was left holding a grant for a pod still on the phone and every ladder read returned
    /// no-peripheral. Exactly one grant may result, and the pod must stay released.
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

        // The redelivered copy must change NOTHING. The assertion that bites is the grant
        // COUNT: without dedupe the second copy takes the stale-state recovery path and the
        // phone re-grants under a NEW epoch, which supersedes the grant the watch is already
        // acting on — that divergence is the field failure, and a "was there a denial?" check
        // does not catch it (verified: that weaker test passed with the fix disabled).
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

    /// The round trip the carb button was disabled for. A carb entered on the wrist rides the
    /// journal like any other record; the hand-back drain must land it in the phone's CarbStore
    /// with quantity, start time and absorption interval intact.
    func testWatchCarbRoundTripsToThePhoneOnHandback() throws {
        let controller = makeController()
        let grant = establishLoan(controller)
        let mealAt = Date().addingTimeInterval(-.minutes(20))

        let acked = expectSend()
        let offer = HandbackOffer(epoch: grant.epoch, handedBackAt: Date(), finalStatus: nil, odometer: nil,
                                  events: [carbEvent(seq: 1, grams: 42, at: mealAt, absorption: .hours(3))],
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
    }

    /// NewCarbEntry carries NO identity and CarbStore mints a fresh syncIdentifier on every
    /// addCarbEntry, so the store itself can never dedupe. Idempotency has to come from the
    /// protocol's committed-ID gate. A redelivered offer (lost ack, row 10) must therefore commit
    /// the carb exactly once — otherwise every resend inflates COB, which is the phantom-COB
    /// failure mode arriving by a different door.
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

    /// forceReclaimToOwner commits STAGED events, and used to do so without
    /// recording their IDs — while also sending no handbackAck, so the watch's 15 s resend loop
    /// kept redelivering the same offer against an unchanged committedIDs set. Every resend
    /// added another copy of the carb.
    ///
    /// This is the path a watch takes whenever it goes unreachable mid-loan (the reclaim ladder
    /// spending both attempts, a stranded relaunch, or a fresh request while loaned), so it is not
    /// an exotic corner. Insulin survived it because NewPumpEvent.raw dedupes at the store;
    /// NewCarbEntry has no identity, so the cursor is the only guard.
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

    /// A STALE offer (an epoch the phone has moved past) used to commit its carbs
    /// unconditionally while committedIDs.formUnion sat inside the `if !isStale` branch — so the
    /// carbs landed and nothing was recorded, and each resend added another. The override change
    /// on the very next line was already correctly gated, which is what makes this an
    /// inconsistency rather than a deliberate choice: a dead loan cannot add carbs either.
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
        // Dosing is no longer restored AT the reclaim — it is held for the audit's verdict.
        // With no odometer on the mock the session is UNVERIFIED, which resumes-the-latch and
        // opens the loop instead of quietly closing it.
        waitUntil(timeout: 5, "audit verdict") { self.pauseCalls.last == false }
        XCTAssertEqual(openLoopCalls, 1, "unverifiable session opens the loop rather than resuming closed")
        XCTAssertTrue(urgentNotices.contains { $0.contains("Unverified") })
    }

    /// A re-Start while the pod is still returning from the previous reclaim must
    /// deny-and-retry — never hand the watch a half-reconnected pod (the race that fails
    /// takeover). Once the pod is truly back (isConnectionReady), the next request grants.
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

        // The link coming up is no longer enough — readiness is a
        // completed pod ROUND-TRIP. Flip the link up, let the chase verify against
        // MockPumpManager (fresh lastSync), and only then does a request grant.
        connectionReady = true
        waitUntil(timeout: 8, "reclaim verification") { !controller.isReclaimSettling }
        let granted = expectSend()
        controller.handleIncoming(userInfo: try LoanMessage.request(LoanRequest(watchBuild: "t")).transportDictionary())
        wait(for: [granted], timeout: 5)
        if case .grant? = lastSent() {} else {
            XCTFail("expected a grant once the round-trip verified, got \(String(describing: lastSent()))")
        }
    }

    /// Spin-wait helper for conditions that settle via background queues (the reclaim
    /// verification chase ticks every 2 s and completes via MockPumpManager's main-queue
    /// ensureCurrentPumpData).
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
        XCTAssertEqual(pauseCalls, [true, false], "dosing restored only after commit")
        XCTAssertFalse(MockPumpManager.testConnectionReleased, "pod reclaimed at loan close")
    }

    // MARK: - Item 1: the phone reads the end-of-loan odometer and cancels the inherited temp

    /// The change in one assertion: the audit's end reading comes from the PHONE's reclaim
    /// round-trip, not from the watch's offer.
    ///
    /// The field case this reproduces (2026-08-11, and every hand-back before it): the watch
    /// released the pod's BLE link after its last dose window, so at hand-back it could not read
    /// the odometer — `freshenSucceeded: false`, endpoint frozen at the last dose ~90 s earlier.
    /// The pod kept delivering in that gap. Audit the loan against that endpoint and you are
    /// measuring the wrong interval, which is why the residuals never quite closed.
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
        let persisted = UserDefaults.standard.object(forKey: "PodLoanPhoneController.deliveredAuthoritative") as? Double
        XCTAssertEqual(persisted ?? .nan, 0.900, accuracy: 0.0001)
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
        waitUntil(timeout: 8, "R33 cancel") { self.lock.lock(); defer { self.lock.unlock() }; return self.cancelCalls > 0 }
        XCTAssertEqual(cancelCalls, 1, "cancel exactly once per loan, on the verified round-trip")
        XCTAssertNotNil(diagMatching("R33 temp cancelled"), "the cancel's outcome must be in the log")

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

        waitUntil(timeout: 8, "failed-cancel diag") { self.diagMatching("R33 temp cancel FAILED") != nil }
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
        // BARRIER. The send fires before the controller has finished the grant on its own serial
        // queue, and `grantOfferedAt` — the anchor this class exists to pin — is stamped there.
        // Returning first let a caller advance the test clock BEFORE the stamp, so the anchor was
        // taken at the later time and the elapsed came out +0s instead of +10s.
        controller.queue.sync { }
        guard case .grant(let grant)? = lastSent() else {
            XCTFail("expected a grant, got \(String(describing: lastSent()))")
            fatalError()
        }
        return grant
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

    /// The dangerous mistake this must NOT make. A watch that HAS the grant and is partway
    /// through taking the pod also reports `holdsPod: false` — reading that as "the grant was
    /// lost" would snatch the pod back mid-takeover, which is worse than the bug being fixed.
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

    /// Silence is not "no", and neither is an older build's blank. `knowsGrant == nil` means the
    /// watch could not answer the question — that must fall through to the original 5-minute
    /// timer, never be read as a denial.
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

    /// Drives one clean loan to the authoritative audit with a chosen residual.
    /// `expected` for an eventless loan is the basal schedule (1.0 U/hr) over the loan window,
    /// which the helper keeps at ~0 by handing back immediately — so `delivered` IS the residual.
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

        waitUntil(timeout: 5, "open-loop verdict") { self.diagMatching("R32 OPEN LOOP") != nil }
        XCTAssertEqual(openLoopCalls, 1, "automatic dosing must be stopped exactly once")
        // Escalation: anything that OPENS the loop rides the urgent channel (banner +
        // time-sensitive), never the quiet list.
        XCTAssertTrue(urgentNotices.contains("Loop Open — Unexplained Insulin"), "the user must be told, loudly")
    }

    /// NEGATIVE beyond the bound: the books carry phantom IOB, so the loop runs CAUTIOUS. Opening
    /// it would make the real failure — under-treatment — worse. Warn, keep looping.
    func testLargeNegativeResidualWarnsButKeepsLooping() throws {
        let controller = makeController()
        let grant = establishLoan(controller)

        // The books say a 2 U bolus was delivered; the pod's odometer says nothing moved.
        // (A bolus, not a temp: bolus units enter `expected` exactly, independent of the loan
        // window's length, so the shortfall does not depend on wall-clock timing in the test.)
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

        waitUntil(timeout: 8, "warn verdict") { self.diagMatching("R32 WARN") != nil }
        XCTAssertEqual(openLoopCalls, 0, "a shortfall must NOT open the loop — that worsens under-treatment")
        // "Overstated", not "High" (ruled 2026-08-15): the pod delivered LESS than the records
        // claim, so the books are wrong, not the body. URGENT channel by the 2026-08-24 ruling
        // (symmetric urgency, asymmetric action): both breach directions speak loudly; only the
        // positive one also opens the loop — which the openLoopCalls assertion above pins.
        XCTAssertTrue(urgentNotices.contains("Insulin On Board May Be Overstated"))
    }

    /// The ordinary case — a residual inside the bounds — must be silent. If routine loans warn,
    /// the warning stops meaning anything.
    func testResidualWithinBoundsIsSilent() throws {
        let controller = makeController()
        try runLoanToAudit(controller, deliveredDuringLoan: 0.10)

        XCTAssertEqual(openLoopCalls, 0)
        XCTAssertNil(diagMatching("R32 OPEN LOOP"))
        XCTAssertNil(diagMatching("R32 WARN"))
        XCTAssertTrue(notices.isEmpty, "a normal loan must produce no notice at all, got \(notices)")
    }

    /// Every authoritative residual is still banked — but as DIAGNOSTICS: R32 closed
    /// 2026-08-27 with the window-scoped verdict ratified at ±0.20 U, so the line reports
    /// both series (whole-loan drift trend + worst-window, the distribution a future band
    /// review would read) and must no longer nag for a review that already happened.
    func testResidualsAreBankedAsDiagnosticsWithTheWorstWindowSeries() throws {
        UserDefaults.standard.removeObject(forKey: "PodLoanPhoneController.residualHistory")
        UserDefaults.standard.removeObject(forKey: "PodLoanPhoneController.windowResidualWorst")
        let controller = makeController()
        try runLoanToAudit(controller, deliveredDuringLoan: 0.10)

        let bank = diagMatching("residual bank:")
        XCTAssertNotNil(bank, "each audit must bank its residual and say how many exist")
        XCTAssertTrue(bank!.contains("n=1"), "got: \(bank!)")
        XCTAssertTrue(bank!.contains("window-worst"), "the worst-window series is the review data now: \(bank!)")
        XCTAssertTrue(bank!.contains("R32 closed"), "the line states the ruling, not a demand for one: \(bank!)")
        XCTAssertFalse(bank!.contains("RE-REVIEW DUE"), "the review happened — no nag: \(bank!)")
        XCTAssertEqual((UserDefaults.standard.array(forKey: "PodLoanPhoneController.residualHistory") as? [Double])?.count, 1)
        XCTAssertEqual((UserDefaults.standard.array(forKey: "PodLoanPhoneController.windowResidualWorst") as? [Double])?.count, 1)
    }

    /// The bank is calibration data for CLEAN hand-backs, and two force-reclaim residuals
    /// (+0.800, +0.850) were banked before it was scoped that way — moving the banked max from
    /// +0.000 to +0.850, which is the number the next threshold review would have read. A one-shot
    /// purge at construction repairs it: no clean hand-back can produce more than +0.5 U (2.5× the
    /// open-loop bound, and the legit distribution tops out at zero), and it runs exactly once,
    /// so a later genuine outlier is never quietly deleted.
    func testContaminatedResidualsArePurgedOnceAtLaunch() {
        UserDefaults.standard.set([-0.200, -0.150, 0.800, 0.850, -0.050],
                                  forKey: "PodLoanPhoneController.residualHistory")
        _ = makeController()
        XCTAssertEqual(UserDefaults.standard.array(forKey: "PodLoanPhoneController.residualHistory") as? [Double],
                       [-0.200, -0.150, -0.050],
                       "the two force-reclaim residuals go; every clean sample survives, order intact")

        // ONE SHOT, not a standing rule: a hand-back genuinely above +0.5 U is a loud open-loop event
        // whose residual is still authentic calibration data.
        UserDefaults.standard.set([0.900], forKey: "PodLoanPhoneController.residualHistory")
        _ = makeController()
        XCTAssertEqual(UserDefaults.standard.array(forKey: "PodLoanPhoneController.residualHistory") as? [Double],
                       [0.900], "the flag is already set — a later launch must not purge again")
    }

    /// The tightening itself (±0.5 → ±0.20 U). +0.25 U is the interesting case: it is
    /// over the new bound and UNDER the old one, so this test fails against the previous
    /// thresholds and passes against these. Without it, a silent revert of the constant would go
    /// unnoticed — the other residual tests use ±2 U and stay green either way.
    func testResidualJustAboveTheTightenedBoundOpensTheLoop() throws {
        let controller = makeController()
        try runLoanToAudit(controller, deliveredDuringLoan: 0.25)

        waitUntil(timeout: 5, "open-loop verdict") { self.diagMatching("R32 OPEN LOOP") != nil }
        XCTAssertEqual(openLoopCalls, 1, "+0.25 U is over the 0.20 U bound — the loop must open")
        XCTAssertTrue(urgentNotices.contains("Loop Open — Unexplained Insulin"))
    }

    /// e223 (2026-08-26, field): the loop opened on "+0.200 exceeds +0.20" — delivered 2.400
    /// minus expected 2.200 is 0.20000000000000018 in binary, and the strict > tripped at
    /// nominal EQUALITY with the bound. ±0.200 is the worst clean banked sample; exactly on
    /// the band is inside it. This replicates e223's exact arithmetic.
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
        XCTAssertNil(diagMatching("R32 OPEN LOOP"))
    }

    /// The negative twin, construction borrowed from the pure line's port (2026-08-30): books
    /// claim 2.4 U, the pod metered 12.2−10.0 = 2.1999999999999993 — a raw residual of
    /// −0.2000000000000007, beyond −0.20 by float dust alone. Sturdier than the positive twin:
    /// any schedule-fill accrual pushes the raw residual FURTHER negative, so the unfixed
    /// compare always trips regardless of timing. (On this line fill is pulse-floored to zero
    /// for sub-3-minute windows anyway; this test does not depend on that.)
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
        XCTAssertNil(diagMatching("R32 WARN"), "exactly −0.200 is ON the band — float dust must not warn")
    }

    // MARK: - Since-last-sync checkpoints (ruled 2026-08-26)

    /// A mid-loan record batch carrying a checkpoint snapshot, the way a live watch streams
    /// one after a dose window. `asOf: nil` models an older watch (no checkpoint possible).
    /// Hand the controller a checkpoint AND WAIT for it to be applied.
    ///
    /// `handleIncoming` hops onto the controller's serial queue, and the checkpoint — including
    /// the audit-base advance — is applied there. Returning without waiting let the next step
    /// read the OLD base, which is how `testForceReclaimJudgesOnlyTheTailSinceTheLastSync` judged
    /// a 0.15 U tail as a 1.30 U whole-loan residual and opened the loop. It passed alone, where
    /// an idle machine let the checkpoint win the race, and failed inside the full class — the
    /// whole of this class's order-dependence, and about two hours of gate retries on 2026-09-17.
    ///
    /// A sync hop on that same serial queue returns only once the checkpoint has been applied,
    /// whichever way it went (accepted, carried or rejected).
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

    /// THE point of the checkpoint design: benign drift that accumulates past the band over a
    /// long loan must NOT trip a verdict when every synced window individually reconciled.
    /// +0.30 U of loan-total drift (the overnight false-open of 2026-08-26 was +0.35) split
    /// across two windows of +0.15 each — the whole-loan framing opens the loop, the
    /// since-last-sync framing correctly stays silent.
    func testCheckpointedDriftWithinEachWindowStaysSilent() throws {
        let controller = makeController()
        let grant = establishLoan(controller)   // audit base = 10.0 @ the takeover reading

        try sendCheckpoint(controller, epoch: grant.epoch, latest: 10.15, asOf: Date().addingTimeInterval(2))
        try finishLoan(controller, epoch: grant.epoch, finalOdometer: 10.30)

        XCTAssertEqual(openLoopCalls, 0, "each window reconciled at a sync — no verdict may fire on the loan total")
        XCTAssertNil(diagMatching("R32 OPEN LOOP"))
        XCTAssertNil(diagMatching("R32 WARN"))
    }

    /// The checkpoint must not blunt detection: insulin the tail cannot explain still opens.
    func testUnexplainedTailAfterACheckpointStillOpensTheLoop() throws {
        let controller = makeController()
        let grant = establishLoan(controller)

        try sendCheckpoint(controller, epoch: grant.epoch, latest: 10.0, asOf: Date().addingTimeInterval(2))
        try finishLoan(controller, epoch: grant.epoch, finalOdometer: 10.5)

        waitUntil(timeout: 5, "open-loop verdict") { self.diagMatching("R32 OPEN LOOP") != nil }
        XCTAssertEqual(openLoopCalls, 1, "+0.5 U since the last sync is unexplained — the loop must open")
    }

    /// An older watch sends snapshots without `asOf`; the base must never advance on one, so
    /// the audit keeps its whole-loan window — the exact pre-checkpoint behavior.
    func testSnapshotWithoutAsOfNeverCheckpoints() throws {
        let controller = makeController()
        let grant = establishLoan(controller)

        try sendCheckpoint(controller, epoch: grant.epoch, latest: 10.15, asOf: nil)
        try finishLoan(controller, epoch: grant.epoch, finalOdometer: 10.30)

        waitUntil(timeout: 5, "open-loop verdict") { self.diagMatching("R32 OPEN LOOP") != nil }
        XCTAssertEqual(openLoopCalls, 1, "no asOf = no checkpoint — +0.30 over the whole loan must still open")
    }

    /// A window that does NOT reconcile is carried, never retired: the base stays put, and
    /// the final audit judges the discrepancy with full records. If a breaching checkpoint
    /// wrongly advanced the base, this unexplained 0.5 U would vanish from the audit.
    func testBreachingCheckpointDoesNotAdvanceTheBase() throws {
        let controller = makeController()
        let grant = establishLoan(controller)

        try sendCheckpoint(controller, epoch: grant.epoch, latest: 10.5, asOf: Date().addingTimeInterval(2))
        try finishLoan(controller, epoch: grant.epoch, finalOdometer: 10.5)

        waitUntil(timeout: 5, "open-loop verdict") { self.diagMatching("R32 OPEN LOOP") != nil }
        XCTAssertEqual(openLoopCalls, 1, "a checkpoint that failed to reconcile must not retire its window")
    }

    /// The scenario the design exists for: a loan that synced, then died. The force-reclaim
    /// audit judges only the tail since the last sync — the synced bolus is already in the
    /// records, so it must be neither unexplained (whole-loan anchor) nor double-counted
    /// (unclipped bolus in the tail's expectation).
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
        XCTAssertNil(diagMatching("R37 OPEN LOOP"))
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

    /// Regression guard for the finalize-deadlock fix. An INTERIM offer
    /// (released:false) carrying a still-running temp must ACK the open temp's cursor
    /// (so the watch's `unackedEvents` can empty and it sends the final offer — otherwise
    /// the pod is never handed back) while WITHHOLDING it from the store write; the
    /// subsequent FINAL offer writes it (re-drained from staging). This exercises the
    /// ack-cursor / committedIDs decoupling that the earlier reroute got wrong.
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

    /// §16: released-flag decode, key ABSENT — the wire shape of a watch that predates the
    /// two-phase hand-back.
    ///
    /// The companion decode test lives in LoanProtocolV2Tests; this pins the CONSEQUENCE,
    /// which is what actually matters: a legacy offer must finalize the loan. Such a watch
    /// only ever offers after it has stopped and released the pod, and it will never send
    /// anything more definitive — so treating nil as "interim" would strand the phone in
    /// .loaned with dosing paused indefinitely.
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
        XCTAssertEqual(pauseCalls, [true, false], "dosing is restored — the loan is not left open")
    }

    /// §16: finalize-on-empty-drain. A final offer carrying NO events (everything already
    /// acked during interim drains) must still ack and close the loan. Asserted explicitly
    /// here rather than as a side effect of the interim test, because the failure mode —
    /// "nothing to write, so nothing happens" — leaves the pod on the watch with the phone
    /// paused, and would be invisible in a test that only counts store writes.
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

    /// Bench 2026-09-19: WatchConnectivity carries a hand-back over WiFi, so with this phone's
    /// Bluetooth off the watch still saw it reachable, the final offer was ACKed, and the phone
    /// owned a pod it could not reach. The ack is the gate; a phone that cannot reclaim withholds it.
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

    // MARK: - Field incident: stale offer clamps a LATER epoch's doses

    /// FIELD: WCSession redelivered two already-acked epoch-1 final
    /// offers after a BT-off window. The phone correctly flagged them stale — but the stale
    /// drain reconciles the SHARED staged map, which by then held epoch-2 temps streamed
    /// during the loan, against the STALE offer's `handedBackAt`. Every epoch-2 temp was
    /// clamped to a moment BEFORE it started, producing negative durations; Core Data
    /// rejected the whole batch (Code=1620 "duration is too small"), so the write failed and
    /// no ack was sent. Jeremy then ended the loan and the genuine epoch-2 hand-back hit the
    /// same poisoned objects and failed too, every 15 s, through hand-back attempt 16+.
    ///
    /// This is item 6's standing practice: the incident becomes a harness test while the log
    /// is fresh. It is written as the DESIRED contract (no dose may end before it starts) and
    /// is expected to fail until this is ruled and fixed — XCTExpectFailure keeps the suite,
    /// and therefore the ship gate, honest and green in the meantime. Delete the
    /// XCTExpectFailure when the fix lands; if the test then passes, the fix is real.
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

        // FIXED (option A): a stale offer now drains only the events it actually carried,
        // so epoch 2's live temp is never in scope to be clamped to epoch 1's handedBackAt.
        let written = addedDoses.flatMap { $0 }
        let inverted = written.filter { $0.endDate < $0.startDate }
        XCTAssertTrue(inverted.isEmpty,
                      "a stale offer must never write a dose that ends before it starts — got \(inverted.count) inverted of \(written.count)")

        // And the point of option A over a blanket clamp: the live temp is not written AT ALL by
        // the stale drain. It stays staged for its own epoch's hand-back, where it is still open
        // and still mutable. A guard that merely repaired the duration would have committed a
        // truncated temp and permanently under-booked epoch 2's insulin.
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

    // MARK: - The outbound handover is two states, not one

    /// The tile used to say "Pod on Watch" from the instant the grant was SENT, because
    /// `podIsOnLoan` is already true in `.grantOffered` — asserting a handover that had not
    /// happened. `isPodTakeoverInProgress` separates the two so the tile can show "Taking over…"
    /// first, and it must flip exactly when the watch confirms.
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
//
// The scenario is the watch-battery-dies test: a loan is running, the watch delivers insulin it
// never gets to stream, dies, and the user force-reclaims from the phone. Before the audit the
// phone resumed CLOSED loop on books missing real insulin, with no odometer check at all (the
// salvage line said so itself: "no odometer check — OBS-9").
//
// The audit is a SUBCATEGORY of the hand-back reconciliation audit, not a new protocol: same
// odometer bracket, same ±0.20 bounds, same sign asymmetry, same bank. What differs is the
// response — dosing is HELD from the reclaim until the pod answers, the alerts escalate (the
// watch is dead; the phone is the only device that can speak), and the unexplained insulin books
// as a placeholder bolus that the watch's return retires.
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
        XCTAssertEqual(booked.first?.syncIdentifier, "PODLOAN-ODOGAP-e\(grant.epoch)",
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
        waitUntil(timeout: 5, "clean verdict") { self.diagMatching("R37 audit CLEAN") != nil }

        lock.lock()
        let opened = openLoopCalls
        let booked = bookedGapDoses
        let resumed = pauseCalls.contains(false)
        lock.unlock()

        XCTAssertEqual(opened, 0, "a clean audit does not open the loop")
        XCTAssertTrue(booked.isEmpty, "nothing to book")
        XCTAssertTrue(resumed, "automatic dosing resumes on the clean verdict")
    }

    /// The hold-open behavior, isolated: with the pod unreachable the verdict cannot land, and
    /// dosing must NOT resume — the old unconditional resume-closed is precisely what let the
    /// loop run on books missing a real bolus.
    func testDosingIsHeldUntilTheAuditVerdictArrives() throws {
        let controller = makeController()
        establishLoan(controller)
        MockPumpManager.testOdometer = 12.5

        lock.lock(); connectionReady = false; lock.unlock()   // the pod is not back yet

        controller.forceReclaimToOwner(reason: "test: watch dead, pod not yet reachable")
        waitForState(controller, .owner)
        settle()

        lock.lock()
        let resumedEarly = pauseCalls.contains(false)
        lock.unlock()
        XCTAssertFalse(resumedEarly, "no verdict, no resumption — 'cannot verify' must never become 'assume fine'")

        lock.lock(); connectionReady = true; lock.unlock()    // the pod comes back
        waitUntil(timeout: 8, "verdict after pod returns") { self.lock.lock(); defer { self.lock.unlock() }; return self.pauseCalls.contains(false) }
        lock.lock(); let opened = openLoopCalls; lock.unlock()
        XCTAssertEqual(opened, 1, "and the verdict still opens on the unexplained 2.5 U")
    }

    /// The dead watch is recharged; its journal re-offers the unstreamed events. The real
    /// records commit with their true timestamps and the placeholder retires — replacement,
    /// not partial offset.
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

        lock.lock()
        let deleted = deletedGapSyncs
        // The urgent channel, not the quiet one: the recovered-records message rewrites IOB
        // and COB, so it rides time-sensitive interruption (field request 2026-08-14).
        let recovered = urgentNotices.contains { $0.contains("Watch Records Recovered") }
        lock.unlock()

        XCTAssertEqual(deleted, ["PODLOAN-ODOGAP-e\(grant.epoch)"], "the placeholder retires by its deterministic identity")
        XCTAssertTrue(recovered, "the user is told their numbers changed, and why")
        waitUntil(timeout: 5, "state cleared") {
            UserDefaults.standard.dictionary(forKey: "PodLoanPhoneController.gapBooking") == nil
        }
    }

    /// A redelivered PRE-death offer carries only events the salvage already committed. It
    /// explains nothing new, so it must not retire the placeholder — that would erase the gap
    /// insulin while the real tail is still missing.
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
        XCTAssertNotNil(UserDefaults.standard.dictionary(forKey: "PodLoanPhoneController.gapBooking"))
    }

    /// The peer session's catch: the doc comment on retireGapBookingIfExplained claimed a failed
    /// delete is "retried on the next offer and at launch" — but retireGapBookingIfExplained has
    /// exactly one caller, inside an offer's write completion, AFTER the handbackAck that stops
    /// the watch's 15 s resend loop. So a delete that fails once could outlive every offer that
    /// would have retried it, with the placeholder stuck forever. This proves the launch half of
    /// that claim is now real: a FRESH controller — no offer, no audit in flight, nothing but the
    /// persisted gap state from a previous session — must retry the delete on construction.
    /// RULED 2026-08-15: the launch retry fires ONLY for a booking whose delete failed AFTER the
    /// watch's real records committed — `deleteFailedAfterRecords`. Before that flag existed this
    /// fixture (a bare booking) also retried, which is the defect: a placeholder that nothing had
    /// explained was deleted at the next launch, silently dropping 0.2-3 U of conservative IOB.
    /// The un-flagged case is now pinned by testPersistedGapWithoutRecordsSurvivesLaunch below.
    func testPersistedGapDeleteRetriesOnFreshLaunch() throws {
        UserDefaults.standard.set(["epoch": 7, "units": 1.75, "bookedAt": Date().timeIntervalSince1970,
                                   "deleteFailedAfterRecords": true],
                                  forKey: "PodLoanPhoneController.gapBooking")

        // Held for the test's duration — init's retry runs on a `[weak self]` queue.async, so an
        // unretained controller can deallocate before its own retry fires.
        let controller = makeController()   // simulates the next app launch finding stale gap state
        _ = controller

        waitUntil(timeout: 5, "launch retry succeeds") {
            UserDefaults.standard.dictionary(forKey: "PodLoanPhoneController.gapBooking") == nil
        }
        lock.lock()
        let deleted = deletedGapSyncs
        lock.unlock()
        XCTAssertEqual(deleted, ["PODLOAN-ODOGAP-e7"], "retried against the PERSISTED epoch, no offer involved")
    }

    /// Launch-while-locked (field crash 2026-08-27, TF 141): a reboot mid-loan relaunches
    /// Loop in the background BEFORE FIRST UNLOCK, where every protected store file is still
    /// sealed. The launch retry must WAIT for protected data, then run — not race the lock.
    func testLaunchStoreWorkWaitsForProtectedData() throws {
        UserDefaults.standard.set(["epoch": 9, "units": 1.0, "bookedAt": Date().timeIntervalSince1970,
                                   "deleteFailedAfterRecords": true],
                                  forKey: "PodLoanPhoneController.gapBooking")
        var unlock: (() -> Void)?
        let controller = makeController(whenProtectedDataAvailable: { work in unlock = work })
        _ = controller

        // Locked: the retry must not have touched the store.
        Thread.sleep(forTimeInterval: 0.3)
        lock.lock(); let attemptsWhileLocked = deletedGapSyncs.count; lock.unlock()
        XCTAssertEqual(attemptsWhileLocked, 0, "store work ran during the pre-first-unlock window")
        XCTAssertNotNil(UserDefaults.standard.dictionary(forKey: "PodLoanPhoneController.gapBooking"))

        // First unlock: the deferred work runs and the retry completes.
        unlock?()
        waitUntil(timeout: 5, "deferred retry runs at unlock") {
            self.lock.lock(); defer { self.lock.unlock() }; return self.deletedGapSyncs == ["PODLOAN-ODOGAP-e9"]
        }
    }

    /// The failure side of the same path: launch retry fails again, state must survive for yet
    /// another attempt rather than being dropped or silently swallowed.
    func testPersistedGapDeleteThatFailsAgainAtLaunchKeepsState() throws {
        UserDefaults.standard.set(["epoch": 3, "units": 0.9, "bookedAt": Date().timeIntervalSince1970,
                                   "deleteFailedAfterRecords": true],
                                  forKey: "PodLoanPhoneController.gapBooking")
        lock.lock(); gapDeleteSucceeds = false; lock.unlock()

        let controller = makeController()
        _ = controller

        waitUntil(timeout: 5, "launch retry attempted") { self.lock.lock(); defer { self.lock.unlock() }; return !self.deletedGapSyncs.isEmpty }
        XCTAssertNotNil(UserDefaults.standard.dictionary(forKey: "PodLoanPhoneController.gapBooking"),
                        "still failing — state must survive for the NEXT launch or offer, not vanish")
    }

    /// The case the old guard could not express, and the reason it was wrong: a placeholder that
    /// nothing ever explained. The watch never came back, so no real records arrived, so no
    /// delete was ever attempted — and the booking is still TRUE. It must survive the launch
    /// intact, because the insulin it stands for is still in the body and the user was told the
    /// booking was there to keep IOB conservative. Losing the watch for good is exactly when
    /// that margin matters most (ruled 2026-08-15).
    func testPersistedGapWithoutRecordsSurvivesLaunch() throws {
        UserDefaults.standard.set(["epoch": 11, "units": 0.85, "bookedAt": Date().timeIntervalSince1970],
                                  forKey: "PodLoanPhoneController.gapBooking")

        let controller = makeController()   // the next app launch
        _ = controller

        // Give init's queue.async retry the same room the other launch tests give it; the
        // assertion is that nothing happens in that window.
        let settled = expectation(description: "launch settled")
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) { settled.fulfill() }
        wait(for: [settled], timeout: 5)

        lock.lock(); let deleted = deletedGapSyncs; lock.unlock()
        XCTAssertTrue(deleted.isEmpty, "an unexplained placeholder must NOT be deleted at launch — the insulin is still real")
        XCTAssertNotNil(UserDefaults.standard.dictionary(forKey: "PodLoanPhoneController.gapBooking"),
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
        XCTAssertNotNil(UserDefaults.standard.dictionary(forKey: "PodLoanPhoneController.gapBooking"),
                        "state survives a failed delete, so the next offer retries it")
    }

    // MARK: - Reclaim ladder (2026-08-13)

    /// Every revoke the controller has sent so far. The ladder's whole contract is "two attempts,
    /// then force", and this is the only way to state the "two" half.
    private func revokeCount() -> Int {
        lock.lock(); defer { lock.unlock() }
        return sent.filter { if case .revoke = $0 { return true } else { return false } }.count
    }

    /// Reclaim tap → the ladder arms the LIVE deadlines, and the force does not run until the
    /// second attempt has been spent. A watch heard from 30 s ago is inside the loan's 300 s log
    /// pulse, so there is a real drain to wait for.
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
        XCTAssertNotNil(diagMatching("reclaim ladder LIVE"), "the branch and its evidence are in the field log")

        ladder.fire("reclaim-resend")
        XCTAssertEqual(revokeCount(), 2, "the second attempt is a resend, not a force")
        XCTAssertEqual(controller.state, .reclaimPending, "an attempt is not a verdict")

        ladder.fire("reclaim-force")
        waitForState(controller, .owner)
        XCTAssertEqual(revokeCount(), 2, "two attempts is the whole budget")
    }

    /// The live handover's bar fills to its 10 s drain promise; past it, the phase concedes
    /// ("No watch reply…") with the bar held at cap and the deadline republished as the force
    /// rung's — the next event that actually resolves anything.
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

    /// The same tap against a watch nobody has heard from in 12 minutes — five of the six field
    /// revokes looked exactly like this. Shorter ladder, and the tile is told to stop implying a
    /// drain is happening.
    /// The dead branch does not wait. The reclaims that land here are, realistically, a lost
    /// watch or a dead battery — nothing can answer — and an alive watch cannot normally reach
    /// this branch at all, because its 300 s log pulse keeps it inside the liveness window. So:
    /// one revoke goes out fire-and-forget (the returning-watch record flow rides on it), the
    /// force is armed at ZERO delay, and no resend rung exists to push a second revoke at a
    /// watch that is not there.
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

    /// A settle that follows a FORCE reclaim runs against its own 15 s promise — a little looser
    /// than the ordinary settle's, because the clean forced sample is thin (one measurement at
    /// +1 s; the earlier +45/+66/+70 s all carried the stale-read signature of the freshness
    /// bug). No re-baseline mid-force, and an overrun holds at the cap.
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
        // ONE promise for both settle flavors (lean ruling 2026-08-23) — the label differs,
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

    /// The good case: the watch drains before the first deadline. Both rungs must die with the
    /// loan — a resend fired afterwards would push a revoke at a watch that already handed back,
    /// and a force would fire against a phone that is already the owner.
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
        XCTAssertNil(controller.reclaimProgress, "nothing left to draw a determinate bar for")

        // Belt and braces: even if a rung reached its deadline anyway, its guards refuse.
        ladder.fire("reclaim-resend")
        ladder.fire("reclaim-force")
        XCTAssertEqual(revokeCount(), revokesAtTap, "no revoke may go out after the loan is over")
        XCTAssertEqual(controller.state, .owner)
    }

    /// A reachability wake-up while a LIVE ladder waits re-sends the parked revoke — the best-
    /// timed attempt available, going out while the watch is provably awake — and it COUNTS
    /// against the two-attempt budget, so the resend rung never buys a third. (The dead-branch
    /// promotion that used to live here is gone with the dead branch's wait: a dead ladder
    /// forces immediately, so there is no window left for a waking watch to promote.)
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

    // MARK: - The BLE settle is the wait the bar draws (2026-08-14)

    /// A REGULARLY ENDED session: the watch hands back on its own, so no reclaim ladder is ever
    /// armed. Everything the user waits through afterwards is the settle, and it used to get an
    /// indeterminate sweep for the whole of it precisely because the progress was gated on a
    /// ladder this path never has.
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

    /// A phone-TAPPED reclaim crosses two waits, and BOTH draw a bar now — the handover against
    /// the drain promise, the settle against its own. The reclaim must stay DESCRIBED across the
    /// whole crossing, because the tile's label is chosen from the published phase and a nil
    /// there relabels the wait to the generic "Reclaiming…" for the length of a store write.
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

    /// The promise is an EXPECTATION, not a ceiling: the slow mode existed (24-190 s on record,
    /// diagnosed as verification calls that skipped the radio and fixed by the forced read) and
    /// could recur. The bar caps at 0.95 and STAYS there — the 5-minute settle timeout is the
    /// real bound — while the elapsed seconds keep climbing, which is the only thing left on
    /// the tile that can say the phone is still working. No re-baseline, no phase change: one
    /// promise, held.
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

    /// The settle must FORCE a real pod round-trip rather than trusting the cheap call, because
    /// the cheap one skips the radio entirely whenever the manager judges its data fresh (under
    /// 6 minutes) and hands back the pre-existing lastSync — which this settle's `lastSync >
    /// started` test then rejects forever. Measured 2026-08-14: 77 such calls returned in about
    /// 150 ms each, no radio involved, and the settle sat at 169 s until a manual status check
    /// broke it.
    ///
    /// The 12 s backoff this test used to assert was DELETED (lean ruling 2026-08-23): with the
    /// reclaim dialing at re-arm, every measured settle verifies on the first read after
    /// link-up, so the spacing guarded radio time no settle spends anymore. What still deserves
    /// asserting is the shape that replaced it: reads are real (forced) from tick 0, and the
    /// in-flight latch — now the only throttle — keeps concurrent ticks from stacking reads.
    ///
    /// The virtual clock is parked an hour ahead so the mock's real-dated lastSync can never
    /// exceed `started` — that keeps the settle open for the whole test instead of verifying on
    /// the first read.
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

        // More 2 s ticks pass; each one may force again (the mock resolves reads instantly, so
        // the latch never blocks here). The assertion is a floor, not a ceiling: reads must
        // KEEP being real for as long as the settle is open.
        let ticksPassed = XCTestExpectation(description: "several ticks pass")
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) { ticksPassed.fulfill() }
        wait(for: [ticksPassed], timeout: 10)
        XCTAssertGreaterThanOrEqual(MockPumpManager.testForcedReadCount, 2,
                                    "an open settle keeps doing REAL round-trips — the cheap no-radio path is what stalled 169 s in the field")
        XCTAssertTrue(controller.isReclaimSettling, "the settle is still open, so ticks are still running")

        // PARK THE CHASE. This settle can never verify (the clock is an hour ahead of anything
        // the mock will report), so it runs to the 5-minute ceiling — and unlike the other
        // settle tests, which hold the link DOWN and leave an inert loop, this one holds it up
        // and would keep calling the shared pump every 2 s straight through the tests that run
        // after it. Dropping the link makes the leftover loop a no-op, as it is everywhere else.
        connectionReady = false
    }

    /// The end condition. "The pod is back" is a completed pod round-trip, not a Bluetooth state,
    /// so the bar clears on the verification and not a moment earlier.
    func testSettleProgressClearsOnceTheRoundTripVerifies() throws {
        // Real clock here on purpose: verification compares the pump's own lastSync against the
        // settle's start, and a frozen clock would be asserting against MockPumpManager's stamp
        // rather than against the controller.
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
        // The background hold pairs with the wait it covered: begun when the settle opened,
        // ended by the verification. Unbalanced at rest = a hold nobody is using, which iOS
        // charges against the app and eventually kills.
        lock.lock(); let begins = backgroundTaskBegins; let ends = backgroundTaskEnds; lock.unlock()
        XCTAssertGreaterThanOrEqual(begins, 1, "the reclaim held background execution for its wait")
        XCTAssertEqual(ends, begins, "every hold released once the wait resolved")
    }

    // MARK: - Request TTL (queued-channel ghosts)

    /// A request that aged past the TTL in the queued channel must not earn a grant. Field
    /// 2026-08-30: two requests queued against a powered-off phone detonated at power-on —
    /// the five-minute-old first copy was granted (releasing the pod at a watch that was
    /// no longer asking), the second denied against .grantOffered, and the recovery
    /// force-reclaimed the fresh grant. The requestID dedupe cannot catch this (two real
    /// taps carry two IDs); age can. A fresh request afterwards must still grant — and
    /// establishLoan's nil-sentAt request doubles as the older-watch compat check.
    func testStaleRequestIsIgnoredAndAFreshOneStillGrants() throws {
        let controller = makeController(now: { self.clock })

        controller.handleIncoming(userInfo: try LoanMessage.request(
            LoanRequest(watchBuild: "t", sentAt: clock.addingTimeInterval(-300))).transportDictionary())

        // The ghost's rejection is a silent return; give its queue block time to run, then
        // assert the state machine never moved. (A regression flips state synchronously
        // inside that block — epoch += 1, state = .grantOffered — so stillness here is the
        // whole assertion, not a race.)
        usleep(400_000)
        XCTAssertEqual(controller.state, .owner, "a stale request must not move the state machine")
        lock.lock(); let sentDuringGhost = sent; lock.unlock()
        XCTAssertTrue(sentDuringGhost.isEmpty, "a stale request earns NOTHING — no grant, no denial: \(sentDuringGhost)")

        try establishLoan(controller)   // fresh (nil-sentAt) request still grants — liveness + back-compat
    }

    // MARK: - Dormant-refresh throttle (R40 seize credential pipe)

    /// The refresh throttle stamps at ENQUEUE, not completion: LoopDataUpdated arrives in
    /// bursts faster than grant assembly finishes, and completion-stamping let five
    /// identical 25 KB refreshes through one gate in a single second (field 2026-08-30) —
    /// straight into the queued channel a 7001 jam later backed up. A burst must yield ONE.
    func testDormantRefreshBurstYieldsOneRefresh() {
        UserDefaults.standard.set(true, forKey: "PodLoanPhoneController.watchSupportsSeize")
        defer { UserDefaults.standard.removeObject(forKey: "PodLoanPhoneController.watchSupportsSeize") }
        let controller = makeController()

        let firstRefresh = expectSend()
        for _ in 0..<5 { controller.considerDormantRefresh() }
        wait(for: [firstRefresh], timeout: 5)
        // All five gate blocks ran before the first assembly's send (same serial queue);
        // any leaked extra assemblies are already enqueued behind it — a short settle
        // flushes them into `sent` where the count can convict them.
        usleep(400_000)

        lock.lock()
        let refreshes = sent.filter { if case .dormantGrant = $0 { return true }; return false }
        lock.unlock()
        XCTAssertEqual(refreshes.count, 1, "one burst, one refresh — the throttle stamps at enqueue")
    }

    // MARK: - PHONE MIRROR (R40(a), the minimum-deviation paradigm)

    private func seizeCredentialOutstanding() -> UUID {
        let token = UUID()
        UserDefaults.standard.set(token.uuidString, forKey: "PodLoanPhoneController.dormantSeizeToken")
        UserDefaults.standard.set(true, forKey: "PodLoanPhoneController.watchSupportsSeize")
        return token
    }

    private func futureEpochBatch(epoch: Int) throws -> [String: Any] {
        let now = Date()
        let event = LoanEvent(id: UUID(), seq: 1, provenance: .confirmed,
                              record: LoanDoseRecord(kind: .bolus, startDate: now, amount: 0.5), loggedAt: now)
        return try LoanMessage.doseRecordBatch(DoseRecordBatch(epoch: epoch, events: [event], tombstones: [])).transportDictionary()
    }

    /// Detector B (row 6): a future-epoch batch at .owner is live evidence of a loan this
    /// phone never granted. Field 2026-08-30 23:43: the drop line fired and the phone went
    /// on to bolus the pod as its own. Now the same evidence yields — pill flips to Pod on
    /// Watch, dosing pauses, and the pod's BLE is released so the watch can keep dosing.
    /// The batch itself stays dropped; booking still waits for the token-bearing offer,
    /// whose retro-ack then clears the flag by adopting the loan for real.
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

        // The watch's INTERIM offer arrives (token + higher epoch; released=false is what
        // a live seized loan streams — nil would mean FINAL by the legacy convention and
        // march straight through .loaned to the drain-close): retro-ack adopts the loan,
        // the flag's job is done, and .loaned HOLDS because the loan is still running.
        controller.handleIncoming(userInfo: try LoanMessage.handbackOffer(
            HandbackOffer(epoch: 5, handedBackAt: Date(), finalStatus: nil, odometer: nil,
                          events: [], tombstones: [], recovered: false, released: false,
                          seizeToken: token)).transportDictionary())
        waitUntil(timeout: 5, "retro-ack adopted") { controller.state == .loaned && !controller.yieldingToInferredLoan }
        XCTAssertFalse(controller.yieldingToInferredLoan, "the inferred loan became the adopted loan")
    }

    /// The pill tap from the yielded posture takes the inherited road: reclaimNow →
    /// ladder (dead branch forces immediately — the watch is silent) → forceReclaimToOwner
    /// → dosing resumes. Same taps, same machinery, same outcome as a granted dead-watch loan.
    func testInferredYieldPillTapTakesTheInheritedRoad() throws {
        _ = seizeCredentialOutstanding()
        let controller = makeController()
        controller.handleIncoming(userInfo: try futureEpochBatch(epoch: 5))
        waitUntil(timeout: 5, "yield engaged") { controller.yieldingToInferredLoan }

        controller.reclaimNow()
        // Wait on the TERMINAL condition, not the state alone: the controller starts at
        // .owner, so a bare waitForState(.owner) can fulfill on a pre-transition sample
        // before reclaimNow's queue block has even run. The dead branch forces
        // immediately; released flipping false is the force's own first act.
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

    /// The veto's posture can never trap the user (the rule, 2026-09-13: phone Bluetooth on
    /// and pod reachable ⇒ the phone can always take the pod). The tile routes its tap to
    /// Reclaim Now from the yield (it used to route on `state != .owner` alone and fall
    /// through to the stock pod screen), the phone says why it went quiet, and the reclaim
    /// re-arms the bid — which is what clears the loan interlock the release armed.
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

    /// The ghost-drain theft, fixed (field 2026-08-31 12:44): a reboot-era FINAL offer
    /// for the old epoch retro-acks and drains while the LIVE successor loan streams.
    /// The batches that arrive mid-drain are remembered as evidence in ANY state, and the
    /// close then commits the books but does NOT resume custody — no reclaim, dosing
    /// stays paused, yield engaged. The old behavior reclaimed the pod and R33-canceled
    /// the live loan's temp out from under it.
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

        XCTAssertEqual(controller.state, .owner, "books closed at .owner…")
        XCTAssertTrue(MockPumpManager.testConnectionReleased, "…but custody NOT resumed — the pod stays the live loan's")
        lock.lock(); let paused = pauseCalls; lock.unlock()
        XCTAssertNotEqual(paused.last, false, "and dosing never resumed under the live loan")
    }

    /// Fix 4b: the epoch rides the dormant-refresh fingerprint, so every epoch advance
    /// re-issues the credential immediately — no 30-minute staleness window in which a
    /// spent provisional epoch can be reused or bricked by a recorded revoke.
    func testEpochAdvanceRefreshesTheDormantCredential() throws {
        let token = seizeCredentialOutstanding()
        UserDefaults.standard.set(true, forKey: "PodLoanPhoneController.watchSupportsSeize")
        let controller = makeController()

        let first = expectSend()
        controller.considerDormantRefresh()
        wait(for: [first], timeout: 5)

        // Advance the epoch without touching settings: retro-ack e3 and drain it closed.
        // (Terminal-condition wait: the controller STARTS at .owner, so wait on the
        // drain's ack instead of the state.)
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

    /// Fix 3: the retro-ack anchors the audit window at the offer's own era instead of
    /// clearing it to nil — which fell back to the reconciler's 2-hour default and judged
    /// a 5-minute seized loan over the whole morning (loanMin=120, phantom -1.15/-1.30).
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

        let anchor = UserDefaults.standard.object(forKey: "PodLoanPhoneController.loanStartedAt") as? Date
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

    /// The ghost-grant wedge, healed (field 2026-08-31 21:21): a queued request detonated at
    /// reunion, the phone granted over a live seized loan, and .grantOffered sat on
    /// "Handing over…" forever — the watch's wrong-phase refusal guarantees no
    /// takeoverComplete. The watch now answers with holdsPod for its newer loan; the phone
    /// abandons the ghost into the yield posture, and the later token-bearing offer adopts
    /// the burned epoch forward exactly as the .owner path always has.
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

        // The reunion: the seized loan's offer adopts the burned epoch forward (276→277 on tape).
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

    /// The pill tap from the yielded posture AIMS the revoke at the live loan the evidence
    /// names (field 2026-08-31 21:24: a revoke at the phone's own stale epoch was refused as
    /// matching no live session, and the ladder force-stole a pod that would have drained).
    /// The watch's drain then answers through the .reclaimPending retro-ack door — no force.
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
        // The revoke is sent from INSIDE reclaimNow's queue block, before that block sets
        // .reclaimPending — and the yield flag is already cleared at its top. Wait for the
        // state, or the terminal condition below can be sampled inside that gap and the offer
        // lands at .owner instead of at the door this test exists to prove.
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

    // MARK: - Grant anchor (2026-08-17)

    /// A FAILED TAKEOVER MUST NOT LEAK ITS CLOCK INTO THE NEXT GRANT.
    ///
    /// `grantOfferedAt` was stamped only when nil and cleared only on a SUCCESSFUL takeover, so an
    /// abandoned attempt left its anchor behind and the next grant inherited it. Field 2026-08-17:
    /// e59 reported "takeover IN PROGRESS at +145s" twenty-one seconds after its own grant — it was
    /// quoting e58's clock.
    ///
    /// Not a cosmetic log defect: the anchor drifts further out with every failure, so a stale
    /// clock misreports every later takeover. It used to be load-bearing — the elapsed was measured
    /// against `takeoverProgressCeiling` to decide whether to extend the dead-man — but that
    /// extension was removed 2026-09-09; this test now pins the anchor itself.
    func testANewGrantDoesNotInheritAFailedTakeoversClock() throws {
        clock = Date()
        let controller = makeController(now: { [weak self] in self?.clock ?? Date() })

        // Grant once, then abandon it the way the field did: the watch says the grant never
        // arrived, which reclaims to owner — and under the old code never cleared the anchor.
        let g1 = offerGrant(controller)
        controller.handleIncoming(userInfo: try LoanMessage.statusReport(
            StatusReport(epoch: g1.epoch, mode: .closedDirect, lastDirectGlucoseAge: nil,
                         lastEventSeq: 0, podFault: nil, holdsPod: false, knowsGrant: false)
        ).transportDictionary())
        waitForState(controller, .owner)

        // SIX minutes, not two: the reclaim's settle window (`reclaimSettleTimeout`, 5 min) denies
        // a new grant until the phone's own pod round-trip has verified the pod is home, and that
        // verification is ASYNCHRONOUS. At two minutes this test was racing it — green on an idle
        // machine, denied ("The pod is still returning from the last session") under load. Stepping
        // past the window settles it on the test's own clock, which is the right dependency: this
        // test is about the grant ANCHOR, not about settle timing.
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


    // MARK: - Dosing strategy is overridden for the loan, never on the phone

    /// The watch doses by temp basal only. Before this, a phone on automaticBolus made the wrist
    /// refuse EVERY cycle — field-confirmed on the first live run: the watch held the pod and never
    /// dosed at all, for a user whose therapy is a continuous stream of small automatic boluses.
    func testGrantCarriesTempBasalOnlyWhenThePhoneRunsAutomaticBolus() {
        settings.automaticDosingStrategy = .automaticBolus
        let controller = makeController()
        let grant = establishLoan(controller)

        guard let carried = LoopSettings(rawValue: try! PropertyListSerialization.propertyList(
                from: grant.therapySettingsRaw, options: [], format: nil) as! LoopSettings.RawValue) else {
            return XCTFail("grant's therapy settings did not decode")
        }
        XCTAssertEqual(carried.automaticDosingStrategy, .tempBasalOnly,
                       "the wrist must receive temps-only, or it refuses every cycle and doses nothing")
    }

    /// The whole reason the override lives in the SNAPSHOT rather than in the phone's stored
    /// setting: there is nothing to restore, so no failed restore can strand her on temps forever.
    /// A relaunch mid-loan, a force reclaim, a dead watch or a killed app would each have skipped a
    /// restore step — and that would be a lasting therapy change from a bookkeeping miss.
    func testOverridingForTheLoanDoesNotTouchThePhonesOwnSetting() {
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

/// Holds the reclaim ladder's rungs still. The controller schedules them through `scheduler`, so
/// a test can read the geometry it armed and jump to a deadline on demand — without which these
/// tests would spend 25 real seconds each waiting for a force.
///
/// Every arming is kept, not just the latest: a superseded rung still exists in production, and a
/// test that discarded it could not say whether the promotion actually retired the old force.
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

    /// 2026-09-08: a watch went silent mid-loan and nothing said so for four hours. The phone now
    /// WARNS — at about twenty, forty and sixty minutes, then stops — and takes nothing: a watch
    /// that is alive but unheard is still dosing, and the decision to take the pod is the user's.
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

    /// An audit consumes its anchors. 2026-09-19: a loan ended cleanly; hours later a reclaim with
    /// no loan of its own audited from that loan's start and booked 3.45 U of already-recorded
    /// insulin.
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

    /// Bench 2026-09-20: the phone took the pod back while the watch was powered off, the queued
    /// revoke arrived 31 minutes late, and the watch resumed the session — both ran the pod for 68
    /// minutes while the phone dropped every batch in silence. Records from a closed session are
    /// the watch saying "I still hold the pod"; the answer is the revoke, again.
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

    /// The watch's standing copy follows the book: a bolus or a carb entry refreshes it without
    /// waiting for the 30-minute floor, a burst collapses to one, and a change inside the short
    /// floor is not lost.
    func testTheStandingCopyFollowsTheBook() {
        UserDefaults.standard.set(true, forKey: "PodLoanPhoneController.watchSupportsSeize")
        defer { UserDefaults.standard.removeObject(forKey: "PodLoanPhoneController.watchSupportsSeize") }
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

    /// 2026-09-18: a queued message landed 65 minutes late and was believed. A report counts by
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
