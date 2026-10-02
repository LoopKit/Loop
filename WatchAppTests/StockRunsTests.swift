//
//  StockRunsTests.swift
//  WatchAppTests
//
//  The watch runs the algorithm three ways, each fed as stock feeds it: the automatic loop
//  (`loop()`), the recommended bolus (`recommendManualBolus`) and the display run
//  (`updateDisplayState`). Each run's result lands under its own name, so the glance reads the
//  display run, the diagnostics page the loop's, and the bolus run changes nothing displayed.
//  Also stock `loop()`'s recency checks, rounding, enact refusals and `lastLoopCompleted`, and
//  the display run's refresh on a store change, as stock's observers do.
//

import XCTest
import LoopKit
import LoopAlgorithm
import LoopCore
import HealthKit
@testable import OmnipodKit
@testable import WatchApp

/// Records what the loop asks the pod for, and sends nothing.
final class RecordingDoseEnactor: WatchDoseEnactor {
    private(set) var calls: [(bolus: Double?, tempBasal: TempBasalRecommendation?)] = []

    override func enact(decisionId: UUID?, bolus: Double?, tempBasal: TempBasalRecommendation?, with pumpManager: PumpManager) async throws {
        calls.append((bolus, tempBasal))
    }
}

final class StockRunsTests: XCTestCase {

    private var dir: URL!
    private var scheduler: RecordingWristAlertScheduler!

    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("stock-runs-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // The loop refreshes the dead-man watchdog when a pod is held; keep it off the real centre.
        scheduler = RecordingWristAlertScheduler()
        WristAlerts.scheduler = scheduler
    }

    override func tearDown() {
        WristAlerts.scheduler = UNUserNotificationCenter.current()
        scheduler = nil
        dir = nil
        super.tearDown()
    }

    private let mgdl = LoopUnit.milligramsPerDeciliter

    private func makeManager(maximumBasalRatePerHour: Double = 4) async -> WatchLoopManager {
        let cacheStore = PersistenceController(directoryURL: dir.appendingPathComponent(UUID().uuidString))
        let doseStore = await DoseStore(healthKitSampleStore: nil, cacheStore: cacheStore,
                                        longestEffectDuration: ExponentialInsulinModelPreset.rapidActingAdult.effectDuration,
                                        provenanceIdentifier: "StockRunsTests")
        let glucoseStore = await GlucoseStore(healthKitSampleStore: nil, cacheStore: cacheStore,
                                              cacheLength: TimeInterval(24 * 3600), provenanceIdentifier: "StockRunsTests")
        let carbStore = CarbStore(healthKitSampleStore: nil, cacheStore: cacheStore,
                                  cacheLength: TimeInterval(24 * 3600), provenanceIdentifier: "StockRunsTests")

        var settings = LoopSettings()
        settings.basalRateSchedule = BasalRateSchedule(dailyItems: [RepeatingScheduleValue(startTime: 0, value: 0.7)])
        settings.insulinSensitivitySchedule = InsulinSensitivitySchedule(
            unit: .milligramsPerDeciliter, dailyItems: [RepeatingScheduleValue(startTime: 0, value: 70)])
        settings.carbRatioSchedule = CarbRatioSchedule(unit: .gram, dailyItems: [RepeatingScheduleValue(startTime: 0, value: 7)])
        settings.glucoseTargetRangeSchedule = GlucoseRangeSchedule(
            unit: .milligramsPerDeciliter,
            dailyItems: [RepeatingScheduleValue(startTime: 0, value: DoubleRange(minValue: 100, maxValue: 115))])
        settings.maximumBolus = 10
        settings.maximumBasalRatePerHour = maximumBasalRatePerHour
        settings.suspendThreshold = GlucoseThreshold(unit: .milligramsPerDeciliter, value: 80)

        let defaults = UserDefaults(suiteName: "StockRunsTests-\(UUID().uuidString)")!
        return WatchLoopManager(doseStore: doseStore, glucoseStore: glucoseStore, carbStore: carbStore,
                                settings: settings, defaults: defaults,
                                stateDirectory: dir.appendingPathComponent(UUID().uuidString, isDirectory: true))
    }

