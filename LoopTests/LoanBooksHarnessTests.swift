//  The largest Sport Mode suite (1801 lines) and the one with the most next-dev drift: DoseEntry
//  and UnfinalizedDose now take a decisionId, SessionInsulinLedger takes an insulinModel function
//  instead of a model provider, and PresetInsulinModelProvider is gone. Roughly 58 sites.
//
//  It is excluded rather than half-ported so the rest of the suite can build and gate. This is
//  the next piece of work, and it matters: this is the harness that pins the dose-identity and
//  book-keeping rules.
//
//
//  LoanBooksHarnessTests.swift
//  LoopTests
//
//  A scripted "session replay" harness for the loan insulin books, built from the field
//  incidents, against the real Core Data DoseStore (mutable-dose lifecycle, raw-identity dedup).
//  Every field incident so far has been a coherence failure BETWEEN writers or ACROSS the
//  handover seam — never in InsulinMath itself. (Until 2026-09-17 the session also kept a second
//  book, the SessionInsulinLedger; it is gone — the watch's DoseStore is the one book, written by
//  the watch's pump manager — and the store-vs-ledger parity tests went with it.) The harness
//  replays one scripted session and pins the seams:
//
//   2. testDuplicateBolusTwinDetection — the zero-length journal bolus + pod-native twin
//      pair double-booking ~0.95 U of phantom IOB in the store.
//   3. testHandbackSeamCloses — the hand-back seam must be fully explained
//      by decay + the zero-temp's withheld basal; when the rows match, nothing leaks.
//   4. testReGrantRoundTripPreservesBooks — seed → enact chain → hand-back fold →
//      re-grant reseed must conserve IOB across the epoch boundary (cross-epoch fidelity).
//   5. testBolusDeliveryQueueShapeDoesNotTrap — the bolus-crash queue invariant: the
//      FIXED dispatch topology (reclaim completion on the loan queue → async hop to the
//      dosing queue → journal mint queue.sync back onto the loan queue) must complete.
//   6. testBolusLandsInTheBookAfterQueueHop — the book-level pin: a bolus delivered
//      through the hopped topology lands in the store (field signature: 2.33).
//   7. testCarbRoundTripDynamicAbsorptionParity — the carb fold seam: a watch loan carb
//      folded to the phone in LoanReconciler's shape, fed the SAME stock-computed ICE
//      velocities, must produce the same dynamic COB and carb-effect curve.
//   8. testTruncatedPhoneICEOverstatesCOB — the relay-gap hypothesis: a phone missing the
//      loan-window glucose observes less absorption → MORE COB (the 6g-vs-7g +1g seam)
//      — the diagnostic pin for glucose-relay completeness.
//
//  Conventions copied from WatchStoreEffectsTests: PersistenceController-per-store temp
//  dirs, the fixed-store construction (shared TemporaryScheduleOverrideHistory at init,
//  schedules via the property setters), seeds through addPumpEvents so stock reconciled()
//  runs, and the identity contract (syncId == hex(raw); LoanSeedIdentity hex-DECODES
//  the phone syncId back to the pod-native bytes). Basal here is 0.70 U/hr FLAT — the
//  field profile behind every number below — not the 1.0 of the older fixtures.
//
//  Determinism: DoseStore's cacheLength (24 h) and purge logic need doses near wall-clock
//  now, so each test derives EVERY instant from a single `let now = Date()` — offsets are
//  fixed, so the arithmetic is deterministic run-to-run even though the absolute dates
//  float. No bare Date() appears anywhere else.
//

import XCTest
import HealthKit
// @testable rather than a plain import: the store-readiness handshake these tests block on
// (`PersistenceController.onReady`) is internal to LoopKit. Handing a driver a store that has
// not finished attaching is the zero-rows race described below, so waiting is not optional.
@testable import LoopKit
import LoopAlgorithm
import LoopCore
@testable import Loop

// MARK: - File fixtures

/// The field basal schedule: 0.70 U/hr flat. The dead-re-arm divergence (test 1b) grows
/// at exactly this rate, and the hand-back seam (test 3) withholds exactly this rate —
/// keeping the fixture equal to the field profile keeps the pinned deltas literal.
private let fieldBasalRate = 0.70

private let iso8601 = ISO8601DateFormatter()

/// Pod-native identity, OmniBLE's `UnfinalizedDose.uniqueKey` shape:
/// raw = utf8("\(doseType) \(units-or-rate) \(ISO8601 start)") — deterministic and
/// cancel-stable (UnfinalizedDose.swift:54). The exact number formatting need not match
/// OmniBLE byte-for-byte here; what the tests rely on is the dose-identity CONTRACT:
/// the phone's stored syncIdentifier IS hex(raw), and LoanSeedIdentity.raw(forSyncIdentifier:)
/// hex-decodes it back to these same bytes.
private func podRaw(type: String, value: Double, start: Date) -> Data {
    return Data("\(type) \(value) \(iso8601.string(from: start))".utf8)
}

private func hexString(_ data: Data) -> String {
    return data.map { String(format: "%02hhx", $0) }.joined()
}

// MARK: - Carb-side fixtures (tests 7-8)

/// The carb therapy fixtures: CR 10 g/U, ISF 50 mg/dL/U → carbohydrate sensitivity
/// 5 mg/dL per gram — the divisor that turns observed counteraction into absorbed grams.
private let fieldCarbRatio = CarbRatioSchedule(unit: .gram, dailyItems: [RepeatingScheduleValue(startTime: 0, value: 10.0)])!
private let fieldISF = InsulinSensitivitySchedule(unit: .milligramsPerDeciliter, dailyItems: [RepeatingScheduleValue(startTime: 0, value: 50.0)])!

/// A bare glucose sample for the stock ICE computation. `counteractionEffects(to:)`
/// (LoopKit GlucoseMath.swift:161) requires matching provenance across each pair, no
/// display-only samples, and >4 min spacing — one fixed provenance and a 5-min grid
/// satisfy all three. (MealDetectionManagerTests' MockGlucoseSample is fileprivate,
/// hence this local twin.)
private struct SimGlucoseSample: GlucoseSampleValue {
    let startDate: Date
    let quantity: LoopQuantity
    let provenanceIdentifier = "LoanBooksHarnessTests"
    let isDisplayOnly = false
    let wasUserEntered = false
    let condition: GlucoseCondition? = nil
    let trend: GlucoseTrend? = nil
    let trendRate: LoopQuantity? = nil
    let syncIdentifier: String? = nil
}

// MARK: - The driver

/// Scripted session-replay driver: one loan session run against BOTH books at once.
///

/// Supplies the scheduled basal history that `DoseStore.addPumpEvents` requires on this
/// architecture. Without a delegate that call throws `DoseStoreError.configurationError`
/// before any dose is written — which reddened this whole file (31 assertions from one cause:
/// no doses land, so every book comparison comes back nan or zero). The harness was ported
/// without it because the delegate requirement is new here.
///
/// A flat schedule at the harness's own field rate: these tests assert about LOAN bookkeeping
/// against a known baseline, not about schedule shape.
final class LoanBooksDoseStoreDelegate: DoseStoreDelegate {
    private let rate: Double
    init(rate: Double) { self.rate = rate }

    func doseStoreHasUpdatedPumpEventData(_ doseStore: DoseStore) {}

    func scheduledBasalHistory(from start: Date, to end: Date) async throws -> [AbsoluteScheduleValue<Double>] {
        [AbsoluteScheduleValue(startDate: start, endDate: end, value: rate)]
    }
}

/// Store side: a real DoseStore fed through `addPumpEvents`, playing the pod's report
/// lifecycle exactly as OmniBLE does — the running temp is re-asserted MUTABLE full-span
/// in every report batch (replacePendingEvents purges and the batch re-asserts), then
/// finalized on supersede/hand-back as the SAME raw with the truncated span, immutable.
/// Grant seeds run the REAL split (`LoanGrant.seedDoseEntries(finishedBy:)`) and land via
/// `addPumpEvents(lastReconciliation:replacePendingEvents: false)` under hex-decoded raws.
private final class LoanBooksDriver {

    let store: DoseStore
    let schedule: BasalRateSchedule

    private unowned let host: XCTestCase

    /// The pod's current unfinalized temp — OmniBLE's UnfinalizedDose, in miniature.
    private struct RunningTemp {
        let raw: Data
        let rate: Double
        let start: Date
        let programmedEnd: Date
    }
    private var runningTemp: RunningTemp?

    /// Hand-back-shaped records accumulated as the session finalizes doses (temps
    /// truncated at supersede, same raws, syncIdentifier = hex(raw) — the identity
    /// contract). `handbackFold` returns seedRecords + these as the next grant.
    private var foldedSession: [LoanDoseRecord] = []
    private var seedRecords: [LoanDoseRecord] = []

    /// The store is built by `makeDriver`, which owns the `await`: `DoseStore.init` is async now,
    /// and the store no longer carries a basal profile, sensitivity schedule or override history
    /// at all. Schedules are applied at READ time by whoever is doing the math.
    /// Retained here because `DoseStore.delegate` is weak — without an owner the delegate
    /// deallocates immediately and `addPumpEvents` is back to throwing configurationError.
    private let storeDelegate: LoanBooksDoseStoreDelegate

    init(host: XCTestCase, store: DoseStore, basalRate: Double, storeDelegate: LoanBooksDoseStoreDelegate) {
        self.host = host
        self.storeDelegate = storeDelegate
        // Fixture construction (force-unwraps allowed here, per file convention).
        self.schedule = BasalRateSchedule(dailyItems: [RepeatingScheduleValue(startTime: 0, value: basalRate)])!
        self.store = store
    }

    // MARK: Script steps

    /// seed(grant records): runs the REAL grant split. Finished history lands in the
    /// store under hex-decoded pod-native raws; a live dose is NOT seeded —
    /// the driver plays the pod and reports it MUTABLE full-span.
    func seed(_ records: [LoanDoseRecord], at instant: Date, epoch: Int = 1) {
        seedRecords = records
        let grant = LoanGrant(epoch: epoch, expiresAt: instant.addingTimeInterval(.minutes(5)),
                              pumpManagerRawState: Data(), podAddress: 0,
                              therapySettingsRaw: Data(), settingsTimeZoneID: TimeZone.current.identifier,
                              doseHistory: records)
        let split = grant.seedDoseEntries(finishedBy: instant)

        let events = split.seed.map { dose in
            NewPumpEvent(date: dose.startDate, dose: dose,
                         raw: LoanSeedIdentity.raw(forSyncIdentifier: dose.syncIdentifier ?? UUID().uuidString),
                         title: "Loan Seed")
        }
        if !events.isEmpty {
            addToStore(events, lastReconciliation: instant, replacePendingEvents: false)
        }

        for dose in split.live where dose.type == .tempBasal {
            let temp = RunningTemp(
                raw: LoanSeedIdentity.raw(forSyncIdentifier: dose.syncIdentifier ?? UUID().uuidString),
                rate: dose.unitsPerHour, start: dose.startDate, programmedEnd: dose.endDate)
            runningTemp = temp
            addToStore([mutableEvent(for: temp)], lastReconciliation: instant, replacePendingEvents: true)
        }
    }

    /// A pod-ACCEPTED temp: the report batch carries the superseded predecessor finalized
    /// (same raw, truncated at this accept, immutable) plus the new temp mutable full-span.
    func enactTemp(rate: Double, at instant: Date, duration: TimeInterval) {
        var batch: [NewPumpEvent] = []
        if let final = finalizeRunningTemp(at: instant) {
            batch.append(final)
        }
        let temp = RunningTemp(raw: podRaw(type: "tempBasal", value: rate, start: instant),
                               rate: rate, start: instant,
                               programmedEnd: instant.addingTimeInterval(duration))
        runningTemp = temp
        batch.append(mutableEvent(for: temp))
        addToStore(batch, lastReconciliation: instant, replacePendingEvents: true)
    }

    /// A pod-ACCEPTED bolus, booked finalized on the next report (typical small bolus:
    /// ~38 s span). The running temp's mutable row is re-asserted in the same batch —
    /// replacePendingEvents purges mutable rows raw-blind, and OmniBLE survives that only
    /// because every report re-asserts the whole unfinalized set.
    func enactBolus(units: Double, at instant: Date, span: TimeInterval = 38) {
        let raw = podRaw(type: "bolus", value: units, start: instant)
        let dose = DoseEntry(type: .bolus, startDate: instant,
                             endDate: instant.addingTimeInterval(span),
                             value: units, unit: .units, decisionId: nil)
        var batch = [NewPumpEvent(date: instant, dose: dose, raw: raw, title: "Bolus")]
        if let temp = runningTemp {
            batch.append(mutableEvent(for: temp))
        }
        // lastReconciliation covers the bolus span: an IMMUTABLE dose must not end after
        // the reconciliation watermark (DoseStore.addPumpEvents' commented-out fatalError
        // documents that contract).
        addToStore(batch, lastReconciliation: instant.addingTimeInterval(span), replacePendingEvents: true)

        foldedSession.append(LoanDoseRecord(kind: .bolus, startDate: instant,
                                            endDate: instant.addingTimeInterval(span),
                                            amount: units, syncIdentifier: hexString(raw)))
    }

