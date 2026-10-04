//
//  StockRunsTests.swift
//  WatchAppTests
//
//  The watch runs the algorithm three ways, each fed as stock feeds it: the automatic loop
//  (`loop()`), the recommended bolus (`recommendManualBolus`) and the display run
//  (`updateDisplayState`). Each run's result lands under its own name, so the glance reads the
//  display run, the diagnostics page the loop's, and the bolus run changes nothing displayed.
//  Also stock `loop()`'s recency checks, rounding, enact refusals and `lastLoopCompleted`, the
//  display run's refresh on a store change, as stock's observers do, and stock's dosing decisions
//  ("loop", "updateRemoteRecommendation", "watchBolus") and their one trip home at a loan's close.
//

import XCTest
import LoopKit
import LoopAlgorithm
import LoopCore
import HealthKit
@testable import OmnipodKit
@testable import WatchApp

/// Records what the loop asks the pod for, and sends nothing.
final class RecordingDoseEnactor: DoseEnactor {
    private(set) var calls: [(bolus: Double?, tempBasal: TempBasalRecommendation?)] = []
    private(set) var decisionIds: [UUID?] = []

    override func enact(decisionId: UUID?, bolus: Double?, tempBasal: TempBasalRecommendation?, with pumpManager: PumpManager) async throws {
        calls.append((bolus, tempBasal))
        decisionIds.append(decisionId)
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
        let dosingDecisionStore = DosingDecisionStore(store: cacheStore, expireAfter: TimeInterval(24 * 3600))

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
                                dosingDecisionStore: dosingDecisionStore,
                                settings: settings, defaults: defaults,
                                stateDirectory: dir.appendingPathComponent(UUID().uuidString, isDirectory: true))
    }

    /// A flat hour of readings ending at `latest` (or `count` readings, five minutes apart).
    private func seedGlucose(_ manager: WatchLoopManager, mgdl value: Double = 250, latest: Date = Date(), count: Int = 12) async {
        let samples: [NewGlucoseSample] = (0..<count).reversed().map { i in
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
    private func makePump(fault: DetailedStatus? = nil, unfinalizedTemp: UnfinalizedDose? = nil,
                          unfinalizedBolus: UnfinalizedDose? = nil) throws -> OmniPumpManager {
        var podState = PodState(address: 0x1f0b3557, firmwareVersion: "2.7.0", iFirmwareVersion: "2.7.0",
                                lotNo: 1, lotSeq: 1, insulinType: .novolog, podType: dashType)
        podState.setupProgress = .completed
        podState.fault = fault
        podState.unfinalizedTempBasal = unfinalizedTemp
        podState.unfinalizedBolus = unfinalizedBolus
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
        manager.recommendManualBolus { if case .success(let r) = $0 { withoutCarbs = r?.amount }; plain.fulfill() }
        let meal = expectation(description: "potential carbs")
        var withCarbs: Double?
        manager.recommendManualBolus(potentialCarbEntry: carbs(60)) { if case .success(let r) = $0 { withCarbs = r?.amount }; meal.fulfill() }
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
        manager.recommendManualBolus { if case .success(let r) = $0 { amount = r?.amount }; done.fulfill() }
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

    private let highTemp = TempBasalRecommendation(unitsPerHour: 2.0, duration: .minutes(30))

    func testAManualTempIsLeftRunning() async throws {
        let manager = await makeManager()
        let manual = UnfinalizedDose(decisionId: nil, tempBasalRate: 0.5, startTime: Date().addingTimeInterval(-.minutes(5)),
                                     duration: .minutes(60), isHighTemp: false, automatic: false,
                                     scheduledCertainty: .certain, insulinType: .novolog)
        let pump = try makePump(unfinalizedTemp: manual)
        let enactor = RecordingDoseEnactor()
        manager.pumpManager = pump
        manager.doseEnactor = enactor

        let error = manager.dataAccessQueue.sync { () -> LoopError? in
            manager.enactAutomaticDose(bolus: nil, tempBasal: highTemp, decisionId: nil)
        }

        guard case .manualTempBasalRunning? = error else { return XCTFail("refused as stock does; got \(String(describing: error))") }
        XCTAssertTrue(enactor.calls.isEmpty, "no temp sent")
        guard case .tempBasal(let dose)? = pump.status.basalDeliveryState else { return XCTFail("the manual temp stays") }
        XCTAssertEqual(dose.unitsPerHour, 0.5, accuracy: 0.001)
        XCTAssertEqual(dose.automatic, false)
    }

    /// As stock's `loop()`, the refusals run on a cycle with nothing to send, so it is not an OK cycle.
    func testTheRefusalsRunWithNothingToSend() async throws {
        let manager = await makeManager()
        let manual = UnfinalizedDose(decisionId: nil, tempBasalRate: 0.5, startTime: Date().addingTimeInterval(-.minutes(5)),
                                     duration: .minutes(60), isHighTemp: false, automatic: false,
                                     scheduledCertainty: .certain, insulinType: .novolog)
        manager.pumpManager = try makePump(unfinalizedTemp: manual)

        let error = manager.dataAccessQueue.sync { () -> LoopError? in
            manager.enactAutomaticDose(bolus: nil, tempBasal: nil, decisionId: nil)
        }

        guard case .manualTempBasalRunning? = error else { return XCTFail("refused as stock does; got \(String(describing: error))") }
    }

    func testAFaultedPodIsRefusedWithoutCallingTheEnactor() async throws {
        let manager = await makeManager()
        let status = try DetailedStatus(encodedData: Data([0x02, 0x0d, 0, 0, 0, 0x06, 0, 0, 0x8f, 0, 0, 0x03, 0xff,
                                                           0, 0, 0, 0, 0x03, 0xa2, 0x03, 0x86, 0xa0]))
        let enactor = RecordingDoseEnactor()
        manager.pumpManager = try makePump(fault: status)
        manager.doseEnactor = enactor

        let error = manager.dataAccessQueue.sync { () -> LoopError? in
            manager.enactAutomaticDose(bolus: nil, tempBasal: highTemp, decisionId: nil)
        }

        guard case .pumpInoperable? = error else { return XCTFail("refused as stock does; got \(String(describing: error))") }
        XCTAssertTrue(enactor.calls.isEmpty, "the enactor is never called")
    }

    // MARK: - Opening the loop, as stock `cancelActiveTempBasal`

    func testOpeningTheLoopCancelsAnAutomaticTempAndStoresTheDecision() async throws {
        let manager = await makeManager()
        let automatic = UnfinalizedDose(decisionId: nil, tempBasalRate: 2.0, startTime: Date().addingTimeInterval(-.minutes(5)),
                                        duration: .minutes(30), isHighTemp: true, automatic: true,
                                        scheduledCertainty: .certain, insulinType: .novolog)
        let enactor = RecordingDoseEnactor()
        manager.pumpManager = try makePump(unfinalizedTemp: automatic)
        manager.doseEnactor = enactor
        manager.setClosedLoopEnabled(true, reason: "test")

        manager.setClosedLoopEnabled(false, reason: "test")
        manager.dataAccessQueue.sync {}

        XCTAssertEqual(enactor.calls.count, 1, "one cancel")
        XCTAssertEqual(enactor.calls.first?.tempBasal, .cancel)
        let decisions = try await storedDecisions(manager)
        let decision = try XCTUnwrap(decisions.first { $0.reason == "automaticDosingDisabled" })
        XCTAssertEqual(enactor.decisionIds.first ?? nil, decision.id, "the cancel carries the decision's id")
    }

    func testOpeningTheLoopWithNoAutomaticTempSendsNothing() async throws {
        let manager = await makeManager()
        let enactor = RecordingDoseEnactor()
        manager.pumpManager = try makePump()
        manager.doseEnactor = enactor
        manager.setClosedLoopEnabled(true, reason: "test")

        manager.setClosedLoopEnabled(false, reason: "test")
        manager.dataAccessQueue.sync {}

        XCTAssertTrue(enactor.calls.isEmpty, "stock cancels only a running automatic temp")
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

    // MARK: - Stock's dosing decisions

    /// Everything the watch's decision store holds, in the order stored.
    private func storedDecisions(_ manager: WatchLoopManager) async throws -> [StoredDosingDecision] {
        let store = try XCTUnwrap(manager.dosingDecisionStore)
        return try await withCheckedThrowingContinuation { continuation in
            store.executeDosingDecisionQuery(fromQueryAnchor: nil, limit: 1000) { result in
                switch result {
                case .success(_, let decisions): continuation.resume(returning: decisions)
                case .failure(let error): continuation.resume(throwing: error)
                }
            }
        }
    }

    /// A closed-loop cycle stores one "loop" decision, as stock builds it, and the dose it enacts
    /// carries that decision's id.
    func testAClosedLoopCycleStoresOneLoopDecisionWhoseIdTheDoseCarries() async throws {
        let manager = await makeManager()
        await seedGlucose(manager)
        await report(manager)
        let enactor = RecordingDoseEnactor()
        manager.pumpManager = try makePump()
        manager.doseEnactor = enactor
        manager.setClosedLoopEnabled(true, reason: "test")

        runLoop(manager)

        let loops = try await storedDecisions(manager).filter { $0.reason == "loop" }
        XCTAssertEqual(loops.count, 1, "one per cycle")
        let decision = try XCTUnwrap(loops.first)
        XCTAssertEqual(enactor.decisionIds.count, 1, "one command")
        XCTAssertEqual(enactor.decisionIds.first ?? nil, decision.id, "the dose carries the decision's id")
        XCTAssertTrue(decision.errors.isEmpty)
        XCTAssertNotNil(decision.automaticDoseRecommendation, "updateFrom: the recommendation")
        XCTAssertEqual(decision.enactedTempBasal, enactor.calls.first?.tempBasal, "what went to the pod")
        XCTAssertNotNil(decision.predictedGlucose, "updateFrom: the forecast")
        XCTAssertNotNil(decision.insulinOnBoard)
        XCTAssertFalse(decision.historicalGlucose?.isEmpty ?? true)
        XCTAssertNotNil(decision.settings, "stock's settings reference")
    }

    /// A cycle that ends in error still stores its "loop" decision, with the error.
    func testAnErrorCycleStillStoresALoopDecisionWithTheError() async throws {
        let manager = await makeManager()
        await seedGlucose(manager)
        await report(manager, reconciledAt: Date().addingTimeInterval(-.minutes(20)))
        let enactor = RecordingDoseEnactor()
        manager.pumpManager = try makePump()
        manager.doseEnactor = enactor
        manager.setClosedLoopEnabled(true, reason: "test")

        runLoop(manager)

        let loops = try await storedDecisions(manager).filter { $0.reason == "loop" }
        XCTAssertEqual(loops.count, 1, "stored on the error arm too")
        let error = try XCTUnwrap(loops.first?.errors.first)
        XCTAssertEqual(error.id, "pumpDataTooOld", "stock's id")
        XCTAssertTrue(enactor.calls.isEmpty, "nothing sent")
    }

    /// Each cycle ends with the display run's "updateRemoteRecommendation" decision, forced, after
    /// the cycle's "loop" decision: stock's pair.
    func testACycleStoresAnUpdateRemoteRecommendationAfterItsLoopDecision() async throws {
        let manager = await makeManager()
        await seedGlucose(manager)
        await report(manager)
        manager.pumpManager = try makePump()

        runLoop(manager)

        let decisions = try await storedDecisions(manager)
        let loopIndex = try XCTUnwrap(decisions.firstIndex { $0.reason == "loop" })
        let remote = try XCTUnwrap(decisions[(loopIndex + 1)...].first { $0.reason == "updateRemoteRecommendation" },
                                   "stored after the loop decision; got \(decisions.map(\.reason))")
        XCTAssertNotNil(remote.predictedGlucose)
        XCTAssertNotNil(remote.manualBolusRecommendation, "the display run's manual recommendation")
        XCTAssertNotNil(remote.pumpManagerStatus)
        XCTAssertNotNil(remote.controllerStatus)
    }

    /// Between loans (no pod) the watch stores no decisions: the phone is the controller.
    func testWithoutAPodNoDecisionIsStored() async throws {
        let manager = await makeManager()
        await seedGlucose(manager)
        await report(manager)

        runLoop(manager)

        let decisions = try await storedDecisions(manager)
        XCTAssertTrue(decisions.isEmpty, "got \(decisions.map(\.reason))")
    }

    /// A wrist bolus stores stock's watchBolus decision (the recommendation shown, the amount, the
    /// carb entry it came with) before the command, and the command carries its id.
    func testAWristBolusStoresAWatchBolusDecisionWhoseIdTheBolusCarries() async throws {
        let manager = await makeManager()
        await seedGlucose(manager)
        await report(manager)
        manager.pumpManager = try makePump()
        var commanded: (id: UUID?, units: Double)?
        manager.enactBolusCommand = { _, decisionId, units, _, completion in
            commanded = (decisionId, units)
            completion(nil)
        }
        runDisplay(manager)
        let meal = carbs(30)

        let shown = expectation(description: "recommendation")
        manager.recommendManualBolus(potentialCarbEntry: meal) { _ in shown.fulfill() }
        await fulfillment(of: [shown], timeout: 20)

        let mealSyncId = UUID().uuidString
        let stored = try await withCheckedThrowingContinuation { continuation in
            manager.carbStore.addCarbEntry(meal, syncIdentifier: mealSyncId) { continuation.resume(with: $0) }
        }

        let accepted = expectation(description: "bolus")
        manager.enactManualBolus(units: 1.0, activationType: .manualNoRecommendation, carbEntry: meal,
                                 storedCarbEntry: stored) { _ in accepted.fulfill() }
        await fulfillment(of: [accepted], timeout: 20)
        manager.dataAccessQueue.sync {}

        let bolusDecisions = try await storedDecisions(manager).filter { $0.reason == "watchBolus" }
        XCTAssertEqual(bolusDecisions.count, 1)
        let decision = try XCTUnwrap(bolusDecisions.first)
        XCTAssertEqual(try XCTUnwrap(commanded).id, decision.id, "the bolus carries the decision's id")
        XCTAssertEqual(decision.manualBolusRequested, 1.0)
        XCTAssertEqual(decision.carbEntry?.quantity.doubleValue(for: .gram) ?? 0, 30, accuracy: 0.001)
        XCTAssertEqual(decision.carbEntry?.syncIdentifier, mealSyncId, "the entry as stored, as stock records it")
        XCTAssertNotNil(decision.manualBolusRecommendation, "the recommendation shown with this carb entry")
        XCTAssertNotNil(decision.predictedGlucose)
        XCTAssertNotNil(decision.settings)
    }

    /// At a loan's close the decisions go home once, in one file: a second close sends only what
    /// was stored since. Also logs the measured size.
    func testALoansDecisionsGoHomeOnceAtItsClose() async throws {
        let manager = await makeManager()
        // The four hours the watch's glucose store keeps, varied as real readings are (a flat
        // trace would encode smaller than any real one).
        let latest = Date()
        let readings: [NewGlucoseSample] = (0..<48).reversed().map { (i: Int) -> NewGlucoseSample in
            let wave: Double = 40 * sin(Double(i) / 5)
            let mgdl: Double = 180 + wave + Double(i % 7)
            return NewGlucoseSample(date: latest.addingTimeInterval(-Double(i) * 5 * 60),
                             quantity: LoopQuantity(unit: .milligramsPerDeciliter, doubleValue: mgdl),
                             condition: nil, trend: .flat, trendRate: nil, isDisplayOnly: false, wasUserEntered: false,
                             syncIdentifier: "stock-runs-\(UUID().uuidString)")
        }
        _ = try await manager.glucoseStore.addGlucoseSamples(readings)
        await report(manager)
        manager.pumpManager = try makePump()
        manager.doseEnactor = RecordingDoseEnactor()
        manager.setClosedLoopEnabled(true, reason: "test")
        runLoop(manager)
        runLoop(manager)

        let controller = PodLoanWatchController(loopManager: manager, journal: LoanEventJournal(directory: dir),
                                                stateDirectory: dir.appendingPathComponent(UUID().uuidString, isDirectory: true))
        let lock = NSLock()
        var files: [(data: Data, metadata: [String: Any])] = []
        controller.transferLoanHistory = { data, metadata in
            lock.lock(); files.append((data, metadata)); lock.unlock()
            return true
        }
        func sendAndSettle() async {
            controller.queue.sync { controller.sendLoanHistoryHome(epoch: 7) }
            try? await Task.sleep(nanoseconds: 500_000_000)
            controller.queue.sync {}
        }

        await sendAndSettle()
        let stored = try await storedDecisions(manager)
        XCTAssertEqual(files.count, 1, "one file")
        let first = try LoanHistory.decode(try XCTUnwrap(files.first).data)
        XCTAssertEqual(first.epoch, 7)
        XCTAssertEqual(first.decisions.map(\.id), stored.map(\.id), "every decision, in the order stored")
        XCTAssertEqual(files.first?.metadata["kind"] as? String, LoanHistory.fileKind)

        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        for reason in ["loop", "updateRemoteRecommendation"] {
            if let one = stored.first(where: { $0.reason == reason }) {
                let size = try encoder.encode(one).count
                print("[decision-size] \(reason): \(size) bytes (binary plist), \(try JSONEncoder().encode(one).count) bytes (JSON)")
            }
        }
        print("[decision-size] file of \(first.decisions.count) decisions: \(files[0].data.count) bytes")

        await sendAndSettle()
        XCTAssertEqual(files.count, 1, "nothing new: no second file")

        runLoop(manager)
        await sendAndSettle()
        XCTAssertEqual(files.count, 2)
        let second = try LoanHistory.decode(files[1].data)
        XCTAssertFalse(second.decisions.isEmpty)
        XCTAssertTrue(Set(second.decisions.map(\.id)).isDisjoint(with: Set(first.decisions.map(\.id))), "only what was stored since")
    }

    // MARK: - What runs a cycle, as stock

    /// Every cycle with a pod held stores one "loop" decision, so the count is the cycles run.
    private func cyclesRun(_ manager: WatchLoopManager) async throws -> Int {
        manager.dataAccessQueue.sync {}
        return try await storedDecisions(manager).filter { $0.reason == "loop" }.count
    }

    /// A held pod, the loop closed, recent glucose and a fresh pump report: a cycle would dose.
    private func makeClosedLoopManager() async throws -> (WatchLoopManager, RecordingDoseEnactor) {
        let manager = await makeManager()
        await seedGlucose(manager)
        await report(manager)
        let enactor = RecordingDoseEnactor()
        manager.pumpManager = try makePump()
        manager.doseEnactor = enactor
        manager.setClosedLoopEnabled(true, reason: "test")
        manager.dataAccessQueue.sync {}
        return (manager, enactor)
    }

    /// A labelled copy of stock `DeviceDataManager.enactBolus`: a manual bolus first cancels an
    /// automatic bolus in progress (the pod refuses a bolus while one runs); a manual bolus in
    /// progress is left alone.
    func testAManualBolusCancelsAnAutomaticBolusInProgressFirst() async throws {
        func inProgress(automatic: Bool) -> UnfinalizedDose {
            UnfinalizedDose(decisionId: nil, bolusAmount: 2.0, startTime: Date().addingTimeInterval(-10),
                            scheduledCertainty: .certain, insulinType: .novolog, automatic: automatic)
        }
        for automatic in [true, false] {
            let manager = await makeManager()
            manager.pumpManager = try makePump(unfinalizedBolus: inProgress(automatic: automatic))
            var commands: [String] = []
            manager.cancelBolusCommand = { _ in commands.append("cancel") }
            manager.enactBolusCommand = { _, _, _, _, completion in
                commands.append("bolus")
                completion(nil)
            }

            let accepted = expectation(description: "bolus")
            manager.enactManualBolus(units: 1.0, activationType: .manualNoRecommendation) { _ in accepted.fulfill() }
            await fulfillment(of: [accepted], timeout: 10)

            XCTAssertEqual(commands, automatic ? ["cancel", "bolus"] : ["bolus"],
                           automatic ? "the automatic bolus is cancelled first" : "a manual bolus is not cancelled")
        }
    }

    private func storedCarbs(_ manager: WatchLoopManager) async -> [StoredCarbEntry] {
        await withCheckedContinuation { continuation in
            manager.carbStore.getCarbEntries(start: Date().addingTimeInterval(-3600)) { result in
                continuation.resume(returning: (try? result.get()) ?? [])
            }
        }
    }

    /// Stock runs no cycle when carbs are saved: on the bench, the wrist's extra cycle
    /// auto-bolused for the meal before the manual bolus reached the pod.
    func testSavingCarbsOnTheWristRunsNoCycle() async throws {
        let (manager, enactor) = try await makeClosedLoopManager()

        manager.addLoanCarbEntry(carbs(40), syncIdentifier: UUID().uuidString)
        var tries = 0
        while await storedCarbs(manager).isEmpty, tries < 50 {
            tries += 1
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        let saved = await storedCarbs(manager)
        XCTAssertEqual(saved.count, 1, "saved")
        try await Task.sleep(nanoseconds: 500_000_000)

        let cycles = try await cyclesRun(manager)
        XCTAssertEqual(cycles, 0, "no cycle on a carb save")
        XCTAssertTrue(enactor.calls.isEmpty, "nothing sent to the pod")
    }

    /// Nor when carbs are deleted.
    func testDeletingCarbsOnTheWristRunsNoCycle() async throws {
        let (manager, enactor) = try await makeClosedLoopManager()
        _ = try await manager.carbStore.addCarbEntry(carbs(40))
        let stored = await storedCarbs(manager)
        let entry = try XCTUnwrap(stored.first)

        let deleted = expectation(description: "deleted")
        manager.deleteLoanCarbEntry(entry) { ok in
            XCTAssertTrue(ok)
            deleted.fulfill()
        }
        await fulfillment(of: [deleted], timeout: 10)

        let cycles = try await cyclesRun(manager)
        XCTAssertEqual(cycles, 0, "no cycle on a carb delete")
        XCTAssertTrue(enactor.calls.isEmpty)
    }

    /// Nor when the pod accepts a manual bolus.
    func testAnAcceptedManualBolusRunsNoCycle() async throws {
        let (manager, enactor) = try await makeClosedLoopManager()
        manager.enactBolusCommand = { _, _, _, _, completion in completion(nil) }

        let accepted = expectation(description: "bolus")
        manager.enactManualBolus(units: 1.0, activationType: .manualNoRecommendation) { error in
            XCTAssertNil(error)
            accepted.fulfill()
        }
        await fulfillment(of: [accepted], timeout: 10)

        let cycles = try await cyclesRun(manager)
        XCTAssertEqual(cycles, 0, "no cycle after a bolus")
        XCTAssertTrue(enactor.calls.isEmpty)
    }

    /// The gate both glucose sources share: one claim per 4.2 minutes.
    func testTheCGMTriggerGateIsClaimedOncePerWindow() async {
        let manager = await makeManager()
        let now = Date()
        XCTAssertTrue(manager.claimCGMLoopTrigger(at: now))
        XCTAssertFalse(manager.claimCGMLoopTrigger(at: now.addingTimeInterval(4 * 60)))
        XCTAssertTrue(manager.claimCGMLoopTrigger(at: now.addingTimeInterval(4.3 * 60)))
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
