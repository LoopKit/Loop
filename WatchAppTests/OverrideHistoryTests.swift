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
    private var cacheStore: PersistenceController!

    override func setUp() {
        super.setUp()
        cacheDir = FileManager.default.temporaryDirectory.appendingPathComponent("override-history-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        cacheStore = PersistenceController(directoryURL: cacheDir)
    }

    override func tearDown() {
        cacheStore = nil
        cacheDir = nil
        super.tearDown()
    }

    private func makeManager(overrideHistory: TemporaryScheduleOverrideHistory = TemporaryScheduleOverrideHistory()) async -> WatchLoopManager {
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
}