    /// A flat hour of readings ending at `latest`.
    private func seedGlucose(_ manager: WatchLoopManager, mgdl value: Double = 250, latest: Date = Date()) async {
        let samples: [NewGlucoseSample] = (0..<12).reversed().map { i in
            NewGlucoseSample(date: latest.addingTimeInterval(-Double(i) * 5 * 60),
                             quantity: LoopQuantity(unit: .milligramsPerDeciliter, doubleValue: value),
                             condition: nil, trend: .flat, trendRate: nil,
                             isDisplayOnly: false, wasUserEntered: false,
                             syncIdentifier: "stock-runs-\(UUID().uuidString)")
        }
        _ = try? await manager.glucoseStore.addGlucoseSamples(samples)
    }

    private func addReading(_ manager: WatchLoopManager, at date: Date, mgdl value: Double = 250) async {
        _ = try? await manager.glucoseStore.addGlucoseSamples([NewGlucoseSample(
            date: date, quantity: LoopQuantity(unit: .milligramsPerDeciliter, doubleValue: value),
            condition: nil, trend: .flat, trendRate: nil, isDisplayOnly: false, wasUserEntered: false,
            syncIdentifier: "stock-runs-\(UUID().uuidString)")])
    }

    /// The pump manager's report; `reconciledAt` is the recency clock (`lastAddedPumpData`).
    private func report(_ manager: WatchLoopManager, _ doses: [DoseEntry] = [], reconciledAt: Date = Date()) async {
        let events = doses.map {
            NewPumpEvent(date: $0.startDate, dose: $0, raw: Data(UUID().uuidString.utf8), title: "\($0.type)")
        }
        do { try await manager.recordPumpEvents(events, lastReconciliation: reconciledAt, replacePendingEvents: true) }
        catch { XCTFail("report failed: \(error)") }
    }

    private func bolus(_ units: Double, start: Date, end: Date, mutable: Bool = false) -> DoseEntry {
        DoseEntry(type: .bolus, startDate: start, endDate: end, value: units, unit: .units,
                  decisionId: nil, syncIdentifier: UUID().uuidString, insulinType: .novolog, isMutable: mutable)
    }

    /// A temp accepted 5 minutes ago with 25 minutes still to run.
    private func runningTemp(_ rate: Double = 2.0, now: Date = Date()) -> DoseEntry {
        let start = now.addingTimeInterval(-.minutes(5))
        return DoseEntry(type: .tempBasal, startDate: start, endDate: start.addingTimeInterval(.minutes(30)),
                         value: rate, unit: .unitsPerHour, decisionId: nil,
                         syncIdentifier: UUID().uuidString, insulinType: .novolog, automatic: true, isMutable: true)
    }

    private func preset(_ context: TemporaryScheduleOverride.Context, target: DoubleRange?, scale: Double?) -> TemporaryScheduleOverride {
        TemporaryScheduleOverride(context: context,
                                  settings: TemporaryPresetSettings(unit: .milligramsPerDeciliter, targetRange: target,
                                                                    insulinNeedsScaleFactor: scale),
                                  startDate: Date().addingTimeInterval(-.minutes(30)), duration: .finite(TimeInterval(2 * 3600)),
                                  enactTrigger: .local, syncIdentifier: UUID())
    }

    private func carbs(_ grams: Double) -> NewCarbEntry {
        NewCarbEntry(quantity: LoopQuantity(unit: .gram, doubleValue: grams), startDate: Date(), foodType: nil, absorptionTime: TimeInterval(3 * 3600))
    }

    /// One automatic cycle, waited out on the manager's queue.
    private func runLoop(_ manager: WatchLoopManager) {
        manager.loop()
        manager.dataAccessQueue.sync {}
    }

    private func runDisplay(_ manager: WatchLoopManager) {
        manager.updateDisplayState()
        manager.dataAccessQueue.sync {}
    }

    private func loopInput(_ manager: WatchLoopManager) -> StoredDataAlgorithmInput? {
        manager.dataAccessQueue.sync { manager.loopRunState.input }
    }

    private func bolusInput(_ manager: WatchLoopManager, carbs entry: NewCarbEntry? = nil) throws -> StoredDataAlgorithmInput {
        try manager.dataAccessQueue.sync { try manager.manualBolusInput(potentialCarbEntry: entry) }
    }

    private func target(_ input: StoredDataAlgorithmInput) -> ClosedRange<Double>? {
        input.target.closestPrior(to: input.predictionStart).map {
            $0.value.lowerBound.doubleValue(for: .milligramsPerDeciliter)...$0.value.upperBound.doubleValue(for: .milligramsPerDeciliter)
        }
    }

