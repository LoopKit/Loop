//
//  WakeResumeTests.swift
//  WatchAppTests
//
//  A relaunch mid-loan rebuilds from saved pump state, as the phone does. Only an active loan
//  with saved state resumes; anything else drains.
//

import XCTest
import LoopKit
import LoopAlgorithm
import LoopCore
@testable import WatchApp

@MainActor
final class WakeResumeTests: XCTestCase {

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
        defaults = UserDefaults(suiteName: "WakeResumeTests-\(UUID().uuidString)")!
    }

    /// Writes the controller's state file as a previous run left it.
    private func saveState(_ change: (inout PodLoanWatchState) -> Void) {
        var store = PersistedProperty<[String: Any]>(key: "PodLoanWatchState", directory: journalDir)
        var state = store.wrappedValue.flatMap(PodLoanWatchState.init(rawValue:)) ?? PodLoanWatchState()
        change(&state)
        store.wrappedValue = state.rawValue
    }

    /// Writes the saved pump manager state as a previous run left it.
    private func savePumpState(_ state: [String: Any]) {
        var store = PersistedProperty<[String: Any]>(key: "PumpManagerState", directory: journalDir)
        store.wrappedValue = state
    }

    /// The grant's settings payload on disk, including the supplement's basal schedule.
    private func persistGrantedSettings() {
        let basal = BasalRateSchedule(dailyItems: [RepeatingScheduleValue(startTime: 0, value: 1.0)])!
        let raw = try! PropertyListSerialization.data(fromPropertyList: LoopSettings().rawValue, format: .binary, options: 0)
        let supplement = try! PropertyListSerialization.data(fromPropertyList: ["basalRateSchedule": basal.rawValue], format: .binary, options: 0)
        let now = Date()
        let history = LoanSettingsHistory(
            basal: [AbsoluteScheduleValue(startDate: now.addingTimeInterval(-.hours(24)), endDate: now, value: 0.8)],
            sensitivity: [], carbRatio: [], targetRange: [])
        saveState {
            $0.grantedSettings = .init(therapySettingsRaw: raw, supplementRaw: supplement,
                                       settingsHistory: history)
        }
    }

    override func tearDown() async throws {
        cacheStore = nil
        cacheDir = nil
        journalDir = nil
        defaults = nil
        try await super.tearDown()
    }

    private func makeController() async -> PodLoanWatchController {
        let doseStore = await DoseStore(healthKitSampleStore: nil, cacheStore: cacheStore,
                                        longestEffectDuration: ExponentialInsulinModelPreset.rapidActingAdult.effectDuration,
                                        provenanceIdentifier: "WakeResumeTests")
        let glucoseStore = await GlucoseStore(healthKitSampleStore: nil, cacheStore: cacheStore,
                                              cacheLength: .hours(4), provenanceIdentifier: "WakeResumeTests")
        let carbStore = CarbStore(healthKitSampleStore: nil, cacheStore: cacheStore,
                                  cacheLength: .hours(24), provenanceIdentifier: "WakeResumeTests")
        let manager = WatchLoopManager(doseStore: doseStore, glucoseStore: glucoseStore, carbStore: carbStore,
                                       defaults: defaults, stateDirectory: journalDir)
        return PodLoanWatchController(loopManager: manager,
                                      journal: LoanEventJournal(directory: journalDir),
                                      stateDirectory: journalDir)
    }

    /// The smallest pump state the watch's registry restores: the Omnipod manager's identifier, a
    /// basal schedule, and a controller id so it takes the DASH path the watch uses. No pod.
    private var readablePumpState: [String: Any] {
        ["managerIdentifier": "Omni",
         "state": ["basalSchedule": ["entries": [["rate": 1.0, "startTime": 0.0]]],
                   "controllerId": UInt32(0x1234_5678), "podId": UInt32(0x1234_5679)] as [String: Any]]
    }

    private func relaunch(phase: PodLoanWatchController.Phase, epoch: Int = 7, savedState: [String: Any]?,
                          granted: Bool = true) async -> PodLoanWatchController {
        if granted { persistGrantedSettings() }
        saveState {
            $0.phase = phase
            $0.epoch = epoch
        }
        if let savedState { savePumpState(savedState) }
        let c = await makeController()
        // The ask before looping answers at once here (no phone); every other timer runs for real.
        c.scheduler = { [weak c] delay, label, work in
            if label == "resume-ask" { work.perform() } else { DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work) }
        }
        c.resumeIfNeeded()   // what the session does once the hooks are wired
        await c.onMain { }     // the resume is built on main; wait for it
        return c
    }

    /// The direct-reading clock is memory, seeded at launch from the sensor.
    func testDirectReadingClockIsSeededAtLaunch() async {
        let c = await makeController()
        XCTAssertNil(c.loopManager.lastGlucoseSourceStamps.direct)

        let reading = Date().addingTimeInterval(-300)
        c.loopManager.seedLastDirectG7At(reading)
        XCTAssertEqual(c.loopManager.lastGlucoseSourceStamps.direct, reading)
        c.loopManager.seedLastDirectG7At(reading.addingTimeInterval(-600))
        XCTAssertEqual(c.loopManager.lastGlucoseSourceStamps.direct, reading, "a seed never moves the clock back")
    }

    /// An interrupted start is reported once: the next relaunch is plain idle, not a second
    /// `takeoverFailed` and a second "start was interrupted".
    func testASecondRelaunchAfterAnInterruptedStartIsIdle() async {
        let first = await relaunch(phase: .takingOver, savedState: nil, granted: false)
        XCTAssertEqual(first.phase, .idle)
        XCTAssertEqual(first.pendingInterruptedTakeoverEpoch, 7, "the first relaunch tells the phone")
        let second = await makeController()
        XCTAssertEqual(second.phase, .idle)
        XCTAssertNil(second.epoch)
        XCTAssertNil(second.pendingInterruptedTakeoverEpoch, "the normalised phase was saved, so nothing is re-reported")
        XCTAssertNil(second.lastIdleNote)
    }

    /// A revoke recorded before a relaunch still refuses a grant at or below it afterwards; in
    /// memory only, the relaunched watch could take a pod the phone had already asked back.
    func testARecordedRevokeSurvivesARelaunch() async throws {
        let c = await makeController()
        c.handleIncoming(userInfo: try LoanMessage.revoke(Revoke(epoch: 8)).transportDictionary())
        await c.onMain { }

        let relaunched = await makeController()
        var failures: [String] = []
        relaunched.send = { dict in
            if case .takeoverFailed(let f)? = try? LoanMessage.decode(fromTransport: dict) { failures.append(f.reason) }
        }
        let grant = LoanGrant(epoch: 8, expiresAt: Date().addingTimeInterval(300), pumpConfiguration: Data([1, 2, 3]),
                              therapySettingsRaw: Data([4, 5]), settingsTimeZoneID: "GMT", doseHistory: [],
                              therapySettingsSupplementRaw: nil)
        await relaunched.onMain { relaunched.handleGrant(grant) }
        XCTAssertEqual(failures.count, 1)
        XCTAssertTrue(failures.first?.contains("last revoke") == true, "refused for the revoke, got: \(failures)")
    }

    /// The stop rides two channels; the later copy of one already acted on changes nothing: no second
    /// teardown, no second offer.
    func testASecondCopyOfTheStopChangesNothing() async throws {
        let c = await relaunch(phase: .active, savedState: readablePumpState)
        var offers = 0
        c.send = { dict in
            if case .handbackOffer? = try? LoanMessage.decode(fromTransport: dict) { offers += 1 }
        }
        c.handleIncoming(userInfo: try LoanMessage.revoke(Revoke(epoch: 7)).transportDictionary())
        await c.onMain { }
        await c.onMain { }
        XCTAssertEqual(c.phase, .revoked)
        XCTAssertEqual(offers, 1, "the stop is answered with the final offer")

        c.handleIncoming(userInfo: try LoanMessage.revoke(Revoke(epoch: 7)).transportDictionary())
        await c.onMain { }
        await c.onMain { }
        XCTAssertEqual(c.phase, .revoked)
        XCTAssertEqual(offers, 1, "the queued copy is dropped")
    }

    func testActiveLoanWithSavedPodStateResumes() async {
        let c = await relaunch(phase: .active, savedState: readablePumpState)
        XCTAssertEqual(c.phase, .active, "an active loan with saved pod state resumes — not drained")
        XCTAssertEqual(c.epoch, 7, "the loan's epoch carries over unchanged")
        XCTAssertNotNil(c.pumpManager, "the pump manager is rebuilt from the saved state")
        XCTAssertNotNil(c.loopManager.pumpManager, "and handed to the loop, so dosing can resume")
        XCTAssertTrue(c.isLoanActive,
                      "live from launch — init loads the phase without its didSet (else: onboarding screen + blank IOB)")
        XCTAssertNotNil(c.loopManager.settings.basalRateSchedule,
                        "the granted therapy settings came back from disk (else: blank IOB, no schedule)")
        XCTAssertNotNil(c.pumpStateStore.wrappedValue,
                        "the saved state stays on disk — the next relaunch resumes the same way")
    }

    func testResumeWithoutTherapySettingsDrains() async {
        // Saved pod state but no granted settings on disk: a pump that cannot dose is not resumed.
        let c = await relaunch(phase: .active, savedState: readablePumpState, granted: false)
        XCTAssertEqual(c.phase, .recoveredDrain)
        XCTAssertNil(c.pumpManager)
        XCTAssertNil(c.pumpStateStore.wrappedValue)
    }

    func testActiveLoanWithoutSavedStateStillDrains() async {
        // A loan from before this build has no saved state: the pre-existing behaviour holds.
        let c = await relaunch(phase: .active, savedState: nil)
        XCTAssertEqual(c.phase, .recoveredDrain)
        XCTAssertNil(c.pumpManager)
    }

    /// State saved before it carried its manager's identifier cannot be routed: drain, as for any
    /// unreadable state.
    func testStateSavedWithoutItsManagersIdentifierFallsBackToDrain() async {
        let c = await relaunch(phase: .active, savedState: readablePumpState["state"] as? [String: Any])
        XCTAssertEqual(c.phase, .recoveredDrain)
        XCTAssertNil(c.pumpManager)
    }

    func testUnreadableSavedStateFallsBackToDrain() async {
        let c = await relaunch(phase: .active, savedState: ["garbage": 1])
        XCTAssertEqual(c.phase, .recoveredDrain, "unreadable state returns the pod, as a relaunch always did")
        XCTAssertNil(c.pumpManager)
        XCTAssertNil(c.pumpStateStore.wrappedValue, "and the bad state is discarded")
    }

    func testOnlyAnActiveLoanResumes() async {
        // Saved state can outlive an ACTIVE phase only by a crash inside teardown; mid-transition
        // phases keep their existing handling whatever is on disk.
        for phase in [PodLoanWatchController.Phase.handingBack, .revoked, .recoveredDrain] {
            let c = await relaunch(phase: phase, savedState: readablePumpState)
            XCTAssertEqual(c.phase, .recoveredDrain, "\(phase) at relaunch drains")
            XCTAssertNil(c.pumpManager, "\(phase) never rebuilds the pump")
        }
    }

    func testLastLoopTimeSurvivesRelaunch() async {
        // Display only, but it is what the ring reads: after a resume the ring must show the
        // real age of the last cycle, as the phone's does after a relaunch, not "never".
        let first = await makeController()
        let completed = Date(timeIntervalSinceNow: -180)
        first.loopManager.seedLastLoopCompleted(completed, source: "test")
        let relaunched = await makeController()
        XCTAssertEqual(relaunched.loopManager.lastLoopCompleted?.timeIntervalSince1970 ?? 0,
                       completed.timeIntervalSince1970, accuracy: 0.001,
                       "the last-loop time comes back from disk (else: gray ring for one cycle)")
    }

    func testEndWithThePhoneAwayIsRefusedAfterTheWaitAndSaysHowToStopDosing() async {
        // The offer is the query (control document, row 8): it goes out by every path; with no
        // acknowledgement within the wait the End is refused, the loan continues, and the watch says
        // why and how to stop dosing instead.
        let c = await relaunch(phase: .active, savedState: readablePumpState)
        XCTAssertNotNil(c.pumpManager)
        c.isPhoneReachable = { false }
        var answerWait: DispatchWorkItem?
        c.scheduler = { _, label, work in if label == "handback-answer" { answerWait = work } }
        var sent: [[String: Any]] = []
        c.send = { sent.append($0) }
        c.beginHandback()
        await c.onMain { }
        XCTAssertEqual(sent.count, 1, "the offer went out, whatever the reachability flag says")
        let snapshot1 = await c.fencedSnapshot()
        XCTAssertTrue(snapshot1.handbackPending, "and the End waits for an answer")

        await c.onMain { answerWait?.perform() }
        XCTAssertEqual(c.phase, .active, "silence: the loan continues")
        XCTAssertNotNil(c.pumpManager, "the watch still holds the pod")
        let snapshot2 = await c.fencedSnapshot()
        XCTAssertFalse(snapshot2.handbackPending)
        let snapshot3 = await c.fencedSnapshot()
        XCTAssertTrue(snapshot3.handbackFailureText?.contains("open the loop") == true,
                      "on screen: why, and how to stop dosing instead")
    }

    func testEndAnsweredWithinTheWaitIsNotRefused() async throws {
        let c = await relaunch(phase: .active, savedState: readablePumpState)
        var answerWait: DispatchWorkItem?
        c.scheduler = { _, label, work in if label == "handback-answer" { answerWait = work } }
        c.send = { _ in }
        c.beginHandback()
        await c.onMain { }
        c.handleIncoming(userInfo: try LoanMessage.handbackAck(HandbackAck(epoch: 7, committedCursor: 0)).transportDictionary())
        await c.onMain { }
        await c.onMain { answerWait?.perform() }
        let snapshot4 = await c.fencedSnapshot()
        XCTAssertNil(snapshot4.handbackFailureText, "the phone answered: not refused")
    }

    func testEveryHandbackOfferGoesWhateverReachabilitySays() async {
        // Reachability chooses the fast path only: resends go whether or not the flag says the
        // phone's app can take a live message.
        let c = await relaunch(phase: .active, savedState: readablePumpState)
        var timers: [(label: String, work: DispatchWorkItem)] = []
        c.scheduler = { _, label, work in timers.append((label, work)) }
        c.isPhoneReachable = { true }
        var sent: [[String: Any]] = []
        c.send = { sent.append($0) }
        c.beginHandback()
        await c.onMain { }
        XCTAssertEqual(sent.count, 1)

        c.isPhoneReachable = { false }
        await c.onMain { timers.last { $0.label == "handback-resend" }?.work.perform() }
        XCTAssertEqual(sent.count, 2, "the resend went, queued")
        let snapshot5 = await c.fencedSnapshot()
        XCTAssertTrue(snapshot5.handbackPending)
    }

    /// The answer to a query says whether the watch can reach the pod and when its loan started
    /// (control document, rows 14 and 19).
    func testTheAnswerCarriesPodReachAndLoanStart() async throws {
        let c = await relaunch(phase: .active, savedState: readablePumpState)
        let started = Date().addingTimeInterval(-.minutes(30))
        c.updateState { $0.deliveredAtTakeoverAt = started }
        var reports: [StatusReport] = []
        c.send = { dict in
            if let m = try? LoanMessage.decode(fromTransport: dict), case .statusReport(let r) = m { reports.append(r) }
        }
        c.handleIncoming(userInfo: try LoanMessage.statusQuery(StatusQuery(epoch: 7)).transportDictionary())
        await c.onMain { }
        let report = try XCTUnwrap(reports.last)
        XCTAssertTrue(report.holdsPod)
        XCTAssertEqual(report.loanStartedAt?.timeIntervalSince1970 ?? 0, started.timeIntervalSince1970, accuracy: 1)
        XCTAssertNotEqual(report.podReachable, true, "no recent reading of the pod: not reported as reachable")
    }

    func testPhoneRefusalEndsTheHandbackAtOnceAndKeepsTheLoan() async throws {
        // With the phone's Bluetooth off, End is refused and the watch
        // knows at once — no budget to wait out. The phone says so; the watch shows its reason.
        let c = await relaunch(phase: .active, savedState: readablePumpState)
        c.isPhoneReachable = { true }
        var sent = 0
        c.send = { _ in sent += 1 }
        c.beginHandback()
        await c.onMain { }
        XCTAssertEqual(sent, 1, "the interim offer went out")
        let reason = "The watch is still looping. To end, turn on iPhone Bluetooth and tap End again."
        c.handleIncoming(userInfo: try LoanMessage.denied(LoanDenied(reason: reason)).transportDictionary())
        await c.onMain { }
        XCTAssertEqual(c.phase, .active, "the loan continues")
        XCTAssertNotNil(c.pumpManager, "the watch still holds the pod")
        let snapshot6 = await c.fencedSnapshot()
        XCTAssertEqual(snapshot6.handbackFailureText, reason, "the glance shows the phone's own reason")
        let snapshot7 = await c.fencedSnapshot()
        XCTAssertFalse(snapshot7.handbackPending, "End is over — tap again once Bluetooth is back")
    }

    func testResumeRestoresEverythingALoanHadInstalled() async {
        // One list, so a new grant field cannot be left out of the saved state.
        let live = await makeController()
        live.loopManager.setClosedLoopEnabled(true, reason: "test")
        live.loopManager.setAlgorithmExperiments(integralRetrospectiveCorrection: true, glucoseBasedApplicationFactor: true,
                                                 guardAndRunway: true, volatilityBaseline: 4.2)
        let override = halfNeeds(start: Date().addingTimeInterval(-.minutes(10)), duration: .indefinite)
        live.loopManager.applyWristOverride(override)
        saveState { $0.deliveredAtTakeover = 12.5 }

        let c = await relaunch(phase: .active, savedState: readablePumpState)
        XCTAssertNotNil(c.loopManager.settings.basalRateSchedule, "therapy settings")
        XCTAssertEqual(c.loopManager.settingsProvider.history?.basal.first?.value, 0.8,
                       "the phone's settings history — else the resumed loan projects today's settings back")
        await c.loopManager.laneSettled()
        XCTAssertTrue(c.loopManager.closedLoopEnabled, "closed-loop mode — else a resumed loan comes back OPEN")
        XCTAssertTrue(c.loopManager.integralRetrospectiveCorrectionEnabled, "retrospective-correction mode")
        XCTAssertTrue(c.loopManager.glucoseBasedApplicationFactorEnabled, "application-factor mode")
        XCTAssertTrue(c.loopManager.guardAndRunwayEnabled, "guard + runway")
        XCTAssertEqual(c.loopManager.volatilityBaseline, 4.2, "the phone's volatility baseline for guard + runway")
        XCTAssertEqual(c.deliveredAtTakeover, 12.5, "the delivery baseline — else the hand-back audit reads delivered=n/a")
        XCTAssertEqual(c.loopManager.scheduleOverride?.syncIdentifier, override.syncIdentifier,
                       "the active override — else the resumed loan doses unscaled")
        XCTAssertTrue(c.isLoanActive, "the loan is live")
    }

    /// A loan resumed after a relaunch is live from launch, with no change of phase to announce it: the
    /// screens are handed the restored override all the same.
    func testAResumedLoanHandsItsOverrideToTheScreens() async {
        let live = await makeController()
        let override = halfNeeds(start: Date().addingTimeInterval(-.minutes(10)), duration: .indefinite)
        live.loopManager.applyWristOverride(override)

        persistGrantedSettings()
        saveState {
            $0.phase = .active
            $0.epoch = 7
        }
        savePumpState(readablePumpState)
        let c = await makeController()
        var published: [TemporaryScheduleOverride??] = []
        c.publishOverride = { published.append($0) }
        c.scheduler = { [weak c] delay, label, work in
            if label == "resume-ask" { work.perform() } else { DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work) }
        }
        c.resumeIfNeeded()
        await c.onMain { }

        guard case .some(let shown)? = published.last else { return XCTFail("nothing handed to the screens") }
        XCTAssertEqual(shown?.syncIdentifier, override.syncIdentifier, "the screens show the override the resumed loan doses with")
    }

    /// The whole history comes back, not only the active override: one that ended before the
    /// relaunch still scales its minutes.
    func testResumeRestoresTheOverrideHistory() async {
        let live = await makeController()
        let now = Date()
        let ended = halfNeeds(start: now.addingTimeInterval(-.hours(2)), duration: .finite(.hours(1)))
        let active = halfNeeds(start: now.addingTimeInterval(-.minutes(30)), duration: .indefinite)
        live.loopManager.applyWristOverride(ended)
        live.loopManager.applyWristOverride(active)

        let c = await relaunch(phase: .active, savedState: readablePumpState)
        XCTAssertEqual(c.loopManager.scheduleOverride?.syncIdentifier, active.syncIdentifier, "the target the cycle drives to")
        let kept = c.loopManager.overrideHistory.getOverrideHistory(startDate: now.addingTimeInterval(-.hours(3)), endDate: now)
        XCTAssertEqual(kept.map(\.syncIdentifier), [ended.syncIdentifier, active.syncIdentifier], "and every override the cycle scales by")
    }

    private func halfNeeds(start: Date, duration: TemporaryScheduleOverride.Duration) -> TemporaryScheduleOverride {
        TemporaryScheduleOverride(context: .custom,
                                  settings: TemporaryPresetSettings(unit: .milligramsPerDeciliter, targetRange: nil,
                                                                    insulinNeedsScaleFactor: 0.5),
                                  startDate: start, duration: duration, enactTrigger: .local, syncIdentifier: UUID())
    }

    func testClosedLoopDoesNotOutliveItsLoan() async {
        let live = await makeController()
        live.loopManager.setClosedLoopEnabled(true, reason: "test")
        live.loopManager.resetClosedLoopForSessionEnd()
        let next = await makeController()
        XCTAssertFalse(next.loopManager.closedLoopEnabled, "loop mode is per loan: the next launch starts open")
    }

    // MARK: insulin the records cannot explain

    private let t0 = Date().addingTimeInterval(-.minutes(30))
    private var flatSchedule: BasalRateSchedule { BasalRateSchedule(dailyItems: [RepeatingScheduleValue(startTime: 0, value: 1.2)])! }

    /// What a reading of `podTotal`, `minutes` after the copy's reading of 10.0 U, books with `records`
    /// in the watch's own store: the ledger's window closes at the reading, as at every pump report.
    private func unexplained(podTotal: Double, after minutes: Double, records: [DoseEntry] = []) async -> Double {
        let c = await makeController()
        var settings = LoopSettings()
        settings.basalRateSchedule = flatSchedule
        c.loopManager.settings = settings
        c.updateState { $0.ledgerLast = (units: 10.0, at: t0) }
        try? await c.loopManager.seedInsulinHistory(records)
        await c.checkOwnPumpTotal(reading: (units: podTotal, at: t0.addingTimeInterval(.minutes(minutes))), pulseUnits: 0.05, insulinType: nil)
        return await booked(in: c, since: t0)
    }

    /// The estimates in the watch's store since `start`, in units.
    private func booked(in c: PodLoanWatchController, since start: Date) async -> Double {
        let doses = (try? await c.loopManager.doseStore.getNormalizedDoseEntries(start: start.addingTimeInterval(-.hours(1)))) ?? []
        return doses.filter { $0.syncIdentifier?.hasPrefix("LOAN-WATCH-GAP") ?? false }.reduce(0) { $0 + ($1.deliveredUnits ?? 0) }
    }

    func testAnOrdinaryStartHasNothingToBook() async {
        // Ten minutes at 1.2 U/h is 0.2 U of scheduled basal, and that is all the pod delivered.
        let clean = await unexplained(podTotal: 10.2, after: 10)
        XCTAssertEqual(clean, 0)
        let inBand = await unexplained(podTotal: 10.35, after: 10)
        XCTAssertEqual(inBand, 0, "0.15 U over is inside the 0.20 U band — the phone's band at reclaim")
    }

    func testAPhoneBolusGivenAfterTheCopyIsBooked() async {
        // A copy older than a phone bolus: the watch books the unexplained insulin.
        let booked = await unexplained(podTotal: 16.2, after: 10)
        XCTAssertEqual(booked, 6.0, accuracy: 0.001)
    }

    func testABolusTheCopyAlreadyKnowsIsNotBookedTwice() async {
        // Still delivering when the copy's pod reading was taken: half of it is in that reading,
        // the other half arrives after it — and the copy's own record explains that half.
        let bolus = DoseEntry(type: .bolus, startDate: t0.addingTimeInterval(-.minutes(2)), endDate: t0.addingTimeInterval(.minutes(2)),
                              value: 6.0, unit: .units, decisionId: nil, deliveredUnits: 6.0, syncIdentifier: "copy-bolus")
        let straddling = await unexplained(podTotal: 10.0 + 3.0 + 0.2, after: 10, records: [bolus])
        XCTAssertEqual(straddling, 0)
        // …and a bolus wholly after the reading is explained in full.
        let later = DoseEntry(type: .bolus, startDate: t0.addingTimeInterval(.minutes(1)), endDate: t0.addingTimeInterval(.minutes(3)),
                              value: 2.0, unit: .units, decisionId: nil, deliveredUnits: 2.0, syncIdentifier: "later-bolus")
        let after = await unexplained(podTotal: 10.0 + 2.0 + 0.2, after: 10, records: [later])
        XCTAssertEqual(after, 0)
    }

    func testATempInTheCopyExplainsItsOwnDelivery() async {
        let temp = DoseEntry(type: .tempBasal, startDate: t0.addingTimeInterval(-.minutes(5)), endDate: t0.addingTimeInterval(.minutes(25)),
                             value: 3.0, unit: .unitsPerHour, decisionId: nil, syncIdentifier: "copy-temp")
        let explained = await unexplained(podTotal: 10.5, after: 10, records: [temp])
        XCTAssertEqual(explained, 0, "ten minutes at 3.0 U/h is 0.5 U")
        let beyond = await unexplained(podTotal: 12.5, after: 10, records: [temp])
        XCTAssertEqual(beyond, 2.0, accuracy: 0.001, "anything beyond it is not")
    }

    /// Back from being off, the watch asks the phone before the loop has the pod: a "this watch holds the
    /// pod" report goes out, and a revoke inside the wait stands it aside without a dose (control row 12).
    func testBackFromOffTheWatchAsksThePhoneBeforeLooping() async throws {
        persistGrantedSettings()
        saveState { $0.phase = .active; $0.epoch = 7 }
        savePumpState(readablePumpState)
        let c = await makeController()
        var reports: [Int] = []
        c.send = { dict in
            if let m = try? LoanMessage.decode(fromTransport: dict), case .statusReport(let r) = m, r.holdsPod { reports.append(r.epoch) }
        }
        var ask: DispatchWorkItem?
        c.scheduler = { _, label, work in if label == "resume-ask" { ask = work } }
        c.resumeIfNeeded()
        await c.onMain { }
        XCTAssertEqual(reports, [7], "the phone is asked at once")
        XCTAssertNil(c.loopManager.pumpManager, "and the loop does not have the pod while the question is out")
        XCTAssertNil(c.pumpManager, "nor is there a pump manager to reach the pod")
        XCTAssertTrue(c.isResuming, "the glance says it is checking with the phone")

        c.handleIncoming(userInfo: try LoanMessage.revoke(Revoke(epoch: 7)).transportDictionary())
        await c.onMain { }
        XCTAssertFalse(c.isResuming, "the phone's stop ends the check")
        await c.onMain { ask?.perform() }
        XCTAssertNil(c.loopManager.pumpManager, "the phone holds the pod: this watch stood aside, no cycle ran")
        XCTAssertNotEqual(c.phase, .active)
    }

    /// The question waits for the link to the phone to start up, and so does the wait for its answer:
    /// asked before, it would be lost and the silence read as no phone.
    func testBackFromOffTheQuestionWaitsForTheLink() async {
        persistGrantedSettings()
        saveState { $0.phase = .active; $0.epoch = 7 }
        savePumpState(readablePumpState)
        let c = await makeController()
        var reports = 0
        c.send = { dict in
            if let m = try? LoanMessage.decode(fromTransport: dict), case .statusReport(let r) = m, r.holdsPod { reports += 1 }
        }
        var linkUp = false
        c.isLinkActivated = { linkUp }
        var asks = 0
        c.scheduler = { _, label, _ in if label == "resume-ask" { asks += 1 } }
        c.resumeIfNeeded()
        await c.onMain { }
        XCTAssertEqual(reports, 0, "nothing sent before the link has started")
        XCTAssertEqual(asks, 0, "and no wait for an answer started")

        linkUp = true
        c.linkDidActivate()
        await c.onMain { }
        XCTAssertEqual(reports, 1, "asked once the link is up")
        XCTAssertEqual(asks, 1, "and the wait starts then")
        XCTAssertNil(c.loopManager.pumpManager)
    }

    /// No answer within the wait: the watch carries on alone.
    func testBackFromOffWithNoAnswerTheWatchCarriesOn() async {
        persistGrantedSettings()
        saveState { $0.phase = .active; $0.epoch = 7 }
        savePumpState(readablePumpState)
        let c = await makeController()
        var ask: DispatchWorkItem?
        c.scheduler = { _, label, work in if label == "resume-ask" { ask = work } }
        c.resumeIfNeeded()
        await c.onMain { }
        XCTAssertNil(c.loopManager.pumpManager)
        XCTAssertTrue(c.isResuming, "checking with the phone")
        await c.onMain { ask?.perform() }
        XCTAssertNotNil(c.loopManager.pumpManager, "silence: the loop has the pod")
        XCTAssertEqual(c.phase, .active)
        XCTAssertFalse(c.isResuming, "and the check is over")
    }

    func testAfterARelaunchNothingDosesBeforeThePodReports() async {
        // Once the check passes the loop has the pod; stock's recency check refuses to dose until the
        // pod's first report, and that report closes the ledger's window before it completes. A failed
        // read is no report, so no dose.
        let c = await relaunch(phase: .active, savedState: readablePumpState)
        XCTAssertNotNil(c.loopManager.pumpManager, "the loop has the pod at once")
        XCTAssertEqual(c.loopManager.doseStore.lastAddedPumpData, .distantPast, "no report yet, so no cycle passes the recency check")
    }

    func testAReadingAfterARelaunchClosesTheWindowFromTheLastReadingBefore() async {
        // The last reading before the watch went off starts the window; the first reading after the
        // relaunch books what the pod delivered meanwhile that the watch's records cannot explain.
        persistGrantedSettings()   // basal 1.0 U/h
        let before = Date().addingTimeInterval(-.minutes(20))
        saveState { $0.phase = .active; $0.epoch = 7; $0.ledgerLast = (units: 10.0, at: before) }
        savePumpState(readablePumpState)
        let c = await makeController()
        c.resumeIfNeeded()
        await c.onMain { }
        XCTAssertEqual(c.persisted.ledgerLast?.units, 10.0, "the window survives the relaunch")
        await c.checkOwnPumpTotal(reading: (units: 13.0, at: Date()), pulseUnits: 0.05, insulinType: nil)   // 20 min of basal is about 0.33 U; the rest nobody recorded
        let estimate = await booked(in: c, since: before)
        XCTAssertEqual(estimate, 2.67, accuracy: 0.06)
        XCTAssertEqual(c.persisted.ledgerLast?.units, 13.0, "and the reading starts the next window")
    }

    func testBookedInsulinIsInTheBookTheLoopDosesFrom() async {
        // The rule is only worth anything if the loop SEES the booking: through the same door the
        // phone's history is seeded by, into the same store insulin on board is computed from.
        let c = await makeController()
        var settings = LoopSettings()
        settings.basalRateSchedule = flatSchedule
        // The rest of a grant's settings, and glucose: IOB is read from the display run, as stock's.
        settings.insulinSensitivitySchedule = InsulinSensitivitySchedule(
            unit: .milligramsPerDeciliter, dailyItems: [RepeatingScheduleValue(startTime: 0, value: 50)])
        settings.carbRatioSchedule = CarbRatioSchedule(unit: .gram, dailyItems: [RepeatingScheduleValue(startTime: 0, value: 10)])
        settings.glucoseTargetRangeSchedule = GlucoseRangeSchedule(
            unit: .milligramsPerDeciliter,
            dailyItems: [RepeatingScheduleValue(startTime: 0, value: DoubleRange(minValue: 100, maxValue: 110))])
        settings.maximumBolus = 10
        settings.maximumBasalRatePerHour = 4
        settings.suspendThreshold = GlucoseThreshold(unit: .milligramsPerDeciliter, value: 80)
        c.loopManager.settings = settings
        _ = try? await c.loopManager.glucoseStore.addGlucoseSamples((0..<6).map { i in
            NewGlucoseSample(date: Date().addingTimeInterval(-Double(i) * 5 * 60),
                             quantity: LoopQuantity(unit: .milligramsPerDeciliter, doubleValue: 120),
                             condition: nil, trend: .flat, trendRate: nil, isDisplayOnly: false,
                             wasUserEntered: false, syncIdentifier: "booked-\(i)")
        })
        let copyAt = Date().addingTimeInterval(-.minutes(10))
        c.updateState { $0.ledgerLast = (units: 10.0, at: copyAt) }
        await c.checkOwnPumpTotal(reading: (units: 16.2, at: Date()), pulseUnits: 0.05, insulinType: nil)   // 0.2 U of basal, 6.0 U nobody recorded
        let iob: Double? = await withCheckedContinuation { done in
            c.loopManager.updateDisplayState { done.resume(returning: $0.activeInsulin?.value) }
        }
        XCTAssertEqual(iob ?? 0, 6.0, accuracy: 0.5, "six units, a minute old, are all still on board")
        let snapshot8 = await c.fencedSnapshot()
        XCTAssertNotNil(snapshot8.startNoteText, "and the wrist says so")
        XCTAssertEqual(c.persisted.ledgerLast?.units, 16.2, "the reading starts the next window")
    }

    // MARK: the rebuild after a relaunch

    func testASavedSessionIsLiveFromLaunchNotFromTheEndOfItsRebuild() async {
        // State shows a live session before the slow pump rebuild finishes.
        persistGrantedSettings()
        saveState {
            $0.phase = .active
            $0.epoch = 7
        }
        savePumpState(readablePumpState)
        let c = await makeController()
        XCTAssertTrue(c.isLoanActive, "live from the moment the saved session is found")
        XCTAssertTrue(c.isResuming, "and known to be rebuilding — what the glance shows instead of nothing")

        c.resumeIfNeeded()
        await c.onMain { }
        XCTAssertTrue(c.isResuming, "restored, and still checking with the phone before looping")
        XCTAssertTrue(c.isLoanActive)
        XCTAssertNil(c.pumpManager, "the pump manager, which reaches the pod by itself, waits for the check")
    }

    func testAFailedRebuildIsNeitherLiveNorResuming() async {
        saveState {
            $0.phase = .active
            $0.epoch = 7
        }
        savePumpState(readablePumpState)
        let c = await makeController()          // no granted settings on disk: the rebuild must fail
        c.resumeIfNeeded()
        await c.onMain { }
        XCTAssertFalse(c.isResuming)
        XCTAssertFalse(c.isLoanActive, "a session that could not be rebuilt is not live")
        XCTAssertTrue(c.wristOwnsAlarms, "the phone still leaves the alarms here until the records land")
    }

    // MARK: the hold

    func testEveryLandedCycleRenewsTheHoldEvenWithNothingToReport() async throws {
        // The watch's hold on the pod is this message being recent — so it goes out on every
        // landed cycle, stamped, by the ordinary paths: the queued one delivers in seconds, and a late
        // one renews nothing because the phone judges it by its stamp.
        let c = await relaunch(phase: .active, savedState: readablePumpState)
        var sent: [[String: Any]] = []
        c.send = { sent.append($0) }
        let before = Date()
        c.renewHold()
        await c.onMain { }
        XCTAssertEqual(sent.count, 1, "one renewal")
        let dictionary = try XCTUnwrap(sent.first)
        XCTAssertNil(dictionary["urgentOnly"], "an empty renewal goes like any other, queued if need be")
        guard case .doseRecordBatch(let batch)? = try LoanMessage.decode(fromTransport: dictionary) else {
            return XCTFail("the renewal is the ordinary record batch")
        }
        XCTAssertEqual(batch.epoch, 7)
        XCTAssertTrue(batch.events.isEmpty)
        XCTAssertEqual(try XCTUnwrap(batch.sentAt).timeIntervalSince(before), 0, accuracy: 2,
                       "stamped with its send time — the phone judges freshness by this")
    }

    func testAnIdleWatchRenewsNothing() async {
        let c = await makeController()
        var sent = 0
        c.send = { _ in sent += 1 }
        c.renewHold()
        await c.onMain { }
        XCTAssertEqual(sent, 0, "no loan, no hold")
    }

    func testAReleasedWatchNeverResumesByTimer() async throws {
        // Once released, no timer brings the watch back to dosing.
        let c = await relaunch(phase: .active, savedState: readablePumpState)
        c.isPhoneReachable = { true }
        var sent: [[String: Any]] = []
        c.send = { sent.append($0) }
        c.beginHandback()
        await c.onMain { }
        c.handleIncoming(userInfo: try LoanMessage.handbackAck(HandbackAck(epoch: 7, committedCursor: 0)).transportDictionary())
        // The ack finalizes: dosing stops on the loop's lane, then the final offer goes out.
        await c.onMain { }; await c.loopManager.laneSettled(); await c.onMain { }; await c.onMain { }
        XCTAssertEqual(c.phase, .handingBack, "released: the final offer is out")
        XCTAssertNil(c.loopManager.pumpManager, "and dosing has stopped")

        await c.onMain { c.handbackTimedOut() }

        XCTAssertNotEqual(c.phase, .active, "released means released")
        XCTAssertEqual(c.phase, .recoveredDrain, "drain-only: the offer itself is the news")
        XCTAssertNil(c.pumpManager, "the pod is let go, so the phone can reach it")
        XCTAssertNil(c.loopManager.pumpManager, "no dosing")
        guard case .handbackOffer(let offer)? = try LoanMessage.decode(fromTransport: try XCTUnwrap(sent.last)) else {
            return XCTFail("it keeps offering")
        }
        XCTAssertEqual(offer.released, true)
        XCTAssertTrue(offer.recovered, "as a drain: it may be queued now — late, it is still true")
    }

    func testTeardownClearsSavedState() async {
        let c = await relaunch(phase: .active, savedState: readablePumpState)
        XCTAssertNotNil(c.pumpManager)
        await c.onMain { c.teardownPump() }
        XCTAssertNil(c.pumpManager)
        XCTAssertNil(c.pumpStateStore.wrappedValue,
                     "no pod held, nothing to resume — a relaunch now sees an ordinary closed loan")
    }
}
