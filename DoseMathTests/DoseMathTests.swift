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


extension ISO8601DateFormatter {
    static func localTimeDateFormatter() -> Self {
        let formatter = self.init()

        formatter.formatOptions = .withInternetDateTime
        formatter.formatOptions.subtract(.withTimeZone)
        formatter.timeZone = .current

        return formatter
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
        let dateFormatter = ISO8601DateFormatter.localTimeDateFormatter()

        return fixture.map {
            return GlucoseFixtureValue(
                startDate: dateFormatter.date(from: $0["date"] as! String)!,
                quantity: HKQuantity(unit: HKUnit.milligramsPerDeciliter(), doubleValue: $0["amount"] as! Double)
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
        return GlucoseRangeSchedule(unit: HKUnit.milligramsPerDeciliter(), dailyItems: [RepeatingScheduleValue(startTime: TimeInterval(0), value: DoubleRange(minValue: 90, maxValue: 120))], overrideRanges: [:])!
    }

    var insulinSensitivitySchedule: InsulinSensitivitySchedule {
        return InsulinSensitivitySchedule(unit: HKUnit.milligramsPerDeciliter(), dailyItems: [RepeatingScheduleValue(startTime: 0.0, value: 60.0)])!
    }
    
    var suspendThreshold: GlucoseThreshold {
        return GlucoseThreshold(unit: HKUnit.milligramsPerDeciliter(), value: 55)
    }

    var insulinModel: InsulinModel {
        return WalshInsulinModel(actionDuration: insulinActionDuration)
    }

    var insulinActionDuration: TimeInterval {
        return TimeInterval(hours: 4)
    }

    func testNoChange() {
        let glucose = loadGlucoseValueFixture("recommend_temp_basal_no_change_glucose")

        let dose = glucose.recommendedTempBasal(
            to: glucoseTargetRange,
            at: glucose.first!.startDate,
            suspendThreshold: suspendThreshold.quantity,
            sensitivity: insulinSensitivitySchedule,
            model: insulinModel,
            basalRates: basalRateSchedule,
            maxBasalRate: maxBasalRate,
            lastTempBasal: nil
        )

        XCTAssertNil(dose)
    }

    func testStartHighEndInRange() {
        let glucose = loadGlucoseValueFixture("recommend_temp_basal_start_high_end_in_range")

        var dose = glucose.recommendedTempBasal(
            to: glucoseTargetRange,
            at: glucose.first!.startDate,
            suspendThreshold: suspendThreshold.quantity,
            sensitivity: insulinSensitivitySchedule,
            model: insulinModel,
            basalRates: basalRateSchedule,
            maxBasalRate: maxBasalRate,
            lastTempBasal: nil
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

        dose = glucose.recommendedTempBasal(
            to: glucoseTargetRange,
            at: glucose.first!.startDate,
            suspendThreshold: suspendThreshold.quantity,
            sensitivity: insulinSensitivitySchedule,
            model: insulinModel,
            basalRates: basalRateSchedule,
            maxBasalRate: maxBasalRate,
            lastTempBasal: lastTempBasal
        )

        XCTAssertEqual(0, dose!.unitsPerHour)
        XCTAssertEqual(TimeInterval(minutes: 0), dose!.duration)
    }

    func testStartLowEndInRange() {
        let glucose = loadGlucoseValueFixture("recommend_temp_basal_start_low_end_in_range")

        var dose = glucose.recommendedTempBasal(
            to: glucoseTargetRange,
            at: glucose.first!.startDate,
            suspendThreshold: suspendThreshold.quantity,
            sensitivity: insulinSensitivitySchedule,
            model: insulinModel,
            basalRates: basalRateSchedule,
            maxBasalRate: maxBasalRate,
            lastTempBasal: nil
        )

        XCTAssertNil(dose)

        let lastTempBasal = DoseEntry(
            type: .tempBasal,
            startDate: glucose.first!.startDate.addingTimeInterval(TimeInterval(minutes: -11)),
            endDate: glucose.first!.startDate.addingTimeInterval(TimeInterval(minutes: 19)),
            value: 1.225,
            unit: .unitsPerHour
        )

        dose = glucose.recommendedTempBasal(
            to: glucoseTargetRange,
            at: glucose.first!.startDate,
            suspendThreshold: suspendThreshold.quantity,
            sensitivity: insulinSensitivitySchedule,
            model: insulinModel,
            basalRates: basalRateSchedule,
            maxBasalRate: maxBasalRate,
            lastTempBasal: lastTempBasal
        )

        XCTAssertEqual(0, dose!.unitsPerHour)
        XCTAssertEqual(TimeInterval(minutes: 0), dose!.duration)
    }

    func testCorrectLowAtMin() {
        let glucose = loadGlucoseValueFixture("recommend_temp_basal_correct_low_at_min")

        // Cancel existing dose
        let lastTempBasal = DoseEntry(
            type: .tempBasal,
            startDate: glucose.first!.startDate.addingTimeInterval(TimeInterval(minutes: -21)),
            endDate: glucose.first!.startDate.addingTimeInterval(TimeInterval(minutes: 9)),
            value: 0.125,
            unit: .unitsPerHour
        )

        var dose = glucose.recommendedTempBasal(
            to: glucoseTargetRange,
            at: glucose.first!.startDate,
            suspendThreshold: suspendThreshold.quantity,
            sensitivity: insulinSensitivitySchedule,
            model: insulinModel,
            basalRates: basalRateSchedule,
            maxBasalRate: maxBasalRate,
            lastTempBasal: lastTempBasal
        )

        XCTAssertEqual(0, dose!.unitsPerHour)
        XCTAssertEqual(TimeInterval(minutes: 0), dose!.duration)

        dose = glucose.recommendedTempBasal(
            to: glucoseTargetRange,
            at: glucose.first!.startDate,
            suspendThreshold: suspendThreshold.quantity,
            sensitivity: insulinSensitivitySchedule,
            model: insulinModel,
            basalRates: basalRateSchedule,
            maxBasalRate: maxBasalRate,
            lastTempBasal: nil
        )

        XCTAssertNil(dose)
    }

    func testStartHighEndLow() {
        let glucose = loadGlucoseValueFixture("recommend_temp_basal_start_high_end_low")

        let dose = glucose.recommendedTempBasal(
            to: glucoseTargetRange,
            at: glucose.first!.startDate,
            suspendThreshold: suspendThreshold.quantity,
            sensitivity: insulinSensitivitySchedule,
            model: insulinModel,
            basalRates: basalRateSchedule,
            maxBasalRate: maxBasalRate,
            lastTempBasal: nil
        )

        XCTAssertEqual(0, dose!.unitsPerHour)
        XCTAssertEqual(TimeInterval(minutes: 30), dose!.duration)
    }

    func testStartLowEndHigh() {
        let glucose = loadGlucoseValueFixture("recommend_temp_basal_start_low_end_high")

        var dose = glucose.recommendedTempBasal(
            to: glucoseTargetRange,
            at: glucose.first!.startDate,
            suspendThreshold: suspendThreshold.quantity,
            sensitivity: insulinSensitivitySchedule,
            model: insulinModel,
            basalRates: basalRateSchedule,
            maxBasalRate: maxBasalRate,
            lastTempBasal: nil
        )

        XCTAssertNil(dose)

        let lastTempBasal = DoseEntry(
            type: .tempBasal,
            startDate: glucose.first!.startDate.addingTimeInterval(TimeInterval(minutes: -11)),
            endDate: glucose.first!.startDate.addingTimeInterval(TimeInterval(minutes: 19)),
            value: 1.225,
            unit: .unitsPerHour
        )

        dose = glucose.recommendedTempBasal(
            to: glucoseTargetRange,
            at: glucose.first!.startDate,
            suspendThreshold: suspendThreshold.quantity,
            sensitivity: insulinSensitivitySchedule,
            model: insulinModel,
            basalRates: basalRateSchedule,
            maxBasalRate: maxBasalRate,
            lastTempBasal: lastTempBasal
        )

        XCTAssertEqual(0, dose!.unitsPerHour)
        XCTAssertEqual(TimeInterval(minutes: 0), dose!.duration)
    }

    func testFlatAndHigh() {
        let glucose = loadGlucoseValueFixture("recommend_temp_basal_flat_and_high")

        let dose = glucose.recommendedTempBasal(
            to: glucoseTargetRange,
            at: glucose.first!.startDate,
            suspendThreshold: suspendThreshold.quantity,
            sensitivity: insulinSensitivitySchedule,
            model: insulinModel,
            basalRates: basalRateSchedule,
            maxBasalRate: maxBasalRate,
            lastTempBasal: nil
        )

        XCTAssertEqual(3.0, dose!.unitsPerHour)
        XCTAssertEqual(TimeInterval(minutes: 30), dose!.duration)
    }

    func testHighAndFalling() {
        let glucose = loadGlucoseValueFixture("recommend_temp_basal_high_and_falling")

        let dose = glucose.recommendedTempBasal(
            to: glucoseTargetRange,
            at: glucose.first!.startDate,
            suspendThreshold: suspendThreshold.quantity,
            sensitivity: insulinSensitivitySchedule,
            model: insulinModel,
            basalRates: basalRateSchedule,
            maxBasalRate: maxBasalRate,
            lastTempBasal: nil
        )

        XCTAssertEqual(1.425, dose!.unitsPerHour, accuracy: 1.0 / 40.0)
        XCTAssertEqual(TimeInterval(minutes: 30), dose!.duration)
    }

    func testInRangeAndRising() {
        let glucose = loadGlucoseValueFixture("recommend_temp_basal_in_range_and_rising")

        let dose = glucose.recommendedTempBasal(
            to: glucoseTargetRange,
            at: glucose.first!.startDate,
            suspendThreshold: suspendThreshold.quantity,
            sensitivity: insulinSensitivitySchedule,
            model: insulinModel,
            basalRates: basalRateSchedule,
            maxBasalRate: maxBasalRate,
            lastTempBasal: nil
        )

        XCTAssertEqual(1.475, dose!.unitsPerHour, accuracy: 1.0 / 40.0)
        XCTAssertEqual(TimeInterval(minutes: 30), dose!.duration)
    }

    func testHighAndRising() {
        let glucose = loadGlucoseValueFixture("recommend_temp_basal_high_and_rising")

        var dose = glucose.recommendedTempBasal(
            to: glucoseTargetRange,
            at: glucose.first!.startDate,
            suspendThreshold: suspendThreshold.quantity,
            sensitivity: self.insulinSensitivitySchedule,
            model: insulinModel,
            basalRates: basalRateSchedule,
            maxBasalRate: maxBasalRate,
            lastTempBasal: nil
        )

        XCTAssertEqual(3.0, dose!.unitsPerHour)
        XCTAssertEqual(TimeInterval(minutes: 30), dose!.duration)

        // Use mmol sensitivity value
        let insulinSensitivitySchedule = InsulinSensitivitySchedule(unit: HKUnit.millimolesPerLiter(), dailyItems: [RepeatingScheduleValue(startTime: 0.0, value: 3.33)])!

        dose = glucose.recommendedTempBasal(
            to: glucoseTargetRange,
            at: glucose.first!.startDate,
            suspendThreshold: suspendThreshold.quantity,
            sensitivity: insulinSensitivitySchedule,
            model: insulinModel,
            basalRates: basalRateSchedule,
            maxBasalRate: maxBasalRate,
            lastTempBasal: nil
        )

        XCTAssertEqual(2.975, dose!.unitsPerHour, accuracy: 1.0 / 40.0)
        XCTAssertEqual(TimeInterval(minutes: 30), dose!.duration)
    }

    func testVeryLowAndRising() {
        let glucose = loadGlucoseValueFixture("recommend_temp_basal_very_low_end_in_range")

        let dose = glucose.recommendedTempBasal(
            to: glucoseTargetRange,
            at: glucose.first!.startDate,
            suspendThreshold: suspendThreshold.quantity,
            sensitivity: insulinSensitivitySchedule,
            model: insulinModel,
            basalRates: basalRateSchedule,
            maxBasalRate: maxBasalRate,
            lastTempBasal: nil
        )
        
        XCTAssertEqual(0.0, dose!.unitsPerHour)
        XCTAssertEqual(TimeInterval(minutes: 30), dose!.duration)
    }

    func testRiseAfterDIA() {
        let glucose = loadGlucoseValueFixture("far_future_high_bg_forecast")

        let dose = glucose.recommendedTempBasal(
            to: glucoseTargetRange,
            at: glucose.first!.startDate,
            suspendThreshold: suspendThreshold.quantity,
            sensitivity: insulinSensitivitySchedule,
            model: insulinModel,
            basalRates: basalRateSchedule,
            maxBasalRate: maxBasalRate,
            lastTempBasal: nil
        )

        XCTAssertNil(dose)
    }


    func testNoInputGlucose() {
        let glucose: [GlucoseValue] = []

        let dose = glucose.recommendedTempBasal(
            to: glucoseTargetRange,
            suspendThreshold: suspendThreshold.quantity,
            sensitivity: insulinSensitivitySchedule,
            model: insulinModel,
            basalRates: basalRateSchedule,
            maxBasalRate: maxBasalRate,
            lastTempBasal: nil
        )

        XCTAssertNil(dose)
    }
}


class RecommendBolusTests: XCTestCase {

    fileprivate let maxBolus = 10.0

    func loadGlucoseValueFixture(_ resourceName: String) -> [GlucoseValue] {
        let fixture: [JSONDictionary] = loadFixture(resourceName)
        let dateFormatter = ISO8601DateFormatter.localTimeDateFormatter()

        return fixture.map {
            return GlucoseFixtureValue(
                startDate: dateFormatter.date(from: $0["date"] as! String)!,
                quantity: HKQuantity(unit: HKUnit.milligramsPerDeciliter(), doubleValue: $0["amount"] as! Double)
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
        return GlucoseRangeSchedule(unit: HKUnit.milligramsPerDeciliter(), dailyItems: [RepeatingScheduleValue(startTime: TimeInterval(0), value: DoubleRange(minValue: 90, maxValue: 120))], overrideRanges: [:])!
    }

    var insulinSensitivitySchedule: InsulinSensitivitySchedule {
        return InsulinSensitivitySchedule(unit: HKUnit.milligramsPerDeciliter(), dailyItems: [RepeatingScheduleValue(startTime: 0.0, value: 60.0)])!
    }
    
    var suspendThreshold: GlucoseThreshold {
        return GlucoseThreshold(unit: HKUnit.milligramsPerDeciliter(), value: 55)
    }

    var insulinModel: InsulinModel {
        return WalshInsulinModel(actionDuration: insulinActionDuration)
    }

    var insulinActionDuration: TimeInterval {
        return TimeInterval(hours: 4)
    }

    func testNoChange() {
        let glucose = loadGlucoseValueFixture("recommend_temp_basal_no_change_glucose")

        let dose = glucose.recommendedBolus(
            to: glucoseTargetRange,
            at: glucose.first!.startDate,
            suspendThreshold: suspendThreshold.quantity,
            sensitivity: insulinSensitivitySchedule,
            model: insulinModel,
            pendingInsulin: 0,
            maxBolus: maxBolus
        )

        XCTAssertEqual(0, dose.amount)
    }

    func testStartHighEndInRange() {
        let glucose = loadGlucoseValueFixture("recommend_temp_basal_start_high_end_in_range")

        let dose = glucose.recommendedBolus(
            to: glucoseTargetRange,
            at: glucose.first!.startDate,
            suspendThreshold: suspendThreshold.quantity,
            sensitivity: insulinSensitivitySchedule,
            model: insulinModel,
            pendingInsulin: 0,
            maxBolus: maxBolus
        )

        XCTAssertEqual(0, dose.amount)
    }

    func testStartLowEndInRange() {
        let glucose = loadGlucoseValueFixture("recommend_temp_basal_start_low_end_in_range")

        let dose = glucose.recommendedBolus(
            to: glucoseTargetRange,
            at: glucose.first!.startDate,
            suspendThreshold: suspendThreshold.quantity,
            sensitivity: insulinSensitivitySchedule,
            model: insulinModel,
            pendingInsulin: 0,
            maxBolus: maxBolus
        )

        XCTAssertEqual(0, dose.amount)
    }

    func testStartHighEndLow() {
        let glucose = loadGlucoseValueFixture("recommend_temp_basal_start_high_end_low")

        let dose = glucose.recommendedBolus(
            to: glucoseTargetRange,
            at: glucose.first!.startDate,
            suspendThreshold: suspendThreshold.quantity,
            sensitivity: insulinSensitivitySchedule,
            model: insulinModel,
            pendingInsulin: 0,
            maxBolus: maxBolus
        )

        XCTAssertEqual(0, dose.amount)
    }

    func testStartLowEndHigh() {
        let glucose = loadGlucoseValueFixture("recommend_temp_basal_start_low_end_high")

        let dose = glucose.recommendedBolus(
            to: glucoseTargetRange,
            at: glucose.first!.startDate,
            suspendThreshold: suspendThreshold.quantity,
            sensitivity: insulinSensitivitySchedule,
            model: insulinModel,
            pendingInsulin: 0,
            maxBolus: maxBolus
        )

        XCTAssertEqual(1.575, dose.amount)

        if case BolusRecommendationNotice.currentGlucoseBelowTarget(let glucose) = dose.notice! {
            XCTAssertEqual(glucose.quantity.doubleValue(for: .milligramsPerDeciliter()), 60)
        } else {
            XCTFail("Expected currentGlucoseBelowTarget, but got \(dose.notice!)")
        }
    }

    func testStartBelowSuspendThresholdEndHigh() {
        // 60 - 200 mg/dL
        let glucose = loadGlucoseValueFixture("recommend_temp_basal_start_low_end_high")

        let dose = glucose.recommendedBolus(
            to: glucoseTargetRange,
            at: glucose.first!.startDate,
            suspendThreshold: HKQuantity(unit: .milligramsPerDeciliter(), doubleValue: 70),
            sensitivity: insulinSensitivitySchedule,
            model: insulinModel,
            pendingInsulin: 0,
            maxBolus: maxBolus
        )

        XCTAssertEqual(0, dose.amount)

        if case BolusRecommendationNotice.glucoseBelowSuspendThreshold(let glucose) = dose.notice! {
            XCTAssertEqual(glucose.quantity.doubleValue(for: .milligramsPerDeciliter()), 60)
        } else {
            XCTFail("Expected currentGlucoseBelowTarget, but got \(dose.notice!)")
        }
    }

    func testStartLowNoSuspendThresholdEndHigh() {
        // 60 - 200 mg/dL
        let glucose = loadGlucoseValueFixture("recommend_temp_basal_start_low_end_high")

        let dose = glucose.recommendedBolus(
            to: glucoseTargetRange,
            at: glucose.first!.startDate,
            suspendThreshold: nil,  // Expected to default to 90
            sensitivity: insulinSensitivitySchedule,
            model: insulinModel,
            pendingInsulin: 0,
            maxBolus: maxBolus
        )

        XCTAssertEqual(0, dose.amount)

        if case BolusRecommendationNotice.glucoseBelowSuspendThreshold(let glucose) = dose.notice! {
            XCTAssertEqual(glucose.quantity.doubleValue(for: .milligramsPerDeciliter()), 60)
        } else {
            XCTFail("Expected currentGlucoseBelowTarget, but got \(dose.notice!)")
        }
    }

    func testDroppingBelowRangeThenRising() {
        let glucose = loadGlucoseValueFixture("recommend_temp_basal_dropping_then_rising")

        let dose = glucose.recommendedBolus(
            to: glucoseTargetRange,
            at: glucose.first!.startDate,
            suspendThreshold: suspendThreshold.quantity,
            sensitivity: insulinSensitivitySchedule,
            model: insulinModel,
            pendingInsulin: 0,
            maxBolus: maxBolus
        )
        
        XCTAssertEqual(1.4, dose.amount)
        XCTAssertEqual(BolusRecommendationNotice.predictedGlucoseBelowTarget(minGlucose: glucose[1]), dose.notice!)
    }


    func testStartLowEndHighWithPendingBolus() {
        let glucose = loadGlucoseValueFixture("recommend_temp_basal_start_low_end_high")
        
        let dose = glucose.recommendedBolus(
            to: glucoseTargetRange,
            at: glucose.first!.startDate,
            suspendThreshold: suspendThreshold.quantity,
            sensitivity: insulinSensitivitySchedule,
            model: insulinModel,
            pendingInsulin: 1,
            maxBolus: maxBolus
        )
        
        XCTAssertEqual(0.575, dose.amount)
    }

    func testStartVeryLowEndHigh() {
        let glucose = loadGlucoseValueFixture("recommend_temp_basal_start_very_low_end_high")
        
        let dose = glucose.recommendedBolus(
            to: glucoseTargetRange,
            at: glucose.first!.startDate,
            suspendThreshold: suspendThreshold.quantity,
            sensitivity: insulinSensitivitySchedule,
            model: insulinModel,
            pendingInsulin: 0,
            maxBolus: maxBolus
        )
        
        XCTAssertEqual(0, dose.amount)
    }

    func testFlatAndHigh() {
        let glucose = loadGlucoseValueFixture("recommend_temp_basal_flat_and_high")

        let dose = glucose.recommendedBolus(
            to: glucoseTargetRange,
            at: glucose.first!.startDate,
            suspendThreshold: suspendThreshold.quantity,
            sensitivity: insulinSensitivitySchedule,
            model: insulinModel,
            pendingInsulin: 0,
            maxBolus: maxBolus
        )

        XCTAssertEqual(1.575, dose.amount, accuracy: 1.0 / 40.0)
    }

    func testHighAndFalling() {
        let glucose = loadGlucoseValueFixture("recommend_temp_basal_high_and_falling")

        let dose = glucose.recommendedBolus(
            to: glucoseTargetRange,
            at: glucose.first!.startDate,
            suspendThreshold: suspendThreshold.quantity,
            sensitivity: insulinSensitivitySchedule,
            model: insulinModel,
            pendingInsulin: 0,
            maxBolus: maxBolus
        )

        XCTAssertEqual(0.325, dose.amount, accuracy: 1.0 / 40.0)
    }

    func testInRangeAndRising() {
        let glucose = loadGlucoseValueFixture("recommend_temp_basal_in_range_and_rising")

        var dose = glucose.recommendedBolus(
            to: glucoseTargetRange,
            at: glucose.first!.startDate,
            suspendThreshold: suspendThreshold.quantity,
            sensitivity: insulinSensitivitySchedule,
            model: insulinModel,
            pendingInsulin: 0,
            maxBolus: maxBolus
        )

        XCTAssertEqual(0.325, dose.amount, accuracy: 1.0 / 40.0)

        // Less existing temp

        dose = glucose.recommendedBolus(
            to: glucoseTargetRange,
            at: glucose.first!.startDate,
            suspendThreshold: suspendThreshold.quantity,
            sensitivity: insulinSensitivitySchedule,
            model: insulinModel,
            pendingInsulin: 0.8,
            maxBolus: maxBolus
        )

        XCTAssertEqual(0, dose.amount, accuracy: .ulpOfOne)
    }

    func testStartLowEndJustAboveRange() {
        let glucose = loadGlucoseValueFixture("recommended_temp_start_low_end_just_above_range")

        let dose = glucose.recommendedBolus(
            to: glucoseTargetRange,
            at: glucose.first!.startDate,
            suspendThreshold: HKQuantity(unit: .milligramsPerDeciliter(), doubleValue: 0),
            sensitivity: insulinSensitivitySchedule,
            model: ExponentialInsulinModel(actionDuration: 21600.0, peakActivityTime: 4500.0),
            pendingInsulin: 0,
            maxBolus: maxBolus
        )

        XCTAssertEqual(0.275, dose.amount)
    }

    func testHighAndRising() {
        let glucose = loadGlucoseValueFixture("recommend_temp_basal_high_and_rising")

        var dose = glucose.recommendedBolus(
            to: glucoseTargetRange,
            at: glucose.first!.startDate,
            suspendThreshold: suspendThreshold.quantity,
            sensitivity: self.insulinSensitivitySchedule,
            model: insulinModel,
            pendingInsulin: 0,
            maxBolus: maxBolus
        )

        XCTAssertEqual(1.25, dose.amount)

        // Use mmol sensitivity value
        let insulinSensitivitySchedule = InsulinSensitivitySchedule(unit: HKUnit.millimolesPerLiter(), dailyItems: [RepeatingScheduleValue(startTime: 0.0, value: 10.0 / 3)])!

        dose = glucose.recommendedBolus(
            to: glucoseTargetRange,
            at: glucose.first!.startDate,
            suspendThreshold: suspendThreshold.quantity,
            sensitivity: insulinSensitivitySchedule,
            model: insulinModel,
            pendingInsulin: 0,
            maxBolus: maxBolus
        )

        XCTAssertEqual(1.25, dose.amount, accuracy: 1.0 / 40.0)
    }

    func testRiseAfterDIA() {
        let glucose = loadGlucoseValueFixture("far_future_high_bg_forecast")

        let dose = glucose.recommendedBolus(
            to: glucoseTargetRange,
            at: glucose.first!.startDate,
            suspendThreshold: suspendThreshold.quantity,
            sensitivity: insulinSensitivitySchedule,
            model: insulinModel,
            pendingInsulin: 0,
            maxBolus: maxBolus
        )

        XCTAssertEqual(0.0, dose.amount)
    }


    func testNoInputGlucose() {
        let glucose: [GlucoseValue] = []

        let dose = glucose.recommendedBolus(
            to: glucoseTargetRange,
            suspendThreshold: suspendThreshold.quantity,
            sensitivity: insulinSensitivitySchedule,
            model: insulinModel,
            pendingInsulin: 0,
            maxBolus: maxBolus
        )

        XCTAssertEqual(0, dose.amount)
    }

}
