//
//  DoseMathTests.swift
//  NateradeTests
//
//  Created by Nathan Racklyeft on 3/8/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import XCTest
import HealthKit
import InsulinKit
import LoopKit


extension XCTestCase {
    public var bundle: Bundle {
        return Bundle(for: type(of: self))
    }

    public func loadFixture<T>(_ resourceName: String) -> T {
        let path = bundle.path(forResource: resourceName, ofType: "json")!
        return try! JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path)), options: []) as! T
    }
}


public typealias JSONDictionary = [String: Any]


extension DateFormatter {
    static func ISO8601LocalTimeDateFormatter() -> Self {
        let dateFormatter = self.init()

        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")

        return dateFormatter
    }
}


struct GlucoseFixtureValue: GlucoseValue {
    let startDate: Date
    let quantity: HKQuantity

    init(startDate: Date, quantity: HKQuantity) {
        self.startDate = startDate
        self.quantity = quantity
    }
}


class RecommendTempBasalTests: XCTestCase {

    fileprivate let maxBasalRate = 3.0

    func loadGlucoseValueFixture(_ resourceName: String) -> [GlucoseValue] {
        let fixture: [JSONDictionary] = loadFixture(resourceName)
        let dateFormatter = DateFormatter.ISO8601LocalTimeDateFormatter()

        return fixture.map {
            return GlucoseFixtureValue(
                startDate: dateFormatter.date(from: $0["date"] as! String)!,
                quantity: HKQuantity(unit: HKUnit.milligramsPerDeciliterUnit(), doubleValue: $0["amount"] as! Double)
            )
        }
    }

    func loadBasalRateScheduleFixture(_ resourceName: String) -> BasalRateSchedule {
        let fixture: [JSONDictionary] = loadFixture(resourceName)

        let items = fixture.map {
            return RepeatingScheduleValue(startTime: TimeInterval(minutes: $0["minutes"] as! Double), value: $0["rate"] as! Double)
        }

        return BasalRateSchedule(dailyItems: items)!
    }

    var basalRateSchedule: BasalRateSchedule {
        return loadBasalRateScheduleFixture("read_selected_basal_profile")
    }

    var glucoseTargetRange: GlucoseRangeSchedule {
        return GlucoseRangeSchedule(unit: HKUnit.milligramsPerDeciliterUnit(), dailyItems: [RepeatingScheduleValue(startTime: TimeInterval(0), value: DoubleRange(minValue: 90, maxValue: 120))], workoutRange: nil)!
    }

    var insulinSensitivitySchedule: InsulinSensitivitySchedule {
        return InsulinSensitivitySchedule(unit: HKUnit.milligramsPerDeciliterUnit(), dailyItems: [RepeatingScheduleValue(startTime: 0.0, value: 60.0)])!
    }

    func testNoChange() {
        let glucose = loadGlucoseValueFixture("recommend_temp_basal_no_change_glucose")

        let dose = DoseMath.recommendTempBasalFromPredictedGlucose(glucose,
            atDate: glucose.first!.startDate,
            lastTempBasal: nil,
            maxBasalRate: maxBasalRate,
            glucoseTargetRange: glucoseTargetRange,
            insulinSensitivity: insulinSensitivitySchedule,
            basalRateSchedule: basalRateSchedule
        )

        XCTAssertNil(dose)
    }

    func testStartHighEndInRange() {
        let glucose = loadGlucoseValueFixture("recommend_temp_basal_start_high_end_in_range")

        var dose = DoseMath.recommendTempBasalFromPredictedGlucose(glucose,
            atDate: glucose.first!.startDate,
            lastTempBasal: nil,
            maxBasalRate: maxBasalRate,
            glucoseTargetRange: glucoseTargetRange,
            insulinSensitivity: insulinSensitivitySchedule,
            basalRateSchedule: basalRateSchedule
        )

        XCTAssertNil(dose)

        // Cancel existing temp basal
        let lastTempBasal = DoseEntry(
            type: .tempBasal,
            startDate: glucose.first!.startDate.addingTimeInterval(TimeInterval(minutes: -11)),
            endDate: glucose.first!.startDate.addingTimeInterval(TimeInterval(minutes: 19)),
            value: 0.125,
            unit: .unitsPerHour
        )

        dose = DoseMath.recommendTempBasalFromPredictedGlucose(glucose,
            atDate: glucose.first!.startDate,
            lastTempBasal: lastTempBasal,
            maxBasalRate: maxBasalRate,
            glucoseTargetRange: glucoseTargetRange,
            insulinSensitivity: insulinSensitivitySchedule,
            basalRateSchedule: basalRateSchedule
        )

        XCTAssertEqual(0, dose!.rate)
        XCTAssertEqual(TimeInterval(minutes: 0), dose!.duration)
    }