    private func isf(_ input: StoredDataAlgorithmInput, at date: Date) -> Double? {
        input.sensitivity.first { $0.startDate <= date && date < $0.endDate }?.value.doubleValue(for: .milligramsPerDeciliter)
    }

    /// An Omnipod manager with a completed pod, optionally faulted or running a temp.
    private func makePump(fault: DetailedStatus? = nil, unfinalizedTemp: UnfinalizedDose? = nil) throws -> OmniPumpManager {
        var podState = PodState(address: 0x1f0b3557, firmwareVersion: "2.7.0", iFirmwareVersion: "2.7.0",
                                lotNo: 1, lotSeq: 1, insulinType: .novolog, podType: dashType)
        podState.setupProgress = .completed
        podState.fault = fault
        podState.unfinalizedTempBasal = unfinalizedTemp
        let raw: [String: Any] = ["basalSchedule": ["entries": [["rate": 0.7, "startTime": 0.0]]],
                                  "controllerId": UInt32(0x1234_5678), "podId": UInt32(0x1234_5679),
                                  "podState": podState.rawValue]
        return try XCTUnwrap(OmniPumpManager(rawState: raw))
    }

    // MARK: - 1. The automatic loop: stock `loop()`'s input

    /// A bolus in flight counts whole (stock's `[SimpleInsulinDose].trimmed(to:)` leaves boluses
    /// alone); a running temp is cut at now, since the loop is about to replace it.
    func testTheLoopCountsABolusInFlightWholeAndCutsARunningTempAtNow() async throws {
        let manager = await makeManager()
        await seedGlucose(manager)
        let now = Date()
        await report(manager, [bolus(2.0, start: now.addingTimeInterval(-60), end: now.addingTimeInterval(60), mutable: true),
                               runningTemp(now: now)])

        runLoop(manager)

        let input = try XCTUnwrap(loopInput(manager), "the loop ran the algorithm")
        let inFlight = try XCTUnwrap(input.doses.first { $0.deliveryType == .bolus })
        XCTAssertEqual(inFlight.volume, 2.0, accuracy: 0.001, "the whole bolus, not the minute delivered so far")
        XCTAssertGreaterThan(inFlight.endDate, input.predictionStart, "left as it is")
        let temp = try XCTUnwrap(input.doses.first { $0.deliveryType == .basal })
        XCTAssertLessThanOrEqual(temp.endDate, input.predictionStart, "the temp ends at now")
        XCTAssertEqual(temp.volume, 2.0 * 5 / 60, accuracy: 0.01, "five minutes of it")
        XCTAssertNil(manager.glanceData().lastLoopErrorText)
    }

    // MARK: - 2. The recommended bolus: stock `recommendManualBolus`'s input

    /// No trim: the bolus goes on top of a temp that keeps running, so the temp is credited
    /// through its scheduled end.
    func testTheBolusRecommendationCreditsARunningTempThroughItsEnd() async throws {
        let manager = await makeManager()
        await seedGlucose(manager)
        await report(manager, [runningTemp()])

        let input = try bolusInput(manager)
        let temp = try XCTUnwrap(input.doses.first { $0.deliveryType == .basal })
        XCTAssertGreaterThan(temp.endDate, input.predictionStart.addingTimeInterval(.minutes(20)), "through its end")
        XCTAssertEqual(temp.volume, 1.0, accuracy: 0.01, "all thirty minutes at 2 U/h")
        XCTAssertEqual(input.recommendationType, .manualBolus)
    }

    /// A pre-meal preset meeting a carb entry is treated as ending now: no preset target, and its
    /// scaling stops at now. Without a carb entry it stays.
    func testWithACarbEntryAPreMealPresetIsTreatedAsEndingNow() async throws {
        let manager = await makeManager()
        await seedGlucose(manager)
        await report(manager)
        manager.scheduleOverride = preset(.preMeal, target: DoubleRange(minValue: 80, maxValue: 80), scale: 0.5)

        let without = try bolusInput(manager)
        XCTAssertEqual(target(without), 80...80, "no carbs: the preset's target")
        XCTAssertEqual(try XCTUnwrap(isf(without, at: Date().addingTimeInterval(.minutes(30)))), 140, accuracy: 0.01,
                       "and its scaling ahead")

        let with = try bolusInput(manager, carbs: carbs(40))
        XCTAssertEqual(target(with), 100...115, "with carbs: the scheduled target")
        XCTAssertEqual(try XCTUnwrap(isf(with, at: Date().addingTimeInterval(.minutes(30)))), 70, accuracy: 0.01,
                       "and the preset's scaling ends at now")
        XCTAssertEqual(try XCTUnwrap(isf(with, at: Date().addingTimeInterval(-.minutes(10)))), 140, accuracy: 0.01,
                       "but still covers its past")
        XCTAssertEqual(with.carbEntries.count, 1, "the potential entry is in the input")
    }

