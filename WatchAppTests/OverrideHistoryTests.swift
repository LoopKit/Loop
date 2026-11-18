//
//  OverrideHistoryTests.swift
//  WatchAppTests
//
//  The watch's algorithm input reads overrides the way stock's does: over stock's windows, from a
//  history that keeps ended overrides for as long as the algorithm looks back. Settings likewise:
//  the phone's settings history before the grant, the granted snapshot after.
//

import XCTest
import LoopKit
import LoopAlgorithm
import LoopCore
@testable import WatchApp

@MainActor
final class OverrideHistoryTests: XCTestCase {

    private var cacheDir: URL!

    override func setUp() async throws {
        try await super.setUp()
        cacheDir = FileManager.default.temporaryDirectory.appendingPathComponent("override-history-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        cacheDir = nil
        try await super.tearDown()
    }

    /// Fresh stores on every call; the override history is whatever the caller passes.
    /// `appCacheLengths`: the stores keep what the app's do (glucose 96 h, doses and carbs the cache duration).
    private func makeManager(overrideHistory: TemporaryScheduleOverrideHistory = TemporaryScheduleOverrideHistory(),
                             appCacheLengths: Bool = false) async -> WatchLoopManager {
        let cacheStore = PersistenceController(directoryURL: cacheDir.appendingPathComponent(UUID().uuidString))
        let glucoseCacheLength: TimeInterval = appCacheLengths ? .hours(96) : .hours(4)
        let historyCacheLength: TimeInterval = appCacheLengths ? Bundle.main.localCacheDuration : .hours(24)
        let doseStore = await DoseStore(healthKitSampleStore: nil, cacheStore: cacheStore, cacheLength: historyCacheLength,
                                        longestEffectDuration: ExponentialInsulinModelPreset.rapidActingAdult.effectDuration,
                                        provenanceIdentifier: "OverrideHistoryTests")
        let glucoseStore = await GlucoseStore(healthKitSampleStore: nil, cacheStore: cacheStore,
                                              cacheLength: glucoseCacheLength, provenanceIdentifier: "OverrideHistoryTests")
        let carbStore = CarbStore(healthKitSampleStore: nil, cacheStore: cacheStore,
                                  cacheLength: historyCacheLength, provenanceIdentifier: "OverrideHistoryTests")

        var settings = LoopSettings()
        settings.basalRateSchedule = BasalRateSchedule(dailyItems: [RepeatingScheduleValue(startTime: 0, value: 1.0)])
        // Hourly items, so the ISF timeline starts where it is asked to rather than at midnight.
        settings.insulinSensitivitySchedule = InsulinSensitivitySchedule(
            unit: .milligramsPerDeciliter,
            dailyItems: (0..<24).map { RepeatingScheduleValue(startTime: .hours(Double($0)), value: 50) })
        settings.carbRatioSchedule = CarbRatioSchedule(unit: .gram, dailyItems: [RepeatingScheduleValue(startTime: 0, value: 10)])
        settings.glucoseTargetRangeSchedule = GlucoseRangeSchedule(
            unit: .milligramsPerDeciliter,
            dailyItems: [RepeatingScheduleValue(startTime: 0, value: DoubleRange(minValue: 100, maxValue: 110))])
        settings.maximumBolus = 10
        settings.maximumBasalRatePerHour = 4
        settings.suspendThreshold = GlucoseThreshold(unit: .milligramsPerDeciliter, value: 80)

        let manager = WatchLoopManager(doseStore: doseStore, glucoseStore: glucoseStore, carbStore: carbStore,
                                       overrideHistory: overrideHistory, settings: settings,
                                       stateDirectory: cacheDir)
        // A pump report just now, so the recency gate lets the input through.
        try? await manager.recordPumpEvents([], lastReconciliation: Date(), replacePendingEvents: true)
        return manager
    }

    private func makeController(overrideHistory: TemporaryScheduleOverrideHistory,
                                appCacheLengths: Bool = false) async -> PodLoanWatchController {
        let manager = await makeManager(overrideHistory: overrideHistory, appCacheLengths: appCacheLengths)
        return PodLoanWatchController(loopManager: manager, journal: LoanEventJournal(directory: cacheDir),
                                      stateDirectory: cacheDir)
    }

    /// A grant with complete settings. Its pump configuration is not a pump, so intake stops
    /// (and tears down) after the overrides are applied.
    private func grant(activeOverride: TemporaryScheduleOverride?, overrideHistory: [TemporaryScheduleOverride]? = nil,
                       settingsHistory: LoanSettingsHistory? = nil, glucoseBasedApplicationFactor: Bool? = nil,
                       guardAndRunway: Bool? = nil, volatilityBaseline: Double? = nil,
                       doseHistory: [LoanDoseRecord] = [], carbHistory: [LoanCarbRecord]? = nil,
                       glucoseHistory: [LoanGlucoseRecord]? = nil,
                       slowRetrospectiveCorrection: Bool = false) -> LoanGrant {
        var settings = LoopSettings()
        settings.glucoseTargetRangeSchedule = GlucoseRangeSchedule(
            unit: .milligramsPerDeciliter,
            dailyItems: [RepeatingScheduleValue(startTime: 0, value: DoubleRange(minValue: 100, maxValue: 110))])
        settings.maximumBasalRatePerHour = 4
        settings.maximumBolus = 10
        settings.suspendThreshold = GlucoseThreshold(unit: .milligramsPerDeciliter, value: 80)
        let supplement: [String: Any] = [
            "basalRateSchedule": BasalRateSchedule(dailyItems: [RepeatingScheduleValue(startTime: 0, value: 1.0)])!.rawValue,
            "insulinSensitivitySchedule": InsulinSensitivitySchedule(
                unit: .milligramsPerDeciliter, dailyItems: [RepeatingScheduleValue(startTime: 0, value: 50)])!.rawValue,
            "carbRatioSchedule": CarbRatioSchedule(unit: .gram, dailyItems: [RepeatingScheduleValue(startTime: 0, value: 10)])!.rawValue,
        ]
        func plist(_ value: Any) -> Data { try! PropertyListSerialization.data(fromPropertyList: value, format: .binary, options: 0) }
        return LoanGrant(epoch: 1, expiresAt: Date().addingTimeInterval(300), pumpConfiguration: Data([1, 2, 3]),
                         therapySettingsRaw: plist(settings.rawValue), settingsTimeZoneID: "GMT",
                         doseHistory: doseHistory, glucoseBasedApplicationFactorEnabled: glucoseBasedApplicationFactor,
                         guardAndRunwayEnabled: guardAndRunway, volatilityBaseline: volatilityBaseline,
                         slowRetrospectiveCorrectionEnabled: slowRetrospectiveCorrection,
                         carbHistory: carbHistory, glucoseHistory: glucoseHistory,
                         activeOverrideRaw: activeOverride.map { plist($0.rawValue) },
                         therapySettingsSupplementRaw: plist(supplement),
                         overrideHistoryRaw: overrideHistory.flatMap(LoanGrant.overrideHistoryRaw),
                         settingsHistory: settingsHistory)
    }

    /// Glucose for the last `hours`, every five minutes: the history starts there, not earlier.
    private func seedGlucose(_ manager: WatchLoopManager, hours: Double) async {
        let now = Date()
        let samples = stride(from: hours * 12, through: 0, by: -1).map { i in
            NewGlucoseSample(date: now.addingTimeInterval(-i * 5 * 60),
                             quantity: LoopQuantity(unit: .milligramsPerDeciliter, doubleValue: 120),
                             condition: nil, trend: .flat, trendRate: nil, isDisplayOnly: false,
                             wasUserEntered: false, syncIdentifier: "override-history-\(i)")
        }
        _ = try? await manager.glucoseStore.addGlucoseSamples(samples)
    }

    /// 50 % insulin needs: basal halves, ISF and carb ratio double.
    private func halfNeeds(start: Date, duration: TimeInterval) -> TemporaryScheduleOverride {
        TemporaryScheduleOverride(context: .custom,
                                  settings: TemporaryPresetSettings(unit: .milligramsPerDeciliter, targetRange: nil,
                                                                    insulinNeedsScaleFactor: 0.5),
                                  startDate: start, duration: .finite(duration), enactTrigger: .local, syncIdentifier: UUID())
    }

    private func value(_ timeline: [LoopAlgorithm.AbsoluteScheduleValue<Double>], at date: Date) -> Double? {
        timeline.first { $0.startDate <= date && date < $0.endDate }?.value
    }

    private func value(_ timeline: [AbsoluteScheduleValue<Double>], at date: Date) -> Double? {
        timeline.first { $0.startDate <= date && date < $0.endDate }?.value
    }

    private func sensitivity(_ input: StoredDataAlgorithmInput, at date: Date) -> Double? {
        input.sensitivityMgdlPerUnit.first { $0.startDate <= date && date < $0.endDate }?.value
    }

    // MARK: - Stock's windows

    /// A carb older than the glucose history (a CGM gap) is covered by the ISF timeline, as in
    /// stock; before, CarbMath trapped on it. An override over that carb scales its ratio.
    func testACarbOlderThanTheGlucoseHistoryIsCoveredAndScaled() async throws {
        let manager = await makeManager()
        let now = Date()
        await seedGlucose(manager, hours: 3)
        let carbStart = now.addingTimeInterval(-.hours(6))
        _ = try await manager.carbStore.addCarbEntry(NewCarbEntry(
            syncIdentifier: UUID().uuidString, quantity: LoopQuantity(unit: .gram, doubleValue: 30), startDate: carbStart, foodType: nil, absorptionTime: .hours(3)))
        manager.overrideHistory.recordOverride(halfNeeds(start: now.addingTimeInterval(-.hours(7)), duration: .hours(2)))

        // After the entry is made: an entry created after the base time is filtered, as in stock.
        let input = try await manager.fetchData(for: Date())

        XCTAssertEqual(input.carbEntries.count, 1, "the 6-hour-old carb is in the input")
        let isfStart = try XCTUnwrap(input.sensitivityMgdlPerUnit.first?.startDate)
        XCTAssertLessThanOrEqual(isfStart, carbStart, "the ISF timeline covers the carb, though glucose starts 3 h ago")
        XCTAssertEqual(try XCTUnwrap(value(input.carbRatio, at: carbStart)), 20, accuracy: 0.001,
                       "the override over the carb doubles its carb ratio")
        XCTAssertEqual(try XCTUnwrap(sensitivity(input, at: carbStart)), 100, accuracy: 0.001, "and its ISF")

        // Before, this trapped in CarbMath; now it runs.
        let output = Algorithm.run(input: input)
        XCTAssertFalse(output.predictedGlucose.isEmpty)
    }

    // MARK: - Ended overrides are kept

    /// An override that expired during the loan still scales its minutes after a glance refresh,
    /// which prunes the history; at LoopKit's 1-second default it was gone within a cycle.
    func testAnOverrideThatEndedStillScalesItsMinutesAfterARefresh() async throws {
        let manager = await makeManager(overrideHistory: StockLoopStack.makeOverrideHistory())
        let now = Date()
        await seedGlucose(manager, hours: 3)
        manager.scheduleOverride = halfNeeds(start: now.addingTimeInterval(-.minutes(90)), duration: .hours(1))

        _ = manager.basalRateScheduleApplyingOverrideHistory   // what every glance and HUD refresh reads
        let input = try await manager.fetchData(for: Date())

        let during = now.addingTimeInterval(-.minutes(60))
        XCTAssertEqual(try XCTUnwrap(value(input.basal, at: during)), 0.5, accuracy: 0.001, "basal halved for its minutes")
        XCTAssertEqual(try XCTUnwrap(sensitivity(input, at: during)), 100, accuracy: 0.001, "ISF doubled")
        XCTAssertEqual(try XCTUnwrap(value(input.carbRatio, at: during)), 20, accuracy: 0.001, "carb ratio doubled")
        XCTAssertEqual(try XCTUnwrap(value(input.basal, at: now.addingTimeInterval(-.minutes(10)))), 1.0, accuracy: 0.001,
                       "and nothing after it ended")
    }

    /// Each grant starts the history over, so an override the phone sends again cannot overlap an
    /// event only this watch kept: LoopKit traps on overlapping overrides.
    func testAGrantStartsTheHistoryOverSoAResentOverrideCannotOverlap() async throws {
        let c = await makeController(overrideHistory: StockLoopStack.makeOverrideHistory())
        let now = Date()
        let granted = TemporaryScheduleOverride(context: .custom,
                                                settings: TemporaryPresetSettings(unit: .milligramsPerDeciliter, targetRange: nil,
                                                                                  insulinNeedsScaleFactor: 0.8),
                                                startDate: now.addingTimeInterval(-.hours(3)), duration: .indefinite,
                                                enactTrigger: .local, syncIdentifier: UUID())
        // The last loan: granted, replaced on the wrist, cleared. The phone never heard of the wrist's.
        c.loopManager.scheduleOverride = granted
        c.loopManager.applyWristOverride(halfNeeds(start: now.addingTimeInterval(-.hours(2)), duration: .hours(3)))
        c.loopManager.applyWristOverride(nil)

        await c.onMain { c.handleGrant(grant(activeOverride: granted)) }

        _ = c.loopManager.basalRateScheduleApplyingOverrideHistory   // traps on an overlap
        let kept = c.loopManager.overrideHistory.getOverrideHistory(startDate: now.addingTimeInterval(-.hours(4)), endDate: Date())
        XCTAssertEqual(kept.map(\.syncIdentifier), [granted.syncIdentifier], "only what the phone sent")
    }

    // MARK: - The phone's history arrives with the grant

    /// An override that ended on the phone 2 h before Start scales the watch's first cycle for
    /// its minutes, from its original start to its early end.
    func testAnOverrideThatEndedBeforeStartScalesTheFirstCycle() async throws {
        let history = StockLoopStack.makeOverrideHistory()
        let c = await makeController(overrideHistory: history)
        let now = Date()
        var ended = halfNeeds(start: now.addingTimeInterval(-.hours(4)), duration: .hours(3))
        ended.actualEnd = .early(now.addingTimeInterval(-.hours(2)))   // cut short on the phone

        await c.onMain { c.handleGrant(grant(activeOverride: nil, overrideHistory: [ended])) }

        let kept = try XCTUnwrap(history.getOverrideHistory(startDate: now.addingTimeInterval(-.hours(24)), endDate: now).first)
        XCTAssertEqual(kept.syncIdentifier, ended.syncIdentifier)
        XCTAssertEqual(kept.startDate.timeIntervalSince(ended.startDate), 0, accuracy: 0.001, "its original start")
        XCTAssertEqual(kept.actualEndDate.timeIntervalSince(ended.actualEndDate), 0, accuracy: 0.001, "and its early end")

        // The cycle reads that same history (the intake's teardown reset this loop's book).
        let loop = await makeManager(overrideHistory: history)
        await seedGlucose(loop, hours: 3)
        let input = try await loop.fetchData(for: Date())
        let during = now.addingTimeInterval(-.hours(3))
        XCTAssertEqual(try XCTUnwrap(value(input.basal, at: during)), 0.5, accuracy: 0.001, "basal halved for its minutes")
        XCTAssertEqual(try XCTUnwrap(sensitivity(input, at: during)), 100, accuracy: 0.001, "ISF doubled")
        XCTAssertEqual(try XCTUnwrap(value(input.carbRatio, at: during)), 20, accuracy: 0.001, "carb ratio doubled")
        XCTAssertEqual(try XCTUnwrap(value(input.basal, at: now.addingTimeInterval(-.hours(1)))), 1.0, accuracy: 0.001,
                       "and nothing after its early end")
    }

    /// A phoneless start rebuilds the standing copy's grant; the history must ride along.
    func testAStartFromTheStandingCopyKeepsTheHistory() {
        let copy = grant(activeOverride: nil, overrideHistory: [halfNeeds(start: Date().addingTimeInterval(-.hours(3)), duration: .hours(1))])
        XCTAssertNotNil(copy.overrideHistoryRaw)
        XCTAssertEqual(copy.withEpoch(9, leaseUntil: Date()).overrideHistoryRaw, copy.overrideHistoryRaw)
    }

    // MARK: - The phone's settings history arrives with the grant

    /// The phone's last day: basal 0.8, ISF 40, carb ratio 8, target 90-100 until `change`, then
    /// the granted snapshot's 1.0, 50, 10, 100-110 up to `now`.
    private func settingsHistory(changedAt change: Date, now: Date) -> LoanSettingsHistory {
        let start = now.addingTimeInterval(-.hours(24))
        func timeline<T>(_ old: T, _ new: T) -> [AbsoluteScheduleValue<T>] {
            [AbsoluteScheduleValue(startDate: start, endDate: change, value: old),
             AbsoluteScheduleValue(startDate: change, endDate: now, value: new)]
        }
        let mgdl = LoopUnit.milligramsPerDeciliter
        return LoanSettingsHistory(
            basal: timeline(0.8, 1.0),
            sensitivity: timeline(LoopQuantity(unit: mgdl, doubleValue: 40), LoopQuantity(unit: mgdl, doubleValue: 50)),
            carbRatio: timeline(8, 10),
            targetRange: timeline(LoopQuantity(unit: mgdl, doubleValue: 90)...LoopQuantity(unit: mgdl, doubleValue: 100),
                                  LoopQuantity(unit: mgdl, doubleValue: 100)...LoopQuantity(unit: mgdl, doubleValue: 110)))
    }

    /// Entries cover the window end to end, with no gap or overlap.
    private func assertContinuous<T>(_ timeline: [AbsoluteScheduleValue<T>], from start: Date, to end: Date,
                                     _ name: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(timeline.first?.startDate, start, "\(name) starts at the window", file: file, line: line)
        XCTAssertEqual(timeline.last?.endDate, end, "\(name) ends at the window", file: file, line: line)
        for (a, b) in zip(timeline, timeline.dropFirst()) {
            XCTAssertEqual(a.endDate, b.startDate, "\(name) is continuous", file: file, line: line)
        }
    }

    /// Basal, ISF and carb ratio changed on the phone 2 h before Start: the watch's settings
    /// queries read the old values before the change and the new ones after.
    func testASettingsChangeBeforeStartReadsTheOldValuesBeforeIt() async throws {
        let c = await makeController(overrideHistory: StockLoopStack.makeOverrideHistory())
        let now = Date()
        await c.onMain { c.handleGrant(grant(activeOverride: nil, settingsHistory: settingsHistory(changedAt: now.addingTimeInterval(-.hours(2)), now: now))) }

        let provider = c.loopManager.settingsProvider
        let start = now.addingTimeInterval(-.hours(6)), end = now.addingTimeInterval(.hours(1))
        let basal = try await provider.getBasalHistory(startDate: start, endDate: end)
        let isf = try await provider.getInsulinSensitivityHistory(startDate: start, endDate: end)
        let carbRatio = try await provider.getCarbRatioHistory(startDate: start, endDate: end)
        let target = try await provider.getTargetRangeHistory(startDate: start, endDate: end)
        let before = now.addingTimeInterval(-.hours(3)), after = now.addingTimeInterval(-.hours(1))
        let later = now.addingTimeInterval(.minutes(30))
        let isfValue: (Date) -> Double? = { d in isf.first { $0.startDate <= d && d < $0.endDate }?.value.doubleValue(for: .milligramsPerDeciliter) }

        XCTAssertEqual(value(basal, at: before), 0.8, "basal: the old rate before the change")
        XCTAssertEqual(value(basal, at: after), 1.0, "and the new one after")
        XCTAssertEqual(value(basal, at: later), 1.0, "and the snapshot past the grant")
        XCTAssertEqual(isfValue(before), 40)
        XCTAssertEqual(isfValue(after), 50)
        XCTAssertEqual(value(carbRatio, at: before), 8)
        XCTAssertEqual(value(carbRatio, at: after), 10)
        XCTAssertEqual(target.first { $0.startDate <= before && before < $0.endDate }?.value.lowerBound.doubleValue(for: .milligramsPerDeciliter), 90)
        assertContinuous(basal, from: start, to: end, "basal")
        assertContinuous(isf, from: start, to: end, "ISF")
        assertContinuous(carbRatio, from: start, to: end, "carb ratio")
        assertContinuous(target, from: start, to: end, "target")
    }

    /// The same change, in the first cycle's input.
    func testTheFirstCycleReadsTheOldValuesBeforeAChangeBeforeStart() async throws {
        let c = await makeController(overrideHistory: StockLoopStack.makeOverrideHistory())
        let now = Date()
        await c.onMain { c.handleGrant(grant(activeOverride: nil, settingsHistory: settingsHistory(changedAt: now.addingTimeInterval(-.hours(2)), now: now))) }
        let before = now.addingTimeInterval(-.hours(3))

        await seedGlucose(c.loopManager, hours: 3)
        try await c.loopManager.recordPumpEvents([], lastReconciliation: Date(), replacePendingEvents: true)
        let input = try await c.loopManager.fetchData(for: Date())
        XCTAssertEqual(try XCTUnwrap(value(input.basal, at: before)), 0.8, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(sensitivity(input, at: before)), 40, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(value(input.carbRatio, at: before)), 8, accuracy: 0.001)
    }

    // MARK: - Algorithm Experiments

    /// The phone's glucose-based application factor reaches the wrist's algorithm input, as
    /// integral retrospective correction does.
    func testTheApplicationFactorFollowsThePhonesExperimentToggle() async throws {
        let experiments = try await experiments(afterGrantWith: true)
        XCTAssertTrue(experiments.contains(.glucoseBasedApplicationFactor))
    }

    /// An older phone sends no flag: the factor stays stock's constant.
    func testAGrantWithoutTheToggleKeepsTheConstantFactor() async throws {
        let experiments = try await experiments(afterGrantWith: nil)
        XCTAssertFalse(experiments.contains(.glucoseBasedApplicationFactor))
    }

    /// The phone's guard + runway reaches the wrist's algorithm input, with the phone's volatility baseline.
    func testGuardAndRunwayFollowsThePhonesExperimentToggle() async throws {
        let input = try await input(afterGrant: grant(activeOverride: nil, guardAndRunway: true, volatilityBaseline: 4.2))
        XCTAssertTrue(input.experiments.contains(.guardAndRunway))
        XCTAssertEqual(input.volatilityBaseline, 4.2)
    }

    /// The watch's dosing decisions record the experiments as the phone's do, guard + runway with its baseline.
    func testTheWatchsDosingDecisionsRecordThePhonesExperiments() async throws {
        let c = await makeController(overrideHistory: StockLoopStack.makeOverrideHistory())
        await c.onMain { c.handleGrant(grant(activeOverride: nil, glucoseBasedApplicationFactor: true, guardAndRunway: true, volatilityBaseline: 4.2)) }
        await c.loopManager.laneSettled()
        let records = c.loopManager.algorithmExperiments(for: .tempBasalOnly)
        XCTAssertEqual(records.map(\.identifier), [ExperimentOption.guardAndRunway.rawValue],
                       "the application factor is in effect only with automatic bolus, as on the phone")
        XCTAssertEqual(records.first?.parameters, .object(["version": .number(2), "volatilityBaseline": .number(4.2)]))
    }

    /// An older phone sends no flag: guard + runway stays off, and a baseline alone is not used.
    func testAGrantWithoutTheGuardAndRunwayToggleLeavesItOff() async throws {
        let input = try await input(afterGrant: grant(activeOverride: nil, volatilityBaseline: 4.2))
        XCTAssertFalse(input.experiments.contains(.guardAndRunway))
        XCTAssertNil(input.volatilityBaseline)
    }

    /// The experiments in the first algorithm input after a grant.
    private func experiments(afterGrantWith flag: Bool?) async throws -> Set<ExperimentOption> {
        let input = try await input(afterGrant: grant(activeOverride: nil, glucoseBasedApplicationFactor: flag))
        return input.experiments
    }

    /// The first algorithm input after a grant, with glucose steady for an hour.
    private func input(afterGrant grant: LoanGrant) async throws -> StoredDataAlgorithmInput {
        let c = await makeController(overrideHistory: StockLoopStack.makeOverrideHistory())
        await c.onMain { c.handleGrant(grant) }
        await c.loopManager.laneSettled()
        XCTAssertEqual(c.loopManager.glucoseBasedApplicationFactorEnabled, grant.glucoseBasedApplicationFactorEnabled ?? false)
        await seedGlucose(c.loopManager, hours: 1)
        try await c.loopManager.recordPumpEvents([], lastReconciliation: Date(), replacePendingEvents: true)
        return try await c.loopManager.fetchData(for: Date())
    }

    /// An older phone sends no history: the snapshot is projected back, as before.
    func testAGrantWithoutSettingsHistoryProjectsTheSnapshotBack() async throws {
        let c = await makeController(overrideHistory: StockLoopStack.makeOverrideHistory())
        let now = Date()
        await c.onMain { c.handleGrant(grant(activeOverride: nil)) }

        let provider = c.loopManager.settingsProvider
        XCTAssertNil(provider.history)
        let basal = try await provider.getBasalHistory(startDate: now.addingTimeInterval(-.hours(6)), endDate: now)
        XCTAssertEqual(value(basal, at: now.addingTimeInterval(-.hours(3))), 1.0, "today's rate, throughout")
    }

    /// A phoneless start rebuilds the standing copy's grant; the settings history rides along.
    func testAStartFromTheStandingCopyKeepsTheSettingsHistory() {
        let now = Date()
        let copy = grant(activeOverride: nil, settingsHistory: settingsHistory(changedAt: now.addingTimeInterval(-.hours(2)), now: now))
        XCTAssertNotNil(copy.settingsHistory)
        XCTAssertEqual(copy.withEpoch(9, leaseUntil: Date()).settingsHistory, copy.settingsHistory)
    }

    // MARK: - Slow retrospective correction

    /// A grant at `now` with slow retrospective correction on, its histories over the experiment's windows as
    /// the phone sends them: readings every 5 min back 72 h, half-hour temps back 79 h, carbs 30 h and 6 h back.
    private func slowRetrospectiveCorrectionGrant(now: Date) -> LoanGrant {
        let windows = LoanGrant.slowRetrospectiveCorrectionWindows(referenceDate: now)
        let glucose = stride(from: 72.0 * 12, through: 0, by: -1).map { i in
            LoanGlucoseRecord(syncIdentifier: "phone-\(i)", startDate: now.addingTimeInterval(-i * 300 - 90),
                              valueMgdl: 110 + i.truncatingRemainder(dividingBy: 7), trendRateMgdlPerMin: nil,
                              isDisplayOnly: false, wasUserEntered: false)
        }.filter { $0.startDate >= windows.glucose }
        let doses = stride(from: 79.0 * 2, through: 1, by: -1).compactMap { i in
            LoanDoseRecord(storeDose: DoseEntry(type: .tempBasal, startDate: now.addingTimeInterval(-i * 1800),
                                                endDate: now.addingTimeInterval(-(i - 1) * 1800), value: 1.2, unit: .unitsPerHour,
                                                doseId: nil, deliveredUnits: 0.6, syncIdentifier: "temp-\(i)",
                                                insulinType: .novolog, automatic: true))
        }.filter { $0.startDate >= windows.doses }
        let carbs = [30.0, 6].map { hours in
            LoanCarbRecord(syncIdentifier: "carb-\(hours)", provenanceIdentifier: "phone", syncVersion: 1,
                           startDate: now.addingTimeInterval(-.hours(hours)), grams: 40, absorptionTime: .hours(3),
                           foodType: nil, userCreatedDate: now.addingTimeInterval(-.hours(hours)), userUpdatedDate: nil)
        }
        return grant(activeOverride: nil, doseHistory: doses, carbHistory: carbs, glucoseHistory: glucose,
                     slowRetrospectiveCorrection: true)
    }

    /// The grant's 72 h go into the watch's stores before the takeover, and the loop reads them there, as the
    /// phone reads its own: every reading once, the old doses and the carb entry 30 h back included.
    func testSlowRetrospectiveCorrectionReadsTheGrantsHistoryFromTheStores() async throws {
        let now = Date()
        let grant = slowRetrospectiveCorrectionGrant(now: now)
        let c = await makeController(overrideHistory: StockLoopStack.makeOverrideHistory(), appCacheLengths: true)
        await c.onMain { c.handleGrant(grant) }
        await c.loopManager.laneSettled()
        XCTAssertTrue(c.loopManager.slowRetrospectiveCorrectionEnabled)

        let seeded = await c.ingestGrantHistory(grant)
        XCTAssertTrue(seeded)
        try await c.loopManager.recordPumpEvents([], lastReconciliation: Date(), replacePendingEvents: true)
        let input = try await c.loopManager.fetchData(for: now)
        XCTAssertTrue(input.experiments.contains(.slowRetrospectiveCorrection))

        let dates = input.glucoseHistory.map(\.startDate)
        XCTAssertEqual(Set(dates).count, dates.count, "no reading twice")
        XCTAssertLessThan(dates.first!, now.addingTimeInterval(-.hours(71.9)))
        XCTAssertEqual(dates.count, grant.glucoseHistory!.filter { $0.startDate >= now.addingTimeInterval(-.hours(72)) }.count)

        XCTAssertLessThan(input.doses.map(\.startDate).min()!, now.addingTimeInterval(-.hours(77)))
        XCTAssertTrue(input.carbEntries.contains { abs($0.startDate.timeIntervalSince(now.addingTimeInterval(-.hours(30)))) < 1 })
    }

    func testWithSlowRetrospectiveCorrectionOffTheExperimentStaysOff() async throws {
        let input = try await input(afterGrant: grant(activeOverride: nil))
        XCTAssertFalse(input.experiments.contains(.slowRetrospectiveCorrection))
    }

    /// The algorithm counts a glucose change only between readings of one identity. The watch records under the
    /// phone app's, so readings by every route (the grant's seed, the watch's own sensor, the stock catch-up,
    /// which keeps the phone's identity) form one series, as on the phone.
    func testEveryRouteRecordsGlucoseUnderThePhoneAppsIdentity() async throws {
        let phoneApp = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "WKCompanionAppBundleIdentifier") as? String)
        XCTAssertEqual(LoopDataManager.glucoseProvenanceIdentifier, phoneApp)