    func testStartLowEndInRange() {
        let glucose = loadGlucoseValueFixture("recommend_temp_basal_start_low_end_in_range")

        var dose = DoseMath.recommendTempBasalFromPredictedGlucose(glucose,
            atDate: glucose.first!.startDate,
            lastTempBasal: nil,
            maxBasalRate: maxBasalRate,
            glucoseTargetRange: glucoseTargetRange,
            insulinSensitivity: insulinSensitivitySchedule,
            basalRateSchedule: basalRateSchedule
        )

        XCTAssertNil(dose)

        let lastTempBasal = DoseEntry(
            type: .tempBasal,
            startDate: glucose.first!.startDate.addingTimeInterval(TimeInterval(minutes: -11)),
            endDate: glucose.first!.startDate.addingTimeInterval(TimeInterval(minutes: 19)),
            value: 1.225,
            unit: .unitsPerHour
        )

        dose = DoseMath.recommendTempBasalFromPredictedGlucose(glucose,
            atDate: glucose.first!.startDate,
            lastTempBasal: lastTempBasal,
            maxBasalRate: maxBasalRate,
            glucoseTargetRange: glucoseTargetRange,
            insulinSensitivity: insulinSensitivitySchedule,
            basalRateSchedule: basalRateSchedule
        )

        XCTAssertEqual(0, dose!.rate)
        XCTAssertEqual(TimeInterval(minutes: 0), dose!.duration)
    }

    func testCorrectLowAtMin() {
        let glucose = loadGlucoseValueFixture("recommend_temp_basal_correct_low_at_min")

        // Cancel existing dose
        var lastTempBasal = DoseEntry(
            type: .tempBasal,
            startDate: glucose.first!.startDate.addingTimeInterval(TimeInterval(minutes: -21)),
            endDate: glucose.first!.startDate.addingTimeInterval(TimeInterval(minutes: 9)),
            value: 0.125,
            unit: .unitsPerHour
        )

        var dose = DoseMath.recommendTempBasalFromPredictedGlucose(glucose,
            atDate: glucose.first!.startDate,
            lastTempBasal: lastTempBasal,
            maxBasalRate: maxBasalRate,
            glucoseTargetRange: glucoseTargetRange,
            insulinSensitivity: insulinSensitivitySchedule,
            basalRateSchedule: basalRateSchedule
        )

        XCTAssertEqual(0, dose!.rate)
        XCTAssertEqual(TimeInterval(minutes: 0), dose!.duration)

        // Allow predictive temp below range
        dose = DoseMath.recommendTempBasalFromPredictedGlucose(glucose,
            atDate: glucose.first!.startDate,
            lastTempBasal: nil,
            maxBasalRate: maxBasalRate,
            glucoseTargetRange: glucoseTargetRange,
            insulinSensitivity: insulinSensitivitySchedule,
            basalRateSchedule: basalRateSchedule
        )

        XCTAssertNil(dose)

        lastTempBasal = DoseEntry(
            type: .tempBasal,
            startDate: glucose.first!.startDate.addingTimeInterval(TimeInterval(minutes: -21)),
            endDate: glucose.first!.startDate.addingTimeInterval(TimeInterval(minutes: 9)),
            value: 0.125,
            unit: .unitsPerHour
        )

        dose = DoseMath.recommendTempBasalFromPredictedGlucose(glucose,
            atDate: glucose.first!.startDate,
            lastTempBasal: lastTempBasal,
            maxBasalRate: maxBasalRate,
            glucoseTargetRange: glucoseTargetRange,
            insulinSensitivity: insulinSensitivitySchedule,
            basalRateSchedule: basalRateSchedule
        )

        XCTAssertEqual(0, dose!.rate)
        XCTAssertEqual(TimeInterval(minutes: 0), dose!.duration)
    }