    // MARK: - 3. Very high insulin needs

    /// An override over 165 % raises the suspend threshold to 110 in both dosing runs.
    func testAVeryHighInsulinNeedsOverrideRaisesTheSuspendThresholdInBothDosingRuns() async throws {
        let manager = await makeManager()
        await seedGlucose(manager)
        await report(manager)
        manager.scheduleOverride = preset(.custom, target: nil, scale: 1.8)

        runLoop(manager)
        let loop = try XCTUnwrap(loopInput(manager))
        XCTAssertEqual(try XCTUnwrap(loop.suspendThreshold).doubleValue(for: mgdl), 110, accuracy: 0.001, "the loop")

        let bolus = try bolusInput(manager)
        XCTAssertEqual(try XCTUnwrap(bolus.suspendThreshold).doubleValue(for: mgdl), 110, accuracy: 0.001, "the recommended bolus")
    }

    // MARK: - 4. The display run

    /// The glance shows the display run's numbers, and the display run is fed as stock's: a day
    /// of doses, ongoing doses projected, `.manualBolus`.
    func testTheGlanceShowsTheDisplayRun() async throws {
        let manager = await makeManager()
        await seedGlucose(manager)
        let now = Date()
        await report(manager, [bolus(1.0, start: now.addingTimeInterval(-TimeInterval(20 * 3600)), end: now.addingTimeInterval(-TimeInterval(20 * 3600))),
                               runningTemp(now: now)])

        runDisplay(manager)

        let state = manager.dataAccessQueue.sync { manager.displayState }
        let input = try XCTUnwrap(state.input)
        let output = try XCTUnwrap(state.output)
        XCTAssertEqual(input.recommendationType, .manualBolus)
        XCTAssertTrue(input.doses.contains { $0.deliveryType == .bolus && $0.startDate < now.addingTimeInterval(-TimeInterval(19 * 3600)) },
                      "doses back a day")
        XCTAssertTrue(input.doses.contains { $0.deliveryType == .basal && $0.endDate > now.addingTimeInterval(.minutes(20)) },
                      "the running temp projected to its end")

        let glance = manager.glanceData()
        XCTAssertEqual(try XCTUnwrap(glance.iob), try XCTUnwrap(output.activeInsulin), accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(glance.eventual).doubleValue(for: mgdl),
                       try XCTUnwrap(output.predictedGlucose.last).quantity.doubleValue(for: mgdl), accuracy: 0.0001)
        let cob: Double? = await withCheckedContinuation { done in manager.glanceCarbsOnBoard { done.resume(returning: $0) } }
        XCTAssertEqual(cob, output.activeCarbs)
    }

    /// Running the recommended bolus with a potential carb entry changes no displayed value.
    func testTheBolusRecommendationChangesNothingDisplayed() async throws {
        let manager = await makeManager()
        await seedGlucose(manager, mgdl: 140)
        await report(manager)
        runLoop(manager)   // the loop and the display run both

        let before = manager.glanceData()
        let cobBefore: Double? = await withCheckedContinuation { done in manager.glanceCarbsOnBoard { done.resume(returning: $0) } }
        XCTAssertNotNil(before.eventual)
        XCTAssertNotNil(before.iob)

        let plain = expectation(description: "no carbs")
        var withoutCarbs: Double?
        manager.recommendManualBolus { if case .success(let r) = $0 { withoutCarbs = r.amount }; plain.fulfill() }
        let meal = expectation(description: "potential carbs")
        var withCarbs: Double?
        manager.recommendManualBolus(potentialCarbEntry: carbs(60)) { if case .success(let r) = $0 { withCarbs = r.amount }; meal.fulfill() }
        await fulfillment(of: [plain, meal], timeout: 20)
        XCTAssertGreaterThan(try XCTUnwrap(withCarbs), try XCTUnwrap(withoutCarbs) + 1, "the carbs reached that run")

        let after = manager.glanceData()
        let cobAfter: Double? = await withCheckedContinuation { done in manager.glanceCarbsOnBoard { done.resume(returning: $0) } }
        XCTAssertEqual(after.eventual, before.eventual, "the glance eventual is the display run's, untouched")
        XCTAssertEqual(after.iob, before.iob)
        XCTAssertEqual(cobAfter, cobBefore)
        XCTAssertEqual(after.dosingEventual, before.dosingEventual, "and the loop's run is untouched too")
    }

