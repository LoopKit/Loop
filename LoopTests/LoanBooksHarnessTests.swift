//
//  LoanBooksHarnessTests.swift
//  LoopTests
//
//  Session-replay harness for the loan insulin books against a real DoseStore: bolus twins, the
//  hand-back seam, re-grant conservation, the bolus queue hop, carb fold parity, force-reclaim
//  salvage. Identity contract: syncId == hex(raw). Basal is the field profile, 0.70 U/hr flat.
//

import XCTest
import HealthKit
// @testable for `PersistenceController.onReady`, so no test uses a store before it attaches.
@testable import LoopKit
import LoopAlgorithm
import LoopCore
@testable import Loop

// MARK: - File fixtures

/// The field profile, so the pinned deltas stay literal.
private let fieldBasalRate = 0.70

private let iso8601 = ISO8601DateFormatter()

/// Pod-native identity in OmniBLE's `uniqueKey` shape; tests rely on syncId == hex(raw).
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

/// A glucose sample for stock ICE: one provenance, 5-min grid.
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

/// Supplies the basal history `addPumpEvents` requires; flat at the field rate.
final class LoanBooksDoseStoreDelegate: DoseStoreDelegate {
    private let rate: Double
    init(rate: Double) { self.rate = rate }

    func doseStoreHasUpdatedPumpEventData(_ doseStore: DoseStore) {}

    func scheduledBasalHistory(from start: Date, to end: Date) async throws -> [AbsoluteScheduleValue<Double>] {
        [AbsoluteScheduleValue(startDate: start, endDate: end, value: rate)]
    }
}

