//
//  CarbMathTests.swift
//  CarbKitTests
//
//  Created by Nathan Racklyeft on 1/18/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import XCTest
@testable import CarbKit
import LoopKit
import HealthKit

typealias JSONDictionary = [String: AnyObject]


class CarbMathTests: XCTestCase {

    func loadFixture<T>(resourceName: String) -> T {
        let path = NSBundle(forClass: self.dynamicType).pathForResource(resourceName, ofType: "json")!
        return try! NSJSONSerialization.JSONObjectWithData(NSData(contentsOfFile: path)!, options: []) as! T
    }

    func loadSchedules() -> (CarbRatioSchedule, InsulinSensitivitySchedule) {
        let fixture: JSONDictionary = loadFixture("read_carb_ratios")
        let schedule = fixture["schedule"] as! [JSONDictionary]

        let items = schedule.map {
            return ScheduleItem(startTime: NSTimeInterval(minutes: $0["offset"] as! Double), value: $0["ratio"] as! Double)
        }

        return (
            CarbRatioSchedule(unit: HKUnit.gramUnit(), dailyItems: items)!,
            InsulinSensitivitySchedule(unit: HKUnit.milligramsPerDeciliterUnit(), dailyItems: [ScheduleItem(startTime: 0.0, value: 40.0)])!
        )
    }

    func loadInputFixture() -> [CarbEntry] {
        let fixture: [JSONDictionary] = loadFixture("carb_effect_from_history_input")
        let dateFormatter = NSDateFormatter.ISO8601LocalTimeDateFormatter()

        return fixture.map {
            return NewCarbEntry(
                quantity: HKQuantity(unit: HKUnit(fromString: $0["unit"] as! String), doubleValue: $0["amount"] as! Double),
                startDate: dateFormatter.dateFromString($0["start_at"] as! String)!,
                foodType: nil,
                absorptionTime: nil
            )
        }
    }

    func loadEffectOutputFixture() -> [GlucoseEffect] {
        let fixture: [JSONDictionary] = loadFixture("carb_effect_from_history_output")
        let dateFormatter = NSDateFormatter.ISO8601LocalTimeDateFormatter()

        return fixture.map {
            return GlucoseEffect(startDate: dateFormatter.dateFromString($0["date"] as! String)!, quantity: HKQuantity(unit: HKUnit(fromString: $0["unit"] as! String), doubleValue:$0["amount"] as! Double))
        }
    }

    func loadCOBOutputFixture() -> [CarbValue] {
        let fixture: [JSONDictionary] = loadFixture("carbs_on_board_output")
        let dateFormatter = NSDateFormatter.ISO8601LocalTimeDateFormatter()

        return fixture.map {
            return CarbValue(startDate: dateFormatter.dateFromString($0["date"] as! String)!, quantity: HKQuantity(unit: HKUnit(fromString: $0["unit"] as! String), doubleValue:$0["amount"] as! Double))
        }
    }

    func testCarbEffectFromHistory() {
        let input = loadInputFixture()
        let output = loadEffectOutputFixture()
        let (carbRatios, insulinSensitivities) = loadSchedules()

        let effects = CarbMath.glucoseEffectsForCarbEntries(input, carbRatios: carbRatios, insulinSensitivities: insulinSensitivities, defaultAbsorptionTime: NSTimeInterval(minutes: 180))

        for (expected, calculated) in zip(output, effects) {
            XCTAssertEqual(expected.startDate, calculated.startDate)
            XCTAssertEqualWithAccuracy(expected.quantity.doubleValueForUnit(HKUnit.milligramsPerDeciliterUnit()), calculated.quantity.doubleValueForUnit(HKUnit.milligramsPerDeciliterUnit()), accuracy: pow(1, -11))
        }
    }

    func testCarbsOnBoardFromHistory() {
        let input = loadInputFixture()
        let output = loadCOBOutputFixture()

        let cob = CarbMath.carbsOnBoardForCarbEntries(input, defaultAbsorptionTime: NSTimeInterval(minutes: 180), delay: NSTimeInterval(minutes: 10), delta: NSTimeInterval(minutes: 5))

        for (expected, calculated) in zip(output, cob) {
            XCTAssertEqual(expected.startDate, calculated.startDate)
            XCTAssertEqualWithAccuracy(expected.quantity.doubleValueForUnit(HKUnit.gramUnit()), calculated.quantity.doubleValueForUnit(HKUnit.gramUnit()), accuracy: pow(1, -11))
        }
    }
}
