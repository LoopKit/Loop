//
//  InsulinBookTests.swift
//  WatchAppTests
//
//  THE INSULIN BOOK THE ALGORITHM ACTUALLY READS.
//
//  On 2026-08-18 the wrist delivered three manual boluses totalling 3.40 U inside six minutes
//  and reported `IOB 0.00` with `insulin +0` after every one of them, republishing
//  `REC bolus 1.66 U` unchanged each time. A recommendation that cannot see the insulin already
//  given cannot decrement, so the wrist kept asking for the same dose again.
//
//  The cause was a seam, not arithmetic: two books, and the algorithm read the empty one. Since
//  2026-09-17 there is ONE book (R35 reversed): the watch's DoseStore, written by the watch's
//  pump manager through `hasNewPumpEvents` exactly as on the phone, seeded at the grant with the
//  phone's finished history through stock's remote-store door, and gated by stock's pump-data
//  recency rule. These tests drive that book through the two seams the session uses — the seed
//  and the pump manager's report — and ask whether delivered insulin reaches the input.
//
//  These tests pin the seam rather than the math. They ask the one question no existing test
//  asked: does insulin that was DELIVERED reach the input the algorithm reasons from? That is
//  pure computation — no pod, no BLE, no phone — so the simulator settles it.
//

import XCTest
import LoopKit
import LoopAlgorithm
import LoopCore
import HealthKit
@testable import WatchApp

final class InsulinBookTests: XCTestCase {

    private var cacheDir: URL!
    private var cacheStore: PersistenceController!

