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

typealias JSONDictionary = [String: AnyObject]


class CarbMathTests: XCTestCase {

    func loadFixtures() -> ([CarbEntry], [GlucoseEffect], CarbRatioSchedule, InsulinSensitivitySchedule) {
        var fixtures: [[JSONDictionary]] = []

        for name in ["input", "output"] {
            let path = NSBundle(forClass: self.dynamicType).pathForResource("carb_effect_from_history_\(name)", ofType: "json")!
            let fixture = try! NSJSONSerialization.JSONObjectWithData(NSData(contentsOfFile: path)!, options: [])

            fixtures.append(fixture as! [JSONDictionary])
        }

        let dateFormatter = NSDateFormatter.ISO8601LocalTimeDateFormatter()
        dateFormatter.dateFromString("2015-10-15T21:35:12")!

        let input: [CarbEntry] = fixtures[0].map {
            return NewCarbEntry(
                value: $0["amount"] as! Double,
                startDate: dateFormatter.dateFromString($0["start_at"] as! String)!,
                foodType: nil,
                absorptionTime: nil
            )
        }

        let output = fixtures[1].map {
            return GlucoseEffect(startDate: dateFormatter.dateFromString($0["date"] as! String)!, value: $0["amount"] as! Double, unit: HKUnit(fromString: $0["unit"] as! String))
        }

        let path = NSBundle(forClass: self.dynamicType).pathForResource("read_carb_ratios", ofType: "json")!
        let fixture = try! NSJSONSerialization.JSONObjectWithData(NSData(contentsOfFile: path)!, options: []) as! JSONDictionary
        let schedule = fixture["schedule"] as! [JSONDictionary]

        let items = schedule.map {
            return ScheduleItem(startTime: NSTimeInterval(minutes: $0["offset"] as! Double), value: $0["ratio"] as! Double)
        }

        return (
            input,
            output,
            CarbRatioSchedule(unit: HKUnit.gramUnit(), dailyItems: items)!,
            InsulinSensitivitySchedule(unit: HKUnit.milligramsPerDeciliterUnit(), dailyItems: [ScheduleItem(startTime: 0.0, value: 40.0)])!
        )
    }

    func testCarbEffectFromHistory() {
        let (input, output, carbRatios, insulinSensitivities) = loadFixtures()

        let effects = CarbMath.glucoseEffectsForCarbEntries(input, carbRatios: carbRatios, insulinSensitivities: insulinSensitivities, defaultAbsorptionTime: NSTimeInterval(minutes: 180))

        for (expected, calculated) in zip(output, effects) {
            XCTAssertEqual(expected.startDate, calculated.startDate)
            XCTAssertEqualWithAccuracy(expected.value, calculated.value, accuracy: pow(10.0, -11))
        }
    }
    
}