    func testStartHighEndLow() {
        let glucose = loadGlucoseValueFixture("recommend_temp_basal_start_high_end_low")

        let dose = DoseMath.recommendTempBasalFromPredictedGlucose(glucose,
            atDate: glucose.first!.startDate,
            lastTempBasal: nil,
            maxBasalRate: maxBasalRate,
            glucoseTargetRange: glucoseTargetRange,
            insulinSensitivity: insulinSensitivitySchedule,
            basalRateSchedule: basalRateSchedule
        )

        XCTAssertEqual(0, dose!.rate)
        XCTAssertEqual(TimeInterval(minutes: 30), dose!.duration)
    }

    func testStartLowEndHigh() {
        let glucose = loadGlucoseValueFixture("recommend_temp_basal_start_low_end_high")

        // Allow predictive temp below range
        var dose = DoseMath.recommendTempBasalFromPredictedGlucose(glucose,
            atDate: glucose.first!.startDate,
            lastTempBasal: nil,
            maxBasalRate: maxBasalRate,
            glucoseTargetRange: glucoseTargetRange,
            insulinSensitivity: insulinSensitivitySchedule,
            basalRateSchedule: basalRateSchedule
        )

        XCTAssertNil(dose)

        let lastTempBasal = DoseEntry(
            type: .tempBasal,
            startDate: glucose.first!.startDate.addingTimeInterval(TimeInterval(minutes: -11)),
            endDate: glucose.first!.startDate.addingTimeInterval(TimeInterval(minutes: 19)),
            value: 1.225,
            unit: .unitsPerHour
        )

        dose = DoseMath.recommendTempBasalFromPredictedGlucose(glucose,
            atDate: glucose.first!.startDate,
            lastTempBasal: lastTempBasal,
            maxBasalRate: maxBasalRate,
            glucoseTargetRange: glucoseTargetRange,
            insulinSensitivity: insulinSensitivitySchedule,
            basalRateSchedule: basalRateSchedule
        )

        XCTAssertEqual(0, dose!.rate)
        XCTAssertEqual(TimeInterval(minutes: 0), dose!.duration)
    }

    func testFlatAndHigh() {
        let glucose = loadGlucoseValueFixture("recommend_temp_basal_flat_and_high")

        let dose = DoseMath.recommendTempBasalFromPredictedGlucose(glucose,
            atDate: glucose.first!.startDate,
            lastTempBasal: nil,
            maxBasalRate: maxBasalRate,
            glucoseTargetRange: glucoseTargetRange,
            insulinSensitivity: insulinSensitivitySchedule,
            basalRateSchedule: basalRateSchedule
        )

        XCTAssertEqual(3.0, dose!.rate)
        XCTAssertEqual(TimeInterval(minutes: 30), dose!.duration)
    }

    func testHighAndFalling() {
        let glucose = loadGlucoseValueFixture("recommend_temp_basal_high_and_falling")

        let dose = DoseMath.recommendTempBasalFromPredictedGlucose(glucose,
            atDate: glucose.first!.startDate,
            lastTempBasal: nil,
            maxBasalRate: maxBasalRate,
            glucoseTargetRange: glucoseTargetRange,
            insulinSensitivity: insulinSensitivitySchedule,
            basalRateSchedule: basalRateSchedule
        )

        XCTAssertEqualWithAccuracy(1.425, dose!.rate, accuracy: 1.0 / 40.0)
        XCTAssertEqual(TimeInterval(minutes: 30), dose!.duration)
    }

    func testInRangeAndRising() {
        let glucose = loadGlucoseValueFixture("recommend_temp_basal_in_range_and_rising")

        let dose = DoseMath.recommendTempBasalFromPredictedGlucose(glucose,
            atDate: glucose.first!.startDate,
            lastTempBasal: nil,
            maxBasalRate: maxBasalRate,
            glucoseTargetRange: glucoseTargetRange,
            insulinSensitivity: insulinSensitivitySchedule,
            basalRateSchedule: basalRateSchedule
        )

        XCTAssertEqualWithAccuracy(1.475, dose!.rate, accuracy: 1.0 / 40.0)
        XCTAssertEqual(TimeInterval(minutes: 30), dose!.duration)
    }

