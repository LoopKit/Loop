//
//  LoopAlgorithmTests.swift
//  LoopTests
//
//  Created by Pete Schwamb on 8/17/23.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import XCTest
import LoopKit
import LoopCore
import HealthKit
import LoopAlgorithm

final class LoopAlgorithmTests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    public var bundle: Bundle {
        return Bundle(for: type(of: self))
    }

    public func loadFixture<T>(_ resourceName: String) -> T {
        let path = bundle.path(forResource: resourceName, ofType: "json")!
        return try! JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path)), options: []) as! T
    }

    func loadBasalRateScheduleFixture(_ resourceName: String) -> BasalRateSchedule {
        let fixture: [JSONDictionary] = loadFixture(resourceName)

        let items = fixture.map {
            return RepeatingScheduleValue(startTime: TimeInterval(minutes: $0["minutes"] as! Double), value: $0["rate"] as! Double)
        }

        return BasalRateSchedule(dailyItems: items, timeZone: .utcTimeZone)!
    }

    func loadPredictedGlucoseFixture(_ name: String) -> [PredictedGlucoseValue] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let url = bundle.url(forResource: name, withExtension: "json")!
        return try! decoder.decode([PredictedGlucoseValue].self, from: try! Data(contentsOf: url))
    }


    func testLiveCaptureWithFunctionalAlgorithm() {
        // This matches the "testForecastFromLiveCaptureInputData" test of LoopDataManagerDosingTests,
        // Using the same input data, but generating the forecast using the LoopAlgorithm.generatePrediction()
        // function.

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let url = bundle.url(forResource: "live_capture_input", withExtension: "json")!
        let input = try! decoder.decode(LoopPredictionInput.self, from: try! Data(contentsOf: url))

        let prediction = LoopAlgorithm.generatePrediction(
            start: input.glucoseHistory.last?.startDate ?? Date(),
            glucoseHistory: input.glucoseHistory,
            doses: input.doses,
            carbEntries: input.carbEntries,
            basal: input.basal,
            sensitivity: input.sensitivity,
            carbRatio: input.carbRatio,
            useIntegralRetrospectiveCorrection: input.useIntegralRetrospectiveCorrection
        )

        let expectedPredictedGlucose = loadPredictedGlucoseFixture("live_capture_predicted_glucose")

        XCTAssertEqual(expectedPredictedGlucose.count, prediction.glucose.count)

        let defaultAccuracy = 1.0 / 40.0

        for (expected, calculated) in zip(expectedPredictedGlucose, prediction.glucose) {
            XCTAssertEqual(expected.startDate, calculated.startDate)
            XCTAssertEqual(expected.quantity.doubleValue(for: .milligramsPerDeciliter), calculated.quantity.doubleValue(for: .milligramsPerDeciliter), accuracy: defaultAccuracy)
        }
    }

    func testAutoBolusMaxIOBClamping() async {
        let now = ISO8601DateFormatter().date(from: "2020-03-11T12:13:14-0700")!

        var input: LoopAlgorithmInput<StoredCarbEntry, StoredGlucoseSample, DoseEntry> = LoopAlgorithmInput.mock(for: now)
        input.recommendationType = .automaticBolus

        // 8U bolus on board, and 100g carbs; CR = 10, so that should be 10U to cover the carbs
        input.doses = [DoseEntry(type: .bolus, startDate: now.addingTimeInterval(-.minutes(5)), value: 8, unit: .units)]
        input.carbEntries = [
            StoredCarbEntry(startDate: now.addingTimeInterval(.minutes(-5)), quantity: .carbs(value: 100))
        ]

        // Max activeInsulin = 2 x maxBolus = 16U
        input.maxBolus = 8
        var output = LoopAlgorithm.run(input: input)
        var recommendedBolus = output.recommendation!.automatic?.bolusUnits
        var activeInsulin = output.activeInsulin!
        XCTAssertEqual(activeInsulin, 8.0)
        XCTAssertEqual(recommendedBolus!, 1.71, accuracy: 0.01)

        // Now try with maxBolus of 4; should not recommend any more insulin, as we're at our max iob
        input.maxBolus = 4
        output = LoopAlgorithm.run(input: input)
        recommendedBolus = output.recommendation!.automatic?.bolusUnits
        activeInsulin = output.activeInsulin!
        XCTAssertEqual(activeInsulin, 8.0)
        XCTAssertEqual(recommendedBolus!, 0, accuracy: 0.01)
    }

    func testTempBasalMaxIOBClamping() {
        let now = ISO8601DateFormatter().date(from: "2020-03-11T12:13:14-0700")!

        var input = LoopAlgorithmInput.mock(for: now)
        input.recommendationType = .tempBasal

        // 8U bolus on board, and 100g carbs; CR = 10, so that should be 10U to cover the carbs
        input.doses = [DoseEntry(type: .bolus, startDate: now.addingTimeInterval(-.minutes(5)), value: 8, unit: .units)]
        input.carbEntries = [
            StoredCarbEntry(startDate: now.addingTimeInterval(.minutes(-5)), quantity: .carbs(value: 100))
        ]

        // Max activeInsulin = 2 x maxBolus = 16U
        input.maxBolus = 8
        var output = LoopAlgorithm.run(input: input)
        var recommendedRate = output.recommendation!.automatic!.basalAdjustment!.unitsPerHour
        var activeInsulin = output.activeInsulin!
        XCTAssertEqual(activeInsulin, 8.0)
        XCTAssertEqual(recommendedRate, 8.0, accuracy: 0.01)

        // Now try with maxBolus of 4; should only recommend scheduled basal (1U/hr), as we're at our max iob
        input.maxBolus = 4
        output = LoopAlgorithm.run(input: input)
        recommendedRate = output.recommendation!.automatic!.basalAdjustment!.unitsPerHour
        activeInsulin = output.activeInsulin!
        XCTAssertEqual(activeInsulin, 8.0)
        XCTAssertEqual(recommendedRate, 1.0, accuracy: 0.01)
    }
}