/// A real DoseStore fed as OmniBLE reports: running temp re-asserted mutable each batch,
/// finalized with the same raw. Seeds run the real grant split.
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

    /// Hand-back-shaped records; `handbackFold` returns seed records plus these.
    private var foldedSession: [LoanDoseRecord] = []
    private var seedRecords: [LoanDoseRecord] = []

    /// Retained because `DoseStore.delegate` is weak.
    private let storeDelegate: LoanBooksDoseStoreDelegate

    init(host: XCTestCase, store: DoseStore, basalRate: Double, storeDelegate: LoanBooksDoseStoreDelegate) {
        self.host = host
        self.storeDelegate = storeDelegate
        // Fixture construction (force-unwraps allowed here, per file convention).
        self.schedule = BasalRateSchedule(dailyItems: [RepeatingScheduleValue(startTime: 0, value: basalRate)])!
        self.store = store
    }

    // MARK: Script steps

    /// Seeds finished history via the real grant split; a live dose is reported by the driver instead.
    func seed(_ records: [LoanDoseRecord], at instant: Date, epoch: Int = 1) {
        seedRecords = records
        let grant = LoanGrant(epoch: epoch, expiresAt: instant.addingTimeInterval(.minutes(5)),
                              pumpConfiguration: Data(), podAddress: 0,
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

    /// A pod-accepted bolus, finalized on the next report; the running temp is re-asserted with it.
    func enactBolus(units: Double, at instant: Date, span: TimeInterval = 38) {
        let raw = podRaw(type: "bolus", value: units, start: instant)
        let dose = DoseEntry(type: .bolus, startDate: instant,
                             endDate: instant.addingTimeInterval(span),
                             value: units, unit: .units, decisionId: nil)
        var batch = [NewPumpEvent(date: instant, dose: dose, raw: raw, title: "Bolus")]
        if let temp = runningTemp {
            batch.append(mutableEvent(for: temp))
        }
        // An immutable dose must not end after the reconciliation watermark.
        addToStore(batch, lastReconciliation: instant.addingTimeInterval(span), replacePendingEvents: true)

        foldedSession.append(LoanDoseRecord(kind: .bolus, startDate: instant,
                                            endDate: instant.addingTimeInterval(span),
                                            amount: units, syncIdentifier: hexString(raw)))
    }

    /// A pure read; tick before a later enact to see the pre-enact view.
    func tick(at instant: Date) -> Double {
        storeIOB(at: instant)
    }

    /// Finalizes the running temp and returns the next grant's dose history.
    func handbackFold(at instant: Date) -> [LoanDoseRecord] {
        if let final = finalizeRunningTemp(at: instant) {
            addToStore([final], lastReconciliation: instant, replacePendingEvents: true)
        }
        return seedRecords + foldedSession
    }

    // MARK: Low-level primitives (for scripting broken shapes)

    /// A finished/truncated row straight into the STORE only — test 1(b)'s known-wrong
    /// dead-re-arm shape (handover truncation record seeded, pod never re-reported).
    func storeFinished(_ dose: DoseEntry, raw: Data, lastReconciliation: Date) {
        addToStore([NewPumpEvent(date: dose.startDate, dose: dose, raw: raw, title: "Temp Basal")],
                   lastReconciliation: lastReconciliation, replacePendingEvents: false)
    }

    /// A raw batch, scripted event by event for the force-reclaim seam.
    func storeEvents(_ events: [NewPumpEvent], lastReconciliation: Date) {
        addToStore(events, lastReconciliation: lastReconciliation, replacePendingEvents: false)
    }

    /// `backfillDoses` against the real store (update-or-insert by syncIdentifier).
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

    /// IOB from the store's rows through the public InsulinMath pipeline, so any disagreement is
    /// a row disagreement.
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

    /// The pod's view of the running temp: mutable, full span, identity from raw.
    private func mutableEvent(for temp: RunningTemp) -> NewPumpEvent {
        let dose = DoseEntry(type: .tempBasal, startDate: temp.start, endDate: temp.programmedEnd,
                             value: temp.rate, unit: .unitsPerHour, decisionId: nil, isMutable: true)
        return NewPumpEvent(date: temp.start, dose: dose, raw: temp.raw, title: "Temp Basal")
    }

    /// Same raw, truncated to min(instant, end), immutable; also records the hand-back shape.
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

    /// Directories are never deleted: unlinking an initializing Core Data stack yields zero-row
    /// stores in whichever suite is running. Unique temp dirs don't collide.
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

        // DoseStore.init is async; `wait(for:)` bridges it so the tests stay synchronous.
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

    /// A bolus seeded as both a zero-length journal row and a pod-native row double-books.
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
                       "the store books BOTH twins: ~2 × 0.95 U of IOB for one physical bolus (+0.95 U phantom)")
    }

    // MARK: - 3. The hand-back seam

    /// The watch-to-phone IOB seam across a hand-back is explained by decay plus the zero temp's
    /// withheld basal, within 0.1 U. Replays a recorded hand-back (2026-07-29): the
    /// odd offsets and the clock times in the comments below are that session's.
    func testHandbackSeamCloses() {
        let now = Date()
        let t = now.addingTimeInterval(-.minutes(20))         // plays 21:16
        let handback = t.addingTimeInterval(.minutes(4.3))    // 21:20:18 — cancel/truncate
        let phoneEval = t.addingTimeInterval(.minutes(4.5))   // 21:21 — first phone sample

        let watch = makeDriver()
        // The recorded numbers: 0.95 U at t−31 min, then 2.80 superseded by 0.00.
        watch.enactBolus(units: 0.95, at: t.addingTimeInterval(-.minutes(31)))
        watch.enactTemp(rate: 2.80, at: t.addingTimeInterval(-.minutes(26)), duration: .minutes(30))
        watch.enactTemp(rate: 0.00, at: t.addingTimeInterval(-.minutes(16)), duration: .minutes(12))

        // Pre-enact reads: replay order matters.
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

    /// Seed → enacts → hand-back fold → re-seed a fresh store conserves IOB across epochs. The
    /// last temp ends at the hand-back, so the fold changes no span.
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

    /// The bolus path's reclaim completion runs on the loan queue; delivery must hop to the
    /// dosing queue with `.async` (a `.sync` would trap). Pins that the fixed shape completes.
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

        // Leg 1: completion on the loan queue, async hop, mint syncs back.
        let reclaimLeg = expectation(description: "reclaim-path delivery completes")
        loanQueue.async {
            dosingQueue.async {
                XCTAssertTrue(mintJournalIntent(),
                              "mint must complete before the pod command — the bug trapped here")
                reclaimLeg.fulfill()   // stands in for pumpManager.enactBolus reaching the pod
            }
        }

        // Leg 2: already on the dosing queue; `.async` makes the re-dispatch legal.
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

    /// A bolus through the hopped topology lands in the book.
    func testBolusLandsInTheBookAfterQueueHop() {
        let now = Date()
        let bolusStart = now.addingTimeInterval(-.minutes(5))  // inside the model delay: IOB is the full dose

        // Booked only after the hopped delivery and mint complete.
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
                       "the store must carry the full delivered bolus")
    }

    // MARK: - Carb-side helpers (tests 7-8)

    /// One CarbStore per side; schedules are supplied at read time.
    private func makeCarbStore() -> CarbStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        cacheDirs.append(dir)
        return CarbStore(
            healthKitSampleStore: nil,
            cacheStore: PersistenceController(directoryURL: dir),
            cacheLength: .hours(24),
            provenanceIdentifier: "LoanBooksHarnessTests")
    }

    /// The store is the idempotency point: one identity, one row; a late replay loses to a local edit.
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

    /// The fold's carb shape: quantity, start, absorption, no identity. Parity rides on those three.
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

    /// Carb status built as `LoopDataManager.fetchData` builds it.
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
        // Entries are fetched one absorption window before `start`; effects over [start, end],
        // as fetchAlgorithmInput does.
        let entriesStart = start.addingTimeInterval(-CarbMath.maximumAbsorptionTimeInterval)
        let status = carbStatus(store, start: entriesStart, end: end, velocities: velocities)
        guard !status.isEmpty else { return [] }
        let spanEnd = end.addingTimeInterval(InsulinMath.defaultInsulinActivityDuration)
        return status.dynamicGlucoseEffects(
            from: start,
            to: spanEnd,
            // Schedules must cover the entries, or a pre-midnight meal trips a precondition.
            carbRatios: fieldCarbRatio.between(start: entriesStart, end: spanEnd),
            insulinSensitivities: fieldISF.quantitiesBetween(start: entriesStart, end: spanEnd),
            absorptionModel: PiecewiseLinearAbsorption())
    }

    /// Sinusoidal BG, 100 → 140 → 180 mg/dL over 90 min.
    private func sinusoidSamples(from start: Date, count: Int = 19) -> [SimGlucoseSample] {
        return (0..<count).map { i in
            let t = TimeInterval(i) * .minutes(5)
            let bg = 140.0 + 40.0 * sin(2.0 * Double.pi * (t - .minutes(45)) / .minutes(180))
            return SimGlucoseSample(startDate: start.addingTimeInterval(t),
                                    quantity: LoopQuantity(unit: .milligramsPerDeciliter, doubleValue: bg))
        }
    }

    /// Stock ICE via `counteractionEffects(to:)`; flat insulin effects make ICE the glucose velocity.
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

    /// Watch and phone (seeded from the folded entry, same ICE) agree on COB within 0.5 g and
    /// on the effect curve.
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

        // Assert the dynamic-vs-static spread, so velocities are proven consumed.
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

    /// A phone missing loan-window glucose credits less absorption and so shows more COB.
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

        // Assert the direction with a ≥1 g floor.
        XCTAssertGreaterThan(phoneTruncatedCOB, watchCOB,
                             "relay-gap direction: the truncated-ICE phone must read HIGHER COB")
        XCTAssertGreaterThan(phoneTruncatedCOB - watchCOB, 1.0,
                             "the gap must be material — at least 1 g")
        XCTAssertLessThanOrEqual(phoneTruncatedCOB, 20.0 + 0.01,
                                 "sanity: COB can never exceed the entry")
    }

    // MARK: - 9. The store's basal boundary vs a late journal commit

    /// Force-reclaim salvage then a late journal: `addPumpEvents` drops basal-shaped rows before
    /// `lastImmutableBasalEndDate`; the backfill upsert lands them.
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

        // The salvage clamps both events at the reclaim; t2's clamp overshoots by 12 min.
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

        // 5. THE BOUNDARY SIGNATURE, from the real store.
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

