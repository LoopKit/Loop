//
//  SeizeActivationTests.swift
//  WatchAppTests
//
//  The phoneless-start (seize) activation contract: live lease on rebuild, offer only with a
//  stored credential, reachability shortens the timeout, token persisted only at `.active`.
//

import XCTest
import HealthKit
import LoopKit
import LoopCore
import LoopAlgorithm
import G7SensorKit
@testable import OmnipodKit
@testable import WatchApp

@MainActor
final class SeizeActivationTests: XCTestCase {

    private var cacheDir: URL!
    private var cacheStore: PersistenceController!
    private var journalDir: URL!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        try await super.setUp()
        cacheDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        cacheStore = PersistenceController(directoryURL: cacheDir)
        journalDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: journalDir, withIntermediateDirectories: true)
        defaults = UserDefaults(suiteName: "SeizeActivationTests-\(UUID().uuidString)")!
    }

    override func tearDown() async throws {
        cacheStore = nil
        cacheDir = nil
        journalDir = nil
        defaults = nil
        try await super.tearDown()
    }

    /// `readsCGM`: the watch has its own CGM reading (Read on Apple Watch), so it can start without the phone.
    private func makeController(readsCGM: Bool = true) async -> PodLoanWatchController {
        let doseStore = await DoseStore(
            healthKitSampleStore: nil,
            cacheStore: cacheStore,
            longestEffectDuration: ExponentialInsulinModelPreset.rapidActingAdult.effectDuration,
            provenanceIdentifier: "SeizeActivationTests"
        )
        let glucoseStore = await GlucoseStore(
            healthKitSampleStore: nil,
            cacheStore: cacheStore,
            cacheLength: 4 * 60 * 60,
            provenanceIdentifier: "SeizeActivationTests"
        )
        let carbStore = CarbStore(
            healthKitSampleStore: nil,
            cacheStore: cacheStore,
            cacheLength: 24 * 60 * 60,
            provenanceIdentifier: "SeizeActivationTests"
        )
        let manager = WatchLoopManager(doseStore: doseStore, glucoseStore: glucoseStore, carbStore: carbStore,
                                       defaults: defaults, stateDirectory: journalDir)
        if readsCGM { manager.noteCGMManager(G7CGMManager()) }
        return PodLoanWatchController(loopManager: manager,
                                      journal: LoanEventJournal(directory: journalDir),
                                      stateDirectory: journalDir)
    }

    /// A dormant credential as the phone builds it (expiresAt == issuedAt). `completeSettings` gets
    /// an activation as far as the journal; it still dies at the pump rebuild.
    private func fixtureDormant(issuedAt: Date, epoch: Int = 3, token: UUID = UUID(),
                                completeSettings: Bool = false) -> DormantGrant {
        let grant = LoanGrant(epoch: epoch, expiresAt: issuedAt,
                              pumpConfiguration: Data([1, 2, 3]), therapySettingsRaw: completeSettings ? Self.completeTherapySettingsRaw() : Data([4, 5]),
                              settingsTimeZoneID: "GMT",
                              doseHistory: [],
                              // `LoopSettings.rawValue` drops the schedules, so a complete grant carries the supplement.
                              therapySettingsSupplementRaw: completeSettings ? Self.settingsSupplementRaw() : nil)
        return DormantGrant(grant: grant, issuedAt: issuedAt, seizeToken: token)
    }

    private static func fixtureSchedules() -> (basal: BasalRateSchedule, isf: InsulinSensitivitySchedule, cr: CarbRatioSchedule) {
        let tz = TimeZone(identifier: "GMT")!
        return (BasalRateSchedule(dailyItems: [RepeatingScheduleValue(startTime: 0, value: 1.0)], timeZone: tz)!,
                InsulinSensitivitySchedule(unit: .milligramsPerDeciliter, dailyItems: [RepeatingScheduleValue(startTime: 0, value: 50.0)], timeZone: tz)!,
                CarbRatioSchedule(unit: .gram, dailyItems: [RepeatingScheduleValue(startTime: 0, value: 10.0)], timeZone: tz)!)
    }

    /// A fully-populated LoopSettings snapshot, serialized the way a grant carries it.
    private static func completeTherapySettingsRaw() -> Data {
        let tz = TimeZone(identifier: "GMT")!
        let schedules = fixtureSchedules()
        var settings = LoopSettings()
        settings.dosingEnabled = false
        settings.glucoseTargetRangeSchedule = GlucoseRangeSchedule(unit: .milligramsPerDeciliter, dailyItems: [RepeatingScheduleValue(startTime: 0, value: DoubleRange(minValue: 100, maxValue: 110))], timeZone: tz)
        settings.insulinSensitivitySchedule = schedules.isf
        settings.basalRateSchedule = schedules.basal
        settings.carbRatioSchedule = schedules.cr
        settings.maximumBasalRatePerHour = 3.0
        settings.maximumBolus = 5.0
        return try! PropertyListSerialization.data(fromPropertyList: settings.rawValue, format: .binary, options: 0)
    }

    /// The schedules rawValue-serialization drops, carried alongside — the wrist re-applies
    /// them before its completeness check (see handleGrant's supplement block).
    private static func settingsSupplementRaw() -> Data {
        let schedules = fixtureSchedules()
        let supplement: [String: Any] = [
            "basalRateSchedule": schedules.basal.rawValue,
            "insulinSensitivitySchedule": schedules.isf.rawValue,
            "carbRatioSchedule": schedules.cr.rawValue,
        ]
        return try! PropertyListSerialization.data(fromPropertyList: supplement, format: .binary, options: 0)
    }

    // MARK: - The root-cause pin

    /// The rebuild mints both the fresh epoch and the live lease (without the lease,
    /// the lease guard kills the takeover at its first read).
    func testActivationRebuildMintsTheEpochAndTheLiveLease() {
        let issuedAt = Date().addingTimeInterval(-3600)   // an hour-old credential, routine for seize
        let dormant = fixtureDormant(issuedAt: issuedAt, epoch: 3)
        XCTAssertEqual(dormant.grant.expiresAt, issuedAt, "precondition: dormant lease is issuedAt by contract")

        let leaseUntil = Date().addingTimeInterval(PodLoanWatchController.seizeActivationLease)
        let rebuilt = dormant.grant.withEpoch(9, leaseUntil: leaseUntil)

        XCTAssertEqual(rebuilt.epoch, 9, "the provisional epoch is forced fresh")
        XCTAssertEqual(rebuilt.expiresAt, leaseUntil,
                       "the LIVE lease is minted at activation — the handshake starts at the confirm, not at issue")
        XCTAssertGreaterThan(rebuilt.expiresAt.timeIntervalSinceNow, PodLoanWatchController.seizeActivationLease - 5,
                             "an hour-old credential must still enter the ladder with (almost) the full lease")
        // Every other field carries verbatim.
        XCTAssertEqual(rebuilt.pumpConfiguration, dormant.grant.pumpConfiguration)
        XCTAssertEqual(rebuilt.therapySettingsRaw, dormant.grant.therapySettingsRaw)
        XCTAssertEqual(rebuilt.settingsTimeZoneID, dormant.grant.settingsTimeZoneID)
    }

    // MARK: - The entry gate

    /// A seized loan's phase and reunion token are saved together: a kill right after the phase
    /// lands can no longer leave an active seized loan the phone cannot retro-acknowledge.
    func testTheReunionTokenIsSavedWithTheActivePhase() async {
        let controller = await makeController()
        let token = UUID()
        controller.pendingSeizeToken = token
        let dir = journalDir!
        var savedAtActive: PodLoanWatchState?
        let observer = NotificationCenter.default.addObserver(forName: .podLoanPhaseDidChange, object: nil, queue: nil) { _ in
            let file = PersistedProperty<[String: Any]>(key: "PodLoanWatchState", directory: dir)
            if let state = file.wrappedValue.flatMap(PodLoanWatchState.init(rawValue:)), state.phase == .active, savedAtActive == nil {
                savedAtActive = state
            }
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        await controller.onMain { controller.recordTakeoverActive(delivered: 10, at: Date()) }
        XCTAssertEqual(savedAtActive?.seizeToken, token, "the first save that reads active already holds the token")
        XCTAssertEqual(savedAtActive?.deliveredAtTakeover, 10)
        XCTAssertNil(controller.pendingSeizeToken)
    }

    /// No credential stored: the timeout keeps its pre-seize behavior (idle note, no offer).
    /// With a stored credential: the offer appears: offered, never auto-taken.
    func testTimedOutRequestOffersOfflineStartOnlyWithACredential() async {
        let controller = await makeController()
        controller.send = { _ in }
        controller.scheduler = { _, _, work in work.perform() }   // virtual time: fire timeouts inline

        controller.requestLoan(watchBuild: "seize-test")
        var snap = await controller.fencedSnapshot()                     // queue.sync — drains the request+timeout block
        XCTAssertNil(snap.seizeOfferIssuedAt, "no credential, no offer")
        XCTAssertNotNil(snap.lastIdleNote, "the pre-seize timeout note stands")

        let issuedAt = Date().addingTimeInterval(-1200)
        controller.handleDormantGrant(fixtureDormant(issuedAt: issuedAt))
        controller.requestLoan(watchBuild: "seize-test")
        snap = await controller.fencedSnapshot()
        XCTAssertNotNil(snap.seizeOfferIssuedAt, "credential stored → the timeout offers the offline start")
        XCTAssertEqual(snap.seizeOfferIssuedAt.map { abs($0.timeIntervalSince(issuedAt)) < 1 }, true,
                       "the offer carries the credential's issue stamp, so its age can be shown")
        XCTAssertNil(snap.lastIdleNote, "the offer replaces the failure note")
    }

    /// A watch not reading the CGM has nothing to dose from: no offer, and the note says why.
    func testTimedOutRequestOffersNoOfflineStartWithoutTheWatchsOwnCGM() async {
        let controller = await makeController(readsCGM: false)
        controller.send = { _ in }
        controller.scheduler = { _, _, work in work.perform() }

        controller.handleDormantGrant(fixtureDormant(issuedAt: Date().addingTimeInterval(-1200)))
        controller.requestLoan(watchBuild: "seize-test")
        let snap = await controller.fencedSnapshot()
        XCTAssertNil(snap.seizeOfferIssuedAt, "credential stored, but no CGM on the watch: no offer")
        XCTAssertEqual(snap.lastIdleNote?.contains("isn't reading the CGM"), true)
    }

    // MARK: - The request is the question

    /// The Start waits the normal time for the phone's answer whatever the reachability flag says: it
    /// reports whether the phone's app can take a live message, not whether the phone is there (control row 2).
    func testTheStartWaitsForAnAnswerWhateverReachabilitySays() async {
        for reachable in [false, true] {
            let controller = await makeController()
            controller.isPhoneReachable = { reachable }
            var sent = 0
            controller.send = { _ in sent += 1 }
            var captured: [(TimeInterval, String)] = []
            let timerArmed = expectation(description: "timeout armed")
            controller.scheduler = { delay, label, _ in captured.append((delay, label)); timerArmed.fulfill() }

            controller.requestLoan(watchBuild: "seize-test")
            await fulfillment(of: [timerArmed], timeout: 5)

            XCTAssertEqual(sent, 1, "the request goes out")
            XCTAssertEqual(captured.map(\.0), [PodLoanWatchController.requestTimeout], "reachable \(reachable): the normal wait")
            XCTAssertEqual(captured.map(\.1), ["request-timeout"])
        }
    }

    /// Control row 25: a start without the phone that gets no pod answer says nobody loops; a granted
    /// Start's timeout keeps saying the phone has the pod, because the phone takes it back.
    func testATakeoverThatTimesOutSaysWhoHasThePod() {
        XCTAssertEqual(PodLoanWatchController.takeoverExpiredNote(offlineStart: true),
                       "The pod didn't answer, so Sport Mode didn't start. Neither device is looping.")
        XCTAssertTrue(PodLoanWatchController.takeoverExpiredNote(offlineStart: false).contains("Your iPhone still has the pod"))
    }

    // MARK: - Reunion-token hygiene

    /// A failed activation leaves no persisted token for the phone's retro-ack to match.
    func testConfirmAloneNeverPersistsTheReunionToken() async {
        let controller = await makeController()
        controller.isPhoneReachable = { false }   // an offline start is one the phone isn't answering
        controller.send = { _ in }
        controller.scheduler = { _, _, work in work.perform() }

        let token = UUID()
        controller.handleDormantGrant(fixtureDormant(issuedAt: Date().addingTimeInterval(-600), token: token))
        controller.requestLoan(watchBuild: "seize-test")
        let snapshot1 = await controller.fencedSnapshot()
        XCTAssertNotNil(snapshot1.seizeOfferIssuedAt, "precondition: the offer is live")

        controller.confirmSeize()
        let snap = await controller.fencedSnapshot()                     // fence: confirm + activation attempt drained

        XCTAssertNil(snap.seizeOfferIssuedAt, "the confirm consumed the offer")
        XCTAssertEqual(snap.phase, .idle, "the fixture activation fails and returns to idle (startable again)")
        XCTAssertNil(controller.persisted.seizeToken,
                     "no .active, no persisted token — a failed activation must leave nothing to echo")
    }

    // MARK: - Re-entry over a parked drain

    /// The journal fold: adoptEpoch re-tags the epoch and keeps every event, seq, cursor,
    /// and tombstone — the one sanctioned way past begin()'s refuse-to-clobber.
    func testJournalAdoptEpochPreservesTheParkedDrain() throws {
        let journal = LoanEventJournal(directory: journalDir)
        try journal.begin(epoch: 5)
        let now = Date()
        let a = try journal.mintEvent(record: LoanDoseRecord(kind: .bolus, startDate: now, amount: 1.0), provenance: .confirmed)
        let b = try journal.mintEvent(record: LoanDoseRecord(kind: .tempBasal, startDate: now, endDate: now.addingTimeInterval(1800), unitsPerHour: 0.8), provenance: .confirmed)
        journal.applyAck(committedCursor: 1)                      // event a acked, b still parked

        XCTAssertThrowsError(try journal.begin(epoch: 9), "begin must still refuse to clobber an undrained loan")

        let carried = journal.adoptEpoch(9)
        XCTAssertEqual(carried, 1, "one undrained event rides the fold")
        XCTAssertEqual(journal.activeEpoch, 9, "epoch re-tagged")
        let unacked = journal.unackedEvents()
        XCTAssertEqual(unacked.map(\.id), [b.id], "same identity — that's what keeps every downstream layer idempotent")
        XCTAssertEqual(unacked.map(\.seq), [b.seq], "same seq — the phone's contiguous-cursor arithmetic just works")
        _ = a
    }

    /// A rebooted watch on a parked drain accepts Start, rests back on the drain at timeout, offers
    /// the seize, and folds the drain into the new loan.
    func testStartAndSeizeOverAParkedDrainFoldsIt() async throws {
        // Park a drain: a prior loan (epoch 5) with one unacked event, as a reboot leaves it.
        let seeded = LoanEventJournal(directory: journalDir)
        try seeded.begin(epoch: 5)
        let parked = try seeded.mintEvent(record: LoanDoseRecord(kind: .bolus, startDate: Date(), amount: 0.5), provenance: .confirmed)

        let controller = await makeController()                          // loads the same journal file
        controller.isPhoneReachable = { false }   // an offline start is one the phone isn't answering
        var sent = 0
        controller.send = { _ in sent += 1 }
        var labels: [String] = []
        controller.scheduler = { _, label, work in
            labels.append(label)
            if label == "request-timeout" { work.perform() }       // inline ONLY the timeout: an inline resend would recurse
        }
        let snapshot2 = await controller.fencedSnapshot()
        XCTAssertEqual(snapshot2.phase, .recoveredDrain, "precondition: woke up on the parked drain")

        let token = UUID()
        controller.handleDormantGrant(fixtureDormant(issuedAt: Date().addingTimeInterval(-900), epoch: 3,
                                                     token: token, completeSettings: true))
        controller.requestLoan(watchBuild: "seize-test")
        var snap = await controller.fencedSnapshot()
        XCTAssertEqual(snap.phase, .recoveredDrain, "timed out → rests ON the drain, not plain idle")
        XCTAssertNotNil(snap.seizeOfferIssuedAt, "…and the offline offer is up")
        XCTAssertTrue(labels.contains("handback-resend"), "the resend chain was re-kicked on return to the drain")
        XCTAssertGreaterThanOrEqual(sent, 2, "the request went out and so did a recovered offer")
        XCTAssertNil(controller.persisted.seizeToken,
                     "before the confirm the token is pending-only")

        controller.confirmSeize()
        snap = await controller.fencedSnapshot()                          // fence: fold + failed activation drained

        let after = LoanEventJournal(directory: journalDir)        // fresh instance = the persisted truth
        XCTAssertEqual(after.activeEpoch, 6, "folded to max(credential 3, journal 5 + 1)")
        XCTAssertEqual(after.unackedEvents().map(\.id), [parked.id], "the parked record rides the new loan's stream")
        XCTAssertEqual(controller.persisted.seizeToken, token,
                       "token persisted at FOLD — a tokenless future-epoch offer would be dropped by the phone")
        XCTAssertEqual(snap.phase, .recoveredDrain, "the failed activation rests back on the drain, still startable")
    }

    // MARK: - The phone's return changes nothing

    /// The phone returning during a seized loan: no prompt, the loan continues, and the phone is told this
    /// watch holds the pod so it stands aside. The looper ends the loan the ordinary way (control row 17).
    func testThePhoneReturningDuringASeizedLoanOnlyTellsThePhone() async throws {
        let controller = await makeController()
        var holdsPodEpochs: [Int] = []
        controller.send = { dict in
            if let message = try? LoanMessage.decode(fromTransport: dict),
               case .statusReport(let r) = message, r.holdsPod {
                holdsPodEpochs.append(r.epoch)
            }
        }
        controller.isPhoneReachable = { true }
        await controller.onMain {
            controller.updateState { $0.epoch = 7 }
            controller.phase = .active
        }
        let snapshot3 = await controller.fencedSnapshot()
        XCTAssertEqual(snapshot3.phase, .active)
        controller.updateState { $0.seizeToken = UUID() }

        controller.noteReachabilityChanged(true)
        let snap = await controller.fencedSnapshot()
        XCTAssertEqual(snap.phase, .active, "the loan continues")
        XCTAssertFalse(snap.handbackPending, "nothing starts a hand-back but the looper")
        XCTAssertEqual(holdsPodEpochs, [snap.epoch].compactMap { $0 }, "the phone is told, once, for the live loan")
    }

    /// A grant numbered at or below a loan this watch already knows is answered as failed, so the
    /// phone takes its pod back at once instead of holding it released until its dead-man runs out.
    func testAStaleGrantIsAnsweredWithATakeoverFailure() async throws {
        let controller = await makeController()
        var failedEpochs: [Int] = []
        controller.send = { dict in
            if let message = try? LoanMessage.decode(fromTransport: dict), case .takeoverFailed(let f) = message {
                failedEpochs.append(f.epoch)
            }
        }
        controller.updateState { $0.epoch = 111 }   // a loan started alone that the phone never heard of

        let grant = fixtureDormant(issuedAt: Date().addingTimeInterval(600), epoch: 110).grant
        controller.handleIncoming(userInfo: try LoanMessage.grant(grant).transportDictionary())
        _ = await controller.fencedSnapshot()
        XCTAssertEqual(failedEpochs, [110])
        let snapshot4 = await controller.fencedSnapshot()
        XCTAssertEqual(snapshot4.phase, .idle)
    }

    /// A seize epoch clears the high-water mark and the recorded revoke.
    func testSeizeEpochClearsHighWaterAndRevokeMarks() async throws {
        defaults.set(5, forKey: "PodLoanWatchController.highWaterEpoch")
        let controller = await makeController()
        controller.isPhoneReachable = { false }   // an offline start is one the phone isn't answering
        var sentEpochs: [Int] = []
        controller.send = { dict in
            if let message = try? LoanMessage.decode(fromTransport: dict), case .takeoverFailed(let f) = message {
                sentEpochs.append(f.epoch)
            }
        }
        controller.scheduler = { _, label, work in if label == "request-timeout" { work.perform() } }

        // The split-brain guard records a revoke even with no live session.
        controller.handleIncoming(userInfo: try LoanMessage.revoke(Revoke(epoch: 7)).transportDictionary())
        _ = await controller.fencedSnapshot()

        controller.handleDormantGrant(fixtureDormant(issuedAt: Date().addingTimeInterval(-600), epoch: 3,
                                                     completeSettings: true))
        controller.requestLoan(watchBuild: "epoch-test")
        let snapshot5 = await controller.fencedSnapshot()
        XCTAssertNotNil(snapshot5.seizeOfferIssuedAt)
        controller.confirmSeize()
        _ = await controller.fencedSnapshot()   // activation dies at the pump rebuild → takeoverFailed carries the minted epoch

        XCTAssertEqual(sentEpochs.last, 8,
                       "max(credential 3, high-water 5, revoked 7) + 1 — every guard cleared, nothing reused")
    }

    /// A late grant while resting on a parked drain is answered, not ignored.
    func testLateGrantWhileRestingOnAParkedDrainIsAnsweredNotIgnored() async throws {
        let seeded = LoanEventJournal(directory: journalDir)
        try seeded.begin(epoch: 5)
        _ = try seeded.mintEvent(record: LoanDoseRecord(kind: .bolus, startDate: Date(), amount: 0.5), provenance: .confirmed)

        let controller = await makeController()
        var sentKinds: [String] = []
        controller.send = { dict in
            if let message = try? LoanMessage.decode(fromTransport: dict), case .takeoverFailed = message {
                sentKinds.append("takeoverFailed")
            } else {
                sentKinds.append("other")
            }
        }
        controller.scheduler = { _, _, _ in }
        let snapshot6 = await controller.fencedSnapshot()
        XCTAssertEqual(snapshot6.phase, .recoveredDrain, "precondition: parked drain")

        let grant = fixtureDormant(issuedAt: Date(), epoch: 9, completeSettings: true).grant
            .withEpoch(9, leaseUntil: Date().addingTimeInterval(300))
        controller.handleIncoming(userInfo: try LoanMessage.grant(grant).transportDictionary())
        let snap = await controller.fencedSnapshot()

        XCTAssertTrue(sentKinds.contains("takeoverFailed"), "the phone hears the denial and can recover")
        XCTAssertEqual(snap.phase, .recoveredDrain, "and the watch rests back on its drain")
    }

    /// Stale status queries, revokes and grants during a live loan answer with what the watch holds.
    func testStaleTrafficWhileActiveAnswersHoldsPod() async throws {
        let controller = await makeController()
        var holdsPodEpochs: [Int] = []
        controller.send = { dict in
            if let message = try? LoanMessage.decode(fromTransport: dict),
               case .statusReport(let r) = message, r.holdsPod {
                holdsPodEpochs.append(r.epoch)
            }
        }
        await controller.onMain {
            controller.updateState { $0.epoch = 7 }
            controller.phase = .active
        }
        let live = await controller.fencedSnapshot()
        XCTAssertEqual(live.phase, .active, "precondition: a live loan")
        guard let ours = live.epoch else { return XCTFail("active loan has no epoch") }

        // A ghost-grant probe for an older epoch — once left unanswered.
        controller.handleIncoming(userInfo: try LoanMessage.statusQuery(StatusQuery(epoch: ours - 1)).transportDictionary())
        _ = await controller.fencedSnapshot()
        XCTAssertEqual(holdsPodEpochs, [ours], "the stale query is answered with the loan we hold")

        // A stale revoke — once 'RECORDED' twice while the phone heard nothing.
        controller.handleIncoming(userInfo: try LoanMessage.revoke(Revoke(epoch: ours - 1)).transportDictionary())
        _ = await controller.fencedSnapshot()
        XCTAssertEqual(holdsPodEpochs, [ours, ours], "the refused revoke says what it refused FOR")

        // The ghost grant itself — once 'grant ignored — wrong phase' with no reply.
        let ghost = fixtureDormant(issuedAt: Date(), epoch: max(ours - 1, 1), completeSettings: true).grant
            .withEpoch(max(ours - 1, 1), leaseUntil: Date().addingTimeInterval(300))
        controller.handleIncoming(userInfo: try LoanMessage.grant(ghost).transportDictionary())
        let snap = await controller.fencedSnapshot()
        XCTAssertEqual(holdsPodEpochs, [ours, ours, ours], "the refused grant answers too")
        XCTAssertEqual(snap.phase, .active, "and none of the three touched the live loan")
        XCTAssertEqual(snap.epoch, ours)
    }

    /// Timeout and seize confirm both cancel queued requests, so none re-grants later.
    func testTimeoutAndSeizeCancelQueuedRequestTransfers() async {
        let controller = await makeController()
        controller.isPhoneReachable = { false }   // an offline start is one the phone isn't answering
        controller.send = { _ in }
        var cancelCalls = 0
        controller.cancelQueuedLoanRequests = { cancelCalls += 1; return 1 }
        controller.scheduler = { _, label, work in if label == "request-timeout" { work.perform() } }

        controller.handleDormantGrant(fixtureDormant(issuedAt: Date().addingTimeInterval(-600), epoch: 3,
                                                     completeSettings: true))
        controller.requestLoan(watchBuild: "cancel-test")
        _ = await controller.fencedSnapshot()
        XCTAssertEqual(cancelCalls, 1, "the timeout is the moment the request stops being wanted")

        let snapshot7 = await controller.fencedSnapshot()
        XCTAssertNotNil(snapshot7.seizeOfferIssuedAt, "precondition: the offline offer is up")
        controller.confirmSeize()
        _ = await controller.fencedSnapshot()
        XCTAssertEqual(cancelCalls, 2, "seize confirm cancels again — the strongest statement that no queued request should ever land")
    }

    // MARK: - The offer answers one unanswered request

    /// An accepted grant withdraws the offline offer.
    func testALateGrantWithdrawsTheOfflineOffer() async throws {
        let controller = await makeController()
        controller.isPhoneReachable = { false }
        controller.send = { _ in }
        var timeoutsFired = 0
        controller.scheduler = { _, label, work in
            if label == "request-timeout" && timeoutsFired == 0 { timeoutsFired += 1; work.perform() }
        }

        controller.handleDormantGrant(fixtureDormant(issuedAt: Date().addingTimeInterval(-120), epoch: 3))
        controller.requestLoan(watchBuild: "late-grant")
        let snapshot8 = await controller.fencedSnapshot()
        XCTAssertNotNil(snapshot8.seizeOfferIssuedAt, "precondition: the timeout put the offer up")

        let late = fixtureDormant(issuedAt: Date(), epoch: 9, completeSettings: true).grant
            .withEpoch(9, leaseUntil: Date().addingTimeInterval(300))
        controller.handleIncoming(userInfo: try LoanMessage.grant(late).transportDictionary())
        let snap = await controller.fencedSnapshot()

        XCTAssertEqual(snap.phase, .idle, "precondition: the takeover ran and ended back at idle")
        XCTAssertNil(snap.seizeOfferIssuedAt, "the accepted grant withdrew the offline offer")
    }

    /// A grant for a Start the looper cancelled at the offline offer starts nothing: the phone is told
    /// and takes the pod back (control row 2, transfer G). A fresh Start asks afresh.
    func testAGrantAfterTheOfferIsDismissedIsRefused() async throws {
        let controller = await makeController()
        controller.isPhoneReachable = { false }
        var cancelled = 0
        controller.send = { dict in
            if case .takeoverFailed(let f)? = try? LoanMessage.decode(fromTransport: dict), f.reason.contains("cancelled") { cancelled += 1 }
        }
        var timeoutsFired = 0
        controller.scheduler = { _, label, work in
            if label == "request-timeout" && timeoutsFired == 0 { timeoutsFired += 1; work.perform() }
        }

        controller.handleDormantGrant(fixtureDormant(issuedAt: Date().addingTimeInterval(-120), epoch: 3))
        controller.requestLoan(watchBuild: "cancelled")
        let snapshot9 = await controller.fencedSnapshot()
        XCTAssertNotNil(snapshot9.seizeOfferIssuedAt, "precondition: the timeout put the offer up")
        controller.dismissSeize()
        await controller.onMain { }

        let late = fixtureDormant(issuedAt: Date(), epoch: 9, completeSettings: true).grant
            .withEpoch(9, leaseUntil: Date().addingTimeInterval(300))
        controller.handleIncoming(userInfo: try LoanMessage.grant(late).transportDictionary())
        await controller.onMain { }
        XCTAssertEqual(cancelled, 1, "the phone is told the Start was cancelled")
        XCTAssertNil(controller.pumpManager, "nothing started")
        let snapshot10 = await controller.fencedSnapshot()
        XCTAssertEqual(snapshot10.phase, .idle)

        // A fresh Start withdraws the cancel: its grant is taken up, not refused.
        controller.requestLoan(watchBuild: "again")
        controller.handleIncoming(userInfo: try LoanMessage.grant(late.withEpoch(10, leaseUntil: Date().addingTimeInterval(300))).transportDictionary())
        await controller.onMain { }
        XCTAssertEqual(cancelled, 1, "the fresh Start's grant is not refused as cancelled")
    }

    /// A new Start supersedes an offer left from an earlier unanswered request; its own timeout
    /// re-offers if the phone is still silent.
    func testANewStartWithdrawsTheOfflineOffer() async {
        let controller = await makeController()
        controller.send = { _ in }
        var timeoutsFired = 0
        controller.scheduler = { _, label, work in
            if label == "request-timeout" && timeoutsFired == 0 { timeoutsFired += 1; work.perform() }
        }

        controller.handleDormantGrant(fixtureDormant(issuedAt: Date().addingTimeInterval(-120), epoch: 3))
        controller.requestLoan(watchBuild: "first")
        let snapshot11 = await controller.fencedSnapshot()
        XCTAssertNotNil(snapshot11.seizeOfferIssuedAt, "precondition: the offer is up")

        controller.requestLoan(watchBuild: "second")
        let snap = await controller.fencedSnapshot()
        XCTAssertEqual(snap.phase, .requested)
        XCTAssertNil(snap.seizeOfferIssuedAt, "the new request withdrew the stale offer")
    }

    // MARK: - The insulin book's seed

    /// A grant for a real pod's configuration, with complete settings.
    private func takeoverGrant(epoch: Int) throws -> LoanGrant {
        let podState = PodState(address: 0x1f0b3558, firmwareVersion: "2.7.0", iFirmwareVersion: "2.7.0",
                                lotNo: 1, lotSeq: 1, insulinType: .novolog, podType: dashType)
        let raw: [String: Any] = ["basalSchedule": ["entries": [["rate": 1.0, "startTime": 0.0]]],
                                  "controllerId": UInt32(0x1234_5678), "podId": UInt32(0x1234_5679),
                                  "podState": podState.rawValue]
        let phonePump = try XCTUnwrap(OmniPumpManager(rawState: raw))
        let configuration = try PropertyListSerialization.data(fromPropertyList: phonePump.exportConfiguration().rawValue,
                                                               format: .binary, options: 0)
        return LoanGrant(epoch: epoch, expiresAt: Date().addingTimeInterval(300), pumpConfiguration: configuration,
                         therapySettingsRaw: Self.completeTherapySettingsRaw(), settingsTimeZoneID: "GMT", doseHistory: [],
                         therapySettingsSupplementRaw: Self.settingsSupplementRaw())
    }

    /// Delivers a takeover grant to a requesting watch; `meanwhile` runs in the same step, before the
    /// insulin book's seed resumes. Returns whether the takeover went on to look for the pod.
    private func takeover(meanwhile: @escaping (PodLoanWatchController) -> Void) async throws -> (PodLoanWatchController, lookedForPod: Bool) {
        let controller = await makeController()
        controller.send = { _ in }
        controller.scheduler = { _, _, _ in }
        controller.requestLoan(watchBuild: "seed-test")
        await controller.onMain { }
        let grant = try takeoverGrant(epoch: 9)
        await controller.onMain {
            controller.handleGrant(grant)
            XCTAssertEqual(controller.phase, .takingOver, "precondition: the pump is built, the seed under way")
            XCTAssertNotNil(controller.pumpManager)
            meanwhile(controller)
        }
        for _ in 0..<20 {
            await controller.onMain { }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        // A pod this watch has never met is looked for first.
        return (controller, controller.takeoverFirstContact)
    }

    /// The takeover waits for the seed without blocking, so other work can run meanwhile. If the loan
    /// moves on in that time, the takeover stops at the seed: the pod is never looked for.
    func testATakeoverWhoseLoanMovedOnDuringTheSeedGoesNoFurther() async throws {
        let (controller, lookedForPod) = try await takeover { $0.teardownPump() }
        XCTAssertFalse(lookedForPod, "the pod was never looked for")
        XCTAssertNil(controller.pumpManager)
    }

    /// The control: left alone, the same takeover seeds the book and looks for the pod.
    func testATakeoverLeftAloneGoesOnToLookForThePod() async throws {
        let (controller, lookedForPod) = try await takeover { _ in }
        XCTAssertTrue(lookedForPod)
        await controller.onMain { controller.teardownPump() }
    }
}