extension LoopAlgorithmInput<StoredCarbEntry, StoredGlucoseSample, DoseEntry> {
    static func mock(for date: Date, glucose: [Double] = [100, 120, 140, 160]) -> LoopAlgorithmInput {

        func d(_ interval: TimeInterval) -> Date {
            return date.addingTimeInterval(interval)
        }

        var input = LoopAlgorithmInput<StoredCarbEntry, StoredGlucoseSample, DoseEntry>(
            predictionStart: date,
            glucoseHistory: [],
            doses: [],
            carbEntries: [],
            basal: [],
            sensitivity: [],
            carbRatio: [],
            target: [],
            suspendThreshold: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 65),
            maxBolus: 6,
            maxBasalRate: 8,
            recommendationInsulinType: .novolog,
            recommendationType: .automaticBolus
        )

        for (idx, value) in glucose.enumerated() {
            let entry = StoredGlucoseSample(startDate: d(.minutes(Double(-(glucose.count - idx)*5)) + .minutes(1)), quantity: .glucose(value: value))
            input.glucoseHistory.append(entry)
        }

        input.doses = [
            DoseEntry(type: .bolus, startDate: d(.minutes(-3)), value: 1.0, unit: .units)
        ]

        input.carbEntries = [
            StoredCarbEntry(startDate: d(.minutes(-4)), quantity: .carbs(value: 20))
        ]

        let forecastEndTime = date.addingTimeInterval(InsulinMath.defaultInsulinActivityDuration).dateCeiledToTimeInterval(.minutes(GlucoseMath.defaultDelta))
        let dosesStart = date.addingTimeInterval(-(CarbMath.maximumAbsorptionTimeInterval + InsulinMath.defaultInsulinActivityDuration))
        let carbsStart = date.addingTimeInterval(-CarbMath.maximumAbsorptionTimeInterval)


        let basalRateSchedule = BasalRateSchedule(
            dailyItems: [
                RepeatingScheduleValue(startTime: 0, value: 1),
            ],
            timeZone: .utcTimeZone
        )!
        input.basal = basalRateSchedule.between(start: dosesStart, end: date)

        let insulinSensitivitySchedule = InsulinSensitivitySchedule(
            unit: .milligramsPerDeciliter,
            dailyItems: [
                RepeatingScheduleValue(startTime: 0, value: 45),
                RepeatingScheduleValue(startTime: 32400, value: 55)
            ],
            timeZone: .utcTimeZone
        )!
        input.sensitivity = insulinSensitivitySchedule.quantitiesBetween(start: dosesStart, end: forecastEndTime)

        let carbRatioSchedule = CarbRatioSchedule(
            unit: .gram(),
            dailyItems: [
                RepeatingScheduleValue(startTime: 0.0, value: 10.0),
            ],
            timeZone: .utcTimeZone
        )!
        input.carbRatio = carbRatioSchedule.between(start: carbsStart, end: date)

        let targetSchedule = GlucoseRangeSchedule(
            unit: .milligramsPerDeciliter,
            dailyItems: [
                RepeatingScheduleValue(startTime: 0, value: DoubleRange(minValue: 100, maxValue: 110)),
            ],
            timeZone: .utcTimeZone
        )!
        input.target = targetSchedule.quantityBetween(start: date, end: forecastEndTime)
        return input
    }
}

