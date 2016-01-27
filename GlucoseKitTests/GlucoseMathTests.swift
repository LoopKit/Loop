//
//  GlucoseMathTests.swift
//  GlucoseKitTests
//
//  Created by Nathan Racklyeft on 1/24/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import XCTest
@testable import GlucoseKit
import LoopKit
import HealthKit

typealias JSONDictionary = [String: AnyObject]


class GlucoseMathTests: XCTestCase {

    func loadFixture<T>(resourceName: String) -> T {
        let path = NSBundle(forClass: self.dynamicType).pathForResource(resourceName, ofType: "json")!
        return try! NSJSONSerialization.JSONObjectWithData(NSData(contentsOfFile: path)!, options: []) as! T
    }

    func loadInputFixture(resourceName: String) -> [GlucoseValue] {
        let fixture: [JSONDictionary] = loadFixture(resourceName)
        let dateFormatter = NSDateFormatter.ISO8601LocalTimeDateFormatter()

        return fixture.map {
            return GlucoseValue(startDate: dateFormatter.dateFromString($0["date"] as! String)!, quantity: HKQuantity(unit: HKUnit.milligramsPerDeciliterUnit(), doubleValue: $0["amount"] as! Double))
        }
    }

    func loadOutputFixture(resourceName: String) -> [GlucoseEffect] {
        let fixture: [JSONDictionary] = loadFixture(resourceName)
        let dateFormatter = NSDateFormatter.ISO8601LocalTimeDateFormatter()

        return fixture.map {
            return GlucoseEffect(startDate: dateFormatter.dateFromString($0["date"] as! String)!, quantity: HKQuantity(unit: HKUnit(fromString: $0["unit"] as! String), doubleValue:$0["amount"] as! Double))
        }
    }
    
    func testMomentumEffectForBouncingGlucose() {
        let input = loadInputFixture("momentum_effect_bouncing_glucose_input")
        let output = loadOutputFixture("momentum_effect_bouncing_glucose_output")

        let effects = GlucoseMath.linearMomentumEffectForGlucoseEntries(input)
        let unit = HKUnit.milligramsPerDeciliterUnit()

        for (expected, calculated) in zip(output, effects) {
            XCTAssertEqual(expected.startDate, calculated.startDate)
            XCTAssertEqualWithAccuracy(expected.quantity.doubleValueForUnit(unit), calculated.quantity.doubleValueForUnit(unit), accuracy: pow(10.0, -14))
        }
    }

    func testMomentumEffectForRisingGlucose() {
        let input = loadInputFixture("momentum_effect_rising_glucose_input")
        let output = loadOutputFixture("momentum_effect_rising_glucose_output")

        let effects = GlucoseMath.linearMomentumEffectForGlucoseEntries(input)
        let unit = HKUnit.milligramsPerDeciliterUnit()

        for (expected, calculated) in zip(output, effects) {
            XCTAssertEqual(expected.startDate, calculated.startDate)
            XCTAssertEqualWithAccuracy(expected.quantity.doubleValueForUnit(unit), calculated.quantity.doubleValueForUnit(unit), accuracy: pow(10.0, -14))
        }
    }

    func testMomentumEffectForFallingGlucose() {
        let input = loadInputFixture("momentum_effect_falling_glucose_input")
        let output = loadOutputFixture("momentum_effect_falling_glucose_output")

        let effects = GlucoseMath.linearMomentumEffectForGlucoseEntries(input)
        let unit = HKUnit.milligramsPerDeciliterUnit()

        for (expected, calculated) in zip(output, effects) {
            XCTAssertEqual(expected.startDate, calculated.startDate)
            XCTAssertEqualWithAccuracy(expected.quantity.doubleValueForUnit(unit), calculated.quantity.doubleValueForUnit(unit), accuracy: pow(10.0, -14))
        }
    }

    func testMomentumEffectForStableGlucose() {
        let input = loadInputFixture("momentum_effect_stable_glucose_input")
        let output = loadOutputFixture("momentum_effect_stable_glucose_output")

        let effects = GlucoseMath.linearMomentumEffectForGlucoseEntries(input)
        let unit = HKUnit.milligramsPerDeciliterUnit()

        for (expected, calculated) in zip(output, effects) {
            XCTAssertEqual(expected.startDate, calculated.startDate)
            XCTAssertEqualWithAccuracy(expected.quantity.doubleValueForUnit(unit), calculated.quantity.doubleValueForUnit(unit), accuracy: pow(10.0, -14))
        }
    }
}
