//
//  InsulinBookTests.swift
//  WatchAppTests
//
//  Does delivered insulin reach the algorithm's input? Drives the one book through its seed and
//  the pump manager's report (the defect pinned: three boluses, dosing IOB stayed 0.00).
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

    /// The book's one writer; an empty report advances the recency clock.
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

    /// The IOB the algorithm dosed with (`predictionBreakdown.iobUnits`), not the glance's.
    private func dosingIOB(_ manager: WatchLoopManager) -> Double? {
        manager.refreshPredictionForGlance()
        settle()
        return manager.glanceData().predictionBreakdown?.iobUnits
    }

    // MARK: -

    /// A bolus in the book appears as insulin on board.
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

    /// Insulin on board reduces the next recommendation.
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
                          "taking \(firstAmount) U must reduce the next recommendation; an unchanged figure is the stacking path")
    }

    /// The displayed and dosing IOB are the same number.
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
                       "the glance showed \(shown) U and the algorithm dosed on \(dosed) U — the defect this file pins")
    }

    /// A running temp is a future-ending row; untrimmed, LoopAlgorithm throws `futureBasalNotAllowed`
    /// on every automatic cycle.
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

    /// A wrist override changes the recommendation, not just the display.
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

        // Insulin needs 50%, indefinite so the effect is unambiguous.
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

    /// With no pump report the algorithm refuses rather than assuming zero IOB.
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