    /// Sample the book. A pure read — replay order matters: tick BEFORE a later enact
    /// lands if the script wants the pre-enact view (the store is one Core Data table;
    /// once a row is in, every evaluation sees it).
    func tick(at instant: Date) -> Double {
        storeIOB(at: instant)
    }

    /// Hand-back: cancel/finalize the running temp at `instant` (same raw, truncated
    /// span, immutable — the pod's own finalization shape) and emit the next grant's
    /// doseHistory: the original seed records plus every session dose in hand-back shape.
    func handbackFold(at instant: Date) -> [LoanDoseRecord] {
        if let final = finalizeRunningTemp(at: instant) {
            addToStore([final], lastReconciliation: instant, replacePendingEvents: true)
        }
        return seedRecords + foldedSession
    }

    // MARK: Low-level primitives (for scripting broken shapes)

    /// A finished/truncated row straight into the STORE only — test 1(b)'s known-wrong
    /// dead-re-arm shape (C5 record seeded, pod never re-reported).
    func storeFinished(_ dose: DoseEntry, raw: Data, lastReconciliation: Date) {
        addToStore([NewPumpEvent(date: dose.startDate, dose: dose, raw: raw, title: "Temp Basal")],
                   lastReconciliation: lastReconciliation, replacePendingEvents: false)
    }

    /// e44: a raw batch straight into the store. The force-reclaim seam is not the pod's report
    /// lifecycle — it is the loan controller writing salvage records, the phone writing its own
    /// resumed basal, and a late journal commit — so it is scripted event by event.
    func storeEvents(_ events: [NewPumpEvent], lastReconciliation: Date) {
        addToStore(events, lastReconciliation: lastReconciliation, replacePendingEvents: false)
    }

    /// e44: `PodLoanPhoneController.Dependencies.backfillDoses` against the real store —
    /// stock's update-or-insert-by-syncIdentifier door, which has no basal boundary in front
    /// of it (the boundary lives on the pump-event → delivery-store sync, not here).
    func backfill(_ doses: [DoseEntry]) {
        let exp = host.expectation(description: "syncDoseEntries")
        Task {
            do {
                try await self.store.syncDoseEntries(doses)
            } catch {
                XCTFail("backfill threw: \(error)")
            }
            exp.fulfill()
        }
        host.wait(for: [exp], timeout: 10)
    }

    /// What every dosing consumer actually reads.
    func normalizedDoses(start: Date, end: Date) -> [DoseEntry] {
        var out: [DoseEntry] = []
        let exp = host.expectation(description: "normalized dose read")
        Task {
            out = (try? await self.store.getNormalizedDoseEntries(start: start, end: end)) ?? []
            exp.fulfill()
        }
        host.wait(for: [exp], timeout: 10)
        return out
    }

    func storeBolusCount(start: Date, end: Date) -> Int {
        return normalizedDoses(start: start, end: end).filter { $0.type == .bolus }.count
    }

    /// IOB from the STORE's rows.
    ///
    /// `DoseStore.insulinOnBoard(at:)` no longer exists: the store holds rows, and the insulin
    /// math is applied by the caller against a schedule the store never sees. So this is now the
    /// store's ROWS run through the public InsulinMath pipeline — annotate
    /// against the basal schedule, take the on-board timeline, sample it stock's way (of the two
    /// 5-min-grid values adjacent to `date`, the larger).
    ///
    /// This does NOT weaken the comparison these tests exist for. The two books were always meant
    /// to differ in their ROWS, not their arithmetic — the bugs it has caught are truncated twins,
    /// dead re-arms and duplicate seeds, all of which are row-level. Sharing one arithmetic path
    /// makes a disagreement unambiguously a row disagreement, which is what the assertions claim.
    func storeIOB(at date: Date) -> Double {
        let doses = normalizedDoses(start: date.addingTimeInterval(-.hours(24)),
                                    end: date.addingTimeInterval(.hours(6)))
        guard !doses.isEmpty else { return 0 }
        return Self.insulinOnBoard(of: doses, at: date, schedule: schedule)
    }

    /// The shared arithmetic, so the store side and any hand-built expectation agree by
    /// construction rather than by two copies of the same lines drifting apart.
    static func insulinOnBoard(of doses: [DoseEntry], at date: Date, schedule: BasalRateSchedule) -> Double {
        let duration = ExponentialInsulinModelPreset.rapidActingAdult.effectDuration
        let start = doses.map { $0.startDate }.min() ?? date
        let end = max(date, doses.map { $0.endDate }.max() ?? date).addingTimeInterval(duration)
        let basal = schedule.between(start: start, end: end).map {
            AbsoluteScheduleValue(startDate: $0.startDate, endDate: $0.endDate, value: $0.value)
        }
        let timeline = doses
            .map { $0.simpleDose(with: ExponentialInsulinModelPreset.rapidActingAdult) }
            .annotated(with: basal)
            .insulinOnBoardTimeline(
                longestEffectDuration: duration,
                from: date.addingTimeInterval(-.minutes(5)),
                to: date.addingTimeInterval(.minutes(5)))
        let before = timeline.last(where: { $0.startDate <= date })?.value
        let after = timeline.first(where: { $0.startDate >= date })?.value
        return max(before ?? 0, after ?? 0)
    }

    // MARK: Internals

    /// The pod's view of the running temp: MUTABLE, full programmed span, identity from
    /// raw only (no syncIdentifier on the dose — PumpEvent derives it from raw, exactly
    /// as OmniBLE's NewPumpEvent(UnfinalizedDose) does).
    private func mutableEvent(for temp: RunningTemp) -> NewPumpEvent {
        let dose = DoseEntry(type: .tempBasal, startDate: temp.start, endDate: temp.programmedEnd,
                             value: temp.rate, unit: .unitsPerHour, decisionId: nil, isMutable: true)
        return NewPumpEvent(date: temp.start, dose: dose, raw: temp.raw, title: "Temp Basal")
    }

    /// Finalization: same raw, span truncated to min(instant, programmed end) — a
    /// supersede truncates, a natural expiry keeps the full span — immutable. Also
    /// appends the hand-back-shaped record (syncIdentifier = hex(raw)).
    private func finalizeRunningTemp(at instant: Date) -> NewPumpEvent? {
        guard let temp = runningTemp else { return nil }
        let end = min(instant, temp.programmedEnd)
        let dose = DoseEntry(type: .tempBasal, startDate: temp.start, endDate: end,
                             value: temp.rate, unit: .unitsPerHour, decisionId: nil)
        foldedSession.append(LoanDoseRecord(kind: .tempBasal, startDate: temp.start, endDate: end,
                                            unitsPerHour: temp.rate,
                                            syncIdentifier: hexString(temp.raw)))
        runningTemp = nil
        return NewPumpEvent(date: temp.start, dose: dose, raw: temp.raw, title: "Temp Basal")
    }

    private func addToStore(_ events: [NewPumpEvent], lastReconciliation: Date, replacePendingEvents: Bool) {
        let exp = host.expectation(description: "addPumpEvents")
        // Defensive, same as WatchStoreEffectsTests: some DoseStore paths double-invoke
        // completions; not our bug and not worth failing over.
        exp.assertForOverFulfill = false
        Task {
            do {
                try await self.store.addPumpEvents(events, lastReconciliation: lastReconciliation,
                                                   replacePendingEvents: replacePendingEvents)
            } catch {
                XCTFail("addPumpEvents threw: \(error)")
            }
            exp.fulfill()
        }
        host.wait(for: [exp], timeout: 10)
    }
}

// MARK: - The tests

final class LoanBooksHarnessTests: XCTestCase {

    /// One isolated PersistenceController per driver — two DoseStores must never share a
    /// Core Data table (test 3 and 4 run a watch store and a phone store side by side).
    private var cacheDirs: [URL] = []

    /// This tearDown used to `removeItem(at:)` every directory, and
    /// that synchronous delete was the flake.
    ///
    /// The mechanism was already written down by LoanOverrideTests in this same file (see its
    /// `cacheStore` comment): `PersistenceController` brings its Core Data stack up
    /// ASYNCHRONOUSLY, so deleting the directory at test end is a "vnode unlinked while in
    /// use" race against a stack that may still be initializing — and the way that race
    /// presents is **a store that answers with zero rows**. That is the flake's exact symptom, and
    /// it is not confined to the test that loses the race: the noise lands on whichever suite
    /// is running in the same process when the unlink hits, which is why the false alarm moved
    /// between `testDuplicateBolusTwinDetection` and `testHandbackSeamCloses` on different
    /// runs, and why both passed in isolation.
    ///
    /// COST OF THE FLAKE, measured: it cost three gate runs and a real scare —
    /// the ship gate refused to archive a DOSING build over a phantom 1 U hand-back-seam
    /// discrepancy, on the one build where a real seam regression was most plausible. A gate
    /// that cannot tell a flake from a regression fails in both directions.
    ///
    /// THE FIX IS TO NOT DELETE. Each directory is a fresh UUID under the OS temp directory,
    /// so nothing collides across tests or runs, the contents are an empty-to-tiny SQLite
    /// store, and the OS reclaims temp itself. Racing an async stack to reclaim a few KB was
    /// never a good trade.
    override func tearDown() {
        cacheDirs = []
        super.tearDown()
    }

    private func makeDriver() -> LoanBooksDriver {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        cacheDirs.append(dir)
        let cache = PersistenceController(directoryURL: dir)
        // The store attaches asynchronously; handing it to a driver that writes immediately is
        // the zero-rows race. Block until it is up — see the note in WatchStoreEffectsTests.
        let ready = expectation(description: "persistent store attached")
        cache.onReady { error in
            XCTAssertNil(error, "store failed to come up")
            ready.fulfill()
        }
        wait(for: [ready], timeout: 10)

        // DoseStore.init is async now. `wait(for:)` pumps the run loop, so the task below makes
        // progress while this call blocks — the same bridge every other async step in this file
        // uses. Kept synchronous deliberately: making it async would push `async` onto all ~30
        // test methods for no gain in what they assert.
        var doseStore: DoseStore?
        let built = expectation(description: "dose store built")
        Task {
            doseStore = await DoseStore(
                healthKitSampleStore: nil,
                cacheStore: cache,
                longestEffectDuration: ExponentialInsulinModelPreset.rapidActingAdult.effectDuration,
                provenanceIdentifier: "LoanBooksHarnessTests")
            built.fulfill()
        }
        wait(for: [built], timeout: 10)
        guard let doseStore else {
            fatalError("dose store must build")
        }
        let delegate = LoanBooksDoseStoreDelegate(rate: fieldBasalRate)
        doseStore.delegate = delegate
        return LoanBooksDriver(host: self,
                               store: doseStore,
                               basalRate: fieldBasalRate,
                               storeDelegate: delegate)
    }

    // MARK: - 1. The inherited running temp — both spans, both books

    // MARK: - 2. The bolus twin pair

    /// FIELD (2026-07-29): the grant carried the same physical 0.95 U bolus TWICE — once
    /// as the phone journal's zero-length row (start == end; LoanReconciler writes
    /// endDate ?? startDate, so a journal event with nil endDate mints exactly this) and
    /// once as the pod-native row (start +1 s, 38 s delivery span, different raw). Two
    /// identities → every dedup layer blind → the seed booked BOTH → ~+0.95 U of phantom
    /// IOB the moment the watch took over.
    func testDuplicateBolusTwinDetection() {
        let now = Date()
        let b = now.addingTimeInterval(-.minutes(5))

        // The journal twin: zero-length, journal-minted identity (non-hex → raw = utf8).
        let journalTwin = LoanDoseRecord(kind: .bolus, startDate: b, endDate: b, amount: 0.95,
                                         syncIdentifier: "loanv2-6D0F2A44-8E4C-4B1B-9A57-2F30E1C0AB12")
        // The pod-native twin: same units, start +1 s, 38 s span, pod-native identity.
        let podStart = b.addingTimeInterval(1)
        let podTwinRaw = podRaw(type: "bolus", value: 0.95, start: podStart)
        let podTwin = LoanDoseRecord(kind: .bolus, startDate: podStart,
                                     endDate: podStart.addingTimeInterval(38), amount: 0.95,
                                     syncIdentifier: hexString(podTwinRaw))

        let driver = makeDriver()
        driver.seed([journalTwin, podTwin], at: now)

        // STORE: two raws → two rows → double books. This is the bug being pinned.
        XCTAssertEqual(driver.storeBolusCount(start: now.addingTimeInterval(-.hours(6)), end: now), 2,
                       "distinct identities blind every store dedup layer — both twins land as rows")
        let sample = driver.tick(at: now)
        XCTAssertEqual(sample, 1.90, accuracy: 0.1,
                       "the store books BOTH twins: ~2 × 0.95 U of IOB for one physical bolus (+0.95 U phantom, field 2026-07-29)")
    }

    // MARK: - 3. The hand-back seam

