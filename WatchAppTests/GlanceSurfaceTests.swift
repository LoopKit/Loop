//
//  GlanceSurfaceTests.swift
//  WatchAppTests
//
//  THE GLANCE SURFACE, tested for the first time.
//
//  Three separate fields were declared on WatchLoopManager, READ into GlanceData, and assigned
//  NOWHERE in the tree — so the wrist showed nothing while the log printed a full prediction
//  every five minutes:
//
//    * predictedGlucoseIncludingPendingInsulin  → glance "eventual" always nil
//    * lastPredictionBreakdown                  → diagnostics "no prediction to reconcile", always
//
//  All three survived because nothing ever asserted on the glance surface. They are pure
//  computation — no BLE, no pod, no phone — so a simulator test catches them, which matters
//  because this is the surface a person reads before deciding to bolus.
//
//  These tests assert the WIRING, not the algorithm's numbers: that what the loop computed
//  actually reaches the surface that displays it.
//

import XCTest
import LoopKit
import LoopAlgorithm
import LoopCore
import HealthKit
@testable import WatchApp

final class GlanceSurfaceTests: XCTestCase {

    private var cacheDir: URL!
    private var cacheStore: PersistenceController!

    override func setUp() {
        super.setUp()
        cacheDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("glance-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        cacheStore = PersistenceController(directoryURL: cacheDir)
    }

    override func tearDown() {
        // Never unlink a live store's directory synchronously — the async-init race answers later
        // reads with zero rows. Unique names mean nothing collides; the OS reclaims temp.
        cacheStore = nil
        cacheDir = nil
        super.tearDown()
    }

    private func makeManager() async -> WatchLoopManager {
        let doseStore = await DoseStore(
            healthKitSampleStore: nil,
            cacheStore: cacheStore,
            longestEffectDuration: ExponentialInsulinModelPreset.rapidActingAdult.effectDuration,
            provenanceIdentifier: "GlanceSurfaceTests")
        let glucoseStore = await GlucoseStore(
            healthKitSampleStore: nil,
            cacheStore: cacheStore,
            cacheLength: .hours(4),
            provenanceIdentifier: "GlanceSurfaceTests")
        let carbStore = CarbStore(
            healthKitSampleStore: nil,
            cacheStore: cacheStore,
            cacheLength: .hours(24),
            provenanceIdentifier: "GlanceSurfaceTests")

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

    /// A flat run of readings — enough history for the algorithm to produce a curve at all.
    private func seedGlucose(_ manager: WatchLoopManager, mgdl: Double = 140) async {
        let now = Date()
        let samples: [NewGlucoseSample] = (0..<12).reversed().map { i in
            NewGlucoseSample(
                date: now.addingTimeInterval(-Double(i) * 5 * 60),
                quantity: LoopQuantity(unit: .milligramsPerDeciliter, doubleValue: mgdl),
                condition: nil, trend: .flat, trendRate: nil,
                isDisplayOnly: false, wasUserEntered: false,
                syncIdentifier: "glance-test-\(i)")
        }
        _ = try? await manager.glucoseStore.addGlucoseSamples(samples)
    }

    /// A pump report in the book, because the algorithm refuses to run without one: stock's
    /// pump-data recency gate (the one-book form of the 2026-08-18 fix — the algorithm must never
    /// dose off a book the pod has not written to). An empty report is exactly what the
    /// takeover's first status read looks like.
    private func seedBook(_ manager: WatchLoopManager) async {
        try? await manager.recordPumpEvents([], lastReconciliation: Date(), replacePendingEvents: true)
    }

    private func settle(_ seconds: TimeInterval = 2.0) {
        let done = expectation(description: "settled")
        DispatchQueue.global().asyncAfter(deadline: .now() + seconds) { done.fulfill() }
        wait(for: [done], timeout: seconds + 5)
    }

    /// THE REGRESSION THIS FILE EXISTS FOR. The glance's eventual read a field nothing assigned,
    /// so the wrist showed no forecast for weeks while `[predict]` logged one every cycle.
    func testGlanceCarriesAnEventualAfterAPredictionRefresh() async {
        let manager = await makeManager()
        await seedGlucose(manager)
        await seedBook(manager)

        manager.refreshPredictionForGlance()
        settle()

        let data = manager.glanceData()
        XCTAssertNotNil(data.eventual,
                        "the glance must carry the eventual the loop just computed — a nil here is the field that nothing assigns")
    }

    /// The diagnostics reconciliation panel reads this; it said "no prediction to reconcile" on
    /// every cycle since the port because the field was never assigned.
    func testDiagnosticsCarriesAPredictionBreakdown() async {
        let manager = await makeManager()
        await seedGlucose(manager)
        await seedBook(manager)

        manager.refreshPredictionForGlance()
        settle()

        let data = manager.glanceData()
        XCTAssertNotNil(data.predictionBreakdown,
                        "the diagnostics panel must receive the decomposition the loop computed")
    }

    /// The panel and the log must describe the SAME cycle: both read the same effects on the same
    /// queue in the same pass, so the breakdown's eventual must equal the glance's eventual.
    func testTheBreakdownAndTheGlanceAgreeOnTheSameCycle() async {
        let manager = await makeManager()
        await seedGlucose(manager)
        await seedBook(manager)

        manager.refreshPredictionForGlance()
        settle()

        let data = manager.glanceData()
        guard let eventual = data.eventual?.doubleValue(for: .milligramsPerDeciliter),
              let breakdown = data.predictionBreakdown else {
            return XCTFail("both surfaces must be populated before they can be compared")
        }
        XCTAssertEqual(breakdown.eventualMgdl, eventual, accuracy: 0.5,
                       "one cycle, one number — the panel and the glance cannot disagree")
    }
}
