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

final class WakeResumeTests: XCTestCase {

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
                                       supportsInterimHandback: true, supportsOverrideRecords: true,
                                       settingsHistory: history)
        }
    }

    override func tearDown() {
        cacheStore = nil
        cacheDir = nil
        journalDir = nil
        defaults = nil
        super.tearDown()
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
        c.resumeIfNeeded()   // what the session does once the hooks are wired
        c.queue.sync { }     // the resume is built on the queue; wait for it
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
        c.handleIncoming(userInfo: try LoanMessage.revoke(Revoke(epoch: 8)).transportDictionary(), channel: .urgent)
        c.queue.sync { }

        let relaunched = await makeController()
        var failures: [String] = []
        relaunched.send = { dict in
            if case .takeoverFailed(let f)? = try? LoanMessage.decode(fromTransport: dict) { failures.append(f.reason) }
        }
        let grant = LoanGrant(epoch: 8, expiresAt: Date().addingTimeInterval(300), pumpConfiguration: Data([1, 2, 3]),
                              podAddress: 0, therapySettingsRaw: Data([4, 5]), settingsTimeZoneID: "GMT", doseHistory: [],
                              therapySettingsSupplementRaw: nil)
        relaunched.queue.sync { relaunched.handleGrant(grant) }
        XCTAssertEqual(failures.count, 1)
        XCTAssertTrue(failures.first?.contains("last revoke") == true, "refused for the revoke, got: \(failures)")
    }

    func testActiveLoanWithSavedPodStateResumes() async {
        let c = await relaunch(phase: .active, savedState: readablePumpState)
        XCTAssertEqual(c.phase, .active, "an active loan with saved pod state resumes — not drained")
        XCTAssertEqual(c.epoch, 7, "the loan's epoch carries over unchanged")
        XCTAssertNotNil(c.pumpManager, "the pump manager is rebuilt from the saved state")
        XCTAssertNotNil(c.loopManager.pumpManager, "and handed to the loop, so dosing can resume")
        XCTAssertTrue(c.isLoanActiveNonBlocking,
                      "the main-safe mirror is set — init loads the phase without its didSet (else: onboarding screen + blank IOB)")
        XCTAssertNotNil(c.loopManager.settings.basalRateSchedule,
                        "the granted therapy settings came back from disk (else: blank IOB, no schedule)")
        XCTAssertTrue(c.phoneSupportsInterimHandback,
                      "the phone's hand-back capability comes back with the grant payload (else: a resumed loan hands back single-phase)")
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

    func testLiveHandbackWithPhoneUnreachableFailsFastAndKeepsTheLoan() async {
        // A live hand-back is never queued. Out of reach, End fails at once
        // and the loan continues — no offer is sent, nothing can land later and take the pod.
        let c = await relaunch(phase: .active, savedState: readablePumpState)
        XCTAssertNotNil(c.pumpManager)
        c.isPhoneReachable = { false }
        var sent: [[String: Any]] = []
        c.send = { sent.append($0) }
        c.beginHandback()
        c.queue.sync { }
        XCTAssertEqual(c.phase, .active, "the loan continues")
        XCTAssertNotNil(c.pumpManager, "the watch still holds the pod")
        XCTAssertTrue(sent.isEmpty, "no offer left the watch — nothing queued to land later")
        XCTAssertNotNil(c.debugSnapshot().handbackFailureText, "and the glance has the reason to show, on screen rather than as a notification")
    }

    func testPhoneRefusalEndsTheHandbackAtOnceAndKeepsTheLoan() async throws {
        // With the phone's Bluetooth off, End is refused and the watch
        // knows at once — no budget to wait out. The phone says so; the watch shows its reason.
        let c = await relaunch(phase: .active, savedState: readablePumpState)
        c.isPhoneReachable = { true }
        var sent = 0
        c.send = { _ in sent += 1 }
        c.beginHandback()
        c.queue.sync { }
        XCTAssertEqual(sent, 1, "the interim offer went out")
        let reason = "iPhone Bluetooth is off — still running"
        c.handleIncoming(userInfo: try LoanMessage.denied(LoanDenied(reason: reason)).transportDictionary(), channel: .urgent)
        c.queue.sync { }
        XCTAssertEqual(c.phase, .active, "the loan continues")
        XCTAssertNotNil(c.pumpManager, "the watch still holds the pod")
        XCTAssertEqual(c.debugSnapshot().handbackFailureText, reason, "the glance shows the phone's own reason")
        XCTAssertFalse(c.debugSnapshot().handbackPending, "End is over — tap again once Bluetooth is back")
    }

    func testResumeRestoresEverythingALoanHadInstalled() async {
        // One list, so a new grant field cannot be left out of the saved state.
        let live = await makeController()
        live.loopManager.setClosedLoopEnabled(true, reason: "test")
        live.loopManager.setAlgorithmExperiments(integralRetrospectiveCorrection: true, glucoseBasedApplicationFactor: true)
        let override = halfNeeds(start: Date().addingTimeInterval(-.minutes(10)), duration: .indefinite)
        live.loopManager.applyWristOverride(override)
        saveState { $0.deliveredAtTakeover = 12.5 }

        let c = await relaunch(phase: .active, savedState: readablePumpState)
        XCTAssertNotNil(c.loopManager.settings.basalRateSchedule, "therapy settings")
        XCTAssertEqual(c.loopManager.settingsProvider.history?.basal.first?.value, 0.8,
                       "the phone's settings history — else the resumed loan projects today's settings back")
        XCTAssertTrue(c.loopManager.closedLoopEnabledNonBlocking, "closed-loop mode — else a resumed loan comes back OPEN")
        XCTAssertTrue(c.loopManager.isIntegralRetrospectiveCorrectionEnabled, "retrospective-correction mode")
        XCTAssertTrue(c.loopManager.isGlucoseBasedApplicationFactorEnabled, "application-factor mode")
        XCTAssertTrue(c.phoneSupportsInterimHandback, "the phone's interim hand-back capability")
        XCTAssertTrue(c.phoneSupportsOverrideRecords, "the phone's override-records capability")
        XCTAssertEqual(c.deliveredAtTakeover, 12.5, "the delivery baseline — else the hand-back audit reads delivered=n/a")
        XCTAssertEqual(c.loopManager.scheduleOverride?.syncIdentifier, override.syncIdentifier,
                       "the active override — else the resumed loan doses unscaled")
        XCTAssertTrue(c.isLoanActiveNonBlocking, "the live-loan mirror")
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
        XCTAssertFalse(next.loopManager.closedLoopEnabledNonBlocking, "loop mode is per loan: the next launch starts open")
    }

    // MARK: insulin the copy cannot explain

    private let t0 = Date(timeIntervalSince1970: 1_790_000_000)
    private var flatSchedule: BasalRateSchedule { BasalRateSchedule(dailyItems: [RepeatingScheduleValue(startTime: 0, value: 1.2)])! }
    private func unexplained(podTotal: Double, after minutes: Double, records: [LoanDoseRecord] = []) -> Double {
        PodLoanWatchController.insulinTheCopyCannotExplain(copyTotal: 10.0, copyAt: t0, podTotal: podTotal,
                                                           now: t0.addingTimeInterval(.minutes(minutes)),
                                                           records: records, schedule: flatSchedule, pulseUnits: 0.05)
    }

    func testAnOrdinaryStartHasNothingToBook() {
        // Ten minutes at 1.2 U/h is 0.2 U of scheduled basal, and that is all the pod delivered.
        XCTAssertEqual(unexplained(podTotal: 10.2, after: 10), 0)
        XCTAssertEqual(unexplained(podTotal: 10.35, after: 10), 0, "0.15 U over is inside the 0.20 U band — the phone's band at reclaim")
    }

    func testAPhoneBolusGivenAfterTheCopyIsBooked() {
        // A copy older than a phone bolus: the watch books the unexplained insulin.
        XCTAssertEqual(unexplained(podTotal: 16.2, after: 10), 6.0, accuracy: 0.001)
    }

    func testABolusTheCopyAlreadyKnowsIsNotBookedTwice() {
        // Still delivering when the copy's pod reading was taken: half of it is in that reading,
        // the other half arrives after it — and the copy's own record explains that half.
        let bolus = LoanDoseRecord(kind: .bolus, startDate: t0.addingTimeInterval(-.minutes(2)),
                                   endDate: t0.addingTimeInterval(.minutes(2)), amount: 6.0)
        XCTAssertEqual(unexplained(podTotal: 10.0 + 3.0 + 0.2, after: 10, records: [bolus]), 0)
        // …and a bolus wholly after the reading is explained in full.
        let later = LoanDoseRecord(kind: .bolus, startDate: t0.addingTimeInterval(.minutes(1)),
                                   endDate: t0.addingTimeInterval(.minutes(3)), amount: 2.0)
        XCTAssertEqual(unexplained(podTotal: 10.0 + 2.0 + 0.2, after: 10, records: [later]), 0)
    }

    func testATempInTheCopyExplainsItsOwnDelivery() {
        let temp = LoanDoseRecord(kind: .tempBasal, startDate: t0.addingTimeInterval(-.minutes(5)),
                                  endDate: t0.addingTimeInterval(.minutes(25)), unitsPerHour: 3.0)
        XCTAssertEqual(unexplained(podTotal: 10.5, after: 10, records: [temp]), 0, "ten minutes at 3.0 U/h is 0.5 U")
        XCTAssertEqual(unexplained(podTotal: 12.5, after: 10, records: [temp]), 2.0, accuracy: 0.001, "anything beyond it is not")
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
        c.queue.sync {
            c.takeoverCopyTotal = (10.0, copyAt)
            c.takeoverCopyRecords = []
            c.bookInsulinTheCopyCannotExplain(podTotal: 16.2, pulseUnits: 0.05, epoch: 7)   // 0.2 U of basal, 6.0 U nobody recorded
        }
        let iob: Double? = await withCheckedContinuation { done in
            c.loopManager.updateDisplayState { done.resume(returning: $0.activeInsulin?.value) }
        }
        XCTAssertEqual(iob ?? 0, 6.0, accuracy: 0.5, "six units, a minute old, are all still on board")
        XCTAssertNotNil(c.debugSnapshot().startNoteText, "and the wrist says so")
        XCTAssertNil(c.takeoverCopyTotal, "consumed: one check per Start")
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
        XCTAssertTrue(c.isLoanActiveNonBlocking, "live from the moment the saved session is found")
        XCTAssertTrue(c.isResumingNonBlocking, "and known to be rebuilding — what the glance shows instead of nothing")

        c.resumeIfNeeded()
        c.queue.sync { }
        XCTAssertFalse(c.isResumingNonBlocking, "rebuilt")
        XCTAssertTrue(c.isLoanActiveNonBlocking)
        XCTAssertNotNil(c.pumpManager)
    }

    func testAFailedRebuildIsNeitherLiveNorResuming() async {
        saveState {
            $0.phase = .active
            $0.epoch = 7
        }
        savePumpState(readablePumpState)
        let c = await makeController()          // no granted settings on disk: the rebuild must fail
        c.resumeIfNeeded()
        c.queue.sync { }
        XCTAssertFalse(c.isResumingNonBlocking)
        XCTAssertFalse(c.isLoanActiveNonBlocking, "a session that could not be rebuilt is not live")
        XCTAssertTrue(c.wristOwnsAlarmsNonBlocking, "the phone still leaves the alarms here until the records land")
    }

    // MARK: the hold

    func testEveryLandedCycleRenewsTheHoldEvenWithNothingToReport() async throws {
        // The watch's hold on the pod is this message being recent — so it goes out on every
        // landed cycle, stamped, and an empty one is never queued (late, it would renew nothing).
        let c = await relaunch(phase: .active, savedState: readablePumpState)
        var sent: [[String: Any]] = []
        c.send = { sent.append($0) }
        let before = Date()
        c.renewHold()
        c.queue.sync { }
        XCTAssertEqual(sent.count, 1, "one renewal")
        let dictionary = try XCTUnwrap(sent.first)
        XCTAssertEqual(dictionary["urgentOnly"] as? Bool, true, "an empty renewal is never queued")
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
        c.queue.sync { }
        XCTAssertEqual(sent, 0, "no loan, no hold")
    }

    func testAReleasedWatchNeverResumesByTimer() async throws {
        // Once released, no timer brings the watch back to dosing.
        let c = await relaunch(phase: .active, savedState: readablePumpState)
        c.isPhoneReachable = { true }
        var sent: [[String: Any]] = []
        c.send = { sent.append($0) }
        c.beginHandback()
        c.queue.sync { }
        c.handleIncoming(userInfo: try LoanMessage.handbackAck(HandbackAck(epoch: 7, committedCursor: 0)).transportDictionary(), channel: .urgent)
        c.queue.sync { }; c.queue.sync { }   // the ack finalizes; finalize sends the final offer on the queue
        XCTAssertEqual(c.phase, .handingBack, "released: the final offer is out")
        XCTAssertNil(c.loopManager.pumpManager, "and dosing has stopped")

        c.queue.sync { c.handbackTimedOut() }

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
        c.queue.sync { c.teardownPump() }
        XCTAssertNil(c.pumpManager)
        XCTAssertNil(c.pumpStateStore.wrappedValue,
                     "no pod held, nothing to resume — a relaunch now sees an ordinary closed loan")
    }
}