    /// FIELD (2026-07-29, 21:16 → 21:21): watch books at 21:16 held a 0.95 U bolus 31 min
    /// old plus the recent temp chain (high temp superseded by a zero temp — the decomp
    /// shape below reconstructs the DOSING-panel numbers). At 21:16 the watch enacted
    /// 0.00 U/hr × 30 min; at ~21:20:18 (+4.3 min) the hand-back cancelled/truncated it;
    /// at ~21:21 (+4.5 min) the phone evaluated its freshly-seeded books.
    ///
    /// The pin: the watch-at-21:16 vs phone-at-21:21 IOB seam must be FULLY explained by
    /// (decay over the window) + (the zero temp's withheld basal, 0.70 U/hr × 4.3 min ≈
    /// 0.050 U) — within 0.1 U, with NO forward terms. Canon: prediction trims at now;
    /// the only forward window in counted IOB is the model delay, and it cancels when the
    /// rows match on both sides.
    func testHandbackSeamCloses() {
        let now = Date()
        let t = now.addingTimeInterval(-.minutes(20))         // plays the field 21:16
        let handback = t.addingTimeInterval(.minutes(4.3))    // 21:20:18 — cancel/truncate
        let phoneEval = t.addingTimeInterval(.minutes(4.5))   // 21:21 — first phone sample

        let watch = makeDriver()
        // Build the 21:16 books via the session's own enacts. 0.95 U at t−31 min is the
        // field number; the temp chain (2.80 superseded by 0.00, expiring t−4 min) is the
        // field decomp's recent high-then-zero shape against the 0.70 schedule.
        watch.enactBolus(units: 0.95, at: t.addingTimeInterval(-.minutes(31)))
        watch.enactTemp(rate: 2.80, at: t.addingTimeInterval(-.minutes(26)), duration: .minutes(30))
        watch.enactTemp(rate: 0.00, at: t.addingTimeInterval(-.minutes(16)), duration: .minutes(12))

        // PRE-ENACT samples — replay order is load-bearing: both are pure reads taken
        // BEFORE the 21:16 enact lands, so preT is the watch's true pre-enact IOB and
        // preT45 is pure decay of the same books (no zero-temp term in either).
        let preT = watch.tick(at: t)
        let preT45 = watch.tick(at: phoneEval)

        // 21:16: enact 0.00 × 30 min. 21:20:18: hand back — the pod finalizes the temp
        // truncated [t, t+4.3], same raw, immutable.
        watch.enactTemp(rate: 0.00, at: t, duration: .minutes(30))
        let finalRecords = watch.handbackFold(at: handback)

        // Phone side: a FRESH store seeded from the truncated final records (the real
        // grant split again — hex syncIds decode back to the very same pod raws).
        let phone = makeDriver()
        phone.seed(finalRecords, at: phoneEval, epoch: 2)
        let phoneT45 = phone.tick(at: phoneEval)
        let watchT45 = watch.tick(at: phoneEval)

        // The explainable seam: decay + the zero temp's actually-withheld basal.
        let decay = preT - preT45
        let zeroTempWithheld = fieldBasalRate * (4.3 / 60.0)   // ≈ 0.050 U never delivered
        let seam = preT - phoneT45
        XCTAssertEqual(seam, decay + zeroTempWithheld, accuracy: 0.1,
                       "the 21:16→21:21 seam must be decay + zero-temp withholding and NOTHING else — any residual is booked insulin leaking across the hand-back")

        // And when the rows match, the seam closes exactly: same records, same instant,
        // both sides all-immutable and past-ended → the model-delay window cancels.
        XCTAssertEqual(watchT45, phoneT45, accuracy: 0.05,
                       "identical final rows on both sides must produce identical IOB — the seam has no store-of-origin term")
    }

    // MARK: - 4. Re-grant round trip

    /// The cross-epoch fidelity pin (the 2026-07-29 session cycled multiple epochs): a
    /// full session — seed → three temp enacts (supersede chain) + a bolus → hand-back
    /// fold (temps truncated at supersede, same raws) → RE-SEED a fresh store
    /// from the folded records — must conserve IOB. Every takeover re-derives the books
    /// from records, so any per-cycle leak compounds across epochs (the class of bug
    /// behind the 7.40 U takeover inflation of 2026-07-22, re-pinned here through the
    /// current fold + split path).
    ///
    /// Geometry note: the last temp's programmed span ends exactly at the hand-back
    /// instant (a loop-cycle hand-back at temp expiry — a real session shape), so the fold
    /// changes no row's span and the comparison at H carries no forward-delay asymmetry.
    func testReGrantRoundTripPreservesBooks() {
        let now = Date()
        let s = now.addingTimeInterval(-.minutes(100))    // epoch-1 takeover
        let h = s.addingTimeInterval(.minutes(50))        // hand-back = temp3's natural expiry

        // Grant history: phone-side rows under the identity contract (syncId = hex(raw)).
        let histTempStart = s.addingTimeInterval(-.minutes(45))
        let histBolusStart = s.addingTimeInterval(-.minutes(40))
        let history = [
            LoanDoseRecord(kind: .tempBasal, startDate: histTempStart,
                           endDate: s.addingTimeInterval(-.minutes(15)), unitsPerHour: 1.40,
                           syncIdentifier: hexString(podRaw(type: "tempBasal", value: 1.40, start: histTempStart))),
            LoanDoseRecord(kind: .bolus, startDate: histBolusStart,
                           endDate: histBolusStart.addingTimeInterval(38), amount: 0.80,
                           syncIdentifier: hexString(podRaw(type: "bolus", value: 0.80, start: histBolusStart))),
        ]

        let epoch1 = makeDriver()
        epoch1.seed(history, at: s, epoch: 1)
        epoch1.enactTemp(rate: 2.80, at: s, duration: .minutes(30))                              // → truncated [s, s+10]
        epoch1.enactTemp(rate: 0.00, at: s.addingTimeInterval(.minutes(10)), duration: .minutes(30)) // → truncated [s+10, s+20]
        epoch1.enactBolus(units: 0.95, at: s.addingTimeInterval(.minutes(15)))
        epoch1.enactTemp(rate: 1.05, at: s.addingTimeInterval(.minutes(20)), duration: .minutes(30)) // runs to natural expiry at h

        let nextGrantRecords = epoch1.handbackFold(at: h)
        let store1 = epoch1.tick(at: h)

        // Epoch 2: a fresh store, seeded from the folded records — the real split runs again,
        // hex syncIds decode back to the same pod-native raws.
        let epoch2 = makeDriver()
        epoch2.seed(nextGrantRecords, at: h, epoch: 2)
        let sample2 = epoch2.tick(at: h)

        XCTAssertGreaterThan(store1, 0.3, "sanity: the session book carries insulin at hand-back")
        XCTAssertEqual(sample2, store1, accuracy: 0.05,
                       "cross-epoch fidelity: IOB is conserved through fold → re-grant → reseed")
    }

    // MARK: - 5. The bolus-crash queue invariant (shape)

    /// FIELD: the pod's BLE link is released between doses, so a bolus must reclaim it
    /// first, and that reclaim completion runs ON the loan controller's serial queue
    /// (reclaimPodForDose wraps every path in queue.async, including the
    /// still-connected short-circuit), and deliverBolus → loanWillEnactBolus → mintIntent
    /// does queue.sync onto that SAME queue — a guaranteed libdispatch trap BEFORE
    /// enactBolus was ever issued (apparent success at the crown, crash 0-40 s later, NO
    /// insulin delivered). The fix (WatchLoopManager.enactManualBolus, ~:1515-1545): hop
    /// to the dosing queue via .async before delivering — and .async is load-bearing,
    /// because when the link is already held the reclaim closure completes SYNCHRONOUSLY
    /// on the dosing queue itself, where a .sync hop would deadlock on itself.
    ///
    /// That code is watch-target-only, so this pins the SHAPE with real DispatchQueues:
    /// both delivery legs of the fixed topology must complete. (No trap-reproduction
    /// test on purpose — the broken shape deadlocks/traps and would hang CI; the
    /// invariant that must never regress is that the fixed shape completes.)
    func testBolusDeliveryQueueShapeDoesNotTrap() {
        let loanQueue = DispatchQueue(label: "test.loan-controller")   // PodLoanWatchController's serial queue
        let dosingQueue = DispatchQueue(label: "test.dataAccessQueue") // WatchLoopManager.dataAccessQueue

        // The journal mint, as loanWillEnactBolus does it: queue.sync onto the LOAN queue.
        // Safe if and only if the caller is NOT already on the loan queue — the invariant.
        func mintJournalIntent() -> Bool {
            var minted = false
            loanQueue.sync { minted = true }
            return minted
        }

        // Leg 1 — the field-crash path, fixed: the reclaim completion arrives ON the loan
        // queue; delivery hops to the dosing queue via .async; the mint then syncs back
        // onto the (now free) loan queue and the pod command follows.
        let reclaimLeg = expectation(description: "reclaim-path delivery completes")
        loanQueue.async {
            dosingQueue.async {
                XCTAssertTrue(mintJournalIntent(),
                              "mint must complete before the pod command — the bug trapped here")
                reclaimLeg.fulfill()   // stands in for pumpManager.enactBolus reaching the pod
            }
        }

        // Leg 2 — the link-already-held short-circuit: the reclaim closure completes SYNCHRONOUSLY
        // on the dosing queue, so the SAME hop line re-dispatches onto the queue it is
        // already on. .async makes that legal; a .sync hop would self-deadlock (the
        // adversarial-review edge documented at the fix site).
        let shortCircuitLeg = expectation(description: "short-circuit delivery completes")
        dosingQueue.async {
            dosingQueue.async {
                XCTAssertTrue(mintJournalIntent(),
                              "the mint must also clear when the hop was a same-queue re-dispatch")
                shortCircuitLeg.fulfill()
            }
        }

        wait(for: [reclaimLeg, shortCircuitLeg], timeout: 5)
    }

    // MARK: - 6. The bolus-crash fix — books land after the hop

    /// The books-level pin: the crash fired BEFORE the pod command, so the field signature of
    /// the FIX is a bolus that (a) survives the queue topology and (b) lands in BOTH books
    /// coherently. This replays the fixed shape, then books the delivered bolus the way the
    /// session does — the pod-style report batch — and pins the IOB (field DOSING panel:
    /// 2.33 after the first post-fix manual bolus).
    func testBolusLandsInTheBookAfterQueueHop() {
        let now = Date()
        let bolusStart = now.addingTimeInterval(-.minutes(5))  // enacted 5 min ago — inside
                                                               // the 10-min model delay, so
                                                               // IOB is the full programmed
                                                               // units in both books

        // The delivery gate: same fixed topology as test 5, one leg. The bolus is booked
        // only after the hopped delivery closure has completed and the mint succeeded —
        // the ordering the fix restores (mint, THEN pod command, THEN books).
        let loanQueue = DispatchQueue(label: "test.loan-controller-books")
        let dosingQueue = DispatchQueue(label: "test.dataAccessQueue-books")
        var mintedBeforeCommand = false
        let delivered = expectation(description: "hopped delivery completes")
        loanQueue.async {
            dosingQueue.async {
                loanQueue.sync { mintedBeforeCommand = true }  // the journal mint
                delivered.fulfill()                            // the pod command issues
            }
        }
        wait(for: [delivered], timeout: 5)
        XCTAssertTrue(mintedBeforeCommand, "no delivery without a completed mint")

        // The book: a pod-accepted bolus, exactly as the session records it.
        let driver = makeDriver()
        driver.enactBolus(units: 2.33, at: bolusStart)

        let sample = driver.tick(at: now)
        XCTAssertEqual(sample, 2.33, accuracy: 0.1,
                       "the store must carry the full delivered bolus (field 20:45: 2.33)")
    }

    // MARK: - Carb-side helpers (tests 7-8)

