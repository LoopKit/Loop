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


    func testLiveCaptureWithFunctionalAlgorithm() throws {
        // This matches the "testForecastFromLiveCaptureInputData" test of LoopDataManagerDosingTests,
        // Using the same input data, but generating the forecast using LoopPrediction

        let mockGlucoseStore = MockGlucoseStore(for: .liveCapture)
        let historicGlucose = mockGlucoseStore.storedGlucose!

        let mockDoseStore = MockDoseStore(for: .liveCapture)
        let doses = mockDoseStore.doseHistory!

        let mockCarbStore = MockCarbStore(for: .liveCapture)
        let carbEntries = mockCarbStore.carbHistory!

        let baseTime = historicGlucose.last!.startDate
        let treatmentInterval = LoopAlgorithm.treatmentHistoryDateInterval(for: baseTime)


        let isfStart = min(treatmentInterval.start, doses.map { $0.startDate }.min() ?? .distantFuture)
        let isfEnd = baseTime.addingTimeInterval(InsulinMath.defaultInsulinActivityDuration).dateCeiledToTimeInterval(GlucoseMath.defaultDelta)

        let basalRateSchedule = loadBasalRateScheduleFixture("basal_profile")

        let insulinSensitivitySchedule = InsulinSensitivitySchedule(
            unit: .milligramsPerDeciliter,
            dailyItems: [
                RepeatingScheduleValue(startTime: 0, value: 45),
                RepeatingScheduleValue(startTime: 32400, value: 55)
            ],
            timeZone: .utcTimeZone
        )!
        let carbRatioSchedule = CarbRatioSchedule(
            unit: .gram(),
            dailyItems: [
                RepeatingScheduleValue(startTime: 0.0, value: 10.0),
            ],
            timeZone: .utcTimeZone
        )!

        let glucoseTargetRangeSchedule = GlucoseRangeSchedule(
            unit: HKUnit.milligramsPerDeciliter,
            dailyItems: [
                RepeatingScheduleValue(startTime: TimeInterval(0), value: DoubleRange(minValue: 100, maxValue: 110)),
                RepeatingScheduleValue(startTime: TimeInterval(28800), value: DoubleRange(minValue: 90, maxValue: 100)),
                RepeatingScheduleValue(startTime: TimeInterval(75600), value: DoubleRange(minValue: 100, maxValue: 110))
            ], 
            timeZone: .utcTimeZone)!

        let settings = LoopAlgorithmSettings(
            basal: basalRateSchedule.between(start: treatmentInterval.start, end: treatmentInterval.end),
            sensitivity: insulinSensitivitySchedule.quantitiesBetween(start: isfStart, end: isfEnd),
            carbRatio: carbRatioSchedule.between(start: treatmentInterval.start, end: treatmentInterval.end),
            target: glucoseTargetRangeSchedule.quantityBetween(start: baseTime, end: isfEnd),
            maximumBasalRatePerHour: 5.0,
            maximumBolus: 10,
            suspendThreshold: GlucoseThreshold(unit: HKUnit.milligramsPerDeciliter, value: 75))

        let input = LoopPredictionInput(
            glucoseHistory: historicGlucose,
            doses: doses,
            carbEntries: carbEntries,
            settings: settings)

        let prediction = try LoopAlgorithm.generatePrediction(input: input)

        let expectedPredictedGlucose = loadPredictedGlucoseFixture("live_capture_predicted_glucose")

        XCTAssertEqual(expectedPredictedGlucose.count, prediction.glucose.count)

        let defaultAccuracy = 1.0 / 40.0

        for (expected, calculated) in zip(expectedPredictedGlucose, prediction.glucose) {
            XCTAssertEqual(expected.startDate, calculated.startDate)
            XCTAssertEqual(expected.quantity.doubleValue(for: .milligramsPerDeciliter), calculated.quantity.doubleValue(for: .milligramsPerDeciliter), accuracy: defaultAccuracy)
        }

        //XCTAssertEqual(1.99, recommendedBasal!.unitsPerHour, accuracy: defaultAccuracy)
    }

    func testPerformanceExample() throws {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }

}