    // MARK: - 5. The diagnostics page

    /// The diagnostics eventual is the automatic loop's last predicted value, kept apart from
    /// the display run's: with a high temp running, the display credits all of it.
    func testTheDiagnosticsEventualIsTheLoopRunsLastPrediction() async throws {
        let manager = await makeManager()
        await seedGlucose(manager, mgdl: 140)
        await report(manager, [runningTemp(3.5)])

        runLoop(manager)

        let loopEventual = try XCTUnwrap(manager.dataAccessQueue.sync { manager.loopRunState.output?.predictedGlucose.last })
        let glance = manager.glanceData()
        XCTAssertEqual(try XCTUnwrap(glance.dosingEventual).doubleValue(for: mgdl),
                       loopEventual.quantity.doubleValue(for: mgdl), accuracy: 0.0001)
        XCTAssertGreaterThan(try XCTUnwrap(glance.dosingEventual).doubleValue(for: mgdl),
                             try XCTUnwrap(glance.eventual).doubleValue(for: mgdl) + 5,
                             "the loop's run cuts the temp at now; the display run credits the rest of it")
    }

    // MARK: - Recency checks, as stock `loop()`

    /// Pump data older than 15 minutes: the loop refuses, the recommended bolus does not
    /// (stock's `recommendManualBolus` has no pump-data check).
    func testOldPumpDataStopsTheLoopButNotTheBolusRecommendation() async throws {
        let manager = await makeManager()
        await seedGlucose(manager)
        await report(manager, reconciledAt: Date().addingTimeInterval(-.minutes(20)))

        runLoop(manager)
        let error = manager.glanceData().lastLoopErrorText ?? ""
        XCTAssertTrue(error.contains("pumpDataTooOld"), "the loop refuses; got: \(error)")

        let done = expectation(description: "recommendation")
        var amount: Double?
        manager.recommendManualBolus { if case .success(let r) = $0 { amount = r.amount }; done.fulfill() }
        await fulfillment(of: [done], timeout: 20)
        XCTAssertGreaterThan(try XCTUnwrap(amount, "the recommended bolus is produced"), 0)
    }

    /// Stock's future-glucose check, on the loop's input: more than 15 minutes ahead is refused,
    /// a few minutes ahead is not.
    func testTheLoopRefusesGlucoseMoreThanFifteenMinutesInTheFuture() async throws {
        let manager = await makeManager()
        await seedGlucose(manager)
        await report(manager)
        let now = Date()
        let input = try await manager.fetchData(for: now)

        func withLatest(at date: Date) -> StoredDataAlgorithmInput {
            var copy = input
            copy.glucoseHistory.append(StoredGlucoseSample(startDate: date, quantity: LoopQuantity(unit: .milligramsPerDeciliter, doubleValue: 250)))
            return copy
        }
        let far = manager.loopInputRecencyError(withLatest(at: now.addingTimeInterval(.minutes(16))), at: now)
        XCTAssertTrue(String(describing: far).contains("invalidFutureGlucose"), "16 min ahead: refused; got \(String(describing: far))")
        XCTAssertNil(manager.loopInputRecencyError(withLatest(at: now.addingTimeInterval(.minutes(4))), at: now),
                     "4 min ahead: within the recency interval")
    }

    /// As in stock, `fetchData` queries glucose up to the base time, so a future-dated reading
    /// never reaches the loop's input and the loop runs on the readings before it.
    func testAFutureReadingDoesNotReachTheLoopsInput() async throws {
        let manager = await makeManager()
        await seedGlucose(manager)
        await report(manager)
        await addReading(manager, at: Date().addingTimeInterval(.minutes(16)))

        runLoop(manager)

        let input = try XCTUnwrap(loopInput(manager))
        XCTAssertLessThan(try XCTUnwrap(input.glucoseHistory.last).startDate, input.predictionStart)
        XCTAssertNil(manager.glanceData().lastLoopErrorText)
    }