        let store = await GlucoseStore(healthKitSampleStore: nil,
                                       cacheStore: PersistenceController(directoryURL: cacheDir.appendingPathComponent(UUID().uuidString)),
                                       cacheLength: .hours(96), provenanceIdentifier: LoopDataManager.glucoseProvenanceIdentifier)
        let now = Date()
        func reading(_ minutesAgo: Double, _ id: String) -> NewGlucoseSample {
            NewGlucoseSample(date: now.addingTimeInterval(-minutesAgo * 60),
                             quantity: LoopQuantity(unit: .milligramsPerDeciliter, doubleValue: 120), condition: nil, trend: nil,
                             trendRate: nil, isDisplayOnly: false, wasUserEntered: false, syncIdentifier: id)
        }
        _ = try await store.addGlucoseSamples([30, 25, 20].map { reading($0, "seed-\($0)") })
        try await store.setSyncGlucoseSamples([15, 10].map {
            StoredGlucoseSample(provenanceIdentifier: phoneApp, syncIdentifier: "catch-up-\($0)", startDate: now.addingTimeInterval(-$0 * 60),
                                quantity: LoopQuantity(unit: .milligramsPerDeciliter, doubleValue: 120))
        })
        _ = try await store.addGlucoseSamples([5, 0].map { reading($0, "direct-\($0)") })

        let samples = try await store.getGlucoseSamples(start: now.addingTimeInterval(-.hours(1)), end: nil)
        XCTAssertEqual(samples.count, 7)
        XCTAssertEqual(Set(samples.map(\.provenanceIdentifier)), [phoneApp])
    }
}