    func testHighAndRising() {
        let glucose = loadGlucoseValueFixture("recommend_temp_basal_high_and_rising")

        var dose = DoseMath.recommendTempBasalFromPredictedGlucose(glucose,
            atDate: glucose.first!.startDate,
            lastTempBasal: nil,
            maxBasalRate: maxBasalRate,
            glucoseTargetRange: glucoseTargetRange,
            insulinSensitivity: self.insulinSensitivitySchedule,
            basalRateSchedule: basalRateSchedule
        )

        XCTAssertEqual(3.0, dose!.rate)
        XCTAssertEqual(TimeInterval(minutes: 30), dose!.duration)

        // Use mmol sensitivity value
        let insulinSensitivitySchedule = InsulinSensitivitySchedule(unit: HKUnit.millimolesPerLiterUnit(), dailyItems: [RepeatingScheduleValue(startTime: 0.0, value: 3.33)])!

        dose = DoseMath.recommendTempBasalFromPredictedGlucose(glucose,
            atDate: glucose.first!.startDate,
            lastTempBasal: nil,
            maxBasalRate: maxBasalRate,
            glucoseTargetRange: glucoseTargetRange,
            insulinSensitivity: insulinSensitivitySchedule,
            basalRateSchedule: basalRateSchedule
        )

        XCTAssertEqualWithAccuracy(2.975, dose!.rate, accuracy: 1.0 / 40.0)
        XCTAssertEqual(TimeInterval(minutes: 30), dose!.duration)
    }

    func testVeryLowAndRising() {
        let glucose = loadGlucoseValueFixture("recommend_tamp_basal_very_low_end_in_range")

        let dose = DoseMath.recommendTempBasalFromPredictedGlucose(glucose,
                                                                   atDate: glucose.first!.startDate,
                                                                   lastTempBasal: nil,
                                                                   maxBasalRate: maxBasalRate,
                                                                   glucoseTargetRange: glucoseTargetRange,
                                                                   insulinSensitivity: self.insulinSensitivitySchedule,
                                                                   basalRateSchedule: basalRateSchedule
        )
        
        XCTAssertEqual(0.0, dose!.rate)
        XCTAssertEqual(TimeInterval(minutes: 30), dose!.duration)
    }


    func testNoInputGlucose() {
        let dose = DoseMath.recommendTempBasalFromPredictedGlucose([],
            lastTempBasal: nil,
            maxBasalRate: maxBasalRate,
            glucoseTargetRange: glucoseTargetRange,
            insulinSensitivity: insulinSensitivitySchedule,
            basalRateSchedule: basalRateSchedule
        )

        XCTAssertNil(dose)
    }
}


class RecommendBolusTests: XCTestCase {

    fileprivate let maxBolus = 10.0

    func loadGlucoseValueFixture(_ resourceName: String) -> [GlucoseValue] {
        let fixture: [JSONDictionary] = loadFixture(resourceName)
        let dateFormatter = DateFormatter.ISO8601LocalTimeDateFormatter()

        return fixture.map {
            return GlucoseFixtureValue(
                startDate: dateFormatter.date(from: $0["date"] as! String)!,
                quantity: HKQuantity(unit: HKUnit.milligramsPerDeciliterUnit(), doubleValue: $0["amount"] as! Double)
            )
        }
    }

    func loadBasalRateScheduleFixture(_ resourceName: String) -> BasalRateSchedule {
        let fixture: [JSONDictionary] = loadFixture(resourceName)

        let items = fixture.map {
            return RepeatingScheduleValue(startTime: TimeInterval(minutes: $0["minutes"] as! Double), value: $0["rate"] as! Double)
        }

        return BasalRateSchedule(dailyItems: items)!
    }

    var basalRateSchedule: BasalRateSchedule {
        return loadBasalRateScheduleFixture("read_selected_basal_profile")
    }

    var glucoseTargetRange: GlucoseRangeSchedule {
        return GlucoseRangeSchedule(unit: HKUnit.milligramsPerDeciliterUnit(), dailyItems: [RepeatingScheduleValue(startTime: TimeInterval(0), value: DoubleRange(minValue: 90, maxValue: 120))], workoutRange: nil)!
    }

    var insulinSensitivitySchedule: InsulinSensitivitySchedule {
        return InsulinSensitivitySchedule(unit: HKUnit.milligramsPerDeciliterUnit(), dailyItems: [RepeatingScheduleValue(startTime: 0.0, value: 60.0)])!
    }

