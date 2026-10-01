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
@testable import WatchApp

final class SeizeActivationTests: XCTestCase {

    private var cacheDir: URL!
    private var cacheStore: PersistenceController!
    private var journalDir: URL!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        cacheDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        cacheStore = PersistenceController(directoryURL: cacheDir)
        journalDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: journalDir, withIntermediateDirectories: true)
        defaults = UserDefaults(suiteName: "SeizeActivationTests-\(UUID().uuidString)")!
    }

    override func tearDown() {
        cacheStore = nil
        cacheDir = nil
        journalDir = nil
        defaults = nil
        super.tearDown()
    }

    private func makeController() async -> PodLoanWatchController {
        let doseStore = await DoseStore(
            healthKitSampleStore: nil,
            cacheStore: cacheStore,
            longestEffectDuration: ExponentialInsulinModelPreset.rapidActingAdult.effectDuration,
            provenanceIdentifier: "SeizeActivationTests"
        )
        let glucoseStore = await GlucoseStore(
            healthKitSampleStore: nil,
            cacheStore: cacheStore,
            cacheLength: .hours(4),
            provenanceIdentifier: "SeizeActivationTests"
        )
        let carbStore = CarbStore(
            healthKitSampleStore: nil,
            cacheStore: cacheStore,
            cacheLength: .hours(24),
            provenanceIdentifier: "SeizeActivationTests"
        )
        let manager = WatchLoopManager(doseStore: doseStore, glucoseStore: glucoseStore, carbStore: carbStore,
                                       defaults: defaults, stateDirectory: journalDir)
        return PodLoanWatchController(loopManager: manager,
                                      journal: LoanEventJournal(directory: journalDir),
                                      stateDirectory: journalDir)
    }

    /// A dormant credential as the phone builds it (expiresAt == issuedAt). `completeSettings` gets
    /// an activation as far as the journal; it still dies at the pump rebuild.
    private func fixtureDormant(issuedAt: Date, epoch: Int = 3, token: UUID = UUID(),
                                completeSettings: Bool = false) -> DormantGrant {
        let grant = LoanGrant(epoch: epoch, expiresAt: issuedAt,
                              pumpConfiguration: Data([1, 2, 3]), podAddress: 0x1F0A2B3C,
                              therapySettingsRaw: completeSettings ? Self.completeTherapySettingsRaw() : Data([4, 5]),
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
        XCTAssertGreaterThan(rebuilt.expiresAt.timeIntervalSinceNow, 240,
                             "an hour-old credential must still enter the ladder with (almost) the full 5-minute budget")
        // Every other field carries verbatim.
        XCTAssertEqual(rebuilt.pumpConfiguration, dormant.grant.pumpConfiguration)
        XCTAssertEqual(rebuilt.podAddress, dormant.grant.podAddress)
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
        controller.queue.sync { controller.recordTakeoverActive(delivered: 10) }
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
        var snap = controller.debugSnapshot()                     // queue.sync — drains the request+timeout block
        XCTAssertNil(snap.seizeOfferIssuedAt, "no credential, no offer")
        XCTAssertNotNil(snap.lastIdleNote, "the pre-seize timeout note stands")

        let issuedAt = Date().addingTimeInterval(-1200)
        controller.handleDormantGrant(fixtureDormant(issuedAt: issuedAt))
        controller.requestLoan(watchBuild: "seize-test")
        snap = controller.debugSnapshot()
        XCTAssertNotNil(snap.seizeOfferIssuedAt, "credential stored → the timeout offers the offline start")
        XCTAssertEqual(snap.seizeOfferIssuedAt.map { abs($0.timeIntervalSince(issuedAt)) < 1 }, true,
                       "the offer carries the credential's issue stamp, so its age can be shown")
        XCTAssertNil(snap.lastIdleNote, "the offer replaces the failure note")
    }

    // MARK: - The shortened timeout

    /// Unreachable shortens the timeout to 8 s but the request is still sent.
    func testUnreachablePhoneShortensTheRequestTimeout() async {
        let controller = await makeController()
        controller.isPhoneReachable = { false }

        var sent = 0
        controller.send = { _ in sent += 1 }
        var captured: [(TimeInterval, String)] = []
        let timerArmed = expectation(description: "timeout armed")
        controller.scheduler = { delay, label, _ in captured.append((delay, label)); timerArmed.fulfill() }

        controller.requestLoan(watchBuild: "seize-test")
        wait(for: [timerArmed], timeout: 5)

        XCTAssertEqual(sent, 1, "unreachable is advisory — the request still goes out")
        XCTAssertEqual(captured.map(\.0), [8], "unreachable phone → the short timeout")
        XCTAssertEqual(captured.map(\.1), ["request-timeout"])
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
        XCTAssertNotNil(controller.debugSnapshot().seizeOfferIssuedAt, "precondition: the offer is live")

        controller.confirmSeize()
        let snap = controller.debugSnapshot()                     // fence: confirm + activation attempt drained

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
        XCTAssertEqual(controller.debugSnapshot().phase, .recoveredDrain, "precondition: woke up on the parked drain")

        let token = UUID()
        controller.handleDormantGrant(fixtureDormant(issuedAt: Date().addingTimeInterval(-900), epoch: 3,
                                                     token: token, completeSettings: true))
        controller.requestLoan(watchBuild: "seize-test")
        var snap = controller.debugSnapshot()
        XCTAssertEqual(snap.phase, .recoveredDrain, "timed out → rests ON the drain, not plain idle")
        XCTAssertNotNil(snap.seizeOfferIssuedAt, "…and the offline offer is up")
        XCTAssertTrue(labels.contains("handback-resend"), "the resend chain was re-kicked on return to the drain")
        XCTAssertGreaterThanOrEqual(sent, 2, "the request went out and so did a recovered offer")
        XCTAssertNil(controller.persisted.seizeToken,
                     "before the confirm the token is pending-only")

        controller.confirmSeize()
        snap = controller.debugSnapshot()                          // fence: fold + failed activation drained

        let after = LoanEventJournal(directory: journalDir)        // fresh instance = the persisted truth
        XCTAssertEqual(after.activeEpoch, 6, "folded to max(credential 3, journal 5 + 1)")
        XCTAssertEqual(after.unackedEvents().map(\.id), [parked.id], "the parked record rides the new loan's stream")
        XCTAssertEqual(controller.persisted.seizeToken, token,
                       "token persisted at FOLD — a tokenless future-epoch offer would be dropped by the phone")
        XCTAssertEqual(snap.phase, .recoveredDrain, "the failed activation rests back on the drain, still startable")
    }

    // MARK: - Reunion: the phone's return ends a seized loan

    /// The phone returning during a seized loan raises a prompt; only the user's choice ends it.
    func testPhoneReturnPromptsAndOnlyTheUsersChoiceEndsASeizedLoan() async {
        let controller = await makeController()
        controller.simFakeLoanFlow = true
        controller.send = { _ in }
        controller.isPhoneReachable = { true }
        var pendingDebounce: [DispatchWorkItem] = []
        controller.scheduler = { _, label, work in
            switch label {
            case "sim-grant", "sim-active", "sim-handback": work.perform()   // virtual time through the sim flow
            case "seize-reunion-debounce": pendingDebounce.append(work)      // held, fired by hand below
            default: break                                                   // watchdogs etc. stay armed-only
            }
        }

        controller.requestLoan(watchBuild: "reunion-test")
        XCTAssertEqual(controller.debugSnapshot().phase, .active, "precondition: sim flow reached the live loan")
        controller.updateState { $0.seizeToken = UUID() }   // mark it SEIZED

        controller.noteReachabilityChanged(true)
        _ = controller.debugSnapshot()                              // fence the arming block
        XCTAssertEqual(pendingDebounce.count, 1, "reachability during a seized loan arms the reunion debounce")

        controller.noteReachabilityChanged(true)
        _ = controller.debugSnapshot()
        XCTAssertEqual(pendingDebounce.count, 1, "flapping reachability must not stack debounces")

        pendingDebounce[0].perform()                                // 30 s later, phone still reachable
        var snap = controller.debugSnapshot()
        XCTAssertTrue(snap.reunionPromptVisible, "the fire raises the PROMPT")
        XCTAssertEqual(snap.phase, .active, "…and the loan continues — never auto-ended")

        // KEEP dismisses; a fresh reachability transition may prompt again later.
        controller.dismissReunionPrompt()
        snap = controller.debugSnapshot()
        XCTAssertFalse(snap.reunionPromptVisible, "Keep clears the prompt")
        XCTAssertEqual(snap.phase, .active, "and the loan still continues")

        // Raise it again (new transition) and choose HAND BACK this time.
        controller.noteReachabilityChanged(true)
        _ = controller.debugSnapshot()
        pendingDebounce[1].perform()
        XCTAssertTrue(controller.debugSnapshot().reunionPromptVisible, "a fresh transition re-prompts")
        controller.confirmReunionHandback()
        // The confirm chain hops the queue twice (beginHandback re-enqueues, then the
        // sim drive re-enqueues) — fence each hop before reading the verdict.
        _ = controller.debugSnapshot()
        _ = controller.debugSnapshot()
        snap = controller.debugSnapshot()
        XCTAssertEqual(snap.phase, .idle, "Hand Back runs the normal hand-back to completion")
        XCTAssertFalse(snap.reunionPromptVisible, "and the prompt is gone")
    }

    /// The three gates that must each keep the debounce unarmed: no reunion token (a
    /// NORMAL loan never prompts), the kill switch, and a reachability LOSS.
    func testReunionDebounceRespectsItsGates() async {
        let controller = await makeController()
        controller.simFakeLoanFlow = true
        controller.send = { _ in }
        controller.isPhoneReachable = { true }
        var pendingDebounce: [DispatchWorkItem] = []
        controller.scheduler = { _, label, work in
            switch label {
            case "sim-grant", "sim-active": work.perform()
            case "seize-reunion-debounce": pendingDebounce.append(work)
            default: break
            }
        }
        controller.requestLoan(watchBuild: "reunion-test")
        XCTAssertEqual(controller.debugSnapshot().phase, .active)

        controller.noteReachabilityChanged(true)                    // NORMAL loan: no token stored
        _ = controller.debugSnapshot()
        XCTAssertTrue(pendingDebounce.isEmpty, "a normal loan must never arm the reunion prompt")

        controller.updateState { $0.seizeToken = UUID() }
        controller.noteReachabilityChanged(false)
        _ = controller.debugSnapshot()
        XCTAssertTrue(pendingDebounce.isEmpty, "a reachability LOSS is not a reunion")

        controller.noteReachabilityChanged(true)
        _ = controller.debugSnapshot()
        XCTAssertEqual(pendingDebounce.count, 1, "with the gates open, the debounce arms")

        // Flicker: reachable at arming, gone at fire — no prompt, the loan continues.
        controller.isPhoneReachable = { false }
        pendingDebounce[0].perform()
        let snap = controller.debugSnapshot()
        XCTAssertFalse(snap.reunionPromptVisible, "a flicker must not raise the prompt")
        XCTAssertEqual(snap.phase, .active, "and must not touch the loan")
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
        controller.handleIncoming(userInfo: try LoanMessage.revoke(Revoke(epoch: 7)).transportDictionary(), channel: .queued)
        _ = controller.debugSnapshot()

        controller.handleDormantGrant(fixtureDormant(issuedAt: Date().addingTimeInterval(-600), epoch: 3,
                                                     completeSettings: true))
        controller.requestLoan(watchBuild: "epoch-test")
        XCTAssertNotNil(controller.debugSnapshot().seizeOfferIssuedAt)
        controller.confirmSeize()
        _ = controller.debugSnapshot()   // activation dies at the pump rebuild → takeoverFailed carries the minted epoch

        XCTAssertEqual(sentEpochs.last, 8,
                       "max(credential 3, high-water 5, revoked 7) + 1 — every guard cleared, nothing reused")
    }

    /// Detector C (fix 2): the reunion prompt and Keep each SEND a holdsPod status
    /// report, so the phone's yield never waits on dose-stream evidence.
    func testReunionPromptAndKeepSendHoldsPodReports() async {
        let controller = await makeController()
        controller.simFakeLoanFlow = true
        var holdsPodEpochs: [Int] = []
        controller.send = { dict in
            if let message = try? LoanMessage.decode(fromTransport: dict),
               case .statusReport(let r) = message, r.holdsPod {
                holdsPodEpochs.append(r.epoch)
            }
        }
        controller.isPhoneReachable = { true }
        var pendingDebounce: [DispatchWorkItem] = []
        controller.scheduler = { _, label, work in
            switch label {
            case "sim-grant", "sim-active": work.perform()
            case "seize-reunion-debounce": pendingDebounce.append(work)
            default: break
            }
        }
        controller.requestLoan(watchBuild: "reunion-test")
        XCTAssertEqual(controller.debugSnapshot().phase, .active)
        controller.updateState { $0.seizeToken = UUID() }

        controller.noteReachabilityChanged(true)
        _ = controller.debugSnapshot()
        pendingDebounce[0].perform()
        _ = controller.debugSnapshot()
        XCTAssertEqual(holdsPodEpochs.count, 1, "the prompt raise tells the phone outright")

        controller.dismissReunionPrompt()
        _ = controller.debugSnapshot()
        XCTAssertEqual(holdsPodEpochs.count, 2, "Keep re-asserts it")
        XCTAssertEqual(holdsPodEpochs.last, controller.debugSnapshot().epoch, "for the live loan's epoch")
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
        XCTAssertEqual(controller.debugSnapshot().phase, .recoveredDrain, "precondition: parked drain")

        let grant = fixtureDormant(issuedAt: Date(), epoch: 9, completeSettings: true).grant
            .withEpoch(9, leaseUntil: Date().addingTimeInterval(300))
        controller.handleIncoming(userInfo: try LoanMessage.grant(grant).transportDictionary(), channel: .queued)
        let snap = controller.debugSnapshot()

        XCTAssertTrue(sentKinds.contains("takeoverFailed"), "the phone hears the denial and can recover")
        XCTAssertEqual(snap.phase, .recoveredDrain, "and the watch rests back on its drain")
    }

    /// Stale status queries, revokes and grants during a live loan answer with what the watch holds.
    func testStaleTrafficWhileActiveAnswersHoldsPod() async throws {
        let controller = await makeController()
        controller.simFakeLoanFlow = true
        var holdsPodEpochs: [Int] = []
        controller.send = { dict in
            if let message = try? LoanMessage.decode(fromTransport: dict),
               case .statusReport(let r) = message, r.holdsPod {
                holdsPodEpochs.append(r.epoch)
            }
        }
        controller.scheduler = { _, label, work in
            if label == "sim-grant" || label == "sim-active" { work.perform() }
        }
        controller.requestLoan(watchBuild: "stale-traffic-test")
        let live = controller.debugSnapshot()
        XCTAssertEqual(live.phase, .active, "precondition: a live loan")
        guard let ours = live.epoch else { return XCTFail("active loan has no epoch") }

        // A ghost-grant probe for an older epoch — once left unanswered.
        controller.handleIncoming(userInfo: try LoanMessage.statusQuery(StatusQuery(epoch: ours - 1)).transportDictionary(), channel: .queued)
        _ = controller.debugSnapshot()
        XCTAssertEqual(holdsPodEpochs, [ours], "the stale query is answered with the loan we hold")

        // A stale revoke — once 'RECORDED' twice while the phone heard nothing.
        controller.handleIncoming(userInfo: try LoanMessage.revoke(Revoke(epoch: ours - 1)).transportDictionary(), channel: .queued)
        _ = controller.debugSnapshot()
        XCTAssertEqual(holdsPodEpochs, [ours, ours], "the refused revoke says what it refused FOR")

        // The ghost grant itself — once 'grant ignored — wrong phase' with no reply.
        let ghost = fixtureDormant(issuedAt: Date(), epoch: max(ours - 1, 1), completeSettings: true).grant
            .withEpoch(max(ours - 1, 1), leaseUntil: Date().addingTimeInterval(300))
        controller.handleIncoming(userInfo: try LoanMessage.grant(ghost).transportDictionary(), channel: .queued)
        let snap = controller.debugSnapshot()
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
        _ = controller.debugSnapshot()
        XCTAssertEqual(cancelCalls, 1, "the timeout is the moment the request stops being wanted")

        XCTAssertNotNil(controller.debugSnapshot().seizeOfferIssuedAt, "precondition: the offline offer is up")
        controller.confirmSeize()
        _ = controller.debugSnapshot()
        XCTAssertEqual(cancelCalls, 2, "seize confirm cancels again — the strongest statement that no queued request should ever land")
    }

    // MARK: - The offer answers one unanswered request

    /// With the phone reachable at confirm, an ordinary request goes out.
    func testConfirmWithThePhoneBackSendsAnOrdinaryRequest() async {
        let controller = await makeController()
        controller.isPhoneReachable = { false }
        var requests = 0
        controller.send = { dict in
            if let message = try? LoanMessage.decode(fromTransport: dict), case .request(_) = message { requests += 1 }
        }
        var timeoutsFired = 0
        controller.scheduler = { _, label, work in
            // Only the first timeout runs: it is the one that puts the offer up.
            if label == "request-timeout" && timeoutsFired == 0 { timeoutsFired += 1; work.perform() }
        }

        controller.handleDormantGrant(fixtureDormant(issuedAt: Date().addingTimeInterval(-600), completeSettings: true))
        controller.requestLoan(watchBuild: "reachable-confirm")
        XCTAssertNotNil(controller.debugSnapshot().seizeOfferIssuedAt, "precondition: the offline offer is up")

        controller.isPhoneReachable = { true }
        controller.confirmSeize()
        _ = controller.debugSnapshot()          // drains the confirm, which queues the request behind itself
        let snap = controller.debugSnapshot()   // drains the request

        XCTAssertEqual(requests, 2, "the confirm went to the phone as a second ordinary request")
        XCTAssertEqual(snap.phase, .requested, "waiting on the phone's grant, not activating the stored credential")
        XCTAssertNil(snap.seizeOfferIssuedAt, "the offer was consumed")
        XCTAssertNil(controller.persisted.seizeToken)
    }

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
        XCTAssertNotNil(controller.debugSnapshot().seizeOfferIssuedAt, "precondition: the timeout put the offer up")

        let late = fixtureDormant(issuedAt: Date(), epoch: 9, completeSettings: true).grant
            .withEpoch(9, leaseUntil: Date().addingTimeInterval(300))
        controller.handleIncoming(userInfo: try LoanMessage.grant(late).transportDictionary(), channel: .queued)
        let snap = controller.debugSnapshot()

        XCTAssertEqual(snap.phase, .idle, "precondition: the takeover ran and ended back at idle")
        XCTAssertNil(snap.seizeOfferIssuedAt, "the accepted grant withdrew the offline offer")
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
        XCTAssertNotNil(controller.debugSnapshot().seizeOfferIssuedAt, "precondition: the offer is up")

        controller.requestLoan(watchBuild: "second")
        let snap = controller.debugSnapshot()
        XCTAssertEqual(snap.phase, .requested)
        XCTAssertNil(snap.seizeOfferIssuedAt, "the new request withdrew the stale offer")
    }
}
