//
//  TemporaryScheduleOverrideAlgorithmTests.swift
//  LoopTests
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import XCTest
import LoopAlgorithm
@testable import LoopKit
@testable import Loop

class TemporaryScheduleOverrideAlgorithmTests: XCTestCase {

    let dateFormatter = ISO8601DateFormatter.localTimeDate(timeZone: .currentFixed)

    private func date(at time: String) -> Date {
        return dateFormatter.date(from: "2019-01-01T\(time):00")!
    }

    func testOverrideScheduleAnnotatingReservoirSplitsDose() {
        let schedule = BasalRateSchedule(dailyItems: [
            RepeatingScheduleValue(startTime: 0, value: 0.225),
            RepeatingScheduleValue(startTime: 3600.0, value: 0.18000000000000002),
            RepeatingScheduleValue(startTime: 10800.0, value: 0.135),
            RepeatingScheduleValue(startTime: 12689.855275034904, value: 0.15),
            RepeatingScheduleValue(startTime: 21600.0, value: 0.2),
            RepeatingScheduleValue(startTime: 32400.0, value: 0.2),
            RepeatingScheduleValue(startTime: 50400.0, value: 0.2),
            RepeatingScheduleValue(startTime: 52403.79680299759, value: 0.16000000000000003),
            RepeatingScheduleValue(startTime: 63743.58014559746, value: 0.2),
            RepeatingScheduleValue(startTime: 63743.58014583588, value: 0.16000000000000003),
            RepeatingScheduleValue(startTime: 69968.05249071121, value: 0.2),
            RepeatingScheduleValue(startTime: 69968.05249094963, value: 0.18000000000000002),
            RepeatingScheduleValue(startTime: 79200.0, value: 0.225),
        ])!

        let start = date(at: "19:25")

        let dose = FixtureInsulinDose(
            deliveryType: .basal,
            startDate: start,
            endDate: date(at: "19:30"),
            volume: 0.8,
            insulinType: .novolog
        )

        let timeline = schedule.between(start: start, end: start.addingTimeInterval(InsulinMath.longestInsulinActivityDuration)).algorithmSchedule()

        let annotated = [dose].annotated(with: timeline)

        XCTAssertEqual(3, annotated.count)
        XCTAssertEqual(dose.volume, annotated.map { $0.volume }.reduce(0, +))
    }

    func testPreMealPreset() {
        let now = ISO8601DateFormatter().date(from: "2020-03-11T12:13:14-0700")!

        var input = AlgorithmInputFixture.mock(for: now)
        input.recommendationType = .tempBasal

        func d(_ interval: TimeInterval) -> Date {
            return now.addingTimeInterval(interval)
        }

        // Flat, in range bg.
        input.glucoseHistory = [
            FixtureGlucoseSample(startDate: d(.minutes(-19)), mgdl: 105),
            FixtureGlucoseSample(startDate: d(.minutes(-14)), mgdl: 105),
            FixtureGlucoseSample(startDate: d(.minutes(-9)), mgdl: 105),
            FixtureGlucoseSample(startDate: d(.minutes(-4)), mgdl: 105),
        ]

        let scheduledRange = LoopQuantity(unit: .milligramsPerDeciliter, doubleValue: 100)...LoopQuantity(unit: .milligramsPerDeciliter, doubleValue: 110)
        let overrideRange = LoopQuantity(unit: .milligramsPerDeciliter, doubleValue: 80)...LoopQuantity(unit: .milligramsPerDeciliter, doubleValue: 90)

        let overrideStartTime = d(.minutes(-10))

        let overrides: [TemporaryScheduleOverride] = [
            .init(
                context: .preMeal,
                settings: .init(targetRange: overrideRange),
                startDate: overrideStartTime,
                duration: .finite(.hours(1)),
                enactTrigger: .local,
                syncIdentifier: UUID()
            )
        ]

        let targetTimeline: [LoopKit.AbsoluteScheduleValue<ClosedRange<LoopQuantity>>] = [
            AbsoluteScheduleValue(startDate: d(.hours(-2)), endDate: d(.hours(10)), value: scheduledRange)
        ]

        input.targetMgdl = overrides.applyTarget(over: targetTimeline, at: now).algorithmMgdlRanges()

        input.doses = []
        input.carbEntries = []

        let output = Algorithm.run(input: input)

        let recommendedRate = output.recommendation!.automatic!.basalAdjustment.unitsPerHour
        let activeInsulin = output.activeInsulin!
        XCTAssertEqual(activeInsulin, 0)
        XCTAssertEqual(recommendedRate, 1.727, accuracy: 0.01)
    }
}

fileprivate extension AlgorithmInputFixture {
    /// Mocks stable, in range glucose, no insulin, no carbs, with reasonable settings
    static func mock(for now: Date = Date()) -> AlgorithmInputFixture {

        func d(_ interval: TimeInterval) -> Date {
            return now.addingTimeInterval(interval)
        }

        let forecastEnd = now.addingTimeInterval(InsulinMath.defaultInsulinActivityDuration).dateCeiledToTimeInterval(GlucoseMath.defaultDelta)

        return AlgorithmInputFixture(
            predictionStart: now,
            glucoseHistory: [
                FixtureGlucoseSample(startDate: d(.minutes(-19)), mgdl: 100),
                FixtureGlucoseSample(startDate: d(.minutes(-14)), mgdl: 120),
                FixtureGlucoseSample(startDate: d(.minutes(-9)), mgdl: 140),
                FixtureGlucoseSample(startDate: d(.minutes(-4)), mgdl: 160),
            ],
            doses: [],
            carbEntries: [],
            basal: [LoopAlgorithm.AbsoluteScheduleValue(startDate: d(.hours(-10)), endDate: now, value: 1.0)],
            sensitivityMgdlPerUnit: [LoopAlgorithm.AbsoluteScheduleValue(startDate: d(.hours(-10)), endDate: forecastEnd, value: 55)],
            carbRatio: [LoopAlgorithm.AbsoluteScheduleValue(startDate: d(.hours(-10)), endDate: now, value: 10)],
            targetMgdl: [LoopAlgorithm.AbsoluteScheduleValue(startDate: d(.hours(-10)), endDate: now, value: 100...110)],
            suspendThresholdMgdl: 65,
            maxBolus: 6,
            maxBasalRate: 8,
            recommendationInsulinType: .novolog,
            recommendationType: .tempBasal
        )
    }
}