    // MARK: - Rounding, as stock

    /// The pump manager's rounding (Omnipod rounds down), not the nearest supported rate.
    func testARecommendationBetweenTwoSupportedRatesIsRoundedDown() async throws {
        let manager = await makeManager(maximumBasalRatePerHour: 4.03)
        manager.pumpManager = try makePump()
        XCTAssertEqual(manager.roundBasalRate(unitsPerHour: 0.74), 0.70, accuracy: 0.0001)

        // End to end: a correction clamped at 4.03 U/h goes to the pod as 4.00, not 4.05.
        await seedGlucose(manager, mgdl: 350)
        await report(manager)
        runLoop(manager)
        let rate = try XCTUnwrap(manager.dataAccessQueue.sync { manager.lastRecommendation?.basalAdjustment.unitsPerHour })
        XCTAssertEqual(rate, 4.00, accuracy: 0.0001)
    }

    // MARK: - Enact refusals, as stock `loop()`

    private func pendingTemp(_ manager: WatchLoopManager) {
        let recommendation = AutomaticDoseRecommendation(basalAdjustment: TempBasalRecommendation(unitsPerHour: 2.0, duration: .minutes(30)),
                                                         direction: .increase)
        manager.recommendedAutomaticDose = (recommendation: recommendation, enactTempBasal: true, date: manager.now())
    }

    func testAManualTempIsLeftRunning() async throws {
        let manager = await makeManager()
        let manual = UnfinalizedDose(decisionId: nil, tempBasalRate: 0.5, startTime: Date().addingTimeInterval(-.minutes(5)),
                                     duration: .minutes(60), isHighTemp: false, automatic: false,
                                     scheduledCertainty: .certain, insulinType: .novolog)
        let pump = try makePump(unfinalizedTemp: manual)
        let enactor = RecordingDoseEnactor()
        manager.pumpManager = pump
        manager.doseEnactor = enactor

        let error = manager.dataAccessQueue.sync { () -> WatchLoopError? in
            pendingTemp(manager)
            return manager.enactRecommendedAutomaticDose()
        }

        guard case .manualTempBasalRunning? = error else { return XCTFail("refused as stock does; got \(String(describing: error))") }
        XCTAssertTrue(enactor.calls.isEmpty, "no temp sent")
        guard case .tempBasal(let dose)? = pump.status.basalDeliveryState else { return XCTFail("the manual temp stays") }
        XCTAssertEqual(dose.unitsPerHour, 0.5, accuracy: 0.001)
        XCTAssertEqual(dose.automatic, false)
    }

    func testAFaultedPodIsRefusedWithoutCallingTheEnactor() async throws {
        let manager = await makeManager()
        let status = try DetailedStatus(encodedData: Data([0x02, 0x0d, 0, 0, 0, 0x06, 0, 0, 0x8f, 0, 0, 0x03, 0xff,
                                                           0, 0, 0, 0, 0x03, 0xa2, 0x03, 0x86, 0xa0]))
        let enactor = RecordingDoseEnactor()
        manager.pumpManager = try makePump(fault: status)
        manager.doseEnactor = enactor

        let error = manager.dataAccessQueue.sync { () -> WatchLoopError? in
            pendingTemp(manager)
            return manager.enactRecommendedAutomaticDose()
        }

        guard case .pumpInoperable? = error else { return XCTFail("refused as stock does; got \(String(describing: error))") }
        XCTAssertTrue(enactor.calls.isEmpty, "the enactor is never called")
    }

    // MARK: - lastLoopCompleted, as stock

    func testAnOpenLoopCycleDoesNotMoveLastLoopCompleted() async {
        let manager = await makeManager()
        await seedGlucose(manager)
        await report(manager)
        XCTAssertNil(manager.lastLoopCompleted)

        runLoop(manager)

        XCTAssertNil(manager.glanceData().lastLoopErrorText, "the cycle itself succeeded")
        XCTAssertNil(manager.lastLoopCompleted, "stock moves it only after a closed-loop enact")
    }

