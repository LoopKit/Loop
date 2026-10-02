//
//  OverrideHistoryTests.swift
//  WatchAppTests
//
//  The watch's algorithm input reads overrides the way stock's does: over stock's windows, from a
//  history that keeps ended overrides for as long as the algorithm looks back.
//

import XCTest
import LoopKit
import LoopAlgorithm
import LoopCore
@testable import WatchApp

final class OverrideHistoryTests: XCTestCase {

    private var cacheDir: URL!

    override func setUp() {
        super.setUp()
        cacheDir = FileManager.default.temporaryDirectory.appendingPathComponent("override-history-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        cacheDir = nil
        super.tearDown()
    }

    /// Fresh stores on every call; the override history is whatever the caller passes.
    private func makeManager(overrideHistory: TemporaryScheduleOverrideHistory = TemporaryScheduleOverrideHistory()) async -> WatchLoopManager {
        let cacheStore = PersistenceController(directoryURL: cacheDir.appendingPathComponent(UUID().uuidString))
        let doseStore = await DoseStore(healthKitSampleStore: nil, cacheStore: cacheStore,
                                        longestEffectDuration: ExponentialInsulinModelPreset.rapidActingAdult.effectDuration,
                                        provenanceIdentifier: "OverrideHistoryTests")
        let glucoseStore = await GlucoseStore(healthKitSampleStore: nil, cacheStore: cacheStore,
                                              cacheLength: .hours(4), provenanceIdentifier: "OverrideHistoryTests")
        let carbStore = CarbStore(healthKitSampleStore: nil, cacheStore: cacheStore,
                                  cacheLength: .hours(24), provenanceIdentifier: "OverrideHistoryTests")

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

    private func makeController(overrideHistory: TemporaryScheduleOverrideHistory) async -> PodLoanWatchController {
        let manager = await makeManager(overrideHistory: overrideHistory)
        return PodLoanWatchController(loopManager: manager, journal: LoanEventJournal(directory: cacheDir),
                                      stateDirectory: cacheDir)
    }

    /// A grant with complete settings. Its pump configuration is not a pump, so intake stops
    /// (and tears down) after the overrides are applied.
    private func grant(activeOverride: TemporaryScheduleOverride?, overrideHistory: [TemporaryScheduleOverride]? = nil) -> LoanGrant {
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
                         podAddress: 0, therapySettingsRaw: plist(settings.rawValue), settingsTimeZoneID: "GMT",
                         doseHistory: [], activeOverrideRaw: activeOverride.map { plist($0.rawValue) },
                         therapySettingsSupplementRaw: plist(supplement),
                         overrideHistoryRaw: overrideHistory.flatMap(LoanGrant.overrideHistoryRaw))
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

    private func value(_ timeline: [AbsoluteScheduleValue<Double>], at date: Date) -> Double? {
        timeline.first { $0.startDate <= date && date < $0.endDate }?.value
    }

    private func sensitivity(_ input: StoredDataAlgorithmInput, at date: Date) -> Double? {
        input.sensitivity.first { $0.startDate <= date && date < $0.endDate }?.value.doubleValue(for: .milligramsPerDeciliter)
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
            quantity: LoopQuantity(unit: .gram, doubleValue: 30), startDate: carbStart, foodType: nil, absorptionTime: .hours(3)))
        manager.overrideHistory.recordOverride(halfNeeds(start: now.addingTimeInterval(-.hours(7)), duration: .hours(2)))

        // After the entry is made: an entry created after the base time is filtered, as in stock.
        let input = try await manager.fetchAlgorithmInput(at: Date(), recommendationType: .tempBasal)

        XCTAssertEqual(input.carbEntries.count, 1, "the 6-hour-old carb is in the input")
        let isfStart = try XCTUnwrap(input.sensitivity.first?.startDate)
        XCTAssertLessThanOrEqual(isfStart, carbStart, "the ISF timeline covers the carb, though glucose starts 3 h ago")
        XCTAssertEqual(try XCTUnwrap(value(input.carbRatio, at: carbStart)), 20, accuracy: 0.001,
                       "the override over the carb doubles its carb ratio")
        XCTAssertEqual(try XCTUnwrap(sensitivity(input, at: carbStart)), 100, accuracy: 0.001, "and its ISF")

        // Before, this trapped in CarbMath; now it runs.
        let output = LoopAlgorithm.run(input: input)
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
        let input = try await manager.fetchAlgorithmInput(at: Date(), recommendationType: .tempBasal)

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

        c.queue.sync { c.handleGrant(grant(activeOverride: granted)) }

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

        c.queue.sync { c.handleGrant(grant(activeOverride: nil, overrideHistory: [ended])) }

        let kept = try XCTUnwrap(history.getOverrideHistory(startDate: now.addingTimeInterval(-.hours(24)), endDate: now).first)
        XCTAssertEqual(kept.syncIdentifier, ended.syncIdentifier)
        XCTAssertEqual(kept.startDate.timeIntervalSince(ended.startDate), 0, accuracy: 0.001, "its original start")
        XCTAssertEqual(kept.actualEndDate.timeIntervalSince(ended.actualEndDate), 0, accuracy: 0.001, "and its early end")

        // The cycle reads that same history (the intake's teardown reset this loop's book).
        let loop = await makeManager(overrideHistory: history)
        await seedGlucose(loop, hours: 3)
        let input = try await loop.fetchAlgorithmInput(at: Date(), recommendationType: .tempBasal)
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
}