/// Temps must carry the pod's floored units; re-deriving by rounding drifts +0.025 U per slice.
final class LoanWireQuantizationTests: XCTestCase {

    /// The seeded temp reproduces the phone's floored units.
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
                             "the fallback rounds UP here — the over-statement, pinned")
    }

    /// The per-slice drift is one-signed.
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
                       "drift scales with slice count at ~0.025 U each")
    }
}

// MARK: - Overrides across the loan

/// Overrides carry both ways through the stock override history. Fixture: 60% insulin needs,
/// target 140-160.
final class LoanOverrideTests: XCTestCase {

    private var cacheDir: URL?
    private var _cacheStore: PersistenceController?

    /// Built on demand: an unused async-initializing store raises other suites' flake rate.
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

    /// A zero-length cancel clips the bracket temp in the audit instead of being discarded.
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

        // Metered: the bolus plus 4 schedule pulses; the 3 s bracket temp floors to zero.
        let odometer = LoanOdometerSnapshot(deliveredAtStart: 50.00, deliveredLatest: 51.50,
                                            freshenSucceeded: true, asOf: t0.addingTimeInterval(2400))

        let expected = LoanReconciler.expectedInsulin(
            events: [bolus, bracket, cancel, nextTemp], schedule: baseBasal, pulseUnits: 0.05,
            from: t0, to: t0.addingTimeInterval(2400))