    func testNoChange() {
        let glucose = loadGlucoseValueFixture("recommend_temp_basal_no_change_glucose")

        let dose = DoseMath.recommendBolusFromPredictedGlucose(glucose,
            atDate: glucose.first!.startDate,
            lastTempBasal: nil,
            maxBolus: maxBolus,
            glucoseTargetRange: glucoseTargetRange,
            insulinSensitivity: insulinSensitivitySchedule,
            basalRateSchedule: basalRateSchedule
        )

        XCTAssertEqual(0, dose)
    }

    func testStartHighEndInRange() {
        let glucose = loadGlucoseValueFixture("recommend_temp_basal_start_high_end_in_range")

        var dose = DoseMath.recommendBolusFromPredictedGlucose(glucose,
            atDate: glucose.first!.startDate,
            lastTempBasal: nil,
            maxBolus: maxBolus,
            glucoseTargetRange: glucoseTargetRange,
            insulinSensitivity: insulinSensitivitySchedule,
            basalRateSchedule: basalRateSchedule
        )

        XCTAssertEqual(0, dose)

        // Don't consider net-negative temp basal
        let lastTempBasal = DoseEntry(
            type: .tempBasal,
            startDate: glucose.first!.startDate.addingTimeInterval(TimeInterval(minutes: -11)),
            endDate: glucose.first!.startDate.addingTimeInterval(TimeInterval(minutes: 19)),
            value: 0.01,
            unit: .unitsPerHour
        )

        dose = DoseMath.recommendBolusFromPredictedGlucose(glucose,
            atDate: glucose.first!.startDate,
            lastTempBasal: lastTempBasal,
            maxBolus: maxBolus,
            glucoseTargetRange: glucoseTargetRange,
            insulinSensitivity: insulinSensitivitySchedule,
            basalRateSchedule: basalRateSchedule
        )

        XCTAssertEqual(0, dose)
    }

    func testStartLowEndInRange() {
        let glucose = loadGlucoseValueFixture("recommend_temp_basal_start_low_end_in_range")

        let dose = DoseMath.recommendBolusFromPredictedGlucose(glucose,
            atDate: glucose.first!.startDate,
            lastTempBasal: nil,
            maxBolus: maxBolus,
            glucoseTargetRange: glucoseTargetRange,
            insulinSensitivity: insulinSensitivitySchedule,
            basalRateSchedule: basalRateSchedule
        )

        XCTAssertEqual(0, dose)
    }

    func testStartHighEndLow() {
        let glucose = loadGlucoseValueFixture("recommend_temp_basal_start_high_end_low")

        let dose = DoseMath.recommendBolusFromPredictedGlucose(glucose,
            atDate: glucose.first!.startDate,
            lastTempBasal: nil,
            maxBolus: maxBolus,
            glucoseTargetRange: glucoseTargetRange,
            insulinSensitivity: insulinSensitivitySchedule,
            basalRateSchedule: basalRateSchedule
        )

        XCTAssertEqual(0, dose)
    }

    func testStartLowEndHigh() {
        let glucose = loadGlucoseValueFixture("recommend_temp_basal_start_low_end_high")

        let dose = DoseMath.recommendBolusFromPredictedGlucose(glucose,
            atDate: glucose.first!.startDate,
            lastTempBasal: nil,
            maxBolus: maxBolus,
            glucoseTargetRange: glucoseTargetRange,
            insulinSensitivity: insulinSensitivitySchedule,
            basalRateSchedule: basalRateSchedule
        )

        XCTAssertEqual(0, dose)
    }

    func testFlatAndHigh() {
        let glucose = loadGlucoseValueFixture("recommend_temp_basal_flat_and_high")

        let dose = DoseMath.recommendBolusFromPredictedGlucose(glucose,
            atDate: glucose.first!.startDate,
            lastTempBasal: nil,
            maxBolus: maxBolus,
            glucoseTargetRange: glucoseTargetRange,
            insulinSensitivity: insulinSensitivitySchedule,
            basalRateSchedule: basalRateSchedule
        )

        XCTAssertEqualWithAccuracy(1.333, dose, accuracy: 1.0 / 40.0)
    }