    /// One isolated CarbStore per side (watch/phone must never share a Core Data table).
    ///
    /// The store no longer holds schedules, absorption times or an override history — it is a row
    /// store, and every consumer supplies the schedules at read time. That is why `cob` and
    /// `carbEffects` below take them as arguments now: the same change the DoseStore made, and the
    /// reason both books in this file can be compared on rows alone.
    private func makeCarbStore() -> CarbStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        cacheDirs.append(dir)
        return CarbStore(
            healthKitSampleStore: nil,
            cacheStore: PersistenceController(directoryURL: dir),
            cacheLength: .hours(24),
            provenanceIdentifier: "LoanBooksHarnessTests")
    }

    /// The store is the idempotency point for DELIVERED carbs. Real CarbStore, real
    /// Core Data: two deliveries of one identity make one row; a late replay loses to a
    /// local edit. This is the layer that makes double-booking structurally impossible rather than
    /// merely guarded against — the check and the insert run in one operation on the
    /// store's own queue, where no caller-side sequencing can be bypassed.
    func testR36DeliveredCarbIdentityInsertIfAbsent() {
        let store = makeCarbStore()
        let now = Date()
        let entry = NewCarbEntry(quantity: LoopQuantity(unit: .gram, doubleValue: 10),
                                 startDate: now.addingTimeInterval(-1800),
                                 foodType: nil,
                                 absorptionTime: .hours(3))
        let wireID = UUID().uuidString   // the watch journal event UUID, as it travels

        var first: StoredCarbEntry?
        let e1 = expectation(description: "first delivery")
        store.addCarbEntry(entry, syncIdentifier: wireID) { result in
            if case .success(let stored) = result { first = stored }
            e1.fulfill()
        }
        wait(for: [e1], timeout: 10)
        XCTAssertEqual(first?.syncIdentifier, wireID, "the wire identity IS the stored identity — no re-mint at the last inch")

        let e2 = expectation(description: "redelivery")
        var second: StoredCarbEntry?
        store.addCarbEntry(entry, syncIdentifier: wireID) { result in
            if case .success(let stored) = result { second = stored }
            e2.fulfill()
        }
        wait(for: [e2], timeout: 10)
        XCTAssertEqual(second?.syncIdentifier, wireID)

        var count = -1
        let e3 = expectation(description: "read back")
        store.getCarbEntries(start: now.addingTimeInterval(-.hours(4))) { result in
            if case .success(let list) = result { count = list.count }
            e3.fulfill()
        }
        wait(for: [e3], timeout: 10)
        XCTAssertEqual(count, 1, "two deliveries, ONE row — the store dedups, not the caller")

        // INSERT-IF-ABSENT, never upsert: a local edit (same identity, bumped version) must
        // beat a late replay of the original. Upsert semantics would clobber the user's edit.
        let edited = NewCarbEntry(quantity: LoopQuantity(unit: .gram, doubleValue: 25),
                                  startDate: entry.startDate, foodType: nil,
                                  absorptionTime: entry.absorptionTime)
        let e4 = expectation(description: "local edit")
        store.replaceCarbEntry(second!, withEntry: edited) { _ in e4.fulfill() }
        wait(for: [e4], timeout: 10)

        var afterReplay: StoredCarbEntry?
        let e5 = expectation(description: "late replay of the ORIGINAL")
        store.addCarbEntry(entry, syncIdentifier: wireID) { result in
            if case .success(let stored) = result { afterReplay = stored }
            e5.fulfill()
        }
        wait(for: [e5], timeout: 10)
        XCTAssertEqual(afterReplay?.quantity.doubleValue(for: .gram) ?? 0, 25, accuracy: 0.01,
                       "the replay returns the EDITED entry untouched — replays never win against later human intent")
    }

    /// The carb fold's data shape, both directions: the watch's loan-time entry AND the
    /// phone-side fold write are the SAME NewCarbEntry surface — quantity + startDate +
    /// absorptionTime, foodType nil, NO carried identity. LoanReconciler.reconcile mints
    /// exactly this (LoanReconciler.swift:169-176) and the phone lands it through
    /// carbStore.addCarbEntry (WatchDataManager.swift:140-145), which mints a FRESH
    /// native syncIdentifier + the phone's own provenance (CarbStore.swift:483-497).
    /// So carb identity is NOT preserved across the fold (unlike insulin's hex(raw)
    /// contract) — round-trip parity rides ONLY on the three absorption-relevant fields,
    /// which is precisely what tests 7-8 exercise.
    private func addCarb(_ store: CarbStore, grams: Double, at start: Date, absorptionTime: TimeInterval) {
        let exp = expectation(description: "addCarbEntry")
        let entry = NewCarbEntry(quantity: LoopQuantity(unit: .gram, doubleValue: grams),
                                 startDate: start, foodType: nil, absorptionTime: absorptionTime)
        store.addCarbEntry(entry) { result in
            if case .failure(let error) = result {
                XCTFail("addCarbEntry failed: \(error)")
            }
            exp.fulfill()
        }
        wait(for: [exp], timeout: 10)
    }

    /// Entries out of the store, which is all the store does now.
    private func carbEntries(_ store: CarbStore, start: Date, end: Date) -> [StoredCarbEntry] {
        var out: [StoredCarbEntry] = []
        let exp = expectation(description: "getCarbEntries")
        Task {
            out = (try? await store.getCarbEntries(start: start, end: end)) ?? []
            exp.fulfill()
        }
        wait(for: [exp], timeout: 10)
        return out
    }

    /// The carb status the two carb reads below share, built the way `LoopDataManager.fetchData`
    /// builds it — entries mapped against the counteraction velocities with the carb ratio and
    /// sensitivity timelines supplied at read time. `CarbStore.carbsOnBoard` and
    /// `getGlucoseEffects` are gone; this is where that math lives now.
    private func carbStatus(_ store: CarbStore, start: Date, end: Date,
                            velocities: [GlucoseEffectVelocity]) -> [CarbStatus<StoredCarbEntry>] {
        let entries = carbEntries(store, start: start, end: end)
        guard !entries.isEmpty else { return [] }
        let spanStart = min(start, entries.map { $0.startDate }.min() ?? start)
        let spanEnd = max(end, entries.map { $0.endDate }.max() ?? end)
            .addingTimeInterval(CarbMath.maximumAbsorptionTimeInterval)
        return entries.map(
            to: velocities,
            carbRatio: fieldCarbRatio.between(start: spanStart, end: spanEnd),
            insulinSensitivity: fieldISF.quantitiesBetween(start: spanStart, end: spanEnd))
    }

    private func cob(_ store: CarbStore, at date: Date, velocities: [GlucoseEffectVelocity]?) -> Double {
        let status = carbStatus(store,
                                start: date.addingTimeInterval(-CarbMath.maximumAbsorptionTimeInterval),
                                end: date,
                                velocities: velocities ?? [])
        guard !status.isEmpty else { return 0 }
        return status.dynamicCarbsOnBoard(at: date, absorptionModel: PiecewiseLinearAbsorption())
    }

    private func carbEffects(_ store: CarbStore, start: Date, end: Date, velocities: [GlucoseEffectVelocity]) -> [GlucoseEffect] {
        // ENTRIES are fetched from one absorption window BEFORE `start`; EFFECTS are computed
        // over [start, end]. Those are two different questions and the harness used to ask the
        // first one with the second one's window.
        //
        // The parity test entered its meal 90 min before hand-back, so fetching entries in
        // [handback, handback + 1h] found nothing and `carbStatus`'s empty guard returned no
        // effects — for BOTH stores, which is why only the `isEmpty` assertion fired and the
        // count-equality on the next line passed on 0 == 0. The test read as "the watch produces
        // no carb-effect curve" when neither side produced one and the watch was fine.
        //
        // Mirrors production: fetchAlgorithmInput uses
        // `carbsStart = baseTime - CarbMath.maximumAbsorptionTimeInterval` for exactly this
        // reason — a meal still absorbing is still an input.
        let entriesStart = start.addingTimeInterval(-CarbMath.maximumAbsorptionTimeInterval)
        let status = carbStatus(store, start: entriesStart, end: end, velocities: velocities)
        guard !status.isEmpty else { return [] }
        let spanEnd = end.addingTimeInterval(InsulinMath.defaultInsulinActivityDuration)
        return status.dynamicGlucoseEffects(
            from: start,
            to: spanEnd,
            // The schedules must cover the ENTRIES, not just the effect window: a timeline asked
            // from `start` begins at that day's schedule boundary, so a meal dated before
            // midnight had no ratio or sensitivity and tripped LoopKit's precondition — this
            // suite crashed its host between 00:00 and 01:30 (2026-09-20).
            carbRatios: fieldCarbRatio.between(start: entriesStart, end: spanEnd),
            insulinSensitivities: fieldISF.quantitiesBetween(start: entriesStart, end: spanEnd),
            absorptionModel: PiecewiseLinearAbsorption())
    }

    /// The sinusoidal session BG: 140 + 40·sin(2π(t−45 min)/180 min) sampled every 5 min
    /// over [0, 90] — 100 → 140 → 180 mg/dL, with the STEEP half of the wave in the middle
    /// and late window (the field evening-meal shape: absorption running ahead of the
    /// model exactly when the loan owns the glucose).
    private func sinusoidSamples(from start: Date, count: Int = 19) -> [SimGlucoseSample] {
        return (0..<count).map { i in
            let t = TimeInterval(i) * .minutes(5)
            let bg = 140.0 + 40.0 * sin(2.0 * Double.pi * (t - .minutes(45)) / .minutes(180))
            return SimGlucoseSample(startDate: start.addingTimeInterval(t),
                                    quantity: LoopQuantity(unit: .milligramsPerDeciliter, doubleValue: bg))
        }
    }

    /// ICE the STOCK way — this is not a replication but the real implementation: the
    /// phone's update cycle calls glucoseStore.getCounteractionEffects (LoopDataManager
    /// .swift:1071) → GlucoseStore.counteractionEffects(for:to:) (GlucoseStore.swift:756)
    /// → the pure collection extension counteractionEffects(to:) (GlucoseMath.swift:161),
    /// which computes velocity = (glucoseChange − insulinEffectChange) / Δt per sample
    /// pair. The tests call that same extension directly. A FLAT (all-zero) insulin-effect
    /// series makes the ICE exactly the glucose velocity — the known-input case.
    private func stockICE(samples: [SimGlucoseSample], flatInsulinEffectsFrom start: Date, to end: Date) -> [GlucoseEffectVelocity] {
        var effects: [GlucoseEffect] = []
        var date = start
        while date <= end {
            effects.append(GlucoseEffect(startDate: date,
                                         quantity: LoopQuantity(unit: .milligramsPerDeciliter, doubleValue: 0)))
            date = date.addingTimeInterval(.minutes(5))
        }
        return samples.counteractionEffects(to: effects)
    }

    // MARK: - 7. Carb round trip — dynamic absorption parity across the fold

    /// Jeremy's round-trip spec: (1) the watch CarbStore takes a 20 g / 3 h entry
    /// mid-session; (2) a sinusoidal BG series + a flat insulin-effect series produce the
    /// ICE velocities the stock way; (3) watch COB and carb effects are read at the
    /// hand-back instant with those velocities; (4) a phone store seeded from the FOLDED
    /// entry (LoanReconciler's shape — same quantity/startDate/absorptionTime, fresh
    /// native identity) and fed the SAME ICE series must agree: COB within 0.5 g, effect
    /// curve within a few mg/dL. When the phone's glucose picture is complete, the carb
    /// seam closes — the null half of the test-8 relay-gap pin.
    func testCarbRoundTripDynamicAbsorptionParity() {
        let now = Date()
        let handback = now
        let meal = now.addingTimeInterval(-.minutes(90))   // entered mid-session

        // (1) The watch-side entry.
        let watchCarbs = makeCarbStore()
        addCarb(watchCarbs, grams: 20, at: meal, absorptionTime: .hours(3))

        // (2) Stock ICE from the sinusoid against flat insulin effects.
        let samples = sinusoidSamples(from: meal)
        let velocities = stockICE(samples: samples,
                                  flatInsulinEffectsFrom: meal.addingTimeInterval(-.minutes(5)),
                                  to: handback.addingTimeInterval(.minutes(5)))
        XCTAssertEqual(velocities.count, 18, "19 samples on a 5-min grid → 18 velocity spans")

        // (3) Watch COB at hand-back. The BG rose 80 mg/dL over the window → at CSF
        // 5 mg/dL/g the ICE credits ~16 g absorbed → COB ~4 g. The static (no-velocity)
        // read stays near ~9 g — assert the spread so the test proves the velocities are
        // actually consumed (dynamic absorption), not silently ignored.
        let watchCOB = cob(watchCarbs, at: handback, velocities: velocities)
        let watchStaticCOB = cob(watchCarbs, at: handback, velocities: nil)
        XCTAssertGreaterThan(watchCOB, 1.0, "sanity: carbs still on board at hand-back (0 would make parity trivial)")
        XCTAssertLessThan(watchCOB, watchStaticCOB - 2.0,
                          "dynamic COB must sit well below static COB here — proof the ICE series drove absorption")

        // (4) The phone store, seeded in the fold's shape, same ICE series.
        let phoneCarbs = makeCarbStore()
        addCarb(phoneCarbs, grams: 20, at: meal, absorptionTime: .hours(3))
        let phoneCOB = cob(phoneCarbs, at: handback, velocities: velocities)
        XCTAssertEqual(phoneCOB, watchCOB, accuracy: 0.5,
                       "same entry fields, same ICE → same dynamic COB; the fold carries everything the math reads")

        // Carb-effect curve parity over the prediction hour after hand-back.
        let watchFx = carbEffects(watchCarbs, start: handback, end: handback.addingTimeInterval(.hours(1)), velocities: velocities)
        let phoneFx = carbEffects(phoneCarbs, start: handback, end: handback.addingTimeInterval(.hours(1)), velocities: velocities)
        XCTAssertFalse(watchFx.isEmpty, "the watch must produce a carb-effect curve")
        XCTAssertEqual(watchFx.count, phoneFx.count, "same entries, same window → same effect grid")
        for i in stride(from: 0, to: min(watchFx.count, phoneFx.count), by: 3) {
            XCTAssertEqual(watchFx[i].startDate, phoneFx[i].startDate, "effect grids must align")
            XCTAssertEqual(watchFx[i].quantity.doubleValue(for: .milligramsPerDeciliter),
                           phoneFx[i].quantity.doubleValue(for: .milligramsPerDeciliter),
                           accuracy: 2.0,
                           "carb-effect curve must match across the fold at sample \(i)")
        }
    }

    // MARK: - 8. The relay gap — truncated phone ICE overstates COB

    /// FIELD (2026-07-29 21:21, the +1 g COB seam): right after hand-back the watch read
    /// ~6 g COB while the phone read ~7 g from the same carb — the 6g-vs-7g signature.
    /// Hypothesis: the phone's glucose history is missing (part of) the loan window (the
    /// relay gap), so its ICE series is TRUNCATED where the meal actually absorbed.
    ///
    /// The mechanism, from the stock math (CarbMath.swift, CarbStatusBuilder): absorption
    /// is only CREDITED where velocities exist — `lastEffectDate = velocities.last.endDate`
    /// freezes observation there, and past it COB extrapolates from the observed-so-far
    /// percent along the model curve. Less observed glucose while BG runs ahead of the
    /// model → less credited absorption → MORE COB → a HIGHER eventual prediction on the
    /// phone. This test pins that direction: it is the diagnostic for whether phone-side
    /// glucose relay completeness matters (if the field seam were store-shape instead,
    /// test 7's parity would fail, not this).
    func testTruncatedPhoneICEOverstatesCOB() {
        let now = Date()
        let handback = now
        let meal = now.addingTimeInterval(-.minutes(90))
        let relayCutoff = meal.addingTimeInterval(.minutes(30))   // last glucose the phone got

        let watchCarbs = makeCarbStore()
        addCarb(watchCarbs, grams: 20, at: meal, absorptionTime: .hours(3))
        let phoneCarbs = makeCarbStore()
        addCarb(phoneCarbs, grams: 20, at: meal, absorptionTime: .hours(3))

        let samples = sinusoidSamples(from: meal)
        let velocities = stockICE(samples: samples,
                                  flatInsulinEffectsFrom: meal.addingTimeInterval(-.minutes(5)),
                                  to: handback.addingTimeInterval(.minutes(5)))
        // The relay gap: the phone's ICE series ends where its glucose history ends.
        let phoneVelocities = velocities.filter { $0.endDate <= relayCutoff }
        XCTAssertEqual(phoneVelocities.count, 6, "30 min of relayed glucose → 6 velocity spans")

        let watchCOB = cob(watchCarbs, at: handback, velocities: velocities)
        let phoneTruncatedCOB = cob(phoneCarbs, at: handback, velocities: phoneVelocities)
        // Control: the same phone store with the FULL series matches the watch — the
        // divergence below is the ICE series, not the store or the folded entry.
        let phoneFullCOB = cob(phoneCarbs, at: handback, velocities: velocities)
        XCTAssertEqual(phoneFullCOB, watchCOB, accuracy: 0.5,
                       "full ICE on the phone closes the seam — isolates the gap to the velocity series")

        // THE PIN — divergence direction: phone sees less absorption → MORE COB.
        // (Field magnitude was +1 g on a shallow rise; this steeper fixture opens a wider
        // gap, so assert the direction with a ≥1 g floor rather than a point value.)
        XCTAssertGreaterThan(phoneTruncatedCOB, watchCOB,
                             "relay-gap direction: the truncated-ICE phone must read HIGHER COB (6g-vs-7g, 2026-07-29 21:21)")
        XCTAssertGreaterThan(phoneTruncatedCOB - watchCOB, 1.0,
                             "the gap must be material — at least the field's +1 g seam")
        XCTAssertLessThanOrEqual(phoneTruncatedCOB, 20.0 + 0.01,
                                 "sanity: COB can never exceed the entry")
    }

    // MARK: - 9. e44 — the store's basal boundary vs a late journal commit

    /// FIELD (loan e44, 2026-08-13): a force-reclaim salvaged the staged tail, the phone resumed
    /// and wrote its own basal records, and the watch came back minutes later with the whole
    /// journal. Every dose was written and only the BOLUS reached the books; the loan came out
    /// 0.25 U light, which is the anti-conservative direction.
    ///
    /// THE MECHANISM, in the real store: `addPumpEvents` saves PumpEvent rows unconditionally, but
    /// syncs them into the InsulinDeliveryStore starting at `lastImmutableBasalEndDate` and drops
    /// anything basal-shaped that begins before it — `|| $0.type == .bolus` is the only escape
    /// (DoseStore.swift:1174). That is why the field signature is a surviving bolus beside
    /// vanished temps. The salvage's clamped record and the phone's own resumed record had walked
    /// the boundary past the whole loan window.
    ///
    /// Two errors, opposite signs, one cause. The temp the phone never held (t3) cannot land at
    /// all; the temp it DID hold (t2) is stuck at the salvage's estimate, which clamped a 30-min
    /// programmed window to the reclaim instant rather than to the successor that actually
    /// superseded it. The backfill upsert fixes both, because both are named by the same store
    /// identity the pump-event path used. Everything before the backfill call is the sabotage
    /// form: delete that one line and the e44 signature is what remains.
    func testForceReclaimSalvageThenLateJournalCommitLandsTempsInTheBooks() {
        let now = Date()
        let loanStart = now.addingTimeInterval(-.minutes(40))
        let t1Start = loanStart.addingTimeInterval(.minutes(2))     // 0.05 U/hr, 30 min programmed
        let t2Start = loanStart.addingTimeInterval(.minutes(8))     // 2.35 U/hr, 30 min programmed
        let bolusAt = loanStart.addingTimeInterval(.minutes(10))    // 0.60 U — the dose that survived
        let t3Start = loanStart.addingTimeInterval(.minutes(14))    // 1.15 U/hr, 30 min programmed
        let reclaim = loanStart.addingTimeInterval(.minutes(26))    // force-reclaim / salvage instant
        let phoneResumedThrough = reclaim.addingTimeInterval(.minutes(1))
        let handedBack = reclaim.addingTimeInterval(.minutes(2))    // the watch's own release stamp

        // Journal identities, exactly LoanReconciler's shape. The store rewrites these to hex(raw)
        // on the pump-event path, which is why the backfill has to carry the hex form.
        let syncT1 = "loanv2-\(UUID().uuidString)"
        let syncT2 = "loanv2-\(UUID().uuidString)"
        let syncBolus = "loanv2-\(UUID().uuidString)"
        let syncT3 = "loanv2-\(UUID().uuidString)"

        func tempDose(_ rate: Double, _ start: Date, _ end: Date) -> DoseEntry {
            DoseEntry(type: .tempBasal, startDate: start, endDate: end, value: rate, unit: .unitsPerHour, decisionId: nil)
        }
        func bolusDose(_ units: Double, _ start: Date) -> DoseEntry {
            DoseEntry(type: .bolus, startDate: start, endDate: start.addingTimeInterval(38),
                      value: units, unit: .units, decisionId: nil)
        }
        /// The controller's `newPumpEvents`: identity in `raw`, discarded from the dose.
        func loanEvent(_ dose: DoseEntry, _ sync: String) -> NewPumpEvent {
            NewPumpEvent(date: dose.startDate, dose: dose, raw: Data(sync.utf8),
                         title: dose.type == .bolus ? "Bolus" : "Temp Basal")
        }
        /// The controller's `storeIdentifiedDoses`: same dose, hex identity.
        func upsert(_ dose: DoseEntry, _ sync: String) -> DoseEntry {
            DoseEntry(type: dose.type, startDate: dose.startDate, endDate: dose.endDate,
                      value: dose.unit == .unitsPerHour ? dose.unitsPerHour : dose.programmedUnits,
                      unit: dose.unit, decisionId: nil, syncIdentifier: hexString(Data(sync.utf8)))
        }

        let driver = makeDriver()

        // 1. Pre-loan: the phone's own basal, immutable, ending as the loan starts. This is what
        //    puts the boundary at `loanStart` — a boundary behind the loan, where it is harmless.
        let preLoanStart = loanStart.addingTimeInterval(-.minutes(30))
        driver.storeEvents([NewPumpEvent(date: preLoanStart,
                                         dose: tempDose(fieldBasalRate, preLoanStart, loanStart),
                                         raw: podRaw(type: "tempBasal", value: fieldBasalRate, start: preLoanStart),
                                         title: "Temp Basal")],
                           lastReconciliation: loanStart)

        // 2. The force-reclaim salvage: the two events the watch had streamed before it went
        //    quiet, reconciled with loanEnd = the reclaim instant (isFinalHandback defaults true,
        //    so both are clamped there). t2's real successor is still on the dead wrist, so its
        //    clamp is an ESTIMATE that runs 12 min past the truth.
        driver.storeEvents([loanEvent(tempDose(0.05, t1Start, reclaim), syncT1),
                            loanEvent(tempDose(2.35, t2Start, reclaim), syncT2)],
                           lastReconciliation: reclaim)

        // 3. The phone resumes and writes its own basal. The boundary is now past every loan temp.
        driver.storeEvents([NewPumpEvent(date: reclaim,
                                         dose: tempDose(fieldBasalRate, reclaim, phoneResumedThrough),
                                         raw: podRaw(type: "tempBasal", value: fieldBasalRate, start: reclaim),
                                         title: "Temp Basal")],
                           lastReconciliation: phoneResumedThrough)

        // 4. The watch returns. The commit writes the WHOLE loan through the pump-event path,
        //    every rate record clamped to the journal's own release stamp.
        driver.storeEvents([loanEvent(tempDose(0.05, t1Start, handedBack), syncT1),
                            loanEvent(tempDose(2.35, t2Start, handedBack), syncT2),
                            loanEvent(bolusDose(0.60, bolusAt), syncBolus),
                            loanEvent(tempDose(1.15, t3Start, handedBack), syncT3)],
                           lastReconciliation: handedBack)

        let hexT1 = hexString(Data(syncT1.utf8))
        let hexT2 = hexString(Data(syncT2.utf8))
        let hexBolus = hexString(Data(syncBolus.utf8))
        let hexT3 = hexString(Data(syncT3.utf8))
        // Prefix match, not equality: `annotated(with:)` suffixes " i/n" onto the syncIdentifier
        // when a dose straddles a basal-schedule boundary, which a run near midnight would do.
        func rows(_ hex: String, _ list: [DoseEntry]) -> [DoseEntry] {
            list.filter { $0.syncIdentifier?.hasPrefix(hex) == true }
        }
        /// Seconds, not Dates: a Core Data round trip is a double, so compare with a tolerance
        /// rather than betting on bit-exact equality. Missing rows read NaN and fail.
        func endOf(_ hex: String, _ list: [DoseEntry]) -> TimeInterval {
            rows(hex, list).map(\.endDate).max()?.timeIntervalSinceReferenceDate ?? .nan
        }
        func units(_ list: [DoseEntry]) -> Double {
            rows(hexT1, list).reduce(0) { $0 + $1.programmedUnits }
                + rows(hexT2, list).reduce(0) { $0 + $1.programmedUnits }
                + rows(hexBolus, list).reduce(0) { $0 + $1.programmedUnits }
                + rows(hexT3, list).reduce(0) { $0 + $1.programmedUnits }
        }

        // 5. THE e44 SIGNATURE, from the real store.
        let broken = driver.normalizedDoses(start: loanStart, end: handedBack)
        XCTAssertFalse(rows(hexBolus, broken).isEmpty, "the bolus escapes the boundary filter — DoseStore.swift:1174")
        XCTAssertTrue(rows(hexT3, broken).isEmpty,
                      "the temp the phone never held cannot land: every basal-shaped dose starting before the boundary is dropped")
        XCTAssertEqual(endOf(hexT2, broken), reclaim.timeIntervalSinceReferenceDate, accuracy: 1,
                       "and the salvage's estimate still stands — the real records could not correct it either")

        // 6. The backfill: the whole loan restated under its store identity, overlaps truncated
        //    the way `DoseStore` truncates them on the path this write bypasses.
        driver.backfill([upsert(tempDose(0.05, t1Start, t2Start), syncT1),
                         upsert(tempDose(2.35, t2Start, t3Start), syncT2),
                         upsert(bolusDose(0.60, bolusAt), syncBolus),
                         upsert(tempDose(1.15, t3Start, handedBack), syncT3)])

        let fixed = driver.normalizedDoses(start: loanStart, end: handedBack)
        XCTAssertFalse(rows(hexT3, fixed).isEmpty, "THE FIX: the missing temp is in the books")
        XCTAssertEqual(endOf(hexT3, fixed), handedBack.timeIntervalSinceReferenceDate, accuracy: 1,
                       "and it ends where the journal says the loan ended")
        XCTAssertEqual(endOf(hexT2, fixed), t3Start.timeIntervalSinceReferenceDate, accuracy: 1,
                       "the salvage extension is TRIMMED to the successor the journal brought — real records replace estimates, as an upsert")
        XCTAssertEqual(endOf(hexT1, fixed), t2Start.timeIntervalSinceReferenceDate, accuracy: 1,
                       "and the record that was already right is left alone — same identity, same row, no duplicate")

        // The whole loan, to the journal's own arithmetic: 6 min at 0.05 + 6 min at 2.35 +
        // 0.60 U bolus + 14 min at 1.15.
        let truth = 0.05 * 6 / 60 + 2.35 * 6 / 60 + 0.60 + 1.15 * 14 / 60
        XCTAssertEqual(units(fixed), truth, accuracy: 0.001,
                       "the loan window's insulin is exactly what the watch journaled")
        XCTAssertGreaterThan(abs(units(broken) - truth), 0.15,
                             "sanity: the pre-backfill books were materially wrong, so the assertion above is load-bearing")
    }
}

