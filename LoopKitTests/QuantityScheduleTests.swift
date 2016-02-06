//
//  QuantityScheduleTests.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 1/18/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import XCTest
import HealthKit
@testable import LoopKit

class QuantityScheduleTests: XCTestCase {

    var items: [RepeatingScheduleValue]!

    override func setUp() {
        super.setUp()

        let path = NSBundle(forClass: self.dynamicType).pathForResource("read_carb_ratios", ofType: "json")!
        let fixture = try! NSJSONSerialization.JSONObjectWithData(NSData(contentsOfFile: path)!, options: []) as! JSONDictionary
        let schedule = fixture["schedule"] as! [JSONDictionary]

        items = schedule.map {
            return RepeatingScheduleValue(startTime: NSTimeInterval(minutes: $0["offset"] as! Double), value: $0["ratio"] as! Double)
        }
    }

    func testCarbRatioScheduleLocalTimeZone() {
        let schedule = CarbRatioSchedule(unit: HKUnit.gramUnit(), dailyItems: items)!
        let calendar = NSCalendar.currentCalendar()

        let midnight = calendar.startOfDayForDate(NSDate())

        XCTAssertEqual(HKQuantity(unit: HKUnit.gramUnit(), doubleValue: 10), schedule.at(midnight))
        XCTAssertEqual(9,
            schedule.at(midnight.dateByAddingTimeInterval(-1)).doubleValueForUnit(schedule.unit)
        )
        XCTAssertEqual(10,
            schedule.at(midnight.dateByAddingTimeInterval(NSTimeInterval(hours: 24))).doubleValueForUnit(schedule.unit)
        )

        let midMorning = calendar.nextDateAfterDate(NSDate(), matchingHour: 10, minute: 29, second: 4, options: [.MatchNextTime])!

        XCTAssertEqual(10, schedule.at(midMorning).doubleValueForUnit(schedule.unit))

        let lunch = calendar.nextDateAfterDate(midMorning, matchingHour: 12, minute: 01, second: 01, options: [.MatchNextTime])!

        XCTAssertEqual(9, schedule.at(lunch).doubleValueForUnit(schedule.unit))

        let dinner = calendar.nextDateAfterDate(midMorning, matchingHour: 19, minute: 0, second: 0, options: [.MatchNextTime])!

        XCTAssertEqual(8, schedule.at(dinner).doubleValueForUnit(schedule.unit))
    }

    func testCarbRatioScheduleUTC() {
        let schedule = CarbRatioSchedule(unit: HKUnit.gramUnit(), dailyItems: items, timeZone: NSTimeZone(forSecondsFromGMT: 0))!
        let calendar = NSCalendar.currentCalendar()

        calendar.timeZone = NSTimeZone(name: "America/Los_Angeles")!

        let june1 = calendar.nextDateAfterDate(NSDate(), matchingUnit: .Month, value: 5, options: [.MatchNextTime])!

        XCTAssertEqual(-7 * 60 * 60, calendar.timeZone.secondsFromGMTForDate(june1))


        let midnight = calendar.startOfDayForDate(june1)

        // This is 7 AM the next day in the Schedule's time zone
        XCTAssertEqual(HKQuantity(unit: HKUnit.gramUnit(), doubleValue: 10), schedule.at(midnight))
        XCTAssertEqual(10,
            schedule.at(midnight.dateByAddingTimeInterval(-1)).doubleValueForUnit(schedule.unit)
        )
        XCTAssertEqual(10,
            schedule.at(midnight.dateByAddingTimeInterval(NSTimeInterval(hours: 24))).doubleValueForUnit(schedule.unit)
        )

        // 10:29:04 AM -> 5:29:04 PM
        let midMorning = calendar.nextDateAfterDate(june1, matchingHour: 10, minute: 29, second: 4, options: [.MatchNextTime])!

        XCTAssertEqual(9, schedule.at(midMorning).doubleValueForUnit(schedule.unit))

        // 12:01:01 PM -> 7:01:01 PM
        let lunch = calendar.nextDateAfterDate(midMorning, matchingHour: 12, minute: 01, second: 01, options: [.MatchNextTime])!

        XCTAssertEqual(8, schedule.at(lunch).doubleValueForUnit(schedule.unit))

        // 7:00 PM -> 2:00 AM
        let dinner = calendar.nextDateAfterDate(midMorning, matchingHour: 19, minute: 0, second: 0, options: [.MatchNextTime])!

        XCTAssertEqual(10, schedule.at(dinner).doubleValueForUnit(schedule.unit))
    }

}