    func testHighAndFalling() {
        let glucose = loadGlucoseValueFixture("recommend_temp_basal_high_and_falling")

        let dose = DoseMath.recommendBolusFromPredictedGlucose(glucose,
            atDate: glucose.first!.startDate,
            lastTempBasal: nil,
            maxBolus: maxBolus,
            glucoseTargetRange: glucoseTargetRange,
            insulinSensitivity: insulinSensitivitySchedule,
            basalRateSchedule: basalRateSchedule
        )

        XCTAssertEqualWithAccuracy(0.067, dose, accuracy: 1.0 / 40.0)
    }

    func testInRangeAndRising() {
        let glucose = loadGlucoseValueFixture("recommend_temp_basal_in_range_and_rising")

        var dose = DoseMath.recommendBolusFromPredictedGlucose(glucose,
            atDate: glucose.first!.startDate,
            lastTempBasal: nil,
            maxBolus: maxBolus,
            glucoseTargetRange: glucoseTargetRange,
            insulinSensitivity: insulinSensitivitySchedule,
            basalRateSchedule: basalRateSchedule
        )

        XCTAssertEqualWithAccuracy(0.083, dose, accuracy: 1.0 / 40.0)

        // Less existing temp
        var lastTempBasal = DoseEntry(
            type: .tempBasal,
            startDate: glucose.first!.startDate.addingTimeInterval(TimeInterval(minutes: -11)),
            endDate: glucose.first!.startDate.addingTimeInterval(TimeInterval(minutes: 19)),
            value: 1.225,
            unit: .unitsPerHour
        )

        dose = DoseMath.recommendBolusFromPredictedGlucose(glucose,
            atDate: glucose.first!.startDate,
            lastTempBasal: lastTempBasal,
            maxBolus: maxBolus,
            glucoseTargetRange: glucoseTargetRange,
            insulinSensitivity: insulinSensitivitySchedule,
            basalRateSchedule: basalRateSchedule
        )

        XCTAssertEqualWithAccuracy(0, dose, accuracy: 1e-13)

        // But not a finished temp
        lastTempBasal = DoseEntry(
            type: .tempBasal,
            startDate: glucose.first!.startDate.addingTimeInterval(TimeInterval(minutes: -35)),
            endDate: glucose.first!.startDate.addingTimeInterval(TimeInterval(minutes: -5)),
            value: 1.225,
            unit: .unitsPerHour
        )

        dose = DoseMath.recommendBolusFromPredictedGlucose(glucose,
            atDate: glucose.first!.startDate,
            lastTempBasal: lastTempBasal,
            maxBolus: maxBolus,
            glucoseTargetRange: glucoseTargetRange,
            insulinSensitivity: insulinSensitivitySchedule,
            basalRateSchedule: basalRateSchedule
        )

        XCTAssertEqualWithAccuracy(0.083, dose, accuracy: 1.0 / 40.0)
    }

    func testHighAndRising() {
        let glucose = loadGlucoseValueFixture("recommend_temp_basal_high_and_rising")

        var dose = DoseMath.recommendBolusFromPredictedGlucose(glucose,
            atDate: glucose.first!.startDate,
            lastTempBasal: nil,
            maxBolus: maxBolus,
            glucoseTargetRange: glucoseTargetRange,
            insulinSensitivity: self.insulinSensitivitySchedule,
            basalRateSchedule: basalRateSchedule
        )

        XCTAssertEqual(1.0, dose)

        // Use mmol sensitivity value
        let insulinSensitivitySchedule = InsulinSensitivitySchedule(unit: HKUnit.millimolesPerLiterUnit(), dailyItems: [RepeatingScheduleValue(startTime: 0.0, value: 10.0 / 3)])!

        dose = DoseMath.recommendBolusFromPredictedGlucose(glucose,
            atDate: glucose.first!.startDate,
            lastTempBasal: nil,
            maxBolus: maxBolus,
            glucoseTargetRange: glucoseTargetRange,
            insulinSensitivity: insulinSensitivitySchedule,
            basalRateSchedule: basalRateSchedule
        )

        XCTAssertEqualWithAccuracy(1.0, dose, accuracy: 1.0 / 40.0)
    }

    func testNoInputGlucose() {
        let dose = DoseMath.recommendBolusFromPredictedGlucose([], lastTempBasal: nil, maxBolus: 4, glucoseTargetRange: glucoseTargetRange, insulinSensitivity: insulinSensitivitySchedule,
            basalRateSchedule: basalRateSchedule)

        XCTAssertEqual(0, dose)
    }

}