// MARK: - Pulse-quantization fidelity across the wire

/// FIELD (2026-07-30 18:45, epoch 73): phone IOB 0.70 vs watch 1.00 on the SAME 41 seeded
/// records — a +0.30 "wire" gap with the watch's two books in perfect agreement (store =
/// ledger = 1.00), so the defect was in TRANSPORT, not storage.
///
/// Mechanism: Omnipod delivers whole 0.05 U pulses, so OmniBLE FLOORS a superseded temp's
/// units and LoopKit reads that via `deliveredUnits`. `LoanDoseRecord` carried actual units
/// for boluses but NOT for temps, so the watch re-derived with `round(programmedUnits)`
/// (DoseEntry.swift:147-153) — +0.025 U per elapsed temp slice, one-signed, saturating near
/// +0.4 U after hours of dense looping. The phone is correct: the pod cannot deliver a
/// fraction of a pulse.
final class LoanWireQuantizationTests: XCTestCase {

    /// A 5-min temp at 0.70 U/hr (== scheduled) delivers floor(0.0583/0.05)*0.05 = 0.05 U.
    /// Rounding instead yields 0.05 too — but at 1.15 U/hr the paths diverge, which is the
    /// general case this pins: the seeded dose must reproduce the phone's FLOORED units.
    func testTempSeedPreservesPodFlooredDelivery() {
        let start = Date().addingTimeInterval(-.minutes(30))
        let end = start.addingTimeInterval(.minutes(5))
        let rate = 1.15                                    // U/hr
        let programmed = rate * 5.0 / 60.0                 // 0.09583 U
        let podFloored = (programmed / 0.05).rounded(.down) * 0.05   // 0.05 U — what the pod gave

        let record = LoanDoseRecord(kind: .tempBasal, startDate: start, endDate: end,
                                    unitsPerHour: rate, syncIdentifier: "wire-1",
                                    deliveredUnits: podFloored)
        guard let seeded = record.seedDoseEntry(syncIdentifier: "wire-1") else {
            return XCTFail("temp record must seed")
        }
        XCTAssertEqual(seeded.deliveredUnits ?? -1, podFloored, accuracy: 1e-9,
                       "the pod's floored delivery must survive the wire")
        XCTAssertEqual(seeded.unitsInDeliverableIncrements, podFloored, accuracy: 1e-9,
                       "LoopKit must consume the floored actual, not round(programmed)")

        // Pre-fix shape: no deliveredUnits → LoopKit's round() fallback over-states delivery.
        let legacy = LoanDoseRecord(kind: .tempBasal, startDate: start, endDate: end,
                                    unitsPerHour: rate, syncIdentifier: "wire-1")
        guard let legacySeeded = legacy.seedDoseEntry(syncIdentifier: "wire-1") else {
            return XCTFail("legacy record must still seed (older phone)")
        }
        XCTAssertNil(legacySeeded.deliveredUnits, "older phones send no actual — fallback path")
        XCTAssertGreaterThan(legacySeeded.unitsInDeliverableIncrements, podFloored,
                             "the fallback rounds UP here — the field over-statement, pinned")
    }