        XCTAssertEqual(odometer.deliveredLatest - odometer.deliveredAtStart, expected, accuracy: 0.05,
                       "honest books must audit clean — pre-fix the discarded cancel left the 2.50 bracket " +
                       "standing 14.5 phantom minutes (12 pulses = 0.60 U) and booked a false shortfall")
    }

    override func tearDown() {
        // Never delete the temp directory (see LoanBooksHarnessTests).
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

    /// A temp during an override nets against the overridden basal.
    func testTempDuringOverrideNetsAgainstTheOverriddenSchedule() {
        let now = Date()
        let overrideStart = now.addingTimeInterval(-.minutes(60))
        let history = TemporaryScheduleOverrideHistory()
        history.recordOverride(exerciseOverride(start: overrideStart, duration: .hours(2)))

        // Resolved off the history, as the wrist does.
        let scaled = history.resolvingRecentBasalSchedule(baseBasal, relativeTo: now)
        XCTAssertEqual(scaled.value(at: now.addingTimeInterval(-.minutes(30))), 0.60, accuracy: 0.001,
                       "mid-override the effective basal is 0.60 — a 0.60 U/hr temp nets to ZERO, not -0.40")
    }

    /// A grant from a phone that never sends the field (or that holds no override) must be a
    /// clean "no override" rather than anything the watch has to special-case.
    func testGrantWithoutAnOverrideCarriesNone() {
        let grant = LoanGrant(
            epoch: 1,
            expiresAt: Date().addingTimeInterval(.minutes(5)),
            pumpConfiguration: Data(),
            podAddress: 0,
            therapySettingsRaw: Data(),
            settingsTimeZoneID: TimeZone.current.identifier,
            doseHistory: [])
        XCTAssertNil(grant.activeOverrideRaw,
                     "an absent field and 'no override active' are the same thing on the wire")
    }

    /// The override moves the target timeline the wrist hands the algorithm.
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

    /// A preset created the way the wrist creates it, with the same content as the granted fixture.
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

    /// 1. The override record round-trips in a real `HandbackOffer` with its identity.
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

    /// 3. A clear round-trips; last record in a drain wins.
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
        XCTAssertEqual(soloOutcome.overrideChange, .cleared(at: decodedClear.startDate), "stamped with the wrist's time")
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
        XCTAssertEqual(pairOutcome.overrideChange, .cleared(at: now),
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

    /// 2. Applying on the phone is idempotent across a replayed drain (committed IDs and syncIdentifier).
    func testPhoneApplyIsIdempotentAcrossAReplayedDrain() {
        let now = Date()
        let override = exercisePreset().createOverride(enactTrigger: .local, beginningAt: now)

        // (a) Replayed FINAL offer: the second delivery must apply nothing.
        let harness = PhoneOverrideHarness()
        defer { harness.tearDown() }
        let record = LoanDoseRecord.overrideChange(override, at: now, note: "🏃 Exercise")
        let event = LoanEvent(id: UUID(), seq: 1, provenance: .confirmed, record: record, loggedAt: now)
        harness.deliverFinalOffer(events: [event], at: now.addingTimeInterval(.hours(1)))
        XCTAssertEqual(harness.applied.count, 1, "the first drain applies the wrist override")
        XCTAssertEqual(harness.appliedAt.first?.timeIntervalSince(now) ?? .infinity, 0, accuracy: 0.01,
                       "at the time the wrist set it, not the hand-back an hour later")
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

        // ...but a clear against a phone that DOES hold one lands exactly once. A minute after
        // the override starts: the wire rounds dates to whole milliseconds.
        let liveHarness = PhoneOverrideHarness()
        defer { liveHarness.tearDown() }
        liveHarness.phoneOverride = override
        let clearEvent2 = LoanEvent(id: UUID(), seq: 1, provenance: .confirmed,
                                    record: .overrideChange(nil, at: now.addingTimeInterval(60)), loggedAt: now)
        liveHarness.deliverFinalOffer(events: [clearEvent2], at: now)
        XCTAssertEqual(liveHarness.applied.count, 1)
        XCTAssertNil(liveHarness.applied.first ?? nil, "the clear applies nil")
        XCTAssertNil(liveHarness.phoneOverride)

        // (d) A clear made before the phone's own override started does not end it.
        let newerHarness = PhoneOverrideHarness()
        defer { newerHarness.tearDown() }
        newerHarness.phoneOverride = override
        let olderClear = LoanEvent(id: UUID(), seq: 1, provenance: .confirmed,
                                   record: .overrideChange(nil, at: now.addingTimeInterval(-60)), loggedAt: now)
        newerHarness.deliverFinalOffer(events: [olderClear], at: now)
        XCTAssertTrue(newerHarness.applied.isEmpty, "the phone's newer override stands")
    }

    /// 4. A wrist-set override rescales schedules like a granted one (same history mechanism).
    func testWristSetOverrideRescalesSchedulesLikeAGrantedOne() {
        let now = Date()
        let start = now.addingTimeInterval(-.minutes(10))

        // Granted route: the phone's override arrives in the grant's own override fields.
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

        // The dosed schedules resolve through that same history.
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

/// The real `PodLoanPhoneController` in LOANED via persisted state, capturing override applies.
private final class PhoneOverrideHarness {

    /// Every applyScheduleOverride call, in order (`nil` element = a clear), and its change time.
    private(set) var applied: [TemporaryScheduleOverride?] = []
    private(set) var appliedAt: [Date] = []
    /// Stands in for `TemporaryPresetsManager.scheduleOverride`: read by the idempotency check,
    /// written by the apply.
    var phoneOverride: TemporaryScheduleOverride?

    private let lock = NSLock()
    private var controller: PodLoanPhoneController!
    private let stateDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

    init(epoch: Int = 1) {
        PhoneLog.directoryOverride = PodLoanPhoneControllerTests.phoneLogDirectory
        try? FileManager.default.createDirectory(at: stateDir, withIntermediateDirectories: true)
        // Persisted-state derivation is how this controller boots: write LOANED at `epoch` and
        // it comes up mid-loan, ready to receive the hand-back offer.
        var saved = PodLoanPhoneState()
        saved.phase = .loaned
        saved.epoch = epoch
        var store = PersistedProperty<[String: Any]>(key: PodLoanPhoneController.stateFileKey, directory: stateDir)
        store.wrappedValue = saved.rawValue

        var settings = LoopSettings()
        settings.basalRateSchedule = BasalRateSchedule(dailyItems: [RepeatingScheduleValue(startTime: 0, value: 1.0)])!

        controller = PodLoanPhoneController(dependencies: .init(
            pumpManager: { nil },
            settings: { settings },
            setAutomaticDosingPaused: { _ in },
            send: { _ in },
            addPumpEvents: { _, _, completion in completion(nil) },
            addCarb: { _, _, completion in completion(nil) },
            // Read by the controller's "already applied?" check.
            scheduleOverride: { [weak self] in self?.phoneOverride },
            applyScheduleOverride: { [weak self] override, changedAt in
                guard let self = self else { return }
                self.lock.lock()
                self.applied.append(override)
                self.appliedAt.append(changedAt)
                self.phoneOverride = override
                self.lock.unlock()
            },
            doseHistory: { _, completion in completion([]) },
            issueNotice: { _, _ in },
            stateDirectory: stateDir,
            addNotification: { _ in },
            removeNotifications: { _ in }))
    }

    /// Delivers a final offer and waits deterministically via `queue.sync` round-trips.
    func deliverFinalOffer(events: [LoanEvent], at date: Date) {
        let offer = HandbackOffer(epoch: 1, handedBackAt: date, finalStatus: nil, odometer: nil,
                                  events: events, tombstones: [], recovered: false, released: true)
        controller.handleIncoming(userInfo: try! LoanMessage.handbackOffer(offer).transportDictionary())
        for _ in 0..<4 { _ = controller.isPodLoanedOut }
    }

    func tearDown() {
        controller = nil
        try? FileManager.default.removeItem(at: stateDir)
    }
}
