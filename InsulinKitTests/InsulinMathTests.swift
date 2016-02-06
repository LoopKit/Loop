//
//  InsulinMathTests.swift
//  InsulinMathTests
//
//  Created by Nathan Racklyeft on 1/27/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import XCTest
import LoopKit
@testable import InsulinKit

typealias JSONDictionary = [String: AnyObject]


struct NewReservoirValue: ReservoirValue {
    let startDate: NSDate
    let unitVolume: Double
}


class InsulinMathTests: XCTestCase {
    
    func loadFixture<T>(resourceName: String) -> T {
        let path = NSBundle(forClass: self.dynamicType).pathForResource(resourceName, ofType: "json")!
        return try! NSJSONSerialization.JSONObjectWithData(NSData(contentsOfFile: path)!, options: []) as! T
    }

    func loadReservoirFixture(resourceName: String) -> [NewReservoirValue] {
        let fixture: [JSONDictionary] = loadFixture(resourceName)
        let dateFormatter = NSDateFormatter.ISO8601LocalTimeDateFormatter()

        return fixture.map {
            return NewReservoirValue(startDate: dateFormatter.dateFromString($0["date"] as! String)!, unitVolume: $0["amount"] as! Double)
        }
    }

    func loadDoseFixture(resourceName: String) -> [DoseEntry] {
        let fixture: [JSONDictionary] = loadFixture(resourceName)
        let dateFormatter = NSDateFormatter.ISO8601LocalTimeDateFormatter()

        return fixture.map {
            let unit = $0["unit"] as! String == "U/hour" ? DoseUnit.UnitsPerHour : DoseUnit.Units

            return DoseEntry(startDate: dateFormatter.dateFromString($0["start_at"] as! String)!, endDate: dateFormatter.dateFromString($0["end_at"] as! String)!, value: $0["amount"] as! Double, unit: unit, description: $0["description"] as? String)
        }
    }

    func loadInsulinValueFixture(resourceName: String) -> [InsulinValue] {
        let fixture: [JSONDictionary] = loadFixture(resourceName)
        let dateFormatter = NSDateFormatter.ISO8601LocalTimeDateFormatter()

        return fixture.map {
            return InsulinValue(startDate: dateFormatter.dateFromString($0["date"] as! String)!, value: $0["amount"] as! Double)
        }
    }

    func loadBasalRateScheduleFixture(resourceName: String) -> BasalRateSchedule {
        let fixture: [JSONDictionary] = loadFixture(resourceName)

        let items = fixture.map {
            return RepeatingScheduleValue(startTime: NSTimeInterval(minutes: $0["minutes"] as! Double), value: $0["rate"] as! Double)
        }

        return BasalRateSchedule(dailyItems: items)!
    }

    func testDoseEntriesFromReservoirValues() {
        let input = loadReservoirFixture("reservoir_history_with_rewind_and_prime_input")
        let output = loadDoseFixture("reservoir_history_with_rewind_and_prime_output").reverse()

        let doses = InsulinMath.doseEntriesFromReservoirValues(input)

        for (expected, calculated) in zip(output, doses) {
            XCTAssertEqual(expected.startDate, calculated.startDate)
            XCTAssertEqual(expected.endDate, calculated.endDate)
            XCTAssertEqualWithAccuracy(expected.value, calculated.value, accuracy: pow(1, -14))
            XCTAssertEqual(expected.unit, calculated.unit)
        }
    }

    func testIOBFromDoses() {
        let input = loadDoseFixture("iob_from_doses_input")
        let output = loadInsulinValueFixture("iob_from_doses_output")

        let iob = InsulinMath.insulinOnBoardForDoses(input, actionDuration: NSTimeInterval(hours: 4))

        for (expected, calculated) in zip(output, iob) {
            XCTAssertEqual(expected.startDate, calculated.startDate)
            XCTAssertEqualWithAccuracy(expected.value, calculated.value, accuracy: pow(1, -14))
        }
    }

    func testIOBFromBolus() {
        let input = loadDoseFixture("iob_from_bolus_input")
        let output = loadInsulinValueFixture("iob_from_bolus_output")

        let iob = InsulinMath.insulinOnBoardForDoses(input, actionDuration: NSTimeInterval(hours: 4))

        for (expected, calculated) in zip(output, iob) {
            XCTAssertEqual(expected.startDate, calculated.startDate)
            XCTAssertEqualWithAccuracy(expected.value, calculated.value, accuracy: pow(1, -14))
        }
    }

    func testNormalizeReservoirDoses() {
        let input = loadDoseFixture("reservoir_history_with_rewind_and_prime_output")
        let output = loadDoseFixture("normalized_reservoir_history_output")
        let basals = loadBasalRateScheduleFixture("basal")

        let doses = InsulinMath.normalize(input, againstBasalSchedule: basals)

        for (expected, calculated) in zip(output, doses) {
            XCTAssertEqual(expected.startDate, calculated.startDate)
            XCTAssertEqual(expected.endDate, calculated.endDate)
            XCTAssertEqualWithAccuracy(expected.value, calculated.value, accuracy: pow(1, -14))
            XCTAssertEqual(expected.unit, calculated.unit)
        }
    }

    func testIOBFromReservoirDoses() {
        let input = loadDoseFixture("normalized_reservoir_history_output")
        let output = loadInsulinValueFixture("iob_from_reservoir_output")

        let iob = InsulinMath.insulinOnBoardForDoses(input, actionDuration: NSTimeInterval(hours: 4))

        for (expected, calculated) in zip(output, iob) {
            XCTAssertEqual(expected.startDate, calculated.startDate)
            XCTAssertEqualWithAccuracy(expected.value, calculated.value, accuracy: pow(1, -14))
        }
    }
}