    func testAClosedLoopCycleMovesLastLoopCompleted() async throws {
        let manager = await makeManager()
        await seedGlucose(manager)
        await report(manager)
        let enactor = RecordingDoseEnactor()
        manager.pumpManager = try makePump()
        manager.doseEnactor = enactor
        manager.setClosedLoopEnabled(true, reason: "test")

        let before = Date()
        runLoop(manager)

        XCTAssertNil(manager.glanceData().lastLoopErrorText)
        XCTAssertFalse(enactor.calls.isEmpty, "the temp was enacted")
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(manager.lastLoopCompleted), before)
    }

    // MARK: - The display run refreshes when stock's does

    /// Polls the display run, with no loop cycle, until `condition` holds.
    private func waitForDisplay(_ manager: WatchLoopManager, _ label: String, timeout: TimeInterval = 10,
                                _ condition: @escaping (AlgorithmDisplayState) -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if manager.dataAccessQueue.sync(execute: { condition(manager.displayState) }) { return }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTFail(label)
    }

    /// A bolus lands in the dose store: the glance IOB follows without waiting for a cycle.
    func testADoseStoreChangeUpdatesTheGlanceIOBWithoutALoopCycle() async throws {
        let manager = await makeManager()
        manager.pumpManager = try makePump()
        await seedGlucose(manager)
        await report(manager)
        runDisplay(manager)
        let before = manager.glanceData().iob ?? 0

        let now = Date()
        await report(manager, [bolus(2.0, start: now.addingTimeInterval(-60), end: now)])

        await waitForDisplay(manager, "the dose store's change refreshed the display run") {
            ($0.activeInsulin?.value ?? 0) > before + 1.5
        }
        XCTAssertGreaterThan(manager.glanceData().iob ?? 0, before + 1.5, "the glance reads it")
        XCTAssertNil(loopInput(manager), "no loop cycle ran")
    }

    /// A carb entry lands in the carb store: the glance COB follows without waiting for a cycle.
    func testACarbEntryUpdatesTheGlanceCOBWithoutALoopCycle() async throws {
        let manager = await makeManager()
        manager.pumpManager = try makePump()
        await seedGlucose(manager)
        await report(manager)
        runDisplay(manager)
        XCTAssertEqual(manager.dataAccessQueue.sync { manager.displayState.activeCarbs?.value } ?? 0, 0, accuracy: 0.01)

        _ = try await manager.carbStore.addCarbEntry(carbs(30))

        await waitForDisplay(manager, "the carb store's change refreshed the display run") {
            ($0.activeCarbs?.value ?? 0) > 20
        }
        let done = expectation(description: "glance COB")
        var cob: Double?
        manager.glanceCarbsOnBoard { cob = $0; done.fulfill() }
        await fulfillment(of: [done], timeout: 5)
        XCTAssertGreaterThan(try XCTUnwrap(cob), 20, "the glance reads it")
        XCTAssertNil(loopInput(manager), "no loop cycle ran")
    }

    /// Between loans (no pod) a store change does not refresh the display run, as before.
    func testBetweenLoansAStoreChangeLeavesTheDisplayRunAlone() async throws {
        let manager = await makeManager()
        await seedGlucose(manager)
        await report(manager)
        runDisplay(manager)
        let before = manager.dataAccessQueue.sync { manager.displayState.input?.predictionStart }

        let now = Date()
        await report(manager, [bolus(2.0, start: now.addingTimeInterval(-60), end: now)])
        try await Task.sleep(nanoseconds: 1_000_000_000)

        XCTAssertEqual(manager.dataAccessQueue.sync { manager.displayState.input?.predictionStart }, before)
    }

    @MainActor
    func testTheGlanceRingIsFreshInOpenLoopWithAnOldLastLoopCompleted() async {
        let manager = await makeManager()
        manager.dataAccessQueue.sync { () -> Void in manager.lastLoopCompleted = Date().addingTimeInterval(-TimeInterval(2 * 3600)) }

        let open = GlanceViewModel.activeState(data: manager.glanceData(), cob: nil, now: Date())
        XCTAssertEqual(open.loopFreshness, .fresh, "stock: open loop presents fresh")

        manager.setClosedLoopEnabled(true, reason: "test")
        let closed = GlanceViewModel.activeState(data: manager.glanceData(), cob: nil, now: Date())
        XCTAssertEqual(closed.loopFreshness, .stale, "closed loop ages from the last cycle")
    }
}