    /// The field signature: ~0.025 U per slice accumulates one-signed across a dense
    /// looping window. 33 slices produced +0.30 in the field; this pins the per-slice
    /// mechanism and its sign rather than re-deriving the whole IOB integral.
    func testQuantizationDriftIsOneSignedAcrossSlices() {
        let base = Date().addingTimeInterval(-.hours(3))
        var flooredTotal = 0.0
        var roundedTotal = 0.0
        for slice in 0..<33 {
            let start = base.addingTimeInterval(.minutes(Double(slice) * 5))
            let rate = 0.70 + Double(slice % 7) * 0.15     // a realistic spread of temps
            let programmed = rate * 5.0 / 60.0
            let podFloored = (programmed / 0.05).rounded(.down) * 0.05
            let withActual = LoanDoseRecord(kind: .tempBasal, startDate: start,
                                            endDate: start.addingTimeInterval(.minutes(5)),
                                            unitsPerHour: rate, syncIdentifier: "s\(slice)",
                                            deliveredUnits: podFloored)
            let withoutActual = LoanDoseRecord(kind: .tempBasal, startDate: start,
                                               endDate: start.addingTimeInterval(.minutes(5)),
                                               unitsPerHour: rate, syncIdentifier: "s\(slice)")
            flooredTotal += withActual.seedDoseEntry(syncIdentifier: "s\(slice)")?.unitsInDeliverableIncrements ?? 0
            roundedTotal += withoutActual.seedDoseEntry(syncIdentifier: "s\(slice)")?.unitsInDeliverableIncrements ?? 0
        }
        XCTAssertGreaterThan(roundedTotal, flooredTotal,
                             "the pre-fix path must over-count — one-signed, never under")
        XCTAssertEqual(roundedTotal - flooredTotal, 0.025 * 33, accuracy: 0.025 * 33 * 0.6,
                       "drift scales with slice count at ~0.025 U each (field: 33 slices → +0.30)")
    }
}

// MARK: - Overrides across the loan

/// Jeremy's ruling (2026-07-31): overrides carry BOTH ways, stock framework, no sport-mode
/// special case. The gap these pin: the watch's stores were built with an override history
/// that nothing ever recorded into, so a granted override changed NOTHING — basal, ISF and
/// carb ratio all resolved unscaled and historical temps netted against the wrong baseline.
/// The phone does exactly one thing (LoopDataManager:270 overrideHistory.recordOverride);
/// the watch now mirrors it in its settings didSet.
///
/// Fixture is Jeremy's: 60% insulin needs, target raised to 140-160.
final class LoanOverrideTests: XCTestCase {

    private var cacheDir: URL?
    private var _cacheStore: PersistenceController?

    /// ON DEMAND, not in setUp. `PersistenceController` initializes its Core Data stack
    /// ASYNCHRONOUSLY, while tearDown deletes the directory synchronously — so every
    /// controller a test does not actually use is still a live "vnode unlinked while in use"
    /// race against the OTHER suites' stores in this same process (the `Failed to stat path
    /// …/tmp/<uuid>/Model.sqlite` noise, which turns into a store that answers with zero rows).
    /// Only two tests in this class need a store; building one for all of them measurably
    /// raised the flake rate of unrelated suites. Nothing else changes — same construction,
    /// same per-test isolation.
    private var cacheStore: PersistenceController {
        if let existing = _cacheStore { return existing }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = PersistenceController(directoryURL: dir)
        let ready = expectation(description: "persistent store attached")
        store.onReady { error in
            XCTAssertNil(error, "store failed to come up")
            ready.fulfill()
        }
        wait(for: [ready], timeout: 10)
        cacheDir = dir
        _cacheStore = store
        return store
    }

    private let baseBasal = BasalRateSchedule(dailyItems: [RepeatingScheduleValue(startTime: 0, value: 1.0)])!
    private let baseISF = InsulinSensitivitySchedule(unit: .milligramsPerDeciliter, dailyItems: [RepeatingScheduleValue(startTime: 0, value: 50.0)])!
    private let baseCR = CarbRatioSchedule(unit: .gram, dailyItems: [RepeatingScheduleValue(startTime: 0, value: 10.0)])!

    /// Field, the dev line's first breakfast loan: the stock carb flow brackets a manual
    /// bolus with a max-temp enact that is cancelled seconds later, and when the cancel takes
    /// the zero-duration form ("temp 0.00 × 0 min") the audit's segment builder DISCARDED the
    /// zero-length record — so the cancelled 2.50 U/hr × 30 min temp stood in the books until
    /// the next real temp, 8 phantom pulses ≈ 0.40 U of expected insulin the pod (correctly
    /// back on schedule) never delivered. Locked −0.25 residual, false "IOB May Be Overstated"
    /// on honest books. The fix admits zero-length segments as TERMINATORS: they clip their
    /// predecessor at the cancel instant and contribute zero delivery themselves.
    ///
    /// This test replays the tape's shape: bolus + bracket temp + zero-length cancel 3 s later
    /// + next real temp 15 min on, odometer metering exactly what the schedule says. Pre-fix
    /// the phantom books a 0.40 U shortfall; post-fix the audit reads dead even.
    /// (Ported by content from her line's ab31d9e7 — same builder, same walk, same field tape.)
    func testZeroDurationCancelClipsThePhantomTempInTheAudit() {
        let t0 = Date()
        let bolus = LoanEvent(id: UUID(), seq: 1, provenance: .confirmed,
                              record: LoanDoseRecord(kind: .bolus, startDate: t0.addingTimeInterval(30), amount: 1.30),
                              loggedAt: t0.addingTimeInterval(30))
        let bracket = LoanEvent(id: UUID(), seq: 2, provenance: .confirmed,
                                record: LoanDoseRecord(kind: .tempBasal, startDate: t0.addingTimeInterval(30),
                                                       endDate: t0.addingTimeInterval(30 + 1800), unitsPerHour: 2.50),
                                loggedAt: t0.addingTimeInterval(30))
        let cancel = LoanEvent(id: UUID(), seq: 3, provenance: .confirmed,
                               record: LoanDoseRecord(kind: .tempBasal, startDate: t0.addingTimeInterval(33),
                                                      endDate: t0.addingTimeInterval(33), unitsPerHour: 0.0),
                               loggedAt: t0.addingTimeInterval(33))
        let nextTemp = LoanEvent(id: UUID(), seq: 4, provenance: .confirmed,
                                 record: LoanDoseRecord(kind: .tempBasal, startDate: t0.addingTimeInterval(900),
                                                        endDate: t0.addingTimeInterval(900 + 1800), unitsPerHour: 0.0),
                                 loggedAt: t0.addingTimeInterval(900))

        // What the pod actually metered: the 1.30 bolus (exact) + schedule (1.0 U/hr, one pulse
        // per 180 s) over the post-cancel gap [t0+33 s, t0+900 s] = 4 pulses = 0.20 U. The
        // bracket temp's 3 live seconds floor to zero pulses; the zero temps deliver nothing.
        let odometer = LoanOdometerSnapshot(deliveredAtStart: 50.00, deliveredLatest: 51.50,
                                            freshenSucceeded: true, asOf: t0.addingTimeInterval(2400))

        let expected = LoanReconciler.expectedInsulin(
            events: [bolus, bracket, cancel, nextTemp], schedule: baseBasal,
            from: t0, to: t0.addingTimeInterval(2400))

        XCTAssertEqual(odometer.deliveredLatest - odometer.deliveredAtStart, expected, accuracy: 0.05,
                       "honest books must audit clean — pre-fix the discarded cancel left the 2.50 bracket " +
                       "standing 14.5 phantom minutes (12 pulses = 0.60 U) and booked a false shortfall")
    }

    override func tearDown() {
        // Same reasoning as LoanBooksHarnessTests above — do not race the async Core Data
        // stack to unlink a temp directory. Lazy creation already limited the blast radius here;
        // dropping the delete removes the race outright.
        _cacheStore = nil
        cacheDir = nil
        super.tearDown()
    }

    /// The fixture: "Exercise" — 60% insulin needs, target 140-160.
    private func exerciseOverride(start: Date, duration: TimeInterval = .hours(1)) -> TemporaryScheduleOverride {
        let settings = TemporaryPresetSettings(
            unit: .milligramsPerDeciliter,
            targetRange: DoubleRange(minValue: 140, maxValue: 160),
            insulinNeedsScaleFactor: 0.6)
        return TemporaryScheduleOverride(context: .custom,
                                         settings: settings,
                                         startDate: start,
                                         duration: .finite(duration),
                                         enactTrigger: .local,
                                         syncIdentifier: UUID())
    }

    /// THE CORE CLAIM: one scale factor moves all three schedules coherently — basal DOWN,
    /// ISF and carb ratio UP (you are more sensitive, so each unit does more).
    func testOverrideScalesAllThreeSchedules() {
        let history = TemporaryScheduleOverrideHistory()
        let now = Date()
        history.recordOverride(exerciseOverride(start: now.addingTimeInterval(-.minutes(5))))

        let scaledBasal = history.resolvingRecentBasalSchedule(baseBasal, relativeTo: now)
        let scaledISF = history.resolvingRecentInsulinSensitivitySchedule(baseISF, relativeTo: now)
        let scaledCR = history.resolvingRecentCarbRatioSchedule(baseCR, relativeTo: now)

        XCTAssertEqual(scaledBasal.value(at: now), 0.60, accuracy: 0.001,
                       "basal scales BY the factor: 1.0 x 0.6")
        XCTAssertEqual(scaledISF.value(at: now), 50.0 / 0.6, accuracy: 0.01,
                       "ISF scales by the RECIPROCAL: more sensitive at 60% needs")
        XCTAssertEqual(scaledCR.value(at: now), 10.0 / 0.6, accuracy: 0.01,
                       "carb ratio likewise — fewer units per gram")
    }