    override func setUp() {
        super.setUp()
        cacheDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("insulin-book-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        cacheStore = PersistenceController(directoryURL: cacheDir)
    }

    override func tearDown() {
        cacheStore = nil
        cacheDir = nil
        super.tearDown()
    }

    private func makeManager() async -> WatchLoopManager {
        let doseStore = await DoseStore(
            healthKitSampleStore: nil,
            cacheStore: cacheStore,
            longestEffectDuration: ExponentialInsulinModelPreset.rapidActingAdult.effectDuration,
            provenanceIdentifier: "InsulinBookTests")
        let glucoseStore = await GlucoseStore(
            healthKitSampleStore: nil,
            cacheStore: cacheStore,
            cacheLength: .hours(4),
            provenanceIdentifier: "InsulinBookTests")
        let carbStore = CarbStore(
            healthKitSampleStore: nil,
            cacheStore: cacheStore,
            cacheLength: .hours(24),
            provenanceIdentifier: "InsulinBookTests")

        var settings = LoopSettings()
        settings.basalRateSchedule = BasalRateSchedule(dailyItems: [RepeatingScheduleValue(startTime: 0, value: 0.7)])
        settings.insulinSensitivitySchedule = InsulinSensitivitySchedule(
            unit: .milligramsPerDeciliter, dailyItems: [RepeatingScheduleValue(startTime: 0, value: 70)])
        settings.carbRatioSchedule = CarbRatioSchedule(
            unit: .gram, dailyItems: [RepeatingScheduleValue(startTime: 0, value: 7)])
        settings.glucoseTargetRangeSchedule = GlucoseRangeSchedule(
            unit: .milligramsPerDeciliter,
            dailyItems: [RepeatingScheduleValue(startTime: 0, value: DoubleRange(minValue: 100, maxValue: 115))])
        settings.maximumBolus = 10
        settings.maximumBasalRatePerHour = 4
        settings.suspendThreshold = GlucoseThreshold(unit: .milligramsPerDeciliter, value: 80)

        return WatchLoopManager(doseStore: doseStore, glucoseStore: glucoseStore,
                                carbStore: carbStore, settings: settings)
    }

    /// A high, flat run — high enough that a correction is genuinely warranted, so the
    /// recommendation is a real number rather than a floor.
    private func seedGlucose(_ manager: WatchLoopManager, mgdl: Double = 250) async {
        let now = Date()
        let samples: [NewGlucoseSample] = (0..<12).reversed().map { i in
            NewGlucoseSample(
                date: now.addingTimeInterval(-Double(i) * 5 * 60),
                quantity: LoopQuantity(unit: .milligramsPerDeciliter, doubleValue: mgdl),
                condition: nil, trend: .flat, trendRate: nil,
                isDisplayOnly: false, wasUserEntered: false,
                syncIdentifier: "insulin-book-\(i)")
        }
        _ = try? await manager.glucoseStore.addGlucoseSamples(samples)
    }

    private func bolus(_ units: Double, minutesAgo: Double) -> DoseEntry {
        let start = Date().addingTimeInterval(-minutesAgo * 60)
        return DoseEntry(type: .bolus, startDate: start, endDate: start,
                         value: units, unit: .units,
                         decisionId: nil,
                         syncIdentifier: UUID().uuidString,
                         insulinType: .novolog)
    }

    /// The grant seed: the phone's finished history, through stock's remote-store door.
    private func seed(_ manager: WatchLoopManager, _ doses: [DoseEntry]) async {
        do { try await manager.seedInsulinHistory(doses) } catch { XCTFail("seed failed: \(error)") }
    }

    /// The pump manager's report — the ONE writer of the book. An empty report is what a status
    /// read with nothing new looks like, and it is what advances the recency clock the algorithm
    /// is gated on.
    private func report(_ manager: WatchLoopManager, _ doses: [DoseEntry] = []) async {
        let events = doses.map {
            NewPumpEvent(date: $0.startDate, dose: $0, raw: Data(UUID().uuidString.utf8), title: "\($0.type)")
        }
        do { try await manager.recordPumpEvents(events, lastReconciliation: Date(), replacePendingEvents: true) }
        catch { XCTFail("report failed: \(error)") }
    }

    private func settle(_ seconds: TimeInterval = 2.0) {
        let done = expectation(description: "settled")
        DispatchQueue.global().asyncAfter(deadline: .now() + seconds) { done.fulfill() }
        wait(for: [done], timeout: seconds + 5)
    }

    /// The IOB **the algorithm dosed with** — not the one on the glance.
    ///
    /// These were two different numbers from two different books, which is the trap that made
    /// the original defect so hard to see. `glanceData().iob` is evaluated live off the book and
    /// so was right all along; the field log shows it
    /// tracking every bolus (0.20 -> 1.85 -> 3.21) during the very session in which dosing
    /// reported `IOB 0.00`. Asserting on the glance therefore proves nothing about dosing —
    /// verified, not assumed: the first draft of these tests did exactly that and stayed GREEN
    /// with the defect deliberately reintroduced.
    ///
    /// `predictionBreakdown.iobUnits` carries `activeInsulin`, which is LoopAlgorithm's own
    /// output, so it is the figure that actually sized the dose.
    private func dosingIOB(_ manager: WatchLoopManager) -> Double? {
        manager.refreshPredictionForGlance()
        settle()
        return manager.glanceData().predictionBreakdown?.iobUnits
    }

    // MARK: -

    /// THE REGRESSION. A bolus in the book must appear as insulin on board.
    ///
    /// This is the whole defect in one assertion: before the fix the ledger held the dose, the
    /// algorithm read the store, and the answer came back 0.00 — for a bolus given two minutes
    /// earlier, of which essentially none has acted yet.
    func testASeededBolusBecomesInsulinOnBoard() async {
        let manager = await makeManager()
        await seedGlucose(manager)
        await seed(manager, [bolus(2.0, minutesAgo: 2)])
        await report(manager)   // the takeover's first status read

        guard let onBoard = dosingIOB(manager) else {
            return XCTFail("a seeded book with a pump report must produce an IOB figure, not nil")
        }
        XCTAssertGreaterThan(onBoard, 1.5,
                             "2.0 U given two minutes ago is almost entirely unabsorbed — an IOB near zero means the algorithm is not reading the book that holds it")
    }

    /// The enact path, not just the seed: the pump manager's report is what a delivered bolus
    /// becomes.
    func testAnEnactedBolusReachesTheAlgorithm() async {
        let manager = await makeManager()
        await seedGlucose(manager)
        await report(manager)

        let before = dosingIOB(manager) ?? 0
        await report(manager, [bolus(1.5, minutesAgo: 0)])
        let after = dosingIOB(manager) ?? 0

        XCTAssertGreaterThan(after - before, 1.0,
                             "delivering 1.5 U must move IOB — this is the seam between the book that records doses and the input the algorithm reasons from")
    }

    /// THE OVERBOLUS PATH, stated directly.
    ///
    /// The field symptom was not a wrong IOB in the abstract — it was `REC bolus 1.66 U`
    /// republished unchanged after each of three boluses. Insulin already on board must reduce
    /// what the wrist asks for next, or following the recommendation stacks doses.
    func testARecommendationDecrementsAfterInsulinIsGiven() async {
        let manager = await makeManager()
        await seedGlucose(manager)
        await report(manager)

        let empty = expectation(description: "first recommendation")
        var first: Double?
        manager.recommendManualBolus { if case .success(let r) = $0 { first = r.amount }; empty.fulfill() }
        wait(for: [empty], timeout: 20)

        guard let firstAmount = first, firstAmount > 0.2 else {
            return XCTFail("a flat 250 mg/dL against a 100-115 target must recommend a correction; got \(String(describing: first))")
        }

        await report(manager, [bolus(firstAmount, minutesAgo: 0)])

        let second = expectation(description: "second recommendation")
        var next: Double?
        manager.recommendManualBolus { if case .success(let r) = $0 { next = r.amount }; second.fulfill() }
        wait(for: [second], timeout: 20)

        guard let nextAmount = next else {
            return XCTFail("the second recommendation must compute")
        }
        XCTAssertLessThan(nextAmount, firstAmount - 0.1,
                          "taking \(firstAmount) U must reduce the next recommendation; an unchanged figure is the stacking path the wrist showed in the field")
    }

    /// ONE WRIST, ONE IOB.
    ///
    /// The defect's real signature was not a wrong number but two numbers: the glance read the
    /// ledger and showed 1.85 U while the algorithm read the empty store and dosed on 0.00, on
    /// the same screen in the same second. Whatever else changes, these two must not diverge —
    /// a wrist that displays one IOB and doses with another is worse than one that is simply
    /// wrong, because the displayed figure vouches for the hidden one.
    func testTheDisplayedIOBAndTheDosingIOBAreTheSameNumber() async {
        let manager = await makeManager()
        await seedGlucose(manager)
        await seed(manager, [bolus(2.0, minutesAgo: 3)])
        await report(manager)

        manager.refreshPredictionForGlance()
        settle()
        let data = manager.glanceData()

        guard let shown = data.iob, let dosed = data.predictionBreakdown?.iobUnits else {
            return XCTFail("both IOB figures must exist before they can be compared")
        }
        XCTAssertEqual(shown, dosed, accuracy: 0.05,
                       "the glance showed \(shown) U and the algorithm dosed on \(dosed) U — that is the 2026-08-18 defect exactly")
    }

    /// A RUNNING TEMP MUST NOT BREAK THE AUTOMATIC CYCLE.
    ///
    /// The pump manager reports a running temp as a MUTABLE full-span row (endDate = programmed
    /// end), so for the whole life of a temp the book holds a basal dose ending in the FUTURE. LoopAlgorithm
    /// refuses that outright on the automated path — `guard !input.recommendationType.automated ||
    /// basalEnd <= input.predictionStart else { throw AlgorithmError.futureBasalNotAllowed }`
    /// (LoopAlgorithm.swift:700-703) — and `.tempBasal.automated` is true.
    ///
    /// So an untrimmed book read makes EVERY automatic cycle decline for as long as a temp is
    /// running: the watch stops adjusting basal entirely while believing it is looping. This case
    /// was invisible to the first version of these tests because they all drove the .manualBolus
    /// path, where `automated` is false and the guard never fires.
    func testARunningTempDoesNotBreakTheAutomaticCycle() async {
        let manager = await makeManager()
        await seedGlucose(manager)

        // A temp accepted 5 minutes ago, running for another 25 — the ordinary steady state.
        let start = Date().addingTimeInterval(-5 * 60)
        let liveTemp = DoseEntry(type: .tempBasal,
                                 startDate: start,
                                 endDate: start.addingTimeInterval(30 * 60),
                                 value: 2.0, unit: .unitsPerHour,
                                 decisionId: nil,
                                 syncIdentifier: UUID().uuidString,
                                 insulinType: .novolog,
                                 isMutable: true)
        await report(manager, [liveTemp])

        manager.loop()
        settle(4.0)

        let error = manager.glanceData().lastLoopErrorText ?? ""
        XCTAssertFalse(error.lowercased().contains("futurebasal"),
                       "a temp still running must not make the automatic cycle decline; got: \(error)")
    }

    /// AN OVERRIDE MUST REACH DOSING, NOT JUST THE DISPLAY.
    ///
    /// `applyWristOverride` existed with ZERO call sites, so the dosing override had exactly one
    /// writer for a loan's lifetime — the grant intake — while the displayed override was driven
    /// independently off the WCSession round-trip. Activating a preset mid-loan redrew the chart
    /// band and printed the new insulin-needs percentage while `applyBasal`/`applySensitivity`/
    /// `applyCarbRatio` stayed identity maps: full-strength insulin toward the pre-exercise
    /// target, during exercise, with every screen saying otherwise.
    ///
    /// Asserted through the RECOMMENDATION rather than by reading the property back, because the
    /// property being set proves nothing about whether the schedules resolved through it. An
    /// override halving insulin needs doubles ISF, so the same excess glucose needs materially
    /// less insulin.
    func testAnOverrideChangesWhatDosingRecommends() async {
        let manager = await makeManager()
        await seedGlucose(manager)
        await report(manager)

        let unscaled = expectation(description: "no override")
        var before: Double?
        manager.recommendManualBolus { if case .success(let r) = $0 { before = r.amount }; unscaled.fulfill() }
        wait(for: [unscaled], timeout: 20)

        guard let baseline = before, baseline > 0.3 else {
            return XCTFail("a flat 250 mg/dL must recommend a correction to compare against; got \(String(describing: before))")
        }

        // "Insulin needs 50%" — the exercise shape. Basal x0.5, ISF and CR /0.5.
        //
        // INDEFINITE deliberately. A finite override scales only the part of the forecast it
        // covers, so a 1-hour override against a 6-hour insulin tail moves the recommendation by
        // ~14% rather than ~50% — correct behaviour, and a threshold written against the naive
        // halving fails on working code. Indefinite makes the assertion unambiguous.
        let override = TemporaryScheduleOverride(
            context: .custom,
            settings: TemporaryPresetSettings(unit: .milligramsPerDeciliter,
                                              targetRange: nil,
                                              insulinNeedsScaleFactor: 0.5),
            startDate: Date().addingTimeInterval(-60),
            duration: .indefinite,
            enactTrigger: .local,
            syncIdentifier: UUID())
        manager.applyWristOverride(override)
        settle()

        let scaled = expectation(description: "override active")
        var after: Double?
        manager.recommendManualBolus { if case .success(let r) = $0 { after = r.amount }; scaled.fulfill() }
        wait(for: [scaled], timeout: 20)

        guard let overridden = after else { return XCTFail("the recommendation must still compute under an override") }
        XCTAssertLessThan(overridden, baseline * 0.8,
                          "halving insulin needs doubles ISF, so the correction must fall well below \(baseline) U; got \(overridden) U — an unchanged figure means the override reached the display and not the dosing")
    }

    /// No pump report means NO DOSING — never a silent empty book.
    ///
    /// Stock's pump-data recency gate is the one-book form of R35's rule: an empty history and
    /// "no insulin on board" are the same number, and the second one licenses a full dose. A
    /// book the pod has not written to — however much history it was seeded with — cannot
    /// license a dose.
    func testWithoutAPumpReportTheAlgorithmRefusesRatherThanAssumingZero() async {
        let manager = await makeManager()
        await seedGlucose(manager)
        await seed(manager, [bolus(2.0, minutesAgo: 2)])
        // Deliberately no report — the pod has never spoken to this book.

        let done = expectation(description: "recommendation attempted")
        var failed = false
        manager.recommendManualBolus { if case .failure = $0 { failed = true }; done.fulfill() }
        wait(for: [done], timeout: 20)

        XCTAssertTrue(failed,
                      "with no pump report the watch must refuse; returning a recommendation here would be a dose computed against a book the pod never wrote")
    }

    /// The book is per loan: a reset empties it, and the next report starts a clean one.
    func testResettingTheBookEmptiesIt() async {
        let manager = await makeManager()
        await seedGlucose(manager)
        await seed(manager, [bolus(2.0, minutesAgo: 2)])
        await report(manager)
        XCTAssertGreaterThan(dosingIOB(manager) ?? 0, 1.5, "sanity: the seeded bolus is on board")

        await manager.resetInsulinBook(reason: "test")
        await report(manager)

        XCTAssertLessThan(dosingIOB(manager) ?? 0, 0.1,
                          "after a reset the book must be empty — a leftover row is the wipe leak this store used to have")
    }
}