    /// The gap that made this a bug rather than a missing feature: a DoseStore built with an
    /// empty history resolves everything unscaled, so a granted override is silently inert.
    func testEmptyHistoryLeavesSchedulesUnscaled_theWatchGapPreFix() {
        let empty = TemporaryScheduleOverrideHistory()
        let now = Date()
        XCTAssertEqual(empty.resolvingRecentBasalSchedule(baseBasal, relativeTo: now).value(at: now),
                       1.0, accuracy: 0.001,
                       "pre-fix watch shape: the override exists in settings but changes nothing")
    }

    /// Retro-netting: a temp that RAN during the override must net against the overridden
    /// basal, not the raw one — this is why history matters and 'is one active now' does not.
    /// 0.60 U/hr under a 0.6-scaled 1.0 schedule is exactly neutral; against the raw
    /// schedule it would look like a 0.40 U/hr suppression.
    func testTempDuringOverrideNetsAgainstTheOverriddenSchedule() {
        let now = Date()
        let overrideStart = now.addingTimeInterval(-.minutes(60))
        let history = TemporaryScheduleOverrideHistory()
        history.recordOverride(exerciseOverride(start: overrideStart, duration: .hours(2)))

        // Resolved off the history directly: the DoseStore no longer carries an override history
        // or pre-scales a basal profile, so this is where the scaling the temp nets against is
        // decided — and it is the same call the wrist makes before handing the algorithm its
        // basal timeline.
        let scaled = history.resolvingRecentBasalSchedule(baseBasal, relativeTo: now)
        XCTAssertEqual(scaled.value(at: now.addingTimeInterval(-.minutes(30))), 0.60, accuracy: 0.001,
                       "mid-override the effective basal is 0.60 — a 0.60 U/hr temp nets to ZERO, not -0.40")
    }

    /// The active override must reach the wrist in the GRANT.
    ///
    /// This test used to assert the override rode inside `LoopSettings.rawValue`, which is how it
    /// worked when `LoopSettings` owned `scheduleOverride`. It does not any more — the active
    /// override lives on `TemporaryPresetsManager` and `therapySettingsRaw` cannot carry it. The
    /// settings blob still carries the override PRESETS (the menu), which is a different thing
    /// from the override in force and is not a substitute for it.
    ///
    /// So the first half of this test pins what actually broke: the settings blob is NOT the
    /// override's transport. The second half pins the transport that replaced it. An override that
    /// fails to arrive does not fail loudly — the wrist simply resolves every schedule unscaled and
    /// doses ~100% where the phone asked for 60%, which is the over-delivery direction during
    /// exercise.
    func testOverrideReachesTheWristInTheGrant() {
        var settings = LoopSettings()
        settings.basalRateSchedule = baseBasal
        settings.insulinSensitivitySchedule = baseISF
        settings.carbRatioSchedule = baseCR
        // The DOSING LIMITS the wrist's loop requires. Absent here until 2026-08-18, because
        // nothing had exercised the temp-basal path: next-dev defaults new LoopSettings() to
        // automaticBolus, and the grant now forces tempBasalOnly (the wrist cannot bolus
        // automatically), so these guards are reached where they never used to be. A fixture
        // missing them is not a finding about the code.
        settings.maximumBolus = 10
        settings.maximumBasalRatePerHour = 4
        settings.suspendThreshold = GlucoseThreshold(unit: .milligramsPerDeciliter, value: 80)
        let now = Date()
        let active = exerciseOverride(start: now)

        // The settings blob still round-trips the SCHEDULES the override scales; it simply has
        // nowhere to put the override itself. Pinned so a future reader does not re-add an
        // override field here and assume the wire picked it up.
        guard let decodedSettings = LoopSettings(rawValue: settings.rawValue) else {
            return XCTFail("settings must round-trip")
        }
        XCTAssertNotNil(decodedSettings.basalRateSchedule, "schedules still ride in the settings blob")

        // The transport: the grant's own field, encoded exactly as the hand-back records encode
        // an override, so both directions of the wire agree on one format.
        guard let raw = try? PropertyListSerialization.data(fromPropertyList: active.rawValue,
                                                           format: .binary, options: 0) else {
            return XCTFail("the active override must encode for the wire")
        }
        let grant = LoanGrant(
            epoch: 1,
            expiresAt: now.addingTimeInterval(.minutes(5)),
            pumpManagerRawState: Data(),
            podAddress: 0,
            therapySettingsRaw: Data(),
            settingsTimeZoneID: TimeZone.current.identifier,
            doseHistory: [],
            activeOverrideRaw: raw)

        guard let carried = grant.activeOverrideRaw,
              let plist = (try? PropertyListSerialization.propertyList(from: carried, options: [], format: nil)) as? TemporaryScheduleOverride.RawValue,
              let override = TemporaryScheduleOverride(rawValue: plist) else {
            return XCTFail("the active override must survive the grant")
        }
        XCTAssertEqual(override.settings.effectiveInsulinNeedsScaleFactor, 0.6, accuracy: 0.001)
        XCTAssertEqual(override.settings.targetRange?.lowerBound.doubleValue(for: .milligramsPerDeciliter) ?? 0,
                       140, accuracy: 0.1)
        XCTAssertEqual(override.settings.targetRange?.upperBound.doubleValue(for: .milligramsPerDeciliter) ?? 0,
                       160, accuracy: 0.1)
        XCTAssertEqual(override.syncIdentifier, active.syncIdentifier,
                       "identity must survive so the two devices can agree on WHICH override")
    }

    /// A grant from a phone that never sends the field (or that holds no override) must be a
    /// clean "no override" rather than anything the watch has to special-case.
    func testGrantWithoutAnOverrideCarriesNone() {
        let grant = LoanGrant(
            epoch: 1,
            expiresAt: Date().addingTimeInterval(.minutes(5)),
            pumpManagerRawState: Data(),
            podAddress: 0,
            therapySettingsRaw: Data(),
            settingsTimeZoneID: TimeZone.current.identifier,
            doseHistory: [])
        XCTAssertNil(grant.activeOverrideRaw,
                     "an absent field and 'no override active' are the same thing on the wire")
    }

    /// Target range: an override must move the target the loop drives to — 140-160, not the base
    /// 100-115.
    ///
    /// The mechanism changed with the stateless algorithm. There is no
    /// `LoopSettings.effectiveGlucoseTargetRangeSchedule()` any more; the watch resolves the
    /// override against the scheduled range itself and hands the RESULT to the algorithm as a
    /// target timeline (`WatchLoopManager.fetchAlgorithmInput`). This asserts that resolution,
    /// which is the call the wrist actually makes.
    func testEffectiveTargetRangeFollowsTheOverride() {
        let base = GlucoseRangeSchedule(
            unit: .milligramsPerDeciliter,
            dailyItems: [RepeatingScheduleValue(startTime: 0, value: DoubleRange(minValue: 100, maxValue: 115))])!
        let now = Date()
        let override = exerciseOverride(start: now.addingTimeInterval(-.minutes(1)))
        XCTAssertTrue(override.isActive(at: now), "the fixture must be running at the instant under test")

        let range = override.effectiveCorrectionRangeDuring(scheduledRange: base.quantityRange(at: now))
        XCTAssertEqual(range.lowerBound.doubleValue(for: .milligramsPerDeciliter), 140, accuracy: 0.1)
        XCTAssertEqual(range.upperBound.doubleValue(for: .milligramsPerDeciliter), 160, accuracy: 0.1)
    }

    // MARK: - PART B: watch-enacted overrides ride the journal home

    /// The wrist fixture, created exactly the way the wrist creates it: the stock
    /// OverrideSelectionController hands a preset to `createOverride(enactTrigger: .local)`
    /// (ActionHUDController :301-303). Same 60% / 140-160 therapy content as the granted
    /// fixture above — the point of the pair is that route does not change effect.
    private func exercisePreset() -> TemporaryPreset {
        TemporaryPreset(
            symbol: "🏃",
            name: "Exercise",
            settings: TemporaryPresetSettings(
                unit: .milligramsPerDeciliter,
                targetRange: DoubleRange(minValue: 140, maxValue: 160),
                insulinNeedsScaleFactor: 0.6),
            duration: .finite(.hours(1)))
    }

    /// 1. The record kind round-trips through the loan wire with the override's IDENTITY
    ///    intact — identity is what makes the phone-side apply idempotent, so losing it
    ///    across the wire would silently turn every replayed drain into a re-apply.
    ///    Encoded inside a real `HandbackOffer` envelope, not just the struct, so the
    ///    envelope's hand-rolled kind discriminator is exercised too.
    func testOverrideChangeRecordRoundTripsWithIdentityIntact() {
        let now = Date()
        let override = exercisePreset().createOverride(enactTrigger: .local, beginningAt: now)
        let record = LoanDoseRecord.overrideChange(override, at: now, note: "🏃 Exercise")

        XCTAssertEqual(record.kind, .overrideChange)
        XCTAssertFalse(record.overrideChangeIsClear, "a SET record must not read as a clear")
        XCTAssertEqual(record.syncIdentifier, override.syncIdentifier.uuidString,
                       "the record's identity IS the override's syncIdentifier")

        let event = LoanEvent(id: UUID(), seq: 7, provenance: .confirmed, record: record, loggedAt: now)
        let offer = HandbackOffer(epoch: 3, handedBackAt: now, finalStatus: nil, odometer: nil,
                                  events: [event], tombstones: [], recovered: false, released: true)
        guard let wire = try? LoanMessage.handbackOffer(offer).transportDictionary(),
              let decodedMessage = try? LoanMessage.decode(fromTransport: wire),
              case .handbackOffer(let decodedOffer) = decodedMessage,
              let decodedRecord = decodedOffer.events.first?.record else {
            return XCTFail("the override record must survive the v2 envelope")
        }

        XCTAssertEqual(decodedRecord.kind, .overrideChange)
        XCTAssertEqual(decodedRecord.syncIdentifier, override.syncIdentifier.uuidString)
        guard let payload = decodedRecord.overrideChangePayload else {
            return XCTFail("the override payload must decode on the phone")
        }
        XCTAssertEqual(payload.syncIdentifier, override.syncIdentifier,
                       "identity must survive the plist payload too, not just the record header")
        XCTAssertEqual(payload.settings.effectiveInsulinNeedsScaleFactor, 0.6, accuracy: 0.001)
        XCTAssertEqual(payload.settings.targetRange?.lowerBound.doubleValue(for: .milligramsPerDeciliter) ?? 0,
                       140, accuracy: 0.1)
        XCTAssertEqual(payload.settings.targetRange?.upperBound.doubleValue(for: .milligramsPerDeciliter) ?? 0,
                       160, accuracy: 0.1)
        if case .preset(let preset) = payload.context {
            XCTAssertEqual(preset.name, "Exercise", "the preset name rides home for the phone's log line")
        } else {
            XCTFail("the preset context must survive — it is what names the override on both devices")
        }
    }

    /// 3. A CLEAR (nil payload) round-trips as a clear and reconciles to `.cleared` — and the
    ///    LAST record in a drain wins, so a set→clear pair inside one drain must NOT resurrect
    ///    the set. That ordering is the whole reason the fold is last-wins.
    func testClearedOverrideRoundTripsAndClears() {
        let now = Date()
        let clear = LoanDoseRecord.overrideChange(nil, at: now)
        XCTAssertTrue(clear.overrideChangeIsClear)
        XCTAssertNil(clear.overrideRaw)
        XCTAssertNil(clear.syncIdentifier, "a clear names no override")
        XCTAssertNil(clear.overrideChangePayload)

        // Through the wire.
        let event = LoanEvent(id: UUID(), seq: 2, provenance: .confirmed, record: clear, loggedAt: now)
        let offer = HandbackOffer(epoch: 1, handedBackAt: now, finalStatus: nil, odometer: nil,
                                  events: [event], tombstones: [], recovered: false, released: true)
        guard let wire = try? LoanMessage.handbackOffer(offer).transportDictionary(),
              case .handbackOffer(let decoded)? = try? LoanMessage.decode(fromTransport: wire),
              let decodedClear = decoded.events.first?.record else {
            return XCTFail("the clear record must survive the v2 envelope")
        }
        XCTAssertTrue(decodedClear.overrideChangeIsClear,
                      "an absent payload must decode as CLEARED, not as 'no override record'")

        // Reconciled alone → cleared.
        let soloOutcome = LoanReconciler.reconcile(LoanReconciler.Input(
            events: [LoanEvent(id: UUID(), seq: 1, provenance: .confirmed, record: decodedClear, loggedAt: now)],
            schedule: baseBasal, loanStart: now.addingTimeInterval(-.hours(1)), loanEnd: now))
        XCTAssertEqual(soloOutcome.overrideChange, .cleared)
        XCTAssertTrue(soloOutcome.doses.isEmpty, "an override record is not dose accounting")

        // Set THEN clear in one drain → cleared (last wins; no resurrection).
        let override = exercisePreset().createOverride(enactTrigger: .local, beginningAt: now.addingTimeInterval(-.minutes(20)))
        let setEvent = LoanEvent(id: UUID(), seq: 1, provenance: .confirmed,
                                 record: .overrideChange(override, at: now.addingTimeInterval(-.minutes(20))),
                                 loggedAt: now.addingTimeInterval(-.minutes(20)))
        let clearEvent = LoanEvent(id: UUID(), seq: 2, provenance: .confirmed, record: clear, loggedAt: now)
        let pairOutcome = LoanReconciler.reconcile(LoanReconciler.Input(
            events: [setEvent, clearEvent], schedule: baseBasal,
            loanStart: now.addingTimeInterval(-.hours(1)), loanEnd: now))
        XCTAssertEqual(pairOutcome.overrideChange, .cleared,
                       "set→clear in one drain must land as CLEARED — the reverse would resurrect a cancelled override")

        // And a drain with no override record at all leaves the phone's override alone.
        let bolus = LoanEvent(id: UUID(), seq: 1, provenance: .confirmed,
                              record: LoanDoseRecord(kind: .bolus, startDate: now, amount: 1.0), loggedAt: now)
        let noneOutcome = LoanReconciler.reconcile(LoanReconciler.Input(
            events: [bolus], schedule: baseBasal,
            loanStart: now.addingTimeInterval(-.hours(1)), loanEnd: now))
        XCTAssertNil(noneOutcome.overrideChange,
                     "no override record must mean 'do not touch', never 'clear'")
    }

    /// 2. Applying on the phone is IDEMPOTENT across a replayed drain. Both layers are pinned:
    ///    the persisted committed-event-ID filter (a resent offer carries the same event), and
    ///    the syncIdentifier check (the phone already holds this override — e.g. the live WC
    ///    push landed first, or the staged state was reset). The second is the one that matters
    ///    for "must not resurrect a cleared override", so the clear arm is pinned too.
    func testPhoneApplyIsIdempotentAcrossAReplayedDrain() {
        let now = Date()
        let override = exercisePreset().createOverride(enactTrigger: .local, beginningAt: now)

        // (a) Replayed FINAL offer: the second delivery must apply nothing.
        let harness = PhoneOverrideHarness()
        defer { harness.tearDown() }
        let record = LoanDoseRecord.overrideChange(override, at: now, note: "🏃 Exercise")
        let event = LoanEvent(id: UUID(), seq: 1, provenance: .confirmed, record: record, loggedAt: now)
        harness.deliverFinalOffer(events: [event], at: now)
        XCTAssertEqual(harness.applied.count, 1, "the first drain applies the wrist override")
        XCTAssertTrue(harness.phoneOverride?.syncIdentifier == override.syncIdentifier,
                      "and the phone ends up holding exactly the wrist's override")

        harness.deliverFinalOffer(events: [event], at: now)
        XCTAssertEqual(harness.applied.count, 1,
                       "a replayed drain must not re-apply — committed event IDs are persisted")

        // (b) Same override arriving under a DIFFERENT event id (staged state lost, or the live
        //     WC push beat the journal home): the syncIdentifier check must skip it.
        let replayUnderNewID = LoanEvent(id: UUID(), seq: 2, provenance: .confirmed, record: record, loggedAt: now)
        harness.deliverFinalOffer(events: [replayUnderNewID], at: now)
        XCTAssertEqual(harness.applied.count, 1,
                       "already-applied by syncIdentifier → SKIP, independent of event bookkeeping")

        // (c) A CLEAR against a phone that holds nothing must also skip — re-clearing would
        //     cancel an override the user set on the PHONE after the loan ended.
        let cleanHarness = PhoneOverrideHarness()
        defer { cleanHarness.tearDown() }
        let clearEvent = LoanEvent(id: UUID(), seq: 1, provenance: .confirmed,
                                   record: .overrideChange(nil, at: now), loggedAt: now)
        cleanHarness.deliverFinalOffer(events: [clearEvent], at: now)
        XCTAssertTrue(cleanHarness.applied.isEmpty,
                      "clearing a phone that already holds no override is a no-op, not a write")

        // ...but a clear against a phone that DOES hold one lands exactly once.
        let liveHarness = PhoneOverrideHarness()
        defer { liveHarness.tearDown() }
        liveHarness.phoneOverride = override
        let clearEvent2 = LoanEvent(id: UUID(), seq: 1, provenance: .confirmed,
                                    record: .overrideChange(nil, at: now), loggedAt: now)
        liveHarness.deliverFinalOffer(events: [clearEvent2], at: now)
        XCTAssertEqual(liveHarness.applied.count, 1)
        XCTAssertNil(liveHarness.applied.first ?? nil, "the clear applies nil")
        XCTAssertNil(liveHarness.phoneOverride)
    }

    /// 4. A WRIST-set override rescales the watch's schedules exactly the way a GRANTED one
    ///    does. Both routes end at the same single mechanism — `overrideHistory.recordOverride`,
    ///    which is all WatchLoopManager's settings didSet does (part A) — so this pins that a
    ///    `.preset`/`.local` override created on the wrist is not a second-class citizen.
    ///    (The watch extension target is not linkable from LoopTests, so the assertion is
    ///    against the same stores/history WatchLoopManager holds, constructed identically to
    ///    StockLoopStack.makeStores.)
    func testWristSetOverrideRescalesSchedulesLikeAGrantedOne() {
        let now = Date()
        let start = now.addingTimeInterval(-.minutes(10))

        // Granted route: the phone's override arrives in the grant's LoopSettings blob.
        let grantedHistory = TemporaryScheduleOverrideHistory()
        grantedHistory.recordOverride(exerciseOverride(start: start, duration: .hours(2)))

        // Wrist route: the user picks the preset on the watch during the loan.
        let wristHistory = TemporaryScheduleOverrideHistory()
        let wristOverride = exercisePreset().createOverride(enactTrigger: .local, beginningAt: start)
        wristHistory.recordOverride(wristOverride)

        XCTAssertEqual(wristHistory.resolvingRecentBasalSchedule(baseBasal, relativeTo: now).value(at: now),
                       grantedHistory.resolvingRecentBasalSchedule(baseBasal, relativeTo: now).value(at: now),
                       accuracy: 0.0001, "basal: wrist-set == granted")
        XCTAssertEqual(wristHistory.resolvingRecentBasalSchedule(baseBasal, relativeTo: now).value(at: now),
                       0.60, accuracy: 0.001, "and both are the 60%-needs value")
        XCTAssertEqual(wristHistory.resolvingRecentInsulinSensitivitySchedule(baseISF, relativeTo: now).value(at: now),
                       grantedHistory.resolvingRecentInsulinSensitivitySchedule(baseISF, relativeTo: now).value(at: now),
                       accuracy: 0.0001, "ISF: wrist-set == granted")
        XCTAssertEqual(wristHistory.resolvingRecentCarbRatioSchedule(baseCR, relativeTo: now).value(at: now),
                       grantedHistory.resolvingRecentCarbRatioSchedule(baseCR, relativeTo: now).value(at: now),
                       accuracy: 0.0001, "carb ratio: wrist-set == granted")

        // The schedules the loop actually doses against resolve through that same history
        // instance — this is the wall: an override that isn't in the history changes nothing.
        //
        // This used to assert it through `DoseStore.basalProfileApplyingOverrideHistory`, because
        // the store held the override history and pre-scaled its own schedules. It no longer holds
        // either: schedules are resolved by the caller at read time and handed to the algorithm.
        // So the wall is the same wall, checked one layer up — where the wrist now stands.
        XCTAssertEqual(wristHistory.resolvingRecentBasalSchedule(baseBasal, relativeTo: now).value(at: now),
                       0.60, accuracy: 0.001,
                       "the wrist nets temps against the WRIST-scaled basal")
        XCTAssertEqual(wristHistory.resolvingRecentInsulinSensitivitySchedule(baseISF, relativeTo: now).value(at: now),
                       50.0 / 0.6, accuracy: 0.01)

        // And the target the watch drives to follows the wrist selection. Resolved the way
        // `WatchLoopManager.fetchAlgorithmInput` resolves it, against the scheduled range.
        let base = GlucoseRangeSchedule(
            unit: .milligramsPerDeciliter,
            dailyItems: [RepeatingScheduleValue(startTime: 0, value: DoubleRange(minValue: 100, maxValue: 115))])!
        let effective = wristOverride.effectiveCorrectionRangeDuring(scheduledRange: base.quantityRange(at: now))
        XCTAssertEqual(effective.lowerBound.doubleValue(for: .milligramsPerDeciliter),
                       140, accuracy: 0.1)
        XCTAssertEqual(effective.upperBound.doubleValue(for: .milligramsPerDeciliter),
                       160, accuracy: 0.1)
    }
}

// MARK: - Phone-side override harness (part B)

/// The real `PodLoanPhoneController`, driven straight into LOANED via its persisted state so a
/// hand-back offer can be delivered without a pump or a live grant. Captures every
/// `applyScheduleOverride` call and models the phone's LoopSettings well enough for the
/// controller's "already applied?" read.
private final class PhoneOverrideHarness {

    /// Every applyScheduleOverride call, in order (`nil` element = a clear).
    private(set) var applied: [TemporaryScheduleOverride?] = []
    /// Stands in for the phone's LoopSettings.scheduleOverride — read by the idempotency check,
    /// written by the apply, exactly as `mutateSettings { $0.scheduleOverride = … }` does.
    var phoneOverride: TemporaryScheduleOverride?

    private let lock = NSLock()
    private var controller: PodLoanPhoneController!
    private static let defaultsKeys = ["PodLoanPhoneController.state", "PodLoanPhoneController.epoch",
                                       "PodLoanPhoneController.cursor", "PodLoanPhoneController.pendingRevoke",
                                       "PodLoanPhoneController.committedIDs", "PodLoanPhoneController.loanStartedAt"]
    private static var stagedFileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("PodLoanStagedRecordsV2.json")
    }

    init(epoch: Int = 1) {
        Self.wipePersistedState()
        // Persisted-state derivation is how this controller boots: write LOANED at `epoch` and
        // it comes up mid-loan, ready to receive the hand-back offer.
        UserDefaults.standard.set("loaned", forKey: "PodLoanPhoneController.state")
        UserDefaults.standard.set(epoch, forKey: "PodLoanPhoneController.epoch")

        var settings = LoopSettings()
        settings.basalRateSchedule = BasalRateSchedule(dailyItems: [RepeatingScheduleValue(startTime: 0, value: 1.0)])!

        controller = PodLoanPhoneController(dependencies: .init(
            pumpManager: { nil },
            settings: { settings },
            setAutomaticDosingPaused: { _ in },
            send: { _ in },
            addPumpEvents: { _, _, completion in completion(nil) },
            addCarb: { _, _, completion in completion(nil) },
            // The phone's active override is its own dependency now rather than a field on
            // LoopSettings — and this harness exists to exercise the controller's "already
            // applied?" check, which is exactly what reads it.
            scheduleOverride: { [weak self] in self?.phoneOverride },
            applyScheduleOverride: { [weak self] override in
                guard let self = self else { return }
                self.lock.lock()
                self.applied.append(override)
                self.phoneOverride = override
                self.lock.unlock()
            },
            doseHistory: { _, completion in completion([]) },
            issueNotice: { _, _ in }))
    }

    /// Deliver a FINAL (released) hand-back offer and run the commit path to completion.
    ///
    /// DETERMINISTIC, not timed: the controller's work is two hops on ONE serial queue
    /// (handleIncoming's async block, then the block the addPumpEvents completion enqueues —
    /// this harness's addPumpEvents calls its completion inline). `isPodLoanedOut` is a
    /// `queue.sync` read, so N round-trips guarantee the first N enqueued blocks have run.
    /// That matters most for the SKIP assertions: "applied.count did not change" is only
    /// meaningful once the path has definitely finished, and a sleep-and-hope would make
    /// those the flakiest assertions in the file.
    func deliverFinalOffer(events: [LoanEvent], at date: Date) {
        let offer = HandbackOffer(epoch: 1, handedBackAt: date, finalStatus: nil, odometer: nil,
                                  events: events, tombstones: [], recovered: false, released: true)
        controller.handleIncoming(userInfo: try! LoanMessage.handbackOffer(offer).transportDictionary())
        for _ in 0..<4 { _ = controller.isPodLoanedOut }
    }

    func tearDown() {
        controller = nil
        Self.wipePersistedState()
    }

    private static func wipePersistedState() {
        for key in defaultsKeys { UserDefaults.standard.removeObject(forKey: key) }
        try? FileManager.default.removeItem(at: stagedFileURL)
    }
}
